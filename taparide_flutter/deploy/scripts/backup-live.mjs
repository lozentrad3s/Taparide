// Saves every public table (and the auth user list: id, email, created) from the LIVE database to
// ../.local-backups/live-<timestamp>.json (gitignored: it holds personal details). Prints counts only.
import pg from 'pg';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './check-keys.mjs';
const here = dirname(fileURLToPath(import.meta.url));
const env = loadEnv(join(here, '..', '..', '.env.local'));
const d = new URL(env.SUPABASE_DB_URL);
const ref = d.hostname.startsWith('db.') ? d.hostname.split('.')[1] : decodeURIComponent(d.username).split('.')[1];
const c = new pg.Client({ host: d.hostname.includes('pooler') ? d.hostname : env.SUPABASE_POOLER_HOST || 'aws-0-eu-west-1.pooler.supabase.com', port: 5432, user: d.hostname.includes('pooler') ? decodeURIComponent(d.username) : `postgres.${ref}`, password: decodeURIComponent(d.password), database: 'postgres', ssl: { rejectUnauthorized: false } });
await c.connect();
const out = { taken_at: new Date().toISOString(), tables: {} };
const tables = (await c.query(`select tablename from pg_tables where schemaname = 'public' order by 1`)).rows.map((r) => r.tablename);
for (const t of tables) out.tables[t] = (await c.query(`select * from public."${t}"`)).rows;
out.auth_users = (await c.query(`select id, email, created_at, banned_until from auth.users order by created_at`)).rows;
await c.end();
const dir = join(here, '..', '..', '.local-backups');
mkdirSync(dir, { recursive: true });
const file = join(dir, `live-${out.taken_at.replace(/[:.]/g, '-')}.json`);
writeFileSync(file, JSON.stringify(out, null, 1));
console.log('saved', file);
console.log(Object.entries(out.tables).filter(([, r]) => r.length).map(([t, r]) => `${t} ${r.length}`).join(', '), `| auth users ${out.auth_users.length}`);
