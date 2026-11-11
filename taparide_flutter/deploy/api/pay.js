// Wallet top-ups through Paystack (card, bank transfer, USSD). One endpoint, four actions:
//   POST /api/pay?action=init     { amount }  -> { url, reference }   (signed-in rider)
//   GET  /api/pay?action=verify&reference=…   -> { status, amount }   (signed-in rider, after returning)
//   GET  /api/pay?action=return&reference=…   -> redirect back into the app (Paystack's callback)
//   POST /api/pay?action=webhook               <- Paystack tells us a charge succeeded
// The wallet is only ever credited by confirm_top_up in the database, after Paystack itself
// confirms the payment to this server. Keys stay here; the app never sees them.
import { createHmac, timingSafeEqual } from "node:crypto";
import { AiError, handleError, send } from "./_lib/ai.js";
import { requireUser } from "./_lib/auth.js";

const PAYSTACK = "https://api.paystack.co";
const key = () => process.env.PAYSTACK_SECRET_KEY;

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
  if (!key() || !process.env.TOPUP_SIGNING_SECRET || !process.env.SUPABASE_URL) throw new AiError(503, "Card and bank top-ups are not switched on yet.");
}

export default async function handler(req, res) {
  const action = `${req.query?.action || ""}`;
  try {
    if (action === "return") {
      // Paystack sends the rider back here; the app then verifies with its own session.
      const reference = `${req.query.reference || req.query.trxref || ""}`.replace(/[^A-Za-z0-9-]/g, "");
      res.statusCode = 302;
      res.setHeader("Location", `/#/app/profile?topup=${reference}`);
      return res.end();
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
