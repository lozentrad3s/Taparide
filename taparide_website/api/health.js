// GET /api/health — for the uptime monitor (Better Stack, UptimeRobot…). 200 when the site and the
// database answer; 503 otherwise. No personal data, no keys in the response.
export default async function handler(req, res) {
  const started = Date.now();
  let db = "not configured";
  let ok = true;
  if (process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY) {
    try {
      const r = await fetch(`${process.env.SUPABASE_URL}/rest/v1/rpc/payments_live`, {
        method: "POST",
        headers: { apikey: process.env.SUPABASE_ANON_KEY, Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
        body: "{}",
        signal: AbortSignal.timeout(4000),
      });
      db = r.ok ? "ok" : `error ${r.status}`;
      ok = r.ok;
    } catch {
      db = "unreachable";
      ok = false;
    }
  }
  res.statusCode = ok ? 200 : 503;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify({ ok, db, ms: Date.now() - started, at: new Date().toISOString() }));
}
