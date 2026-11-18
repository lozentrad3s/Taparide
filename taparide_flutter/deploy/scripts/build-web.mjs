// Builds the Flutter web app into deploy/public.
// - Creates a private master-admin password in ../.env.local the first time (never printed).
// - Passes only a salted SHA-256 hash of it to the app, plus the public Supabase URL/anon key if set.
// - Serves CanvasKit from our own domain (--no-web-resources-cdn).
// Usage: node scripts/build-web.mjs                       -> whole app at /, into deploy/public (standalone site)
//        node scripts/build-web.mjs --target=rider --out=DIR      -> rider app for taparide.com/app
//        node scripts/build-web.mjs --target=dashboard --out=DIR  -> dashboards for taparide.com/dashboard
import { createHash, randomBytes } from 'node:crypto';
import { cpSync, existsSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './check-keys.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const arg = (name) => process.argv.find((a) => a.startsWith(`--${name}=`))?.split('=').slice(1).join('=');
const target = arg('target') || 'all';
if (!['all', 'rider', 'dashboard'].includes(target)) throw new Error(`Unknown --target=${target}`);
const baseHref = { all: '/', rider: '/app/', dashboard: '/dashboard/' }[target];
const app = join(here, '..', '..');
// Master admin credentials live in their own git-ignored file so editing .env.local can't lose them.
const masterFile = join(app, '.env.master.local');
const env = loadEnv(join(app, '.env.local'));
let master = existsSync(masterFile) ? loadEnv(masterFile) : {};

if (!master.MASTER_ADMIN_EMAIL || !master.MASTER_ADMIN_PASSWORD) {
  const lines = ['# Master admin (private). Sign in on the Partner portal with these. Never share or commit.'];
  lines.push(`MASTER_ADMIN_EMAIL=${master.MASTER_ADMIN_EMAIL || 'master@taparide.app'}`);
  lines.push(`MASTER_ADMIN_PASSWORD=${master.MASTER_ADMIN_PASSWORD || randomBytes(18).toString('base64url')}`);
  writeFileSync(masterFile, lines.join('\n') + '\n');
  master = loadEnv(masterFile);
  console.log('Created master admin credentials in .env.master.local (open the file to read them).');
}

// Supabase goes live only when the URL is valid AND the schema has been migrated; otherwise demo data.
const supabaseUrl = (v) => (!v ? '' : /^[a-z0-9]{20}$/.test(v) ? `https://${v}.supabase.co` : v.replace(/\/$/, ''));
let live = false;
const sbUrl = supabaseUrl(env.SUPABASE_URL);
if (sbUrl && env.SUPABASE_ANON_KEY) {
  try {
    const r = await fetch(`${sbUrl}/rest/v1/providers?select=id&limit=1`, { headers: { apikey: env.SUPABASE_ANON_KEY } });
    live = r.ok;
    if (!live) console.log(`Supabase reachable but not ready (HTTP ${r.status}); run the migrations first. Building with demo data.`);
  } catch {
    console.log('Supabase URL is not reachable; building with demo data.');
  }
}

const salt = randomBytes(12).toString('base64url');
const hash = createHash('sha256').update(`${salt}:${master.MASTER_ADMIN_PASSWORD}`).digest('hex');
const defines = {
  MASTER_ADMIN_EMAIL: master.MASTER_ADMIN_EMAIL,
  MASTER_ADMIN_NAME: master.MASTER_ADMIN_NAME || 'Platform owner',
  MASTER_ADMIN_SALT: salt,
  MASTER_ADMIN_HASH: hash,
  // Public by design (Supabase row-level security protects the data):
  ...(live ? { SUPABASE_URL: sbUrl, SUPABASE_ANON_KEY: env.SUPABASE_ANON_KEY } : {}),
  ...(target === 'all' ? {} : { APP_MODE: target }),
  // Live builds never show the demo sign-in shortcuts (those accounts are locked on the live database).
  ...(live && !process.env.SHOW_DEMO_ACCOUNTS ? { HIDE_DEMO_ACCOUNTS: 'true' } : {}),
};

const flutter = process.env.FLUTTER || 'C:/src/flutter/bin/flutter.bat';
const args = ['build', 'web', '--release', '--no-wasm-dry-run', '--no-web-resources-cdn', `--base-href=${baseHref}`, ...Object.entries(defines).map(([k, v]) => `"--dart-define=${k}=${v}"`)];
const r = spawnSync(flutter, args, { cwd: app, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', shell: true });
const tail = (r.stdout + r.stderr).trim().split('\n').slice(-2).join('\n');
if (r.status !== 0) {
  console.error('Build failed:\n' + tail);
  process.exit(1);
}
const out = arg('out');
const pub = out ? (out.match(/^[A-Za-z]:|^\//) ? out : join(process.cwd(), out)) : join(here, '..', 'public');
rmSync(pub, { recursive: true, force: true });
cpSync(join(app, 'build', 'web'), pub, { recursive: true });
rmSync(join(pub, '_phone.html'), { force: true });
console.log(`Built ${target} web app (base ${baseHref}) → ${pub} (master admin: ${master.MASTER_ADMIN_EMAIL}; Supabase: ${defines.SUPABASE_URL ? 'live' : 'demo data'})`);
