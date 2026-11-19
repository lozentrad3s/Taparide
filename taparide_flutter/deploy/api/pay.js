// Wallet top-ups through Bachs (bachs.io: card, bank transfer) or Paystack. One endpoint, five actions:
//   GET  /api/pay?action=status                -> is the key accepted? (yes/no only, never the key)
//   POST /api/pay?action=init     { amount }  -> { url, reference }   (signed-in rider)
//   GET  /api/pay?action=verify&reference=…   -> { status, amount }   (signed-in rider, after returning)
//   GET  /api/pay?action=return&reference=…   -> redirect back into the app (the provider's callback)
//   POST /api/pay?action=webhook               <- the provider tells us a payment succeeded
// Provider: Bachs when BACHS_SECRET_KEY is set (sk_sandbox_… uses the sandbox, sk_live_… production),
// otherwise Paystack (PAYSTACK_SECRET_KEY). Webhooks: BACHS_WEBHOOK_SECRET from the Bachs Developer Portal,
// endpoint https://taparide.com/api/pay?action=webhook.
// The wallet is only ever credited by confirm_top_up in the database, after the provider itself
// confirms the payment to this server. Keys stay here; the app never sees them.
import { createHmac, timingSafeEqual } from "node:crypto";
import { AiError, handleError, send } from "./_lib/ai.js";
import { limitByIp, requireUser } from "./_lib/auth.js";

const PAYSTACK = "https://api.paystack.co";
const key = () => process.env.PAYSTACK_SECRET_KEY;

// ---------------------------------------------------------------- Bachs
const bachsKey = () => process.env.BACHS_SECRET_KEY;
const useBachs = () => !!bachsKey();
const bachsBase = () => process.env.BACHS_API_BASE || (bachsKey()?.startsWith("sk_live_") ? "https://api.bachs.io" : "https://sandbox-api.bachs.io");

async function bachs(path, init = {}) {
  const res = await fetch(`${bachsBase()}${path}`, { ...init, headers: { Authorization: `Bearer ${bachsKey()}`, "Content-Type": "application/json", ...(init.headers || {}) } });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new AiError(502, body.detail || `The payment service is unavailable (${res.status}).`);
  return body;
}

/** Bachs amounts are decimal strings in naira ("1000.00"); confirm_top_up wants kobo. */
const toKobo = (amount) => Math.round(Number.parseFloat(`${amount}`) * 100);

/** Asks Bachs for the checkout's real state; credits the wallet when it is paid in NGN. */
async function settleBachs(checkoutId) {
  const c = await bachs(`/v1/checkout-sessions/${encodeURIComponent(checkoutId)}`);
  const paid = c.status === "completed" && `${c.payment_status}`.toLowerCase() === "succeeded" && c.charge && `${c.charge.currency}`.toUpperCase() === "NGN";
  if (!paid) return { status: c.status === "expired" || c.status === "cancelled" || `${c.payment_status}`.toLowerCase() === "failed" ? "failed" : "pending", amount: c.charge ? Math.round(toKobo(c.charge.amount) / 100) : 0 };
  return confirm({ reference: c.reference, amount: toKobo(c.charge.amount), channel: "bachs" });
}

/** Reads the raw request body (needed for the signature) without letting the runtime parse it first. */
async function rawBody(req) {
  let raw = "";
  try {
    for await (const chunk of req) raw += chunk;
  } catch {}
  if (raw) return raw;
  return typeof req.body === "string" ? req.body : JSON.stringify(req.body || {});
}

function bachsSignatureOk(req, raw) {
  const secret = process.env.BACHS_WEBHOOK_SECRET;
  if (!secret) return false;
  const v2 = `${req.headers["x-bachs-signature-v2"] || ""}`;
  const parts = Object.fromEntries(v2.split(",").map((p) => p.trim().split("=")).filter((p) => p.length === 2));
  const ts = parts.t || `${req.headers["x-bachs-timestamp"] || ""}`;
  if (!ts || Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false;
  const expected = createHmac("sha256", secret).update(`${ts}.${raw}`).digest("hex");
  const given = [...v2.matchAll(/v1=([a-f0-9]+)/g)].map((m) => m[1]);
  if (!given.length && req.headers["x-bachs-signature"]) given.push(`${req.headers["x-bachs-signature"]}`);
  return given.some((g) => g.length === expected.length && timingSafeEqual(Buffer.from(g), Buffer.from(expected)));
}

async function paystack(path, init = {}) {
  const res = await fetch(`${PAYSTACK}${path}`, { ...init, headers: { Authorization: `Bearer ${key()}`, "Content-Type": "application/json", ...(init.headers || {}) } });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.status === false) throw new AiError(502, body.message || `The payment service is unavailable (${res.status}).`);
  return body.data;
}

async function rpc(name, params, token) {
  const res = await fetch(`${process.env.SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token || process.env.SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new AiError(res.status === 404 ? 404 : 400, body.message || "The wallet could not be updated.");
  return body;
}

/** Credits the wallet for a transaction Paystack reports as successful. Safe to call twice. */
const confirm = (tx) =>
  rpc("confirm_top_up", { p_secret: process.env.TOPUP_SIGNING_SECRET, p_reference: tx.reference, p_amount_kobo: tx.amount, p_channel: tx.channel || null });

function ready() {
  if ((!key() && !useBachs()) || !process.env.TOPUP_SIGNING_SECRET || !process.env.SUPABASE_URL) throw new AiError(503, "Card and bank top-ups are not switched on yet.");
}

export default async function handler(req, res) {
  const action = `${req.query?.action || ""}`;
  try {
    if (action === "return") {
      // Paystack sends the rider back here; the app then verifies with its own session.
      const reference = `${req.query.reference || req.query.trxref || ""}`.replace(/[^A-Za-z0-9-]/g, "");
      // Bachs adds ?checkout_id=…; it travels with the reference so the app can ask us to verify it.
      const checkout = `${req.query.checkout_id || ""}`.replace(/[^A-Za-z0-9_]/g, "");
      res.statusCode = 302;
      res.setHeader("Location", `/app/#/app/profile?topup=${reference}${checkout ? `.${checkout}` : ""}`);
      return res.end();
    }

    if (action === "status") {
      // Set-up check: is the payment key accepted by the provider, and is the webhook secret set?
      // Looks up a checkout that cannot exist (404 = key accepted, 401/403 = key rejected).
      // Answers with yes/no only, never a key, and creates nothing.
      await limitByIp(req, "pay-status", 6);
      const out = { provider: useBachs() ? "bachs" : key() ? "paystack" : null, mode: null, key: null, webhookSecret: false, signingSecret: !!process.env.TOPUP_SIGNING_SECRET };
      if (useBachs()) {
        out.mode = bachsKey().startsWith("sk_live_") ? "live" : bachsKey().startsWith("sk_sandbox_") ? "sandbox" : "unknown";
        out.webhookSecret = !!process.env.BACHS_WEBHOOK_SECRET;
        const r = await fetch(`${bachsBase()}/v1/checkout-sessions/chk_taparide_status_check`, { headers: { Authorization: `Bearer ${bachsKey()}` }, signal: AbortSignal.timeout(8000) }).catch(() => null);
        out.key = !r ? "unreachable" : r.status === 401 || r.status === 403 ? "rejected" : r.status < 500 ? "accepted" : "provider error";
        out.providerStatus = r?.status ?? null;
      }
      return send(res, 200, out);
    }

    if (action === "webhook" && (req.headers["x-bachs-signature-v2"] || req.headers["x-bachs-signature"])) {
      ready();
      if (req.method !== "POST") throw new AiError(405, "POST only.");
      const raw = await rawBody(req);
      if (!bachsSignatureOk(req, raw)) throw new AiError(401, "Bad signature.");
      const event = JSON.parse(raw || "{}");
      const d = event.data || {};
      if (event.type === "collection.succeeded" && d.checkout_id && `${d.reference || ""}`.startsWith("TAR-")) {
        // Ask Bachs again rather than trusting the payload alone; crediting twice is impossible.
        await settleBachs(d.checkout_id);
      }
      return send(res, 200, { received: true });
    }

    if (action === "webhook") {
      ready();
      if (req.method !== "POST") throw new AiError(405, "POST only.");
      const signature = `${req.headers["x-paystack-signature"] || ""}`;
      const expected = createHmac("sha512", key()).update(JSON.stringify(req.body)).digest("hex");
      const ok = signature.length === expected.length && timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
      if (!ok) throw new AiError(401, "Bad signature.");
      const event = req.body || {};
      if (event.event === "charge.success" && event.data?.status === "success" && `${event.data.reference}`.startsWith("TAR-")) {
        // Ask Paystack again rather than trusting the payload alone.
        const tx = await paystack(`/transaction/verify/${encodeURIComponent(event.data.reference)}`);
        if (tx.status === "success" && tx.currency === "NGN") await confirm(tx);
      }
      return send(res, 200, { received: true });
    }

    if (action === "init") {
      if (req.method !== "POST") throw new AiError(405, "POST only.");
      const user = await requireUser(req, { perMinute: 10 });
      ready();
      const amount = Math.round(Number(req.body?.amount));
      if (!Number.isFinite(amount) || amount < 100 || amount > 50000) throw new AiError(400, "Top up between ₦100 and ₦50,000.");
      const token = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
      const topup = await rpc("start_top_up", { p_amount: amount }, token);
      const origin = `https://${req.headers["x-forwarded-host"] || req.headers.host}`;
      if (useBachs()) {
        const back = `${origin}/api/pay?action=return&reference=${encodeURIComponent(topup.reference)}`;
        const session = await bachs("/v1/checkout-sessions", {
          method: "POST",
          headers: { "Idempotency-Key": topup.reference },
          body: JSON.stringify({
            pricing: { currency: "NGN", amount: `${amount}.00` },
            customer: { email: user.email },
            success_url: back,
            cancel_url: back,
            reference: topup.reference,
            expires_in_minutes: 60,
            metadata: { purpose: "Tap A Ride wallet top-up", user_id: user.id },
          }),
        });
        return send(res, 200, { url: session.checkout_url, reference: topup.reference });
      }
      const tx = await paystack("/transaction/initialize", {
        method: "POST",
        body: JSON.stringify({
          email: user.email,
          amount: amount * 100, // kobo
          currency: "NGN",
          reference: topup.reference,
          callback_url: `${origin}/api/pay?action=return`,
          channels: ["card", "bank", "ussd", "bank_transfer"],
          metadata: { purpose: "Tap A Ride wallet top-up", user_id: user.id },
        }),
      });
      return send(res, 200, { url: tx.authorization_url, reference: topup.reference });
    }

    if (action === "verify") {
      await requireUser(req, { perMinute: 30 });
      ready();
      const reference = `${req.query.reference || ""}`;
      // Bachs: "TAR-….chk_…" (reference and checkout id from the return redirect).
      const bachsRef = /^(TAR-[A-Z0-9]{6,40})\.(chk_[A-Za-z0-9_]{4,80})$/.exec(reference);
      if (bachsRef && useBachs()) {
        const result = await settleBachs(bachsRef[2]);
        return send(res, 200, { status: result.status, amount: result.amount });
      }
      if (!/^TAR-[A-Z0-9]{6,40}$/.test(reference)) throw new AiError(400, "Unknown payment reference.");
      const tx = await paystack(`/transaction/verify/${encodeURIComponent(reference)}`);
      if (tx.status !== "success" || tx.currency !== "NGN") return send(res, 200, { status: tx.status === "abandoned" || tx.status === "failed" ? "failed" : "pending", amount: Math.round(tx.amount / 100) });
      const result = await confirm(tx);
      return send(res, 200, { status: result.status, amount: result.amount });
    }

    throw new AiError(404, "Unknown payment action.");
  } catch (error) {
    handleError(res, error);
  }
}
