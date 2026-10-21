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
  const r = await fetch(`${url.replace(/\/$/, '')}/auth/v1/settings`, { headers: { apikey: env.SUPABASE_ANON_KEY } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const s = await r.json();
  return `auth reachable · email confirmation ${s.mailer_autoconfirm ? 'off (auto-confirm)' : 'ON'}`;
});

await check('Supabase database URL', 'SUPABASE_DB_URL', async (u) => {
  const parsed = new URL(u);
  if (!/^postgres(ql)?:$/.test(parsed.protocol)) throw new Error('not a postgres:// URL');
  return `host ${parsed.hostname.replace(/^[^.]+/, '***')}`;
});

console.log(results.join('\n'));
}
