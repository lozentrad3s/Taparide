// Upstash Redis over its REST API (works from serverless functions, no open connections).
// Optional: set UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN in Vercel. Without them every
// helper returns null and callers fall back (in-memory limits, no cache), so nothing breaks.
// The same file lives in taparide_website/api/_lib and taparide_flutter/deploy/api/_lib.
const url = () => process.env.UPSTASH_REDIS_REST_URL?.replace(/\/$/, "");
const token = () => process.env.UPSTASH_REDIS_REST_TOKEN;
export const redisReady = () => !!(url() && token());

async function send(path, body) {
  const res = await fetch(`${url()}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(1500),
  });
  if (!res.ok) throw new Error(`Redis ${res.status}`);
  return res.json();
}

/** Fixed-window rate limit shared by every server. true = over the limit, null = Redis not available. */
export async function overLimit(key, limit, windowSeconds = 60) {
  if (!redisReady()) return null;
  try {
    const k = `rl:${key}:${Math.floor(Date.now() / 1000 / windowSeconds)}`;
    const [incr] = await send("/pipeline", [["INCR", k], ["EXPIRE", k, String(windowSeconds + 5)]]);
    return Number(incr.result) > limit;
  } catch {
    return null;
  }
}

/** Read-through cache: returns the cached JSON, or runs `load` and stores its result for `ttlSeconds`. */
export async function cached(key, ttlSeconds, load) {
  if (!redisReady()) return load();
  try {
    const { result } = await send("", ["GET", `c:${key}`]);
    if (result) return JSON.parse(result);
  } catch {}
  const value = await load();
  if (value != null) send("", ["SET", `c:${key}`, JSON.stringify(value), "EX", String(ttlSeconds)]).catch(() => {});
  return value;
}
