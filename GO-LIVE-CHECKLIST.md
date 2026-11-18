# Tap A Ride: go-live checklist

Status on 18 November 2026. LIVE at https://taparide.com (website), /app (rider app) and /dashboard (partners, FCTA, admin); www., app. and dashboard. redirect there. Live Supabase database; demo accounts locked. Security steps for your dashboards are in SECURITY.md.

## 1. Already in place

| Service | Used for | State |
|---|---|---|
| GitHub (lozentrad3s/Taparide) | Code | Pushing works from the dev PC |
| Vercel (project `taparide`) | Hosting for website, app, dashboards, API | Deployed |
| Supabase (eu-west-1) | Database, sign-in, file storage | Live; waitlist, Tech Week, real routes, events and ads updates applied |
| Gemini | AI assistant and dashboard insights | Key set in Vercel |
| CARTO | Map tiles (until MapTiler is added) | Key set in Vercel |

## 2. Do now (this week, before Tech Week on 24 Nov)

1. ~~**Domain DNS**~~ done on 18 Nov (taparide.com is live). For reference, the records are:
   - `A` record: `@` → `216.198.79.1`
   - `CNAME` records: `www`, `dashboard` and `app` → `17f9810751af2f9b.vercel-dns-017.com`
   - The domains are already added in Vercel. HTTPS switches on by itself once DNS updates.
2. **Supabase → Authentication → URL configuration:**
   - Site URL: `https://taparide.com/app/`
   - Redirect URLs: `https://taparide.com/app/**` and `https://taparide.vercel.app/app/**`
3. **Redis (Upstash, via Vercel Marketplace → Storage):**
   - Connect it to the `taparide` project. That adds `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN`.
   - The code already uses them for shared rate limits, seat-count caching and place-search caching.
4. **MapTiler:**
   - Add `MAPTILER_API_KEY` in Vercel (Production).
   - In MapTiler, allow only `taparide.com` and `taparide.vercel.app`.
   - Maps and place search switch to MapTiler automatically.
5. **Vercel Pro plan:** the free Hobby plan is for non-commercial use only. Pro is about $20 per member per month.
6. **Supabase Pro plan** (about $25/month): no project pausing, daily backups, more connections. Point-in-time recovery is an extra add-on.
7. **Apply the fleet-drivers database update** (`20261118030000_fleet_drivers.sql`). It is tested on a fresh copy. Run: `node scripts/supabase-setup.mjs` in `taparide_flutter/deploy`.
8. **Tech Week operations:**
   - Bus capacity and plate numbers per pick-up point.
   - Driver names and phones.
   - Staff at each point at 6:30 AM.
   - Boarding lists come from Dashboard → Website sign-ups → "Copy boarding list".

## 3. Payments: Bachs.io (available)

We need from Bachs:
- API documentation; sandbox and live keys; webhook signing secret.
- Settlement account details.
- Do they support:
  - wallets or virtual accounts per rider
  - payouts to operators and drivers
  - refunds
  - card / bank / USSD top-ups
  - NFC or tokenised phone-to-phone payments?
- Their licence: Tap A Ride's wallet is stored value, so it must sit on a CBN-licensed partner's rails.

We will:
- Add `BACHS_*` keys to Vercel.
- Build the top-up and payout flows behind the existing wallet; Paystack stays as the fallback.
- Add webhook verification and reconciliation reports in the admin dashboard.

## 4. Sign-in, email, SMS, WhatsApp

| Need | Service | What to set up |
|---|---|---|
| Continue with Google | Google Cloud Console | OAuth client (Web); redirect `https://<project>.supabase.co/auth/v1/callback`; enable in Supabase |
| Continue with Apple | Apple Developer Program ($99/yr) | Services ID, Team ID, Key ID, .p8 key; enable in Supabase |
| Mailboxes (info@, partnership@) | Google Workspace or Zoho Mail | MX records on taparide.com |
| App emails (confirm account, receipts) | Resend or Postmark | SPF, DKIM, DMARC DNS records; set as custom SMTP in Supabase |
| Phone OTP, ride SMS | Termii (Nigeria) | API key; sender ID "TapARide" approval |
| WhatsApp confirmations (+234 911 050 2561) | Meta WhatsApp Business Cloud API | Meta Business verification, message templates |

## 5. Scaling ("load balancer", servers 1, 2, 3)

- **App and API:** Vercel runs every page and API function on its global network and starts as many copies as traffic needs. Load balancing is built in, so there is no server 1/2/3 to manage. Set the functions region to Dublin (`dub1`), next to the database.
- **Database:**
  - Supabase's connection pooler is already used.
  - At around 100k daily riders, add read replicas (Supabase add-on) and a larger compute size.
  - Partition the bookings table by month.
- **Redis:** shared limits and caches across all copies (section 2.3). Later it also holds live bus positions and ad counters.
- **Dedicated servers, only if needed later** (live GPS stream for thousands of buses, trip matching): Google Cloud Run or Fly.io. Both include their own load balancers and auto-scaling; put them behind `api.taparide.com`.
- **Map tiles at scale:** self-hosted vector tiles for the FCT on Cloudflare R2 instead of per-request tile calls.

## 6. Security and monitoring

- Turn on Vercel Firewall (bot protection, rate limits on /api).
- Add Cloudflare Turnstile to the waitlist and Tech Week forms against bot sign-ups.
- MFA for admin and FCTA accounts (Supabase Auth MFA).
- Supabase leaked-password protection.
- Rotate keys every quarter.
- Sentry for app and API errors; Better Stack (or similar) for uptime; Vercel Analytics.
- Pen test before the public launch. Already done: role rules in the database (RLS), demo accounts locked.

## 7. Mobile apps and tap-to-pay

- Google Play developer account ($25 one-off). The Flutter app already builds for Android.
- Apple App Store (same $99 Apple Developer account as Sign in with Apple).
- NFC phone-to-phone tap-to-pay:
  - Android only (host card emulation) in the native app; iPhone uses QR codes.
  - Needs Bachs to support it, plus test phones with NFC.

## 8. Legal and compliance

- CAC registration details on the website footer and terms.
- Nigeria Data Protection Act 2023: register with the NDPC, name a data protection officer, and do the annual audit.
- A lawyer to review /terms and /privacy.
- Written agreements and logo permission: Abuja Tech Week (official ride partner), Pi-CNG (spelling and logo).
- FCTA engagement for operator verification and transport permits.
- Passenger insurance cover with partners.
- Driver checks: NIN and licence verification provider (Prembly/Dojah/YouVerify).

## 9. Content and operations

- An EV photo you own. The robotaxi and Ford images can't be used (other brands).
- Licence check for the live-map illustration.
- Onboard real bus operators and confirm fares on the 15 corridors (see `taparide_flutter/docs/route-operators.md`).
- Customer support: WhatsApp line rota; Freshdesk or Zendesk later.
- Analytics: PostHog or GA4 for the waitlist funnel, with cookie consent.

## Deploying (important)

GitHub pushes do NOT deploy (root `vercel.json` turns Git deployments off). A Git build would publish the repository root, which is not the site.
To deploy:
1. `node scripts/assemble.mjs` in `taparide_website`.
2. `cd .output && npx vercel deploy --prod --scope lozen-s-projects`.
3. Check the site.
4. If the domains don't move to the new deployment by themselves, run `npx vercel promote <deployment-url> --scope lozen-s-projects`.
