# Tap A Ride website

The public website for Tap A Ride. It is a separate project from the app in `../taparide_flutter` and shares nothing with it except the database, so it can move to its own repository whenever you like.

## What's on it

- **Home (`public/index.html`):** one ride story per section, each with real Abuja photos and real app screens: city buses, event buses (Abuja Tech Week), Tag Along, electric cars, live map, Tap & Pay, safety, partners, the waitlist and questions.
- **Waitlist:** join with an email and get a free first ride (₦1,000 ride credit), a place in line and an invite link (`/r/CODE`). Each friend who joins with your link moves you up.
- **Abuja Tech Week buses:** people pick the day, their area and a departure time and reserve a free seat. Demand is shown live by area. A bus is confirmed once 14 people from one area pick the same day and time.
- **Privacy notice (`public/privacy.html`)** and photo credits.

## Run it on your computer

```
node scripts/dev.mjs 8090
```

Then open http://localhost:8090. Without database keys, sign-ups are saved in a temporary file on this computer (the page shows "Preview mode"). "Open the app" links go to the local app at http://localhost:8080 when you run it locally, and to https://taparide.vercel.app otherwise.

## Go live

1. Apply the database migration `../taparide_flutter/supabase/migrations/20261118000000_waitlist.sql` (with `node scripts/supabase-setup.mjs` in `../taparide_flutter/deploy`). It creates the waitlist, seat requests and the free-ride credit that's paid when a waitlisted email opens and confirms an account.
2. Create a new Vercel project from this folder, and set `SUPABASE_URL` and `SUPABASE_ANON_KEY`, the same values the app uses. Set `SITE_ORIGINS` if the domain isn't `taparide.com`.
3. Point the domain at it, e.g. `taparide.com` for the website and `app.taparide.com` for the app. Then change the app address in `vercel.json` (redirects) and in `public/js/site.js` (`APP`).

## Swapping in your own photos and flyers

All images are in `public/img`:

| File | Used for |
|---|---|
| `photos/brt-berger.jpg` | Hero background |
| `photos/abuja-light-rail.jpg` | City buses story |
| `photos/abuja-taxis.jpg` | Tag Along story |
| `photos/ev-charging.jpg` | Electric story (full-width background) |
| `app/*.jpg` | App screens inside the phone frames (786 × 1704) |
| `og.jpg` | Preview image when the link is shared (1200 × 630) |

Replace a file with your own under the same name, or change the `src` in `index.html`. When you change a photo, update its credit line on the page and in `privacy.html`. Wikimedia photos need their credit; your own photos don't.

## Safety notes

- Strict security headers: the page loads nothing from other sites.
- The API (`api/waitlist.js`) accepts calls only from the website's own address, rate-limits each visitor and has a bot trap.
- Nobody can read the waitlist directly from the database: only counts and your own place in line come back.
- The free ride is paid once per account, only after the email is confirmed, for the first 5,000 people on the list.
