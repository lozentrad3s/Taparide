// GET /api/tiles/{z}/{x}/{y}[@2x].png — map tiles for the app.
// MapTiler (MAPTILER_API_KEY, style MAPTILER_STYLE, default streets-v2) first, then CARTO basemaps
// (CARTO_API_KEY), then OpenStreetMap. Keys stay on the server. Cached at the edge for a month.
// Only serves the region around Abuja (and low zooms), so it can't be used as a free tile server.

const UA = "TapARide/1.0 (+https://taparide.vercel.app)";

function tileToLng(x, z) {
  return (x / 2 ** z) * 360 - 180;
}
function tileToLat(y, z) {
  const n = Math.PI - (2 * Math.PI * y) / 2 ** z;
  return (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
}
// Nigeria's FCT and surroundings.
function allowed(z, x, y) {
  if (z <= 7) return true;
  const west = tileToLng(x, z), east = tileToLng(x + 1, z);
  const north = tileToLat(y, z), south = tileToLat(y + 1, z);
  return east > 6.3 && west < 8.3 && north > 8.0 && south < 10.0;
}

async function get(url) {
  try {
    const r = await fetch(url, { headers: { "User-Agent": UA } });
    return r.ok ? Buffer.from(await r.arrayBuffer()) : null;
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  const q = new URL(req.url, "http://x").searchParams;
  const z = Number.parseInt(q.get("z"), 10);
  const x = Number.parseInt(q.get("x"), 10);
  const m = /^(\d+)(@2x)?\.png$/.exec(q.get("f") || "");
  const y = m ? Number.parseInt(m[1], 10) : NaN;
  const max = 2 ** z;
  if (!m || !(z >= 0 && z <= 19) || !(x >= 0 && x < max) || !(y >= 0 && y < max)) {
    res.statusCode = 400;
    return res.end("Bad tile");
  }
  if (!allowed(z, x, y)) {
    res.statusCode = 404;
    return res.end("Outside service area");
  }

  const key = process.env.CARTO_API_KEY;
  const maptiler = process.env.MAPTILER_API_KEY;
  let source = "osm";
  let body = null;
  if (maptiler) {
    const style = process.env.MAPTILER_STYLE || "streets-v2";
    body = await get(`https://api.maptiler.com/maps/${style}/256/${z}/${x}/${y}${m[2] || ""}.png?key=${encodeURIComponent(maptiler)}`);
    if (body) source = "maptiler";
  }
  if (!body && key) {
    const style = process.env.CARTO_BASEMAP_STYLE || "light_all";
    body = await get(`https://basemaps.cartocdn.com/rastertiles/${style}/${z}/${x}/${y}${m[2] || ""}.png?key=${encodeURIComponent(key)}`);
    if (body) source = "carto";
  }
  if (!body) body = await get(`https://tile.openstreetmap.org/${z}/${x}/${y}.png`);
  if (!body) {
    res.statusCode = 502;
    return res.end("Tile unavailable");
  }
  res.statusCode = 200;
  res.setHeader("Content-Type", "image/png");
  res.setHeader("X-Tile-Source", source);
  res.setHeader("Cache-Control", "public, max-age=86400, s-maxage=2592000, stale-while-revalidate=604800");
  res.end(body);
}
