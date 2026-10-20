// GET /api/config — which services are switched on (never the keys themselves).
// The app uses it for the map credit line and to show whether AI is live.
import { provider, send } from "./_lib/ai.js";

export default function handler(req, res) {
  const ai = provider();
  const aiReady = (ai === "gemini" && !!process.env.GEMINI_API_KEY) || (ai === "anthropic" && !!process.env.ANTHROPIC_API_KEY);
  send(res, 200, {
    tiles: process.env.CARTO_API_KEY ? "carto" : "osm",
    geocoder: process.env.CARTO_API_KEY ? "carto" : "osm",
    ai: aiReady ? ai : null,
    aiFallback: ai === "gemini" ? !!process.env.ANTHROPIC_API_KEY : !!process.env.GEMINI_API_KEY,
    backend: process.env.SUPABASE_URL ? "supabase" : "demo",
  });
}
