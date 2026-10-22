// Sets up the live Supabase database: schema, security rules, demo data and sign-in accounts.
// Safe to re-run: migrations are tracked, data and accounts are only added if missing.
// Reads ../.env.local (SUPABASE_DB_URL) and ../.env.master.local (master admin). Prints no secrets.
// Usage: node scripts/supabase-setup.mjs
import pg from 'pg';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './check-keys.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '..', '..');
const env = loadEnv(join(app, '.env.local'));
const masterFile = join(app, '.env.master.local');
const master = existsSync(masterFile) ? loadEnv(masterFile) : {};
if (!env.SUPABASE_DB_URL) throw new Error('SUPABASE_DB_URL is not set');

// The direct db.<ref>.supabase.co host is IPv6-only; use the IPv4 session pooler with the same password.
const direct = new URL(env.SUPABASE_DB_URL);
const ref = direct.hostname.startsWith('db.') ? direct.hostname.split('.')[1] : decodeURIComponent(direct.username).split('.')[1];
const poolerHost = env.SUPABASE_POOLER_HOST || 'aws-0-eu-west-1.pooler.supabase.com';
const client = new pg.Client({
  host: direct.hostname.includes('pooler') ? direct.hostname : poolerHost,
  port: 5432,
  user: direct.hostname.includes('pooler') ? decodeURIComponent(direct.username) : `postgres.${ref}`,
  password: decodeURIComponent(direct.password),
  database: 'postgres',
  ssl: { rejectUnauthorized: false },
});
await client.connect();
const q = (sql, params) => client.query(sql, params);
const log = (...a) => console.log(...a);

// ---------------------------------------------------------------- migrations
await q('create schema if not exists taparide_meta');
await q('create table if not exists taparide_meta.migrations (name text primary key, applied_at timestamptz not null default now())');
const dir = join(app, 'supabase', 'migrations');
for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
  const done = await q('select 1 from taparide_meta.migrations where name = $1', [file]);
  if (done.rowCount) continue;
  await q('begin');
  try {
    await q(readFileSync(join(dir, file), 'utf8'));
    await q('insert into taparide_meta.migrations (name) values ($1)', [file]);
    await q('commit');
    log('migrated', file);
  } catch (e) {
    await q('rollback');
    throw new Error(`${file}: ${e.message}`);
  }
}

// ---------------------------------------------------------------- base demo data
if (!(await q('select 1 from public.providers limit 1')).rowCount) {
  await q('begin');
  try {
    await q(readFileSync(join(app, 'supabase', 'seed.sql'), 'utf8'));
    await q('commit');
    log('seeded base data');
  } catch (e) {
    await q('rollback');
    throw new Error(`seed.sql: ${e.message}`);
  }
}

// ---------------------------------------------------------------- sign-in accounts
const DEMO_PASSWORD = 'Ride2026!';
const accounts = [
  { key: 'aisha', email: 'aisha@taparide.demo', name: 'Aisha Bello', phone: '+234 803 000 1122', org: 'Federal Secretariat', role: 'passenger' },
  { key: 'emeka', email: 'emeka@taparide.demo', name: 'Emeka Nwosu', org: 'Banex Plaza offices', role: 'passenger' },
  { key: 'zainab', email: 'zainab@taparide.demo', name: 'Zainab Yusuf', org: 'Jabi tech hub', role: 'passenger' },
  { key: 'musa', email: 'musa@taparide.demo', name: 'Musa Abdullahi', phone: '+234 803 555 0101', role: 'passenger' },
  { key: 'ngozi', email: 'ngozi@capitalcabs.demo', name: 'Ngozi Eze', phone: '+234 802 555 0202', org: 'Capital City Cabs Ltd', role: 'passenger' },
  { key: 'ops', email: 'ops@abujametro.demo', name: 'Ibrahim Musa', phone: '+234 809 000 3344', role: 'operator', provider: 'p_metro' },
  { key: 'fleet', email: 'fleet@greenfleet.demo', name: 'Chiamaka Obi', phone: '+234 812 000 5566', role: 'fleet_owner', provider: 'p_greenfleet' },
  { key: 'ev', email: 'ev@naviride.demo', name: 'Tunde Bello', phone: '+234 815 000 7788', role: 'operator', provider: 'p_naviride' },
  { key: 'fcta', email: 'transport@fcta.demo', name: 'Fatima Lawal', phone: '+234 806 000 9900', org: 'FCTA Transport Secretariat', role: 'government' },
  { key: 'grace', email: 'grace@taparide.demo', name: 'Grace Okafor', phone: '+234 805 555 0404', role: 'operator', provider: 'p_grace' },
  // Shared demo admin; the protect_admins migration stops it from touching admin accounts.
  { key: 'daniel', email: 'admin@taparide.demo', name: 'Daniel Adeyemi', phone: '+234 701 000 3434', role: 'admin' },
];
if (master.MASTER_ADMIN_EMAIL && master.MASTER_ADMIN_PASSWORD) {
  accounts.push({ key: 'master', email: master.MASTER_ADMIN_EMAIL, name: master.MASTER_ADMIN_NAME || 'Platform owner', role: 'admin', password: master.MASTER_ADMIN_PASSWORD });
}

// Grace (approved private driver) must exist before her profile points at it.
await q(`insert into public.providers (id, name, kind, status, area, contact_name, contact_email, joined_at, description)
  values ('p_grace', 'Grace Okafor', 'private_driver', 'verified', 'Wuse 2', 'Grace Okafor', 'grace@taparide.demo', '2026-09-28', 'Private driver approved through partner registration (Toyota Camry).')
  on conflict (id) do nothing`);
await q(`insert into public.vehicles (id, operator_id, plate, kind, model, capacity, status, verification, area, month_earnings, base_fare, per_km_fare, driver_name)
  values ('v_grace_car', 'p_grace', 'ABJ 552 TR', 'car', 'Toyota Camry', 4, 'on_trip', 'verified', 'Wuse 2', 186500, 1000, 150, 'Grace Okafor')
  on conflict (id) do nothing`);

const ids = {};
for (const a of accounts) {
  const found = await q('select id from auth.users where lower(email) = lower($1)', [a.email]);
  if (found.rowCount) {
    ids[a.key] = found.rows[0].id;
    if (a.password) await q(`update auth.users set encrypted_password = extensions.crypt($2, extensions.gen_salt('bf')) where id = $1`, [ids[a.key], a.password]);
  } else {
    const meta = { full_name: a.name, phone: a.phone || null, organisation: a.org || null };
    const r = await q(
      `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                               created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
       values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', $1,
               extensions.crypt($2, extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', $3, now(), now(), '', '', '', '')
       returning id`,
      [a.email, a.password || DEMO_PASSWORD, meta],
    );
    ids[a.key] = r.rows[0].id;
    log('created account', a.password ? '(master admin)' : a.email);
  }
  // Email sign-in needs an identity row too (added if missing, e.g. after an interrupted run).
  await q(
    `insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
     select gen_random_uuid(), $1::uuid, $2::text, jsonb_build_object('sub', $2::text, 'email', $3::text, 'email_verified', true), 'email', now(), now(), now()
     where not exists (select 1 from auth.identities where user_id = $1::uuid and provider = 'email')`,
    [ids[a.key], String(ids[a.key]), a.email],
  );
  await q('update public.profiles set role = $2, provider_id = $3, verified = true where id = $1', [ids[a.key], a.role, a.provider || null]);
}

// ---------------------------------------------------------------- live activity (bookings, rides, applications)
if (!(await q('select 1 from public.bookings limit 1')).rowCount) {
  const day = (d, h, m) => `(date_trunc('day', now()) - interval '${d} days' + interval '${h} hours ${m} minutes')`;
  const transit = [
    ['aisha', 'Aisha Bello', 'r01', 'Wuse', 'Maitama', day(1, 8, 0), 500, 'v_abj021', 'completed', 'S08', 'p_metro'],
    ['aisha', 'Aisha Bello', 'r01', 'Wuse', 'Maitama', day(2, 8, 0), 500, 'v_abj021', 'completed', 'S05', 'p_metro'],
    ['aisha', 'Aisha Bello', 'r01', 'Wuse', 'Maitama', day(4, 8, 0), 500, 'v_abj021', 'completed', 'S11', 'p_metro'],
    ['aisha', 'Aisha Bello', 'r02', 'Central Area', 'Gwarinpa', day(3, 17, 45), 700, 'v_abj015', 'completed', 'S21', 'p_metro'],
    ['aisha', 'Aisha Bello', 'r02', 'Central Area', 'Gwarinpa', day(8, 17, 45), 700, 'v_abj015', 'completed', 'S02', 'p_metro'],
    ['emeka', 'Emeka Nwosu', 'r01', 'Wuse', 'Maitama', day(0, 8, 0), 500, 'v_abj021', 'confirmed', 'S14', 'p_metro'],
    ['zainab', 'Zainab Yusuf', 'r02', 'Central Area', 'Gwarinpa', day(0, 7, 45), 700, 'v_abj015', 'confirmed', 'S03', 'p_metro'],
  ];
  for (const [who, name, route, from, to, at, fare, vehicle, status, seat, provider] of transit) {
    await q(
      `insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare, payment_method, ticket_code, created_at, seat, route_id, vehicle_id, provider_id)
       values ($1, $2, 'transit', $3, $4, $5, ${at}, $6, 'tap_card', 'TR-' || upper(substr(md5(random()::text), 1, 6)), ${at} - interval '2 hours', $7, $8, $9, $10)`,
      [ids[who], name, status, from, to, fare, seat, route, vehicle, provider],
    );
  }
  for (const [who, name, from, to, fare, ago, status] of [
    ['zainab', 'Zainab Yusuf', 'Jabi', 'Wuse 2', 2400, 6, 'confirmed'],
    ['emeka', 'Emeka Nwosu', 'Maitama', 'Central Area', 1900, 95, 'completed'],
    ['aisha', 'Aisha Bello', 'Wuse 2', 'Garki', 2150, 210, 'completed'],
  ]) {
    await q(
      `insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare, payment_method, ticket_code, created_at, title, vehicle_id, provider_id)
       values ($1, $2, 'electric', $3, $4, $5, now() - make_interval(mins => $6), $7, 'tap_card', 'EV-' || upper(substr(md5(random()::text), 1, 4)), now() - make_interval(mins => $6 + 6), 'Toyota Camry · ABJ 552 TR', 'v_grace_car', 'p_grace')`,
      [ids[who], name, status, from, to, ago, fare],
    );
  }
  log('added bookings');
}

// The rest of the demo commutes (rail, Nyanya and Kubwa), added once each.
for (const [who, name, route, from, to, at, fare, vehicle, status, seat] of [
  ['aisha', 'Aisha Bello', 'r03', 'Central Station', 'Idu', `(date_trunc('day', now()) - interval '6 days' + interval '9 hours 20 minutes')`, 600, 'v_amr1', 'completed', 'C3'],
  ['emeka', 'Emeka Nwosu', 'r05', 'Nyanya', 'Central Area', `(date_trunc('day', now()) + interval '6 hours 40 minutes')`, 600, 'v_abj010', 'confirmed', 'S30'],
  ['zainab', 'Zainab Yusuf', 'r04', 'Kubwa', 'Central Area', `(date_trunc('day', now()) + interval '7 hours')`, 800, 'v_abj007', 'confirmed', 'S17'],
]) {
  const r = await q(
    `insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare, payment_method, ticket_code, created_at, seat, route_id, vehicle_id, provider_id)
     select $1, $2, 'transit', $3, $4, $5, ${at}, $6, 'tap_card', 'TR-' || upper(substr(md5(random()::text), 1, 6)), ${at} - interval '2 hours', $7, $8::text, $9, (select provider_id from public.routes where id = $8::text)
     where exists (select 1 from public.routes where id = $8::text) and exists (select 1 from public.vehicles where id = $9)
       and not exists (select 1 from public.bookings where user_id = $1 and route_id = $8::text)`,
    [ids[who], name, status, from, to, fare, seat, route, vehicle],
  );
  if (r.rowCount) log('added booking', route, 'for', name);
}

if (!(await q('select 1 from public.partner_applications limit 1')).rowCount) {
  await q(
    `insert into public.partner_applications (user_id, partner_type, status, full_name, email, phone, date_of_birth, address, area, nin, next_of_kin_name, next_of_kin_phone,
       licence_number, licence_class, licence_expiry, vehicle_make, vehicle_model, vehicle_year, vehicle_colour, plate_number, chassis_number, engine_number, seats, documents, ai_check, created_at)
     values ($1, 'private_driver', 'submitted', 'Musa Abdullahi', 'musa@taparide.demo', '+234 803 555 0101', '1988-04-12', '14 Ahmadu Bello Way', 'Gwarinpa', '12345678901', 'Hauwa Abdullahi', '+234 806 555 0303',
       'ABJ58213AA49', 'B', '2029-03-31', 'Toyota', 'Corolla', 2019, 'Silver', 'GWA 482 KD', '2T1BURHE5KC214587', '2ZR4471029', 4, '[]',
       '{"overall":"pass","summary":"Licence and vehicle papers match the details entered. Licence is valid until March 2029.","checks":[]}', now() - interval '5 hours')`,
    [ids.musa],
  );
  await q(
    `insert into public.partner_applications (user_id, partner_type, status, full_name, email, phone, date_of_birth, address, area, company_name, rc_number, tin, fleet_size, contact_role, documents, ai_check, created_at)
     values ($1, 'fleet_owner', 'submitted', 'Ngozi Eze', 'ngozi@capitalcabs.demo', '+234 802 555 0202', '1990-01-01', 'Plot 22, Aminu Kano Crescent', 'Wuse 2', 'Capital City Cabs Ltd', 'RC1842207', '20481937-0001', 38, 'Operations director', '[]',
       '{"overall":"review","summary":"CAC certificate matches the company name and RC number. The operating permit expires in 6 weeks; ask for the renewal.","checks":[]}', now() - interval '26 hours')`,
    [ids.ngozi],
  );
  log('added partner applications');
}

const counts = await q(`select (select count(*) from public.providers) providers, (select count(*) from public.routes) routes, (select count(*) from public.vehicles) vehicles,
  (select count(*) from public.bookings) bookings, (select count(*) from public.profiles) profiles, (select count(*) from public.partner_applications) applications,
  (select count(*) from pg_tables where schemaname = 'public' and rowsecurity) rls_tables, (select count(*) from pg_tables where schemaname = 'public') tables`);
log('database:', JSON.stringify(counts.rows[0]));
await client.end();
