# Tap A Ride · Abuja Smart Mobility Platform

**Ride • Connect • Go.** One platform where riders book and pay for fixed-fare transport across the FCT with a tap card or QR code, and operators, fleet owners and the FCTA see every trip, every naira and every verified vehicle.

Built with Flutter for **web (desktop + mobile browsers) and Android** from one codebase, backed by **Supabase** (Auth + Postgres with row-level security). Without Supabase keys it runs on an on-device demo backend that applies the same rules.

## What's in the app

| Area | Screens |
|---|---|
| **Get Started** (public) | Landing page from the mockup: hero with a live next-departure card, feature strip, "One Platform. Everyone Connected.", EV + Tag Along, partner section, photo credits |
| **Sign in** | Passenger and partner-portal sign-in, registration, password reset. Partner accounts are refused on the passenger side and vice versa |
| **Rider app** | Home (greeting, search, quick actions, popular routes, Travel Smart, EVs, Tag Along), route search, route details on a real map with departure times, payment (Tap Card or QR), boarding pass with QR, trips, profile with wallet top-up and safety centre |
| **Electric vehicles** | Live battery and range, fare estimate between Abuja areas, booking, charging stations |
| **Tag Along** | Shared rides from verified colleagues, request to join (host accepts), offer a ride |
| **Partner portal** | Platform overview, FCTA dashboard, operator dashboard, fleet-owner dashboard, transport providers, electric vehicles, routes & fares, vehicle register, bookings, verification queue, users & roles, audit log |

Every rider booking flows into the operator, fleet-owner and FCTA views. Each role only sees and changes what it is allowed to:

| Role | Lands on | Can do |
|---|---|---|
| Passenger | Rider home | Book, pay, cancel (refund), top up, Tag Along, EVs |
| Transport operator | Operator dashboard | Edit own fares, manage own vehicles, see own bookings |
| Fleet owner | Fleet dashboard | See owned vehicles, earnings, set vehicle status |
| Government / FCTA | FCTA dashboard | Approve providers, verify vehicles, see all data, audit log |
| Platform admin | Platform overview | Everything, including suspensions and role changes |

## Run it

The Flutter SDK must live in a path **without spaces** (e.g. `C:\src\flutter`). Building from a path with spaces fails in the native-assets step on Windows.

```bash
flutter pub get
flutter run -d chrome          # web
flutter run -d <android-device> # Android
flutter build web --release    # static site in build/web
```

### Demo mode (default)

With no Supabase keys the app uses demo data stored on the device. Every demo account uses the password `Ride2026!`:

| Account | Role |
|---|---|
| aisha@taparide.demo | Passenger |
| ops@abujametro.demo | Operator · Abuja Metro Bus Co. |
| fleet@greenfleet.demo | Fleet owner · GreenFleet Logistics |
| ev@naviride.demo | Operator · NaviRide Electric |
| transport@fcta.demo | Government / FCTA |
| admin@taparide.demo | Platform admin |

Profile → *Reset demo data* restores the original data.

### Supabase mode

1. Create a Supabase project.
2. In the SQL editor, run `supabase/migrations/20261016000000_taparide_schema.sql`, then `supabase/seed.sql`. With the Supabase CLI, `supabase db reset` runs both.
3. Run the app with your project URL and publishable (anon) key:
   ```bash
   flutter run -d chrome --dart-define=SUPABASE_URL=https://<project>.supabase.co --dart-define=SUPABASE_ANON_KEY=<publishable-key>
   ```
4. Sign up in the app (new accounts are passengers with a ₦2,500 starter balance), then promote partner accounts in SQL:
   ```sql
   update profiles set role = 'admin' where email = 'you@example.com';
   update profiles set role = 'operator', provider_id = 'p_metro' where email = 'ops@example.com';
   ```
   After the first admin exists, roles can be changed from **Users & roles** in the portal.

Reads are guarded by row-level security; all writes (bookings, payments, approvals, fare changes, role changes) go through `security definer` SQL functions that re-check the caller's role and write the audit log.

## Project structure

```
lib/
  app/        theme (tokens from the logo), router (role-based redirects), app shell
  core/       models, formatters, dashboards maths, app state
    backend/  Backend interface, DemoBackend (on-device), SupabaseBackend, demo seed
  shared/     brand lockup, UI kit (panels, route line, status pills, charts), map
  features/   landing, auth, passenger, ev, tag_along, portal, common
assets/
  brand/      Tap A Ride logo variants cut from the original artwork
  photos/     openly licensed photographs (see Photo credits)
  fonts/      Barlow (UI) + Fira Sans (₦ glyph fallback), SIL OFL
supabase/     schema, RLS, functions and seed
test/         flow + permission tests; test/screens renders review screenshots
```

## Tests

```bash
flutter test                                                        # flows and permission rules
flutter test test/screens --update-goldens --dart-define=SCREENS=true  # renders screens to test/screens/out
```

## Not yet production

- Wallet top-ups go through Paystack (`deploy/api/pay.js`) once `PAYSTACK_SECRET_KEY` is set in `.env.local`, synced with `node scripts/sync-vercel-env.mjs`, and `node scripts/supabase-setup.mjs` is re-run. Until then top-ups are test money and the app says so. Point the Paystack webhook at `/api/pay?action=webhook`.
- Vehicles report GPS from the driver or operator dashboard while it is open; background tracking needs the Android validator app.
- Map tiles come from CARTO's free basemap (OpenStreetMap data). Use a commercial tile plan for production traffic.
- Dashboard figures, organisations and people are illustrative demo data and are labelled as such in the app.

## Photo credits

All photographs are from Wikimedia Commons under CC BY / CC BY-SA licences. Authors, licences and source links are listed in-app (**Photo credits**) and in `lib/core/photos.dart`.
