// /api/waitlist
//   POST {action:"join", email, name?, phone?, area?, role?, ref?}   -> place in line + invite code
//   POST {action:"seat", code, event, day, area, slot}               -> event-bus seat request
//   GET  ?code=XXXXXX                                                -> place in line
//   GET  ?event=abuja-tech-week-2026                                 -> seat demand (counts only)
import { call, isPreview, StoreError } from "./_lib/store.js";

const hits = new Map();
const ALLOWED = new Set(
  ["https://taparide.com", "https://www.taparide.com", ...(process.env.SITE_ORIGINS || "").split(",")].map((o) => o.trim()).filter(Boolean),
);
const allowedOrigin = (o) =>
  !o || ALLOWED.has(o) || /^https:\/\/taparide-site[a-z0-9-]*\.vercel\.app$/.test(o) || /^http:\/\/localhost(:\d+)?$/.test(o);

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

function limited(req, perMinute) {
  const ip = String(req.headers["x-forwarded-for"] || req.socket?.remoteAddress || "unknown").split(",")[0].trim();
  const now = Date.now();
  const recent = (hits.get(ip) || []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.set(ip, recent);
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

export default async function handler(req, res) {
  try {
    if (!allowedOrigin(req.headers.origin)) return send(res, 403, { error: "This form only works on the Tap A Ride website." });
    const url = new URL(req.url, "http://local");

    if (req.method === "GET") {
      if (limited(req, 60)) return send(res, 429, { error: "Too many requests. Wait a minute and try again." });
      const event = url.searchParams.get("event");
      const code = url.searchParams.get("code");
      if (event) return send(res, 200, { ...(await call("event_seat_demand", { p_event: event.slice(0, 60) })), preview: isPreview() });
      if (code) return send(res, 200, { ...(await call("waitlist_status", { p_code: code.slice(0, 12) })), preview: isPreview() });
      return send(res, 400, { error: "Missing code or event." });
    }

    if (req.method !== "POST") return send(res, 405, { error: "Use GET or POST." });
    if (limited(req, 10)) return send(res, 429, { error: "Too many tries. Wait a minute and try again." });
    const b = await readBody(req);
    // Bots fill every field; people never see this one.
    if (b.company) return send(res, 400, { error: "Something went wrong. Please try again." });

    if (b.action === "join") {
      const out = await call("join_waitlist", {
        p_email: str(b.email, 254),
        p_name: str(b.name, 80) ?? null,
        p_phone: str(b.phone, 30) ?? null,
        p_area: str(b.area, 40) ?? null,
        p_ref: str(b.ref, 12) ?? null,
        p_role: str(b.role, 20) ?? "rider",
        p_source: str(b.source, 40) ?? "website",
      });
      return send(res, 200, { ...out, preview: isPreview() });
    }
    if (b.action === "seat") {
      const out = await call("request_event_seat", {
        p_code: str(b.code, 12),
        p_event: str(b.event, 60),
        p_day: str(b.day, 10),
        p_area: str(b.area, 40),
        p_slot: str(b.slot, 5),
        p_name: str(b.name, 80) ?? null,
        p_phone: str(b.phone, 30) ?? null,
      });
      return send(res, 200, { ...out, preview: isPreview() });
    }
    return send(res, 400, { error: "Unknown action." });
  } catch (e) {
    if (e instanceof SyntaxError) return send(res, 400, { error: "That request could not be read." });
    if (e instanceof StoreError) return send(res, e.status, { error: e.message });
    console.error(e);
    return send(res, 500, { error: "Something went wrong on our side. Please try again." });
  }
}
