// Local preview with the /api routes, no Vercel login needed.
//   node scripts/dev.mjs                       website only (public/), http://localhost:8090
//   node scripts/dev.mjs --dir .output         website + /app + /dashboard (after scripts/assemble.mjs)
//   node scripts/dev.mjs --port 8091
// The app's API keys are read from ../taparide_flutter/.env.local (maps, AI). Website sign-ups go to a
// temp-folder file unless you add --live, which also passes the Supabase keys (writes to the real database).
import { createServer } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const opt = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : fallback;
};
const root = resolve(site, opt("dir", "."));
const pub = join(root, "public");
const port = Number(opt("port", 8090));
const live = process.argv.includes("--live");
const config = JSON.parse(await readFile(join(root, "vercel.json"), "utf8"));

const envFile = join(site, "..", "taparide_flutter", ".env.local");
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (!m || !m[2] || m[2].startsWith("#") || process.env[m[1]]) continue;
    if (m[1].startsWith("SUPABASE") && !live) continue;
    process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

const types = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json",
  ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".woff2": "font/woff2", ".ttf": "font/ttf", ".otf": "font/otf",
  ".txt": "text/plain; charset=utf-8", ".xml": "application/xml", ".ico": "image/x-icon", ".wasm": "application/wasm", ".webmanifest": "application/manifest+json",
};

// Vercel-style ":name" / ":name*" patterns.
function match(source, path) {
  const keys = [];
  const re = new RegExp("^" + source.replace(/:(\w+)\*/g, (_, k) => (keys.push(k), "(.*)")).replace(/:(\w+)/g, (_, k) => (keys.push(k), "([^/]+)")) + "$");
  const m = path.match(re);
  return m ? Object.fromEntries(keys.map((k, i) => [k, m[i + 1]])) : null;
}
const fill = (dest, params) => Object.entries(params).reduce((d, [k, v]) => d.replaceAll(`:${k}*`, v).replaceAll(`:${k}`, v), dest);

async function file(path) {
  const candidates = path.endsWith("/") ? [path + "index.html"] : [path, path + ".html", path + "/index.html"];
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
  let url = new URL(req.url, `http://localhost:${port}`);
  try {
    for (const r of config.redirects || []) {
      if (r.has) continue; // host-based rules only apply on the real domains
      const p = match(r.source, url.pathname);
      if (p) {
        res.writeHead(307, { Location: fill(r.destination, p) });
        return res.end();
      }
    }
    for (const r of config.rewrites || []) {
      const p = match(r.source, url.pathname);
      if (p && !r.destination.startsWith("http")) {
        url = new URL(fill(r.destination, p), url);
        req.url = url.pathname + url.search;
        break;
      }
    }
    if (url.pathname.startsWith("/api/")) {
      const fn = join(root, "api", url.pathname.slice(5).replace(/\/$/, "") + ".js");
      if (!existsSync(fn)) {
        res.writeHead(404, { "Content-Type": types[".json"] });
        return res.end(JSON.stringify({ error: "No such API route on this preview." }));
      }
      const mod = await import(pathToFileURL(fn).href);
      if (!req.query) req.query = Object.fromEntries(url.searchParams);
      return await mod.default(req, res);
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
    if (!res.headersSent) res.writeHead(500);
    res.end("Server error");
  }
}).listen(port, () => console.log(`Tap A Ride preview: http://localhost:${port}  (serving ${pub})`));
