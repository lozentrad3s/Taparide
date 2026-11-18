// Puts the website, the rider app and the dashboards together into one deployable folder:
//
//   .output/public/            website (this folder's public/)
//   .output/public/app/        rider app        -> taparide.com/app
//   .output/public/dashboard/  partner, FCTA and admin dashboards -> taparide.com/dashboard
//   .output/api/               website API + the app's API (maps, search, AI, payments)
//
// The website and the app stay in their own folders; only this output joins them.
// Usage (from taparide_website):
//   node scripts/assemble.mjs              build both Flutter apps, then assemble
//   node scripts/assemble.mjs --no-build   reuse the last Flutter builds
// Preview:  node scripts/dev.mjs --dir .output
// Deploy:   cd .output && npx vercel deploy --prod   (project linked from ../taparide_flutter/deploy/.vercel)
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const flutter = join(site, "..", "taparide_flutter");
const appDeploy = join(flutter, "deploy");
const out = join(site, ".output");
const builds = join(site, ".builds");
const skipBuild = process.argv.includes("--no-build");

function build(target) {
  const dest = join(builds, target);
  if (skipBuild && existsSync(join(dest, "index.html"))) return dest;
  console.log(`Building the ${target} app…`);
  const r = spawnSync(process.execPath, [join(appDeploy, "scripts", "build-web.mjs"), `--target=${target}`, `--out=${dest}`], { cwd: appDeploy, stdio: "inherit" });
  if (r.status !== 0) process.exit(r.status ?? 1);
  return dest;
}

const rider = build("rider");
const dashboard = build("dashboard");

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
cpSync(join(site, "public"), join(out, "public"), { recursive: true });
cpSync(rider, join(out, "public", "app"), { recursive: true });
cpSync(dashboard, join(out, "public", "dashboard"), { recursive: true });
for (const dir of [join(out, "public", "app"), join(out, "public", "dashboard")]) rmSync(join(dir, "_phone.html"), { force: true });

// API: the app's functions first, then the website's (both keep their _lib helpers).
cpSync(join(appDeploy, "api"), join(out, "api"), { recursive: true });
cpSync(join(site, "api"), join(out, "api"), { recursive: true });

cpSync(join(site, "vercel.json"), join(out, "vercel.json"));
const appPkg = JSON.parse(readFileSync(join(appDeploy, "package.json"), "utf8"));
writeFileSync(join(out, "package.json"), JSON.stringify({
  name: "taparide",
  private: true,
  type: "module",
  engines: { node: ">=20" },
  dependencies: appPkg.dependencies || {},
}, null, 2) + "\n");
// Deploy to the same Vercel project as before, so its environment variables (Supabase, AI, maps) carry over.
if (existsSync(join(appDeploy, ".vercel"))) cpSync(join(appDeploy, ".vercel"), join(out, ".vercel"), { recursive: true });
if (existsSync(join(appDeploy, "node_modules"))) cpSync(join(appDeploy, "node_modules"), join(out, "node_modules"), { recursive: true });

console.log(`Assembled ${out}\n  website  /\n  app      /app\n  dashboards /dashboard`);
