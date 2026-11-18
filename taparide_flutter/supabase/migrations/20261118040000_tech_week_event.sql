-- Abuja Tech Week 2026 as a listed event in the app. Tap A Ride is the official ride partner;
-- free bus seats are reserved on taparide.com (waitlist migration), so this row has no tickets.
insert into public.events (id, title, venue, area, lat, lng, starts_at, ends_at, category, description, organiser_name, status, sponsored)
values ('ev_techweek', 'Abuja Tech Week 2026', 'Velodrome, National Stadium', 'Kukwaba', 9.0392, 7.4556,
  '2026-11-24 09:00:00+01', '2026-11-26 17:00:00+01', 'conference',
  'Abuja Tech & Digital Economy Week at the Velodrome, National Stadium. Tap A Ride is the official ride partner: free buses leave at 7:00 AM sharp from University of Abuja (Gwagwalada), Nnamdi Azikiwe Airport, Old Parade Ground (corps members), Nile University, Police Signboard (Lugbe) and the checkpoint between Maraba and Nyanya. Powered by Pi-CNG & EV.',
  'Abuja Tech & Digital Economy Week', 'listed', true)
on conflict (id) do update set
  title = excluded.title, venue = excluded.venue, area = excluded.area, lat = excluded.lat, lng = excluded.lng,
  starts_at = excluded.starts_at, ends_at = excluded.ends_at, description = excluded.description,
  organiser_name = excluded.organiser_name, status = 'listed', sponsored = true;
