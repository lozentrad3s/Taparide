// Applies ONE migration file to the live database (and records it), leaving other pending ones alone.
// Usage: node scripts/apply-migration.mjs 20261118060000_tech_week_tickets.sql
// Reads ../.env.local (SUPABASE_DB_URL). Prints no secrets.
import pg from 'pg';
import { readFileSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './check-keys.mjs';

const file = basename(process.argv[2] || '');
if (!/^\d{14}_[a-z0-9_]+\.sql$/.test(file)) throw new Error('Give a migration file name, e.g. 20261118060000_tech_week_tickets.sql');
const here = dirname(fileURLToPath(import.meta.url));
const sql = readFileSync(join(here, '..', '..', 'supabase', 'migrations', file), 'utf8');
const env = loadEnv(join(here, '..', '..', '.env.local'));
const d = new URL(env.SUPABASE_DB_URL);
const ref = d.hostname.startsWith('db.') ? d.hostname.split('.')[1] : decodeURIComponent(d.username).split('.')[1];
const client = new pg.Client({
  host: d.hostname.includes('pooler') ? d.hostname : env.SUPABASE_POOLER_HOST || 'aws-0-eu-west-1.pooler.supabase.com',
  port: 5432,
  user: d.hostname.includes('pooler') ? decodeURIComponent(d.username) : `postgres.${ref}`,
  password: decodeURIComponent(d.password),
  database: 'postgres',
  ssl: { rejectUnauthorized: false },
});
await client.connect();
const done = await client.query('select 1 from taparide_meta.migrations where name = $1', [file]);
if (done.rowCount) {
  console.log(`${file} was already applied.`);
} else {
  await client.query('begin');
  try {
    await client.query(sql);
    await client.query('insert into taparide_meta.migrations (name) values ($1)', [file]);
    await client.query('commit');
    console.log(`applied ${file}`);
  } catch (e) {
    await client.query('rollback');
    throw new Error(`${file}: ${e.message}`);
  }
}
await client.end();
