// GET /api/geocode?q=… — turns a place name into coordinates inside the FCT.
// CARTO Location Data Services when CARTO_API_KEY is set; OpenStreetMap Nominatim otherwise.
// The key stays on the server.
import { AiError, handleError, send } from "./_lib/ai.js";
import { requireUser } from "./_lib/auth.js";

// Federal Capital Territory bounds (lon/lat).
const FCT = { minLat: 8.4, maxLat: 9.45, minLng: 6.75, maxLng: 7.65 };
const inFct = (p) => p.lat >= FCT.minLat && p.lat <= FCT.maxLat && p.lng >= FCT.minLng && p.lng <= FCT.maxLng;

/** Finds every {latitude, longitude} pair in a provider response, whatever its nesting. */
function collect(node, out = []) {
  if (!node || typeof node !== "object") return out;
  const lat = node.latitude ?? node.lat;
  const lng = node.longitude ?? node.lng ?? node.lon;
  if (typeof lat === "number" && typeof lng === "number") {
    out.push({ lat, lng, name: node.formattedAddress || node.formatted_address || node.label || node.display_name || null });
  }
  for (const v of Array.isArray(node) ? node : Object.values(node)) if (v && typeof v === "object") collect(v, out);
  return out;
}

async function carto(q) {
  const key = process.env.CARTO_API_KEY;
  if (!key) return null;
  const base = (process.env.CARTO_API_BASE || "https://gcp-us-east1.api.carto.com").replace(/\/$/, "");
  const url = `${base}/v3/lds/geocoding/geocode?address=${encodeURIComponent(`${q}, Abuja`)}&country=NG&limit=5`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${key}` } });
  if (res.status === 401 || res.status === 403) throw new AiError(503, "The CARTO API key was refused.");
  if (!res.ok) return null;
  return collect(await res.json()).map((p) => ({ ...p, source: "carto" }));
}

async function nominatim(q) {
  const box = `${FCT.minLng},${FCT.maxLat},${FCT.maxLng},${FCT.minLat}`;
  const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=5&countrycodes=ng&bounded=1&viewbox=${box}&q=${encodeURIComponent(q)}`;
  const res = await fetch(url, { headers: { "User-Agent": "TapARide/1.0 (taparide.vercel.app)", "Accept-Language": "en" } });
  if (!res.ok) return [];
  const rows = await res.json();
  return rows.map((r) => ({ lat: Number(r.lat), lng: Number(r.lon), name: r.display_name, source: "osm" }));
}

export default async function handler(req, res) {
  if (req.method !== "GET") return send(res, 405, { error: "Use GET." });
  try {
    await requireUser(req, { perMinute: 30 });
    const q = String(new URL(req.url, "http://x").searchParams.get("q") || "").trim().slice(0, 120);
    if (q.length < 2) throw new AiError(400, "Enter a place name.");
    let results = null;
    try {
      results = await carto(q);
    } catch (e) {
      if (e instanceof AiError && e.status !== 503) throw e;
    }
    if (!results || results.length === 0) results = await nominatim(q);
    results = results.filter(inFct).map((r) => ({ ...r, name: (r.name || q).split(",").slice(0, 3).join(",").trim() }));
    send(res, 200, { results: results.slice(0, 5) });
  } catch (error) {
    handleError(res, error);
  }
}
