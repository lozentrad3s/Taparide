// Checks every key in ../.env.local against its real service. Prints PASS/FAIL only, never a key.
// Usage: node scripts/check-keys.mjs
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export function loadEnv(file = join(here, '..', '..', '.env.local')) {
  const env = {};
  for (const line of readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    let v = m[2].trim();
    if (v.startsWith('#')) v = '';
    v = v.replace(/\s+#.*$/, '').replace(/^["']|["']$/g, '').trim();
    if (v) env[m[1]] = v;
  }
  return env;
}

// Only run the checks when this file is executed directly (other scripts import loadEnv).
if (process.argv[1]?.endsWith('check-keys.mjs')) await main();

async function main() {
const env = loadEnv();
const results = [];
const report = (name, ok, note = '') => results.push(`${ok === null ? 'SKIP' : ok ? 'PASS' : 'FAIL'}  ${name}${note ? ' · ' + note : ''}`);

async function check(name, key, fn) {
  if (!env[key]) return report(name, null, `${key} not set`);
  try {
    const note = await fn(env[key]);
    report(name, true, note);
  } catch (e) {
    report(name, false, String(e.message || e).slice(0, 140));
  }
}

await check('Gemini API', 'GEMINI_API_KEY', async (k) => {
  const r = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200', { headers: { 'x-goog-api-key': k } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const models = (await r.json()).models || [];
  const flash = models.filter((m) => /gemini-.*flash/.test(m.name) && (m.supportedGenerationMethods || []).includes('generateContent')).length;
  const tts = models.filter((m) => /tts/.test(m.name)).map((m) => m.name.replace('models/', ''));
  return `${models.length} models, ${flash} flash models, TTS: ${tts.slice(0, 3).join(', ') || 'none'}`;
});

await check('Anthropic API', 'ANTHROPIC_API_KEY', async (k) => {
  const r = await fetch('https://api.anthropic.com/v1/models', { headers: { 'x-api-key': k, 'anthropic-version': '2023-06-01' } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return `${((await r.json()).data || []).length} models visible`;
});

await check('CARTO basemap tiles', 'CARTO_API_KEY', async (k) => {
  const r = await fetch(`https://basemaps.cartocdn.com/rastertiles/light_all/13/4266/3889.png?key=${encodeURIComponent(k)}`);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const type = r.headers.get('content-type');
  const bytes = (await r.arrayBuffer()).byteLength;
  return `${type}, ${bytes} bytes`;
});

await check('CARTO geocoding (LDS)', 'CARTO_API_KEY', async (k) => {
  const base = (env.CARTO_API_BASE || 'https://gcp-us-east1.api.carto.com').replace(/\/$/, '');
  const r = await fetch(`${base}/v3/lds/geocoding/geocode?address=${encodeURIComponent('Jabi Lake Mall, Abuja')}&country=NG`, { headers: { Authorization: `Bearer ${k}` } });
  if (!r.ok) throw new Error(`HTTP ${r.status} (basemap-only keys can't geocode; OpenStreetMap is used instead)`);
  return 'geocoding allowed';
});

await check('Supabase REST', 'SUPABASE_URL', async (url) => {
  if (!env.SUPABASE_ANON_KEY) throw new Error('SUPABASE_ANON_KEY not set');
  const base = /^[a-z0-9]{20}$/.test(url) ? `https://${url}.supabase.co` : url.replace(/\/$/, '');
  const r = await fetch(`${base}/auth/v1/settings`, { headers: { apikey: env.SUPABASE_ANON_KEY } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const s = await r.json();
  return `auth reachable · email confirmation ${s.mailer_autoconfirm ? 'off (auto-confirm)' : 'ON'}`;
});

await check('Supabase database URL', 'SUPABASE_DB_URL', async (u) => {
  const parsed = new URL(u);
  if (!/^postgres(ql)?:$/.test(parsed.protocol)) throw new Error('not a postgres:// URL');
  return `host ${parsed.hostname.replace(/^[^.]+/, '***')}`;
});

await check('Upstash Redis', 'UPSTASH_REDIS_REST_URL', async (u) => {
  if (!env.UPSTASH_REDIS_REST_TOKEN) throw new Error('UPSTASH_REDIS_REST_TOKEN not set');
  const r = await fetch(`${u.replace(/\/$/, '')}/ping`, { headers: { Authorization: `Bearer ${env.UPSTASH_REDIS_REST_TOKEN}` } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return `answers ${(await r.json()).result}`;
});

await check('Sentry DSN', 'SENTRY_DSN', async (dsn) => {
  const u = new URL(dsn);
  if (!u.username || !/^\/?\d+$/.test(u.pathname)) throw new Error('not a Sentry DSN (https://key@oXXX.ingest.sentry.io/123)');
  return `host ${u.host.replace(/^o\d+\./, 'o***.')}`;
});

await check('MapTiler tiles', 'MAPTILER_API_KEY', async (k) => {
  const r = await fetch(`https://api.maptiler.com/maps/streets-v2/256/13/4266/3889.png?key=${encodeURIComponent(k)}`);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return `${r.headers.get('content-type')}`;
});

await check('Cloudflare Turnstile', 'TURNSTILE_SECRET_KEY', async (k) => {
  if (!env.TURNSTILE_SITE_KEY) throw new Error('TURNSTILE_SITE_KEY not set (the website needs both)');
  const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: new URLSearchParams({ secret: k, response: 'key-check' }) });
  const codes = (await r.json())['error-codes'] || [];
  if (codes.includes('invalid-input-secret')) throw new Error('secret key rejected');
  return 'secret key accepted';
});

await check('Resend email', 'RESEND_API_KEY', async (k) => {
  const r = await fetch('https://api.resend.com/domains', { headers: { Authorization: `Bearer ${k}` } });
  const restricted = r.status === 403 || (r.status === 401 && /only send emails/i.test(await r.clone().text()));
  if (restricted) {
    // Sending-only key (the right kind for the server): try a send to Resend's own test inbox.
    const s = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${k}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: 'Tap A Ride <no-reply@taparide.com>', to: ['delivered@resend.dev'], subject: 'Tap A Ride key check', text: 'Key check.' }),
    });
    if (s.ok) return 'sending-only key · taparide.com verified, test email accepted';
    const msg = (await s.json().catch(() => ({}))).message || `HTTP ${s.status}`;
    if (/not verified/i.test(msg)) throw new Error('key OK, but taparide.com is not verified in Resend > Domains yet');
    throw new Error(msg.slice(0, 120));
  }
  if (r.status === 401) throw new Error('key rejected');
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const d = ((await r.json()).data || []).find((x) => x.name === 'taparide.com');
  return d ? `taparide.com ${d.status}` : 'taparide.com NOT added in Resend > Domains yet';
});

await check('Supabase access token (local set-up)', 'SUPABASE_ACCESS_TOKEN', async (k) => {
  const ref = (env.SUPABASE_URL || '').match(/[a-z0-9]{20}/)?.[0];
  if (!ref) throw new Error('SUPABASE_URL has no project ref');
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}`, { headers: { Authorization: `Bearer ${k}` } });
  if (!r.ok) throw new Error(`HTTP ${r.status}${r.status === 401 ? ' (token rejected)' : r.status === 403 || r.status === 404 ? ' (token belongs to another account)' : ''}`);
  return `project "${(await r.json()).name}" reachable`;
});

for (const [name, key, ok] of [
  ['Daily summary recipients', 'ADMIN_NOTIFY_EMAIL', (v) => v.split(',').every((e) => /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(e.trim()))],
  ['Sender address', 'MAIL_FROM', (v) => /@taparide\.com>?\s*$/i.test(v)],
  ['Cron secret', 'CRON_SECRET', (v) => v.length >= 24],
  ['Google OAuth client', 'GOOGLE_OAUTH_CLIENT_ID', (v) => /\.apps\.googleusercontent\.com$/.test(v) && !!env.GOOGLE_OAUTH_CLIENT_SECRET],
  ['Summary webhook', 'SUMMARY_WEBHOOK_URL', (v) => /^https:\/\//.test(v)],
]) {
  if (!env[key]) report(name, null, `${key} not set`);
  else report(name, ok(env[key]), ok(env[key]) ? 'format ok' : 'check the format');
}

console.log(results.join('\n'));
}
