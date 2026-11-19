// /api/waitlist
//   POST {action:"join", email, name?, phone?, area?, role?, ref?}   -> place in line + invite code
//   POST {action:"seat", access, event, days[], area, name, phone}     -> one personal bus pass for those days
//        (older pages send a single "day": that books every day of the event; one pass covers them all)
//   GET  ?code=XXXXXX                                                -> place in line
//   GET  ?event=abuja-tech-week-2026                                 -> seat demand (counts only)
import { call, isPreview, StoreError } from "./_lib/store.js";
import { cached, overLimit } from "./_lib/redis.js";
import { reportError } from "./_lib/sentry.js";
import { sendMail } from "./_lib/mail.js";
import { passEmail, welcomeEmail } from "./_lib/emails.js";

// Anti-bot: forms must be filled by a person in a browser.
// 1. a hidden honeypot field ("company") that people never see;
// 2. at least 3 seconds between the page loading and the form being sent ("elapsed");
// 3. Cloudflare Turnstile when TURNSTILE_SECRET_KEY / TURNSTILE_SITE_KEY are set (invisible check).
const MIN_FILL_MS = 3000;
async function turnstileOk(token, ip) {
  const secret = process.env.TURNSTILE_SECRET_KEY;
  if (!secret) return true;
  if (!token) return false;
  try {
    const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ secret, response: String(token).slice(0, 2048), remoteip: ip }),
      signal: AbortSignal.timeout(4000),
    });
    return (await r.json()).success === true;
  } catch {
    return false;
  }
}

const hits = new Map();
const ALLOWED = new Set(
  ["https://taparide.com", "https://www.taparide.com", "https://taparide.vercel.app", ...(process.env.SITE_ORIGINS || "").split(",")].map((o) => o.trim()).filter(Boolean),
);
const allowedOrigin = (o) =>
  !o || ALLOWED.has(o) || /^https:\/\/taparide-[a-z0-9-]+-lozen-s-projects\.vercel\.app$/.test(o) || /^http:\/\/localhost(:\d+)?$/.test(o);

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

// Shared across every server through Redis when configured; per-server memory otherwise.
async function limited(req, perMinute, scope) {
  const ip = String(req.headers["x-forwarded-for"] || req.socket?.remoteAddress || "unknown").split(",")[0].trim();
  const shared = await overLimit(`waitlist:${scope}:${ip}`, perMinute);
  if (shared !== null) return shared;
  const now = Date.now();
  // One counter per scope: page reads (seat counts) must not use up the sign-up allowance.
  const key = `${scope}:${ip}`;
  const recent = (hits.get(key) || []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.set(key, recent);
  if (hits.size > 5000) hits.clear();
  return recent.length > perMinute;
}

async function readBody(req) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string") return JSON.parse(req.body || "{}");
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 10_000) throw new StoreError(413, "That request is too large.");
  }
  return JSON.parse(raw || "{}");
}

const str = (v, max) => (typeof v === "string" ? v.slice(0, max) : undefined);

/** Event days from the form: up to 3 YYYY-MM-DD strings, or null (= every day of the event). */
function daysFrom(b) {
  if (!Array.isArray(b.days)) return null;
  const days = [...new Set(b.days.filter((d) => typeof d === "string" && /^\d{4}-\d{2}-\d{2}$/.test(d)))];
  if (!days.length || days.length > 3 || days.length !== b.days.length) throw new StoreError(400, "Pick the days you'll ride from the list.");
  return days;
}

/** Sends an email but never holds the response for more than a few seconds or fails it. */
const mailSoon = (msg) => Promise.race([sendMail(msg), new Promise((ok) => setTimeout(() => ok({ sent: false, reason: "slow" }), 6000))]);

// Until migration 20261119000000 is on the database: book each day with the older one-day function
// and show the result as one pass. Remove once reserve_event_pass is live everywhere.
const EVENT_DAYS = { "abuja-tech-week-2026": ["2026-11-24", "2026-11-25", "2026-11-26"] };
async function passOneDayAtATime(a) {
  const days = a.p_days?.length ? a.p_days : EVENT_DAYS[a.p_event] || [];
  if (!days.length) throw new StoreError(400, "Pick days of the event only.");
  let first, last;
  for (const day of days) {
    last = await call("reserve_event_seat", { p_access: a.p_access, p_event: a.p_event, p_day: day, p_area: a.p_area, p_slot: a.p_slot, p_name: a.p_name, p_phone: a.p_phone });
    first ||= last;
  }
  // The migration later gives every day the first day's pass ID, so show that one now.
  const t = last.ticket;
  return { pass: { code: first.ticket.code, event: t.event, name: t.name, days, area: t.area, slot: t.slot }, riders: last.riders, summary: last.summary };
}

export default async function handler(req, res) {
  try {
    if (!allowedOrigin(req.headers.origin)) return send(res, 403, { error: "This form only works on the Tap A Ride website." });
    const url = new URL(req.url, "http://local");

    if (req.method === "GET") {
      if (await limited(req, 60, "read")) return send(res, 429, { error: "Too many requests. Wait a minute and try again." });
      if (url.searchParams.has("config")) return send(res, 200, { turnstile: process.env.TURNSTILE_SITE_KEY || null });
      const event = url.searchParams.get("event");
      const code = url.searchParams.get("code");
      if (event) {
        const p_event = event.slice(0, 60);
        return send(res, 200, { ...(await cached(`demand:${p_event}`, 15, () => call("event_seat_demand", { p_event }))), preview: isPreview() });
      }
      if (code) return send(res, 200, { ...(await call("waitlist_status", { p_code: code.slice(0, 12) })), preview: isPreview() });
      return send(res, 400, { error: "Missing code or event." });
    }

    if (req.method !== "POST") return send(res, 405, { error: "Use GET or POST." });
    // 20 a minute per address: many people share one mobile-network address in Nigeria.
    if (await limited(req, 20, "write")) return send(res, 429, { error: "Too many tries. Wait a minute and try again." });
    const b = await readBody(req);
    // Bots fill every field; people never see this one.
    if (b.company) return send(res, 400, { error: "Something went wrong. Please try again." });
    if (!(Number(b.elapsed) >= MIN_FILL_MS)) return send(res, 400, { error: "That was quick! Please check your details and send again." });
    const ip = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim();
    if (b.action === "join" && !(await turnstileOk(b.turnstile, ip))) return send(res, 400, { error: "We couldn't confirm you're a person. Refresh the page and try again." });

    if (b.action === "join") {
      if (b.terms !== "v1") return send(res, 400, { error: "Please agree to the Terms and Privacy notice to claim your free ride." });
      const out = await call("join_waitlist", {
        p_email: str(b.email, 254),
        p_name: str(b.name, 80) ?? null,
        p_phone: str(b.phone, 30) ?? null,
        p_area: str(b.area, 40) ?? null,
        p_ref: str(b.ref, 12) ?? null,
        p_role: str(b.role, 20) ?? "rider",
        p_source: str(b.source, 40) ?? "website",
        p_terms: "v1",
      });
      // Tech Week sign-ups get their pass email right after this instead.
      if (out && out.existing === false && out.email && b.source !== "tech-week") {
        await mailSoon({ to: out.email, ...welcomeEmail({ name: out.name, code: out.code, position: out.position, freeRideLeft: out.free_ride_left }) });
      }
      return send(res, 200, { ...out, preview: isPreview() });
    }
    if (b.action === "seat") {
      // The private access key (returned when joining), never the public invite code.
      const args = {
        p_access: str(b.access, 80),
        p_event: str(b.event, 60),
        p_area: str(b.area, 40),
        p_name: str(b.name, 80) ?? null,
        p_phone: str(b.phone, 30) ?? null,
        p_days: daysFrom(b),
        p_slot: "07:00",
      };
      const out = await call("reserve_event_pass", args).catch((e) => (e.missing ? passOneDayAtATime(args) : Promise.reject(e)));
      // The pass goes to the email they joined with, straight away.
      const to = out?.summary?.email;
      const mail = out?.pass && to ? await mailSoon({ to, ...passEmail(out.pass) }) : { sent: false };
      return send(res, 200, { ...out, emailed: mail.sent === true, preview: isPreview() });
    }
    return send(res, 400, { error: "Unknown action." });
  } catch (e) {
    if (e instanceof SyntaxError) return send(res, 400, { error: "That request could not be read." });
    if (e instanceof StoreError) {
      if (e.status >= 500) reportError(e, { route: "waitlist" });
      return send(res, e.status, { error: e.message });
    }
    console.error(e);
    reportError(e, { route: "waitlist" });
    return send(res, 500, { error: "Something went wrong on our side. Please try again." });
  }
}
