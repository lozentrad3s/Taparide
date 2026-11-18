// POST /api/client-error — errors from the rider app and dashboards, forwarded to Sentry
// (SENTRY_DSN). Small, rate-limited and without personal data; returns 204 either way.
import { reportError } from "./_lib/sentry.js";
import { overLimit } from "./_lib/redis.js";

const hits = new Map();

async function readBody(req) {
  if (req.body && typeof req.body === "object") return req.body;
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 8000) break;
  }
  try {
    return JSON.parse(raw || "{}");
  } catch {
    return {};
  }
}

export default async function handler(req, res) {
  res.statusCode = 204;
  try {
    if (req.method !== "POST") return res.end();
    const ip = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "unknown";
    let limited = await overLimit(`client-error:${ip}`, 20);
    if (limited === null) {
      const now = Date.now();
      const recent = (hits.get(ip) || []).filter((t) => now - t < 60_000);
      recent.push(now);
      hits.set(ip, recent);
      limited = recent.length > 20;
    }
    if (limited) return res.end();
    const b = await readBody(req);
    const err = new Error(String(b.message || "Unknown client error").slice(0, 500));
    err.name = `ClientError(${String(b.app || "app").slice(0, 20)})`;
    if (b.stack) err.stack = `${err.name}: ${err.message}\n${String(b.stack).slice(0, 4000)}`;
    await reportError(err, { app: String(b.app || "").slice(0, 20), route: String(b.route || "").slice(0, 100) });
  } catch {}
  res.end();
}
