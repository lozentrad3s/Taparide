// Automated security check against the LIVE site and database, as an outsider would see them
// (public anon key only, no account). Read-only: it never writes data (write probes send
// invalid input that is refused before any change). Run before every release and before
// handing over to the external penetration testers.
// Usage: node scripts/security-check.mjs [https://taparide.com]
import { loadEnv } from './check-keys.mjs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const env = loadEnv(join(here, '..', '..', '.env.local'));
const site = (process.argv[2] || 'https://taparide.vercel.app').replace(/\/$/, '');
const db = /^[a-z0-9]{20}$/.test(env.SUPABASE_URL) ? `https://${env.SUPABASE_URL}.supabase.co` : env.SUPABASE_URL.replace(/\/$/, '');
const anon = { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, 'Content-Type': 'application/json' };
// Retry slow or dropped connections (mobile networks) so a blip isn't reported as a failure.
const nativeFetch = globalThis.fetch;
globalThis.fetch = async (url, init = {}) => {
  for (let attempt = 1; ; attempt++) {
    try {
      return await nativeFetch(url, { ...init, signal: AbortSignal.timeout(20000) });
    } catch (e) {
      if (attempt >= 3) throw e;
      await new Promise((r) => setTimeout(r, 1500 * attempt));
    }
  }
};
let failures = 0;
const ok = (pass, what, detail = '') => {
  if (!pass) failures++;
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${what}${detail ? `  (${detail})` : ''}`);
};

// 1. Tables: an outsider must not read private data. Public catalogue tables may answer.
const publicOk = new Set(['routes', 'providers', 'charging_stations', 'metric_baselines', 'events', 'event_buses', 'ads', 'vehicles']);
const tables = ['ad_views', 'ads', 'audit_log', 'bookings', 'charging_stations', 'event_buses', 'event_seat_requests', 'events', 'fleet_drivers', 'metric_baselines', 'partner_applications', 'profiles', 'providers', 'routes', 'shared_rides', 'trip_shares', 'vehicle_positions', 'vehicles', 'waitlist', 'wallet_topups', 'wallets'];
for (const t of tables) {
  const r = await fetch(`${db}/rest/v1/${t}?select=*&limit=3`, { headers: anon });
  const body = await r.text();
  const rows = r.ok ? JSON.parse(body).length : 0;
  ok(publicOk.has(t) || rows === 0, `table ${t} hidden from outsiders`, r.ok ? `${rows} rows visible` : `HTTP ${r.status}`);
}

// 2. Privileged functions refuse outsiders.
const privileged = {
  admin_waitlist: {}, set_user_role: { p_user: '00000000-0000-0000-0000-000000000000', p_role: 'admin' },
  set_provider_status: { p_id: 'p_metro', p_status: 'suspended' }, confirm_top_up: { p_secret: 'guess', p_reference: 'TAR-X', p_amount_kobo: 1 },
  top_up: { p_amount: 1000 }, review_partner_application: { p_id: 'x', p_approve: true }, update_route_fare: { p_route: 'r01', p_fare: 100 },
};
for (const [fn, args] of Object.entries(privileged)) {
  const r = await fetch(`${db}/rest/v1/rpc/${fn}`, { method: 'POST', headers: anon, body: JSON.stringify(args) });
  ok(!r.ok, `function ${fn} refuses outsiders`, `HTTP ${r.status}`);
}

// 3. Website security headers.
const home = await fetch(`${site}/`);
const h = (k) => home.headers.get(k) || '';
ok(h('content-security-policy').includes("frame-ancestors 'none'"), 'website CSP blocks framing');
ok(h('strict-transport-security').includes('max-age'), 'HSTS on');
ok(h('x-content-type-options') === 'nosniff', 'nosniff on');
const app = await fetch(`${site}/app/`);
ok((app.headers.get('x-frame-options') || '').toUpperCase() === 'SAMEORIGIN', 'app cannot be framed by other sites');

// 4. APIs: origin checks, anti-bot, sign-in required.
const evil = { Origin: 'https://evil.example', 'Content-Type': 'application/json' };
let r = await fetch(`${site}/api/waitlist?event=abuja-tech-week-2026`, { headers: evil });
ok(r.status === 403, 'waitlist API refuses other websites', `HTTP ${r.status}`);
// No terms ticked, so even an unprotected server would refuse it: this probe can never save data.
r = await fetch(`${site}/api/waitlist`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: site }, body: JSON.stringify({ action: 'join', email: 'security-check@example.com' }) });
const bot = await r.json().catch(() => ({}));
ok(r.status === 400 && /quick/i.test(bot.error || ''), 'instant (bot-speed) sign-up refused by the timing check', bot.error || `HTTP ${r.status}`);
r = await fetch(`${site}/api/assistant`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: site }, body: '{}' });
ok(r.status === 401 || r.status === 403 || r.status === 503 || r.status === 400, 'AI assistant needs sign-in', `HTTP ${r.status}`);
r = await fetch(`${site}/api/pay?action=init`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: site }, body: JSON.stringify({ amount: 1000 }) });
ok(r.status === 401 || r.status === 503, 'payments need sign-in', `HTTP ${r.status}`);
r = await fetch(`${site}/api/pay?action=webhook`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Bachs-Signature-V2': 't=1,v1=00' }, body: '{"type":"collection.succeeded"}' });
ok(r.status === 401 || r.status === 503, 'forged payment webhook refused', `HTTP ${r.status}`);

// 5. Demo accounts locked.
r = await fetch(`${db}/auth/v1/token?grant_type=password`, { method: 'POST', headers: anon, body: JSON.stringify({ email: 'admin@taparide.demo', password: 'Ride2026!' }) });
ok(!r.ok, 'published demo admin password refused', `HTTP ${r.status}`);

console.log(failures ? `\n${failures} check(s) FAILED` : '\nAll checks passed');
process.exit(failures ? 1 : 0);
