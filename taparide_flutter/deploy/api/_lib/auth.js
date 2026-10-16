// Confirms the caller is a signed-in Tap A Ride user (Supabase session) and applies a
// small per-instance rate limit, so the public AI endpoints can't be used to burn quota.
import { AiError } from "./ai.js";

const hits = new Map();

export async function requireUser(req, { perMinute = 20 } = {}) {
  const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "unknown";
  const now = Date.now();
  const recent = (hits.get(ip) || []).filter((t) => now - t < 60_000);
  if (recent.length >= perMinute) throw new AiError(429, "Too many requests. Wait a minute and try again.");
  recent.push(now);
  hits.set(ip, recent);

  const url = process.env.SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY;
  if (!url || !anon) return { id: "demo", demo: true }; // demo deployments have no accounts server-side

  const token = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!token) throw new AiError(401, "Sign in to use the assistant.");
  const res = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anon, Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new AiError(401, "Your session has ended. Please sign in again.");
  const user = await res.json();
  return { id: user.id, email: user.email };
}
