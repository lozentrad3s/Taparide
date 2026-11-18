// Read-only report of demo/sample data on the LIVE database: rows per table, demo accounts and
// "(sample)" operators. The removal itself is migration 20261118070000_remove_demo_data.sql.
//   node scripts/demo-data.mjs
// Reads ../.env.local (SUPABASE_DB_URL). Prints table names and counts only, never secrets.
import pg from 'pg';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './check-keys.mjs';

const here = dirname(fileURLToPath(import.meta.url));
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

const tables = (await client.query(`
  select c.relname t,
         (select array_agg(a.attname::text order by a.attnum) from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) cols
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' order by c.relname`)).rows;

const report = [];
for (const { t, cols } of tables) {
  const total = Number((await client.query(`select count(*) n from public."${t}"`)).rows[0].n);
  const textCols = cols.filter((c) => /name|title|label|operator|provider|sponsor|headline|description/.test(c));
  let sample = 0;
  if (textCols.length) {
    const cond = textCols.map((c) => `"${c}"::text ilike '%(sample)%'`).join(' or ');
    sample = Number((await client.query(`select count(*) n from public."${t}" where ${cond}`)).rows[0].n);
  }
  report.push({ table: t, total, sample_named: sample });
}
const demoUsers = (await client.query(`select count(*) n from auth.users where email like '%.demo'`)).rows[0].n;
const realUsers = (await client.query(`select count(*) n from auth.users where email not like '%.demo'`)).rows[0].n;
console.log(`accounts: ${realUsers} real, ${demoUsers} demo`);
console.table(report.filter((r) => r.total > 0));

// Foreign keys pointing at profiles / auth.users / providers, to find demo-owned rows.
const fks = (await client.query(`
  select cl.relname src, att.attname col, rcl.relname dst, rn.nspname dst_schema
  from pg_constraint con
  join pg_class cl on cl.oid = con.conrelid join pg_namespace n on n.oid = cl.relnamespace
  join pg_class rcl on rcl.oid = con.confrelid join pg_namespace rn on rn.oid = rcl.relnamespace
  join pg_attribute att on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
  where con.contype = 'f' and n.nspname = 'public'`)).rows;
console.log('links:', fks.map((f) => `${f.src}.${f.col} -> ${f.dst_schema}.${f.dst}`).join(', '));
await client.end();
