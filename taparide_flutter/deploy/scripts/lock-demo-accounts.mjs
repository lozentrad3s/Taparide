// Locks the demo accounts (emails ending in .demo) on the LIVE database, so the published demo
// password stops working: they are banned from signing in, get a random password and their sessions
// end. Nothing is deleted (their sample routes, vehicles and bookings stay).
// Usage: node scripts/lock-demo-accounts.mjs            lock
//        node scripts/lock-demo-accounts.mjs --unlock   allow sign-in again (password stays random)
// Reads ../.env.local (SUPABASE_DB_URL). Prints only emails, never secrets.
import pg from 'pg';
import { randomBytes } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './check-keys.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const env = loadEnv(join(here, '..', '..', '.env.local'));
if (!env.SUPABASE_DB_URL) throw new Error('SUPABASE_DB_URL is not set');
const direct = new URL(env.SUPABASE_DB_URL);
const ref = direct.hostname.startsWith('db.') ? direct.hostname.split('.')[1] : decodeURIComponent(direct.username).split('.')[1];
const client = new pg.Client({
  host: direct.hostname.includes('pooler') ? direct.hostname : env.SUPABASE_POOLER_HOST || 'aws-0-eu-west-1.pooler.supabase.com',
  port: 5432,
  user: direct.hostname.includes('pooler') ? decodeURIComponent(direct.username) : `postgres.${ref}`,
  password: decodeURIComponent(direct.password),
  database: 'postgres',
  ssl: { rejectUnauthorized: false },
});
await client.connect();
const unlock = process.argv.includes('--unlock');

const users = (await client.query(`select id, email from auth.users where email like '%.demo' order by email`)).rows;
await client.query('begin');
try {
  for (const u of users) {
    if (unlock) {
      await client.query(`update auth.users set banned_until = null where id = $1`, [u.id]);
    } else {
      await client.query(
        `update auth.users set banned_until = '2999-12-31', encrypted_password = extensions.crypt($2, extensions.gen_salt('bf')) where id = $1`,
        [u.id, randomBytes(24).toString('base64url')],
      );
      await client.query(`delete from auth.refresh_tokens where user_id = $1::text`, [u.id]).catch(() => {});
      await client.query(`delete from auth.sessions where user_id = $1`, [u.id]).catch(() => {});
    }
  }
  await client.query('commit');
} catch (e) {
  await client.query('rollback');
  throw e;
}
console.log(`${unlock ? 'Unlocked' : 'Locked'} ${users.length} demo accounts:`, users.map((u) => u.email).join(', '));
const admins = (await client.query(`select count(*) n from public.profiles p join auth.users u on u.id = p.id where p.role = 'admin' and u.email not like '%.demo' and (u.banned_until is null or u.banned_until < now())`)).rows[0].n;
console.log(`Admin accounts still able to sign in (not demo): ${admins}`);
await client.end();
