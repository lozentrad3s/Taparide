// Copies server-side keys from ../.env.local into Vercel (production) as sensitive variables.
// Values are passed on stdin, never on the command line, and never printed.
// Usage: node scripts/sync-vercel-env.mjs [NAME,NAME...]   (default: every allowed key that is set)
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './check-keys.mjs';

// Only what the serverless functions need. SUPABASE_DB_URL and GITHUB_TOKEN are deliberately excluded.
const ALLOWED = ['AI_PROVIDER', 'GEMINI_API_KEY', 'GEMINI_MODEL', 'ANTHROPIC_API_KEY', 'CARTO_API_KEY', 'CARTO_LDS_TOKEN', 'CARTO_GEOCODING', 'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'PAYSTACK_SECRET_KEY', 'TOPUP_SIGNING_SECRET'];
const env = loadEnv();
// Generated server-only secrets (see supabase-setup.mjs).
const serverFile = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '.env.server.local');
if (existsSync(serverFile)) Object.assign(env, loadEnv(serverFile));
// A bare project ref becomes the full API URL, as the web build does.
if (env.SUPABASE_URL && /^[a-z0-9]{20}$/.test(env.SUPABASE_URL)) env.SUPABASE_URL = `https://${env.SUPABASE_URL}.supabase.co`;
const wanted = process.argv[2] ? process.argv[2].split(',') : ALLOWED;
const scope = ['--scope', 'lozen-s-projects'];
const vercel = (args, input) => spawnSync('npx', ['vercel', ...args, ...scope], { input, encoding: 'utf8', shell: true });

for (const name of wanted) {
  if (!ALLOWED.includes(name)) {
    console.log(`SKIP  ${name} (not a server-side key)`);
    continue;
  }
  if (!env[name]) {
    console.log(`SKIP  ${name} (not set in .env.local)`);
    continue;
  }
  vercel(['env', 'rm', name, 'production', '--yes']);
  const r = vercel(['env', 'add', name, 'production', '--sensitive'], env[name]);
  console.log(`${r.status === 0 ? 'SET ' : 'FAIL'}  ${name}${r.status === 0 ? '' : ' · ' + (r.stderr || '').split('\n').find((l) => /error/i.test(l))?.slice(0, 120)}`);
}
