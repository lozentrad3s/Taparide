// Supabase Auth settings for taparide.com, through the Supabase Management API.
//   node scripts/supabase-auth-setup.mjs           show the current settings (secrets masked)
//   node scripts/supabase-auth-setup.mjs --apply   apply the settings below, then show them again
// Needs SUPABASE_ACCESS_TOKEN in ../.env.local (supabase.com/dashboard/account/tokens). Never prints a key.
//
// What --apply sets:
//   - Site URL https://taparide.com and the allowed return addresses (fixes "localhost:3000" links in emails)
//   - New passwords: at least 8 characters with small and capital letters, numbers and symbols
//   - With RESEND_API_KEY: emails sent by Resend from MAIL_FROM (Tap A Ride <no-reply@taparide.com>)
//   - With GOOGLE_OAUTH_CLIENT_ID + GOOGLE_OAUTH_CLIENT_SECRET: "Continue with Google" switched on
//   - Branded Tap A Ride emails: confirm account, reset password, magic link, change email, invite
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { brandEmail } from '../api/_lib/app-mail-layout.js';
import { loadEnv } from './check-keys.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const env = loadEnv(join(here, '..', '..', '.env.local'));
const apply = process.argv.includes('--apply');
const ref = (env.SUPABASE_URL || '').match(/[a-z0-9]{20}/)?.[0];
if (!ref) throw new Error('SUPABASE_URL in .env.local has no project ref.');
if (!env.SUPABASE_ACCESS_TOKEN) {
  console.log('SUPABASE_ACCESS_TOKEN is empty in taparide_flutter/.env.local.\nCreate one at https://supabase.com/dashboard/account/tokens, paste it after SUPABASE_ACCESS_TOKEN= and run this again.');
  process.exit(1);
}
const api = `https://api.supabase.com/v1/projects/${ref}/config/auth`;
const headers = { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' };

async function current() {
  const r = await fetch(api, { headers });
  if (!r.ok) throw new Error(`Supabase answered ${r.status}${r.status === 401 ? ' (token rejected)' : r.status === 403 || r.status === 404 ? ' (the token belongs to another Supabase account)' : ''}.`);
  return r.json();
}

const yes = (v) => (v ? 'set' : 'not set');
function show(c, title) {
  console.log(`\n${title}`);
  const rows = [
    ['Site URL', c.site_url],
    ['Allowed return addresses', (c.uri_allow_list || '').split(',').filter(Boolean).join('\n' + ' '.repeat(28)) || '(none)'],
    ['Email confirmation', c.mailer_autoconfirm ? 'OFF (accounts confirm themselves)' : 'ON'],
    ['Password minimum length', c.password_min_length],
    ['Password must contain', !c.password_required_characters ? 'no rule' : c.password_required_characters.split(':').length >= 4 ? 'small + capital letters, numbers, symbols' : c.password_required_characters.split(':').length === 3 ? 'small + capital letters, numbers' : 'letters and numbers'],
    ['Custom email (SMTP)', c.smtp_host ? `${c.smtp_host}:${c.smtp_port} · user ${yes(c.smtp_user)} · password ${yes(c.smtp_pass)} · from "${c.smtp_sender_name || ''}" <${c.smtp_admin_email || ''}>` : "not set: Supabase's built-in sender (a few emails an hour)"],
    ['Emails per hour', c.rate_limit_email_sent],
    ['Continue with Google', c.external_google_enabled ? `ON · client id ${yes(c.external_google_client_id)} · secret ${yes(c.external_google_secret)}` : 'OFF'],
    ['Continue with Apple', c.external_apple_enabled ? 'ON' : 'OFF'],
    ['Confirm-email subject', c.mailer_subjects_confirmation],
  ];
  for (const [k, v] of rows) console.log(`  ${k.padEnd(26)}${v ?? '(default)'}`);
}

const ALL_CHARS = "abcdefghijklmnopqrstuvwxyz:ABCDEFGHIJKLMNOPQRSTUVWXYZ:0123456789:!@#$%^&*()_+-=[]{};'\\\\:\"|<>?,./`~";
const ALL_CHARS_ALT = "abcdefghijklmnopqrstuvwxyz:ABCDEFGHIJKLMNOPQRSTUVWXYZ:0123456789:!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~";

const email = (heading, intro, button, after) =>
  brandEmail({
    heading,
    bodyHtml: `<p style="margin:0 0 12px">${intro}</p>${after ? `<p style="margin:0;color:#5B6B62;font-size:13.5px">${after}</p>` : ''}`,
    cta: { label: button, url: '{{ .ConfirmationURL }}' },
    footnote: "If you didn't ask for this, you can ignore this email; nothing changes on your account.",
  });

function patchFor(c) {
  const allow = new Set((c.uri_allow_list || '').split(',').map((s) => s.trim()).filter(Boolean));
  for (const u of ['https://taparide.com/**', 'https://taparide.com/app/**', 'https://taparide.com/dashboard/**', 'https://www.taparide.com/**', 'http://localhost:8090/**', 'http://localhost:8091/**']) allow.add(u);
  const p = {
    site_url: 'https://taparide.com',
    uri_allow_list: [...allow].join(','),
    password_min_length: Math.max(8, c.password_min_length || 0),
    password_required_characters: ALL_CHARS,
  };
  // Branded emails need a custom sender on Supabase's free plan, so they go in together with Resend.
  if (env.RESEND_API_KEY && senderReady) Object.assign(p, {
    mailer_subjects_confirmation: 'Confirm your Tap A Ride account',
    mailer_templates_confirmation_content: email('Confirm your email', 'Welcome to Tap A Ride. Tap the button to confirm {{ .Email }} and finish creating your account.', 'Confirm my account', 'The link works once and expires in 24 hours.'),
    mailer_subjects_recovery: 'Reset your Tap A Ride password',
    mailer_templates_recovery_content: email('Reset your password', 'Someone (hopefully you) asked to reset the password for {{ .Email }}. Tap the button to choose a new one.', 'Choose a new password', 'The link works once and expires in 1 hour.'),
    mailer_subjects_magic_link: 'Your Tap A Ride sign-in link',
    mailer_templates_magic_link_content: email('Sign in to Tap A Ride', 'Tap the button to sign in as {{ .Email }}.', 'Sign me in', 'The link works once and expires in 1 hour.'),
    mailer_subjects_email_change: 'Confirm your new email for Tap A Ride',
    mailer_templates_email_change_content: email('Confirm your new email', 'Tap the button to change your Tap A Ride email from {{ .Email }} to {{ .NewEmail }}.', 'Confirm new email'),
    mailer_subjects_invite: "You're invited to Tap A Ride",
    mailer_templates_invite_content: email("You're invited", 'You have been invited to a Tap A Ride account for {{ .Email }}. Tap the button to accept and set your password.', 'Accept the invite'),
  });
  if (env.RESEND_API_KEY && senderReady) {
    const from = sender;
    Object.assign(p, {
      smtp_host: 'smtp.resend.com',
      smtp_port: '465',
      smtp_user: 'resend',
      smtp_pass: env.RESEND_API_KEY,
      smtp_admin_email: (from.match(/<([^>]+)>/)?.[1] || from).trim(),
      smtp_sender_name: from.includes('<') ? from.split('<')[0].trim() || 'Tap A Ride' : 'Tap A Ride',
      rate_limit_email_sent: 100,
    });
  }
  // Never overwrite a Google set-up that is already working.
  if (env.GOOGLE_OAUTH_CLIENT_ID && env.GOOGLE_OAUTH_CLIENT_SECRET && !c.external_google_enabled) {
    Object.assign(p, { external_google_enabled: true, external_google_client_id: env.GOOGLE_OAUTH_CLIENT_ID, external_google_secret: env.GOOGLE_OAUTH_CLIENT_SECRET });
  }
  return p;
}

async function patch(body) {
  const r = await fetch(api, { method: 'PATCH', headers, body: JSON.stringify(body) });
  const text = await r.text();
  return { ok: r.ok, status: r.status, message: r.ok ? '' : text.slice(0, 300).replaceAll(env.SUPABASE_ACCESS_TOKEN, '***').replaceAll(env.RESEND_API_KEY || '\u0000', '***') };
}

// Resend only takes over sign-in emails once it can really send from this address; otherwise
// switching would stop every confirmation and password-reset email.
const sender = env.MAIL_FROM || 'Tap A Ride <no-reply@taparide.com>';
let senderReady = false;
if (env.RESEND_API_KEY) {
  const t = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: sender, to: ['delivered@resend.dev'], subject: 'Tap A Ride sender check', text: 'Sender check.' }),
  }).catch(() => null);
  senderReady = !!t?.ok;
  if (!senderReady) console.log(`Resend can't send from the MAIL_FROM address yet (verify its domain in Resend > Domains); sign-in emails stay on Supabase's sender for now.`);
}

const before = await current();
show(before, apply ? 'Before:' : 'Current Supabase Auth settings:');
if (!apply) {
  console.log('\nRun with --apply to set taparide.com, the password rules' + (env.RESEND_API_KEY ? ', Resend email' : '') + (env.GOOGLE_OAUTH_CLIENT_ID ? ', Google sign-in' : '') + ' and the branded emails.');
  if (!env.RESEND_API_KEY) console.log('  (RESEND_API_KEY is empty: emails stay on the built-in sender.)');
  if (!env.GOOGLE_OAUTH_CLIENT_ID) console.log('  (GOOGLE_OAUTH_CLIENT_ID is empty: Google sign-in is left as it is.)');
  process.exit(0);
}

const body = patchFor(before);
let res = await patch(body);
if (!res.ok && /password_required_characters/.test(res.message)) {
  // The API takes one exact string for "letters, digits and symbols"; try the other escaping.
  res = await patch({ ...body, password_required_characters: ALL_CHARS_ALT });
  if (!res.ok && /password_required_characters/.test(res.message)) {
    const { password_required_characters, ...rest } = body;
    res = await patch(rest);
    if (res.ok) console.log('\nNOTE: set the symbol rule by hand: Authentication > Providers > Email > Password requirements > "Lowercase, uppercase letters, digits and symbols".');
  }
}
if (!res.ok) {
  console.log(`\nSupabase refused the change (${res.status}): ${res.message}`);
  process.exit(1);
}
const after = await current();
show(after, 'After:');
const changed = Object.keys(body).filter((k) => JSON.stringify(before[k]) !== JSON.stringify(after[k]) && !/pass|secret|templates/.test(k));
const templates = Object.keys(body).filter((k) => /templates/.test(k) && before[k] !== after[k]).length;
const secrets = Object.keys(body).filter((k) => /smtp_pass|secret/.test(k)).length;
console.log(`\nChanged: ${changed.join(', ') || 'nothing visible'}${templates ? ` · ${templates} email templates` : ''}${secrets ? ` · ${secrets} secret(s) saved (not shown)` : ''}.`);
