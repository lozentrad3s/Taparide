# Tap A Ride security and monitoring

## Built into the code

| Protection | Where | Switch |
|---|---|---|
| Row-level security on every table; all writes go through checked database functions | Supabase migrations | Always on |
| Demo accounts locked on the live database | `taparide_flutter/deploy/scripts/lock-demo-accounts.mjs` | Done 18 Nov 2026 |
| Live builds hide demo sign-in shortcuts | build script | Always on |
| Two-step sign-in (authenticator app) for admin and FCTA accounts | App screen `two_step_page.dart`; database rule `20261118050000_staff_two_step.sql` | App: deployed. Database rule: waiting for approval to apply |
| Sign-up anti-bot: hidden honeypot field, minimum fill time, Cloudflare Turnstile | `taparide_website/api/waitlist.js` | Turnstile switches on with `TURNSTILE_SITE_KEY` and `TURNSTILE_SECRET_KEY` |
| Rate limits shared across all servers | `api/_lib/redis.js` | `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` (per-server limits until then) |
| API origin checks (only taparide.com and the Vercel address may call the APIs) | `waitlist.js`, `_lib/auth.js` | Always on |
| Payments are credited only after the provider confirms; webhooks are signed (HMAC) | `api/pay.js` | Bachs keys |
| Security headers: CSP, HSTS, no framing, nosniff | `taparide_website/vercel.json` | Always on |
| Error reports to Sentry (API and app; no personal data) | `api/_lib/sentry.js`, `/api/client-error`, `lib/core/error_reporting.dart` | `SENTRY_DSN` |
| Health endpoint for uptime monitors | `GET /api/health` (200 healthy, 503 if the database is down) | Always on |
| Outsider security check (read-only) | `node scripts/security-check.mjs https://taparide.com` in `taparide_flutter/deploy` | Run before every release |

## Settings for you to make (in your dashboards)

### Supabase (supabase.com → project)
1. **Authentication → URL Configuration**
   - Site URL: `https://taparide.com/app/`
   - Redirect URLs: add `https://taparide.com/app/**`, `https://www.taparide.com/app/**` and `https://taparide.vercel.app/app/**`.
2. **Authentication → Sign In / Providers**
   - Google: on; paste the Google Cloud OAuth client ID and secret. In Google Cloud, the authorised redirect URI is the callback URL shown on that Supabase page.
   - Apple: on; Services ID, Team ID, Key ID and the .p8 key.
3. **Authentication → Multi-Factor**
   - TOTP: enabled.
   - Then tell me to apply the two-step database rule.
4. **Authentication → Attack Protection**
   - Leaked password protection: on.
   - Captcha: Turnstile with the same keys as the website (optional).
5. **Billing:** upgrade to **Pro** (daily backups, no pausing); add Point-in-Time Recovery when there are paying riders.

### Vercel (vercel.com → lozen-s-projects → taparide → Firewall)
1. **Bot Protection:** on (managed ruleset). Blocks known bad bots and scrapers.
2. **Custom rule "API rate limit":**
   - Condition: path starts with `/api/`.
   - Action: rate limit, 60 requests per 60 seconds per IP, then deny for 1 minute.
3. **Custom rule "Sign-up burst":**
   - Condition: path equals `/api/waitlist` AND method is POST.
   - Action: rate limit, 10 per minute per IP.
4. **Attack Challenge Mode:** leave off; switch it on only during an attack (it challenges every visitor).
5. **Settings → Environment Variables (Production):** add as they become available:
   - `BACHS_SECRET_KEY`, `BACHS_WEBHOOK_SECRET`
   - `MAPTILER_API_KEY`
   - `SENTRY_DSN`
   - `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY`
   - Upstash is added automatically when connected through the Marketplace.
6. **Upgrade to Pro:** commercial use requires it; it also gives more firewall rules and log retention.

### Sentry (sentry.io, free Developer plan to start)
1. Create an organisation "Tap A Ride" and a project "taparide" (platform: Node.js).
2. Copy the DSN into Vercel as `SENTRY_DSN`. App and API errors then start arriving; nothing else is needed.
3. Alerts: email (and Slack, if you use it) on new issues.

### Uptime monitor (Better Stack Uptime or UptimeRobot, free tier)
1. HTTP monitor `https://taparide.com/api/health` every 1 minute; alert when the status is not 200.
2. Keyword monitor `https://taparide.com/`; alert if the text "Tap A Ride" is missing.
3. Notify by email and SMS or WhatsApp to the on-call phone. Optional: a public status page at status.taparide.com.

### Bachs (app.bachs.io)
1. Sign up and request access to the sandbox; create a **sandbox** API key (`sk_sandbox_…`).
2. Developer Portal → Webhooks:
   - Add endpoint `https://taparide.com/api/pay?action=webhook` with events `collection.succeeded` and `checkout.completed`.
   - Copy its signing secret.
3. Put both in Vercel (`BACHS_SECRET_KEY`, `BACHS_WEBHOOK_SECRET`). Top-ups then go through Bachs checkout in test mode.
4. After merchant verification, swap in the **live** key (`sk_live_…`) and run `node scripts/supabase-setup.mjs`. That turns off test money.
5. Ask Bachs which licensed bank or PSP holds NGN funds (their terms say they are a technology provider), and for virtual accounts and payouts access (for driver and operator payouts).

## Penetration test (before the public launch)

**Who:** a CREST- or OSCP-certified firm. Nigerian options include Cyberguard Africa, Kamtech and Digital Encode; international options include Cobalt and HackerOne Pentest. Budget roughly $3,000–$8,000 for this scope.

**Scope to give them:**
- `https://taparide.com` (website and APIs under `/api/*`), `/app` (rider web app), `/dashboard` (partner, FCTA and admin dashboards).
- Supabase project (REST and RPC API, Auth). Provide test accounts for each role: rider, operator, fleet owner, fleet driver, event partner, FCTA, admin. Use a staging copy if possible.
- Priorities:
  1. Access control between roles and organisations (one operator reading another's bookings).
  2. Wallet and payment integrity (top-ups, refunds, ad rewards, free-ride credit).
  3. Waitlist abuse (fake sign-ups, invite fraud).
  4. Authentication (password reset, OAuth, two-step bypass).
  5. Location and trip-sharing privacy.
  6. Injection and XSS.
  7. Rate limits.
- Out of scope: denial-of-service, social engineering, third parties (Bachs, Supabase, Vercel infrastructure).

**Before they start:** apply the pending database rules (fleet drivers, two-step), create a staging Supabase project, and run `security-check.mjs`. **After:** fix the findings, ask for a retest letter, and keep it for partners, the FCTA and investors.
