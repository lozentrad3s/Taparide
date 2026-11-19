// Confirms the caller is a signed-in Tap A Ride user (Supabase session) and applies a
// small per-instance rate limit, so the public AI endpoints can't be used to burn quota.
import { AiError } from "./ai.js";
import { overLimit } from "./redis.js";

const hits = new Map();

// Browsers send Origin on cross-site requests; only our own site may call these endpoints from a page.
const ALLOWED_ORIGINS = new Set(["https://taparide.com", "https://www.taparide.com", "https://taparide.vercel.app", ...(process.env.EXTRA_ORIGINS || "").split(",").map((o) => o.trim()).filter(Boolean)]);
const isAllowedOrigin = (origin) => !origin || ALLOWED_ORIGINS.has(origin) || /^https:\/\/taparide-[a-z0-9-]+-lozen-s-projects\.vercel\.app$/.test(origin) || /^http:\/\/localhost(:\d+)?$/.test(origin);

export async function requireUser(req, { perMinute = 20 } = {}) {
  if (!isAllowedOrigin(req.headers.origin)) throw new AiError(403, "This service is only available from Tap A Ride.");
  const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "unknown";
  const shared = await overLimit(`api:${new URL(req.url, "http://x").pathname}:${ip}`, perMinute);
  if (shared === true) throw new AiError(429, "Too many requests. Wait a minute and try again.");
  if (shared === null) {
    const now = Date.now();
    // One counter per service, as in Redis: busy map tiles must not block payments or the assistant.
    const key = `${new URL(req.url, "http://x").pathname}:${ip}`;
    const recent = (hits.get(key) || []).filter((t) => now - t < 60_000);
    if (recent.length >= perMinute) throw new AiError(429, "Too many requests. Wait a minute and try again.");
    recent.push(now);
    hits.set(key, recent);
    if (hits.size > 5000) hits.clear();
  }

  const url = process.env.SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY;
  if (!url || !anon) return { id: "demo", demo: true }; // demo deployments have no accounts server-side

  const token = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!token) throw new AiError(401, "Sign in to continue.");
  const res = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anon, Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new AiError(401, "Your session has ended. Please sign in again.");
  const user = await res.json();
  return { id: user.id, email: user.email };
}
