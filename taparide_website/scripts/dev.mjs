// Local preview of the website with its /api routes, no Vercel login needed.
// Usage (from taparide_website): node scripts/dev.mjs [port]   -> http://localhost:8090
// Waitlist sign-ups go to a temp-folder file unless SUPABASE_URL / SUPABASE_ANON_KEY are set.
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const pub = join(root, "public");
const port = Number(process.argv[2] || 8090);
const config = JSON.parse(await readFile(join(root, "vercel.json"), "utf8"));
const types = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".json": "application/json",
  ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".woff2": "font/woff2",
  ".txt": "text/plain; charset=utf-8", ".xml": "application/xml", ".ico": "image/x-icon", ".webmanifest": "application/manifest+json",
};

function redirectFor(path) {
  for (const r of config.redirects || []) {
    const keys = [];
    const re = new RegExp("^" + r.source.replace(/:(\w+)/g, (_, k) => (keys.push(k), "([^/]+)")) + "$");
    const m = path.match(re);
    if (m) return keys.reduce((d, k, i) => d.replaceAll(`:${k}`, m[i + 1]), r.destination);
  }
  return null;
}

async function file(path) {
  const candidates = path.endsWith("/") ? [path + "index.html"] : [path, path + ".html"];
  for (const c of candidates) {
    const full = normalize(join(pub, c));
    if (!full.startsWith(pub)) return null;
    try {
      if ((await stat(full)).isFile()) return full;
    } catch {}
  }
  return null;
}

createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);
  try {
    if (url.pathname.startsWith("/api/")) {
      const mod = await import(pathToFileURL(join(root, url.pathname + ".js")).href);
      return await mod.default(req, res);
    }
    const to = redirectFor(url.pathname);
    if (to) {
      res.writeHead(307, { Location: to.startsWith("http") ? to : to + (url.search && !to.includes("?") ? url.search : "") });
      return res.end();
    }
    const found = await file(decodeURIComponent(url.pathname));
    if (!found) {
      res.writeHead(404, { "Content-Type": types[".html"] });
      return res.end(await readFile(join(pub, "404.html")));
    }
    res.writeHead(200, { "Content-Type": types[extname(found)] || "application/octet-stream", "Cache-Control": "no-cache" });
    res.end(await readFile(found));
  } catch (e) {
    console.error(e);
    res.writeHead(500);
    res.end("Server error");
  }
}).listen(port, () => console.log(`Tap A Ride website: http://localhost:${port}`));
