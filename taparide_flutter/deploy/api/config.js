// GET /api/config — which services are switched on (never the keys themselves).
// The app uses it for the map credit line and to show whether AI is live.
import { provider, send } from "./_lib/ai.js";

export default function handler(req, res) {
  const ai = provider();
  const aiReady = (ai === "gemini" && !!process.env.GEMINI_API_KEY) || (ai === "anthropic" && !!process.env.ANTHROPIC_API_KEY);
  send(res, 200, {
    tiles: process.env.MAPTILER_API_KEY ? "maptiler" : process.env.CARTO_API_KEY ? "carto" : "osm",
    geocoder: process.env.MAPTILER_API_KEY ? "maptiler" : process.env.CARTO_LDS_TOKEN || process.env.CARTO_GEOCODING === "true" ? "carto" : "osm",
    ai: aiReady ? ai : null,
    aiFallback: ai === "gemini" ? !!process.env.ANTHROPIC_API_KEY : !!process.env.GEMINI_API_KEY,
    backend: process.env.SUPABASE_URL ? "supabase" : "demo",
    redis: !!(process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN),
    // "paystack" once card and bank top-ups are switched on; until then wallet money is test money.
    payments: process.env.PAYSTACK_SECRET_KEY && process.env.TOPUP_SIGNING_SECRET ? "paystack" : "test",
  });
}
