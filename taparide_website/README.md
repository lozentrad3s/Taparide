# Tap A Ride website

The public website for Tap A Ride. It is a separate project from the app in `../taparide_flutter` and shares nothing with it except the database, so it can move to its own repository whenever you like.

## What's on it

- **Home (`public/index.html`):** one ride story per section, each with real Abuja photos and real app screens: city buses, event buses (Abuja Tech Week), Tag Along, electric cars, live map, Tap & Pay, safety, partners, the waitlist and questions.
- **Waitlist:** join with an email and get a free first ride (₦1,000 ride credit), a place in line and an invite link (`/r/CODE`). Each friend who joins with your link moves you up.
- **Abuja Tech Week buses:** people pick the day, their area and a departure time and reserve a free seat. Demand is shown live by area. A bus is confirmed once 14 people from one area pick the same day and time.
- **Privacy notice (`public/privacy.html`)** and photo credits.

## How it is hosted

One Vercel project serves everything on taparide.com:

| Address | What | Built from |
|---|---|---|
| `taparide.com/` | This website | `public/` |
| `taparide.com/app` | Rider app (onboarding, sign-in with Google/Apple/email, booking) | `../taparide_flutter`, `APP_MODE=rider` |
| `taparide.com/dashboard` | Partner, operator, FCTA, fleet, event-partner and admin dashboards | `../taparide_flutter`, `APP_MODE=dashboard` |
| `dashboard.taparide.com`, `app.taparide.com`, `www.` | Redirect to the addresses above | `vercel.json` |
| `/api/*` | Website waitlist + the app's maps, search, AI and payments | `api/` + `../taparide_flutter/deploy/api` |

The website and the app stay in separate folders; `scripts/assemble.mjs` joins them only in `.output/` (git-ignored).

```
node scripts/assemble.mjs              # builds the rider app and the dashboards, then assembles .output/
node scripts/assemble.mjs --no-build   # reuse the last Flutter builds
node scripts/dev.mjs --dir .output     # preview everything at http://localhost:8090
node scripts/dev.mjs                   # website only
```

Without `--live`, website sign-ups in the preview are saved in a temp file (the page says "Preview mode").

## Go live

1. Apply the database migrations in `../taparide_flutter/supabase/migrations` (`node scripts/supabase-setup.mjs` in `../taparide_flutter/deploy`): the waitlist and Tech Week seats (`20261118000000_waitlist.sql`) and the real Abuja routes (`20261118010000_real_routes.sql`).
2. `node scripts/assemble.mjs`, then `cd .output && npx vercel deploy --prod`. It deploys to the existing `taparide` Vercel project, so its keys (Supabase, AI, maps) carry over.
3. In Vercel, add the domains `taparide.com`, `www.taparide.com`, `dashboard.taparide.com` and `app.taparide.com`, and set the DNS records Vercel shows.
4. In Supabase → Authentication: set the Site URL to `https://taparide.com/app/`, add it under Redirect URLs, and switch on Google and Apple with their client IDs.

## Swapping in your own photos and flyers

All images are in `public/img`:

| File | Used for |
|---|---|
| `photos/back-seat.jpg` | Hero (full-width photo) |
| `photos/friends-bus.jpg` | Bus rides story |
| `photos/tagalong.jpg` | Tagalong story and the "Drive with us" card |
| `photos/tap-to-pay.jpg` | Tap to Pay story |
| `photos/rider-in-car.jpg` | Safety story |
| `photos/bus.jpg`, `photos/festival.jpg` | Partner cards (operators, event organisers) |
| `flyers/tech-week.jpg` | Abuja Tech Week section |
| `flyers/*.jpg` | "Smarter travel. Together." campaign gallery and the advertise banner |
| `og.jpg` | Preview image when the link is shared (1200 × 630) |

All of these come from Tap A Ride's own artwork in `../website image and app onbaording images/`; some are crops of the flyers without their text. The Electric card uses a drawn illustration until there is an electric-car photo. To swap an image, save yours under the same name, or change the `src` in `index.html`.

## Safety notes

- Strict security headers: the page loads nothing from other sites.
- The API (`api/waitlist.js`) accepts calls only from the website's own address, rate-limits each visitor and has a bot trap.
- Nobody can read the waitlist directly from the database: only counts and your own place in line come back.
- The free ride is paid once per account, only after the email is confirmed, for the first 5,000 people on the list.
