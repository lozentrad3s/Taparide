-- Launch clean-up: the live database keeps only real people, real routes and real numbers.
--
-- Removes
--   * the demo accounts (emails ending in .demo) and everything they own: bookings, Tagalong rides,
--     events they organised, wallets, profiles;
--   * the fictional "(sample)" operators and the demo private driver, with their vehicles, charging
--     stations and event buses;
--   * the invented dashboard baselines (metric_baselines) and the invented 30-day trip counts on routes;
--   * audit-log lines written by demo staff.
-- Keeps
--   * the 15 real Abuja corridors with their public "who runs this corridor" notes. They have no Tap A
--     Ride operator yet (provider_id becomes null), so riders can see them but cannot book a seat until
--     a real operator is attached (book_transit already refuses routes without a verified operator);
--   * real accounts, the waitlist, Tech Week seats, partner applications, house ads.
-- Real riders who paid for a confirmed seat on a sample operator get the fare back on their tap card.

alter table public.routes alter column provider_id drop not null;

create temp table _demo_users on commit drop as
  select id from auth.users where email like '%.demo';
create temp table _demo_names on commit drop as
  select distinct full_name from public.profiles where id in (select id from _demo_users) and full_name is not null;
create temp table _sample_providers on commit drop as
  select id from public.providers
  where name ilike '%(sample)%'
     or id in (select provider_id from public.profiles where id in (select id from _demo_users) and provider_id is not null);
create temp table _sample_vehicles on commit drop as
  select id from public.vehicles
  where operator_id in (select id from _sample_providers) or owner_id in (select id from _sample_providers);
create temp table _demo_rides on commit drop as
  select id from public.shared_rides
  where id like 'seed\_%' or host_id not in (select id::text from auth.users where email not like '%.demo');
create temp table _demo_events on commit drop as
  select id from public.events where organiser_id in (select id from _demo_users);

-- Refund real riders' paid, still-confirmed seats on sample operators.
update public.wallets w set balance = w.balance + x.total
from (
  select b.user_id, sum(b.fare) total from public.bookings b
  where b.status = 'confirmed' and b.payment_method = 'tap_card' and b.user_id not in (select id from _demo_users)
    and (b.provider_id in (select id from _sample_providers) or b.vehicle_id in (select id from _sample_vehicles))
  group by b.user_id
) x where w.user_id = x.user_id;

delete from public.bookings
where user_id in (select id from _demo_users)
   or provider_id in (select id from _sample_providers)
   or vehicle_id in (select id from _sample_vehicles)
   or ride_id in (select id from _demo_rides)
   or event_id in (select id from _demo_events)
   or event_bus_id in (select id from public.event_buses where provider_id in (select id from _sample_providers) or vehicle_id in (select id from _sample_vehicles));

delete from public.shared_rides where id in (select id from _demo_rides);
delete from public.event_buses where provider_id in (select id from _sample_providers) or vehicle_id in (select id from _sample_vehicles);
delete from public.events where id in (select id from _demo_events);

update public.routes set provider_id = null where provider_id in (select id from _sample_providers);
update public.routes set monthly_trips = 0;

delete from public.charging_stations where operator_id in (select id from _sample_providers);
update public.partner_applications set vehicle_id = null where vehicle_id in (select id from _sample_vehicles);
update public.partner_applications set provider_id = null where provider_id in (select id from _sample_providers);
delete from public.vehicles where id in (select id from _sample_vehicles);
update public.profiles set provider_id = null where provider_id in (select id from _sample_providers);

delete from public.audit_log
where actor_name in (select full_name from _demo_names)
   or actor_name not in (select p.full_name from public.profiles p join auth.users u on u.id = p.id
                         where u.email not like '%.demo' and p.full_name is not null);
delete from auth.users where id in (select id from _demo_users);
delete from public.providers where id in (select id from _sample_providers);

delete from public.metric_baselines;

-- The electric-car ad promised verified EVs across the city; there are none on the platform yet.
update public.ads set active = false where id = 'ad_ev';
