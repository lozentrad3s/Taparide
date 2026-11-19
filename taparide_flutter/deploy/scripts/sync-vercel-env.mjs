// Copies server-side keys from ../.env.local into Vercel (production) as sensitive variables.
// Values are passed on stdin, never on the command line, and never printed.
// Usage: node scripts/sync-vercel-env.mjs [NAME,NAME...]   (default: every allowed key that is set)
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './check-keys.mjs';

// Only what the serverless functions need. Empty values in .env.local count as not set and are skipped.
const ALLOWED = ['AI_PROVIDER', 'GEMINI_API_KEY', 'GEMINI_MODEL', 'ANTHROPIC_API_KEY', 'CARTO_API_KEY', 'CARTO_LDS_TOKEN', 'CARTO_GEOCODING', 'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'PAYSTACK_SECRET_KEY', 'TOPUP_SIGNING_SECRET', 'BACHS_SECRET_KEY', 'BACHS_WEBHOOK_SECRET', 'MAPTILER_API_KEY', 'MAPTILER_STYLE', 'UPSTASH_REDIS_REST_URL', 'UPSTASH_REDIS_REST_TOKEN', 'SENTRY_DSN', 'TURNSTILE_SECRET_KEY', 'TURNSTILE_SITE_KEY', 'RESEND_API_KEY', 'MAIL_FROM', 'ADMIN_NOTIFY_EMAIL', 'SUMMARY_WEBHOOK_URL', 'CRON_SECRET'];
// Never synced: SUPABASE_DB_URL, SUPABASE_ACCESS_TOKEN, GOOGLE_OAUTH_* (local set-up only) and GITHUB_TOKEN.
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
