-- Live app: event rides, host-approved Tag Along with held cost shares, shareable trip links,
-- live vehicle positions and real wallet top-ups (Paystack, confirmed by the server).

-- ------------------------------------------------------------------ private settings
-- Server-only values. Not exposed through the API: only security-definer functions read them.
create schema if not exists taparide_private;
revoke all on schema taparide_private from public, anon, authenticated;
create table if not exists taparide_private.settings (key text primary key, value text not null);

create or replace function public.payments_live() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value = 'true' from taparide_private.settings where key = 'payments_live'), false)
$$;

-- ------------------------------------------------------------------ events
create table if not exists public.events (
  id             text primary key default 'ev_' || substr(md5(random()::text), 1, 10),
  title          text not null check (char_length(title) between 3 and 120),
  venue          text not null check (char_length(venue) between 2 and 120),
  area           text not null default 'Abuja',
  lat            double precision,
  lng            double precision,
  starts_at      timestamptz not null,
  ends_at        timestamptz,
  category       text not null default 'community' check (category in ('conference', 'concert', 'sport', 'worship', 'wedding', 'community', 'other')),
  description    text not null default '',
  organiser_id   uuid references auth.users (id) on delete set null,
  organiser_name text not null,
  status         text not null default 'listed' check (status in ('listed', 'removed')),
  created_at     timestamptz not null default now()
);
create index if not exists events_starts_idx on public.events (starts_at);
alter table public.events enable row level security;
drop policy if exists events_read on public.events;
create policy events_read on public.events for select to authenticated
  using (status = 'listed' or public.is_staff() or organiser_id = auth.uid());

create or replace function public.create_event(p_title text, p_venue text, p_area text, p_starts_at timestamptz, p_ends_at timestamptz default null,
                                               p_category text default 'community', p_description text default '',
                                               p_lat double precision default null, p_lng double precision default null)
returns public.events
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  e  public.events;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if p_starts_at < now() then raise exception 'Choose a start time later than now.'; end if;
  if p_ends_at is not null and p_ends_at < p_starts_at then raise exception 'The event cannot end before it starts.'; end if;
  if not public.is_staff() and (select count(*) from public.events where organiser_id = me.id and status = 'listed' and starts_at > now()) >= 5 then
    raise exception 'You can list up to 5 upcoming events at a time.';
  end if;
  insert into public.events (title, venue, area, lat, lng, starts_at, ends_at, category, description, organiser_id, organiser_name)
  values (trim(p_title), trim(p_venue), coalesce(nullif(trim(p_area), ''), 'Abuja'), p_lat, p_lng, p_starts_at, p_ends_at,
          coalesce(p_category, 'community'), trim(coalesce(p_description, '')), me.id, coalesce(me.organisation, me.full_name))
  returning * into e;
  return e;
end;
$$;

create or replace function public.remove_event(p_event_id text)
returns public.events
language plpgsql security definer set search_path = public as $$
declare
  e public.events;
begin
  select * into e from public.events where id = p_event_id;
  if not found then raise exception 'Event not found.' using errcode = 'P0003'; end if;
  if e.organiser_id is distinct from auth.uid() and not public.is_staff() then
    raise exception 'Your account is not allowed to remove this event.' using errcode = '42501';
  end if;
  update public.events set status = 'removed' where id = e.id returning * into e;
  if public.is_staff() then perform public.log_action('Removed event', e.title); end if;
  return e;
end;
$$;

-- ------------------------------------------------------------------ Tag Along: real hosts, held cost shares
alter table public.shared_rides add column if not exists event_id text references public.events (id);
alter table public.shared_rides add column if not exists status text not null default 'open' check (status in ('open', 'cancelled'));

-- Rides seeded with made-up hosts cannot answer requests, so they leave the live list.
update public.shared_rides set status = 'cancelled'
 where status = 'open' and host_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- Hosts can read the requests on their own rides.
drop policy if exists bookings_read on public.bookings;
create policy bookings_read on public.bookings for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_staff()
    or (public.my_role() = 'operator' and provider_id = public.my_provider())
    or (public.my_role() = 'fleet_owner' and vehicle_id in (select id from public.vehicles where owner_id = public.my_provider()))
    or (ride_id is not null and ride_id in (select id from public.shared_rides where host_id = auth.uid()::text))
  );

drop function if exists public.offer_shared_ride(text, text, timestamptz, integer, integer, text, text);
create or replace function public.offer_shared_ride(p_origin text, p_destination text, p_depart_at timestamptz, p_seats integer,
                                                    p_cost_share integer, p_vehicle_label text, p_note text default '', p_event_id text default null)
returns public.shared_rides
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  r  public.shared_rides;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if p_depart_at < now() then raise exception 'Choose a departure time later than now.'; end if;
  if p_cost_share < 0 or p_cost_share > 10000 then raise exception 'The cost share must be between ₦0 and ₦10,000 per seat.'; end if;
  if p_event_id is not null and not exists (select 1 from public.events where id = p_event_id and status = 'listed') then
    raise exception 'This event is no longer listed.' using errcode = 'P0003';
  end if;
  insert into public.shared_rides (host_id, host_name, host_org, host_verified, origin, destination, depart_at,
                                   seats_total, cost_share, vehicle_label, note, event_id)
  values (me.id::text, me.full_name, coalesce(me.organisation, 'Tap A Ride member'), me.verified, trim(p_origin), trim(p_destination),
          p_depart_at, p_seats, p_cost_share, trim(p_vehicle_label), trim(coalesce(p_note, '')), p_event_id)
  returning * into r;
  return r;
end;
$$;

create or replace function public.request_shared_ride(p_ride_id text)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  r  public.shared_rides;
  b  public.bookings;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  select * into r from public.shared_rides where id = p_ride_id;
  if not found or r.status <> 'open' then raise exception 'This ride has been withdrawn by the host.' using errcode = 'P0003'; end if;
  if r.depart_at < now() then raise exception 'This ride has already left.'; end if;
  if r.host_id = me.id::text then raise exception 'You are hosting this ride.'; end if;
  if r.seats_taken >= r.seats_total then raise exception 'This ride is full.'; end if;
  if exists (select 1 from public.bookings where user_id = me.id and ride_id = r.id and status in ('requested', 'accepted')) then
    raise exception 'You have already asked to join this ride.';
  end if;
  if (select balance from public.wallets where user_id = me.id) < r.cost_share then
    raise exception 'Top up your Tap Card: you need % for your share of this ride.', '₦' || r.cost_share using errcode = 'P0002';
  end if;

  insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare,
                               payment_method, ticket_code, title, ride_id)
  values (me.id, me.full_name, 'tag_along', 'requested', r.origin, r.destination, r.depart_at, r.cost_share,
          'split_cost', 'TA-' || upper(substr(md5(random()::text), 1, 6)), 'With ' || r.host_name, r.id)
  returning * into b;
  return b;
end;
$$;

-- The host accepts or declines. Accepting takes the rider's share and holds it until the ride leaves.
create or replace function public.respond_ride_request(p_booking_id text, p_accept boolean)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  r public.shared_rides;
begin
  select * into b from public.bookings where id = p_booking_id and kind = 'tag_along' for update;
  if not found then raise exception 'Request not found.' using errcode = 'P0003'; end if;
  select * into r from public.shared_rides where id = b.ride_id for update;
  if r.host_id is distinct from auth.uid()::text then raise exception 'Only the host can answer this request.' using errcode = '42501'; end if;
  if b.status <> 'requested' then raise exception 'This request has already been answered.'; end if;

  if not p_accept then
    update public.bookings set status = 'declined' where id = b.id returning * into b;
    return b;
  end if;
  if r.status <> 'open' or r.depart_at < now() then raise exception 'This ride is no longer open.'; end if;
  if r.seats_taken >= r.seats_total then raise exception 'Your ride is full.'; end if;
  update public.wallets set balance = balance - b.fare where user_id = b.user_id and balance >= b.fare;
  if not found then raise exception '% no longer has enough balance for their share.', b.passenger_name using errcode = 'P0002'; end if;
  update public.shared_rides set seats_taken = seats_taken + 1 where id = r.id;
  update public.bookings set status = 'accepted' where id = b.id returning * into b;
  return b;
end;
$$;

-- The host withdraws the ride: riders already accepted get their share back.
create or replace function public.cancel_shared_ride(p_ride_id text)
returns public.shared_rides
language plpgsql security definer set search_path = public as $$
declare
  r public.shared_rides;
  b public.bookings;
begin
  select * into r from public.shared_rides where id = p_ride_id for update;
  if not found then raise exception 'Ride not found.' using errcode = 'P0003'; end if;
  if r.host_id is distinct from auth.uid()::text then raise exception 'Only the host can withdraw this ride.' using errcode = '42501'; end if;
  if r.depart_at < now() then raise exception 'This ride has already left.'; end if;
  for b in select * from public.bookings where ride_id = r.id and status in ('requested', 'accepted') for update loop
    if b.status = 'accepted' then update public.wallets set balance = balance + b.fare where user_id = b.user_id; end if;
    update public.bookings set status = case when b.status = 'accepted' then 'cancelled' else 'declined' end where id = b.id;
  end loop;
  update public.shared_rides set status = 'cancelled', seats_taken = 0 where id = r.id returning * into r;
  return r;
end;
$$;

-- Requests on the rides I host, newest first.
create or replace function public.my_ride_requests()
returns setof public.bookings
language sql stable security definer set search_path = public as $$
  select b.* from public.bookings b
    join public.shared_rides r on r.id = b.ride_id
   where r.host_id = auth.uid()::text and b.kind = 'tag_along'
   order by b.created_at desc
   limit 200
$$;

-- Runs when a rider or host opens the app: once a ride has left, held shares are paid to the host
-- and requests nobody answered lapse. (Replaces the old demo auto-accept.)
create or replace function public.settle_tag_along_requests()
returns void
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  host uuid;
begin
  for b in
    select bk.* from public.bookings bk
      join public.shared_rides r on r.id = bk.ride_id
     where bk.kind = 'tag_along' and bk.status in ('requested', 'accepted') and r.depart_at < now()
       and (bk.user_id = auth.uid() or r.host_id = auth.uid()::text)
     for update of bk
  loop
    if b.status = 'accepted' then
      select p.id into host from public.profiles p join public.shared_rides r on r.host_id = p.id::text where r.id = b.ride_id;
      if host is not null then update public.wallets set balance = balance + b.fare where user_id = host; end if;
      update public.bookings set status = 'completed' where id = b.id;
    else
      update public.bookings set status = 'declined' where id = b.id;
    end if;
  end loop;
end;
$$;

create or replace function public.cancel_booking(p_booking_id text)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0003'; end if;
  if b.user_id <> auth.uid() then raise exception 'Your account is not allowed to cancel this booking.' using errcode = '42501'; end if;
  if b.status not in ('confirmed', 'requested', 'accepted') then raise exception 'This booking can no longer be cancelled.'; end if;

  if b.payment_method <> 'split_cost' and b.departure_at > now() then
    update public.wallets set balance = balance + b.fare where user_id = b.user_id;
  end if;
  if b.kind = 'electric' and b.vehicle_id is not null then
    update public.vehicles set status = 'active' where id = b.vehicle_id;
  end if;
  if b.kind = 'tag_along' and b.status = 'accepted' then
    update public.shared_rides set seats_taken = greatest(0, seats_taken - 1) where id = b.ride_id;
    -- The held share goes back to the rider if the ride has not left yet.
    if b.departure_at > now() then update public.wallets set balance = balance + b.fare where user_id = b.user_id; end if;
  end if;
  update public.trip_shares set revoked = true where booking_id = b.id;
  update public.bookings set status = 'cancelled' where id = b.id returning * into b;
  return b;
end;
$$;

-- Live vehicle positions (table first: the shared-trip view reads it).
create table if not exists public.vehicle_positions (
  vehicle_id  text primary key references public.vehicles (id) on delete cascade,
  lat         double precision not null,
  lng         double precision not null,
  heading     double precision,
  speed_kmh   double precision,
  updated_at  timestamptz not null default now(),
  reported_by uuid references auth.users (id) on delete set null
);
alter table public.vehicle_positions enable row level security;
drop policy if exists vehicle_positions_read on public.vehicle_positions;
create policy vehicle_positions_read on public.vehicle_positions for select to authenticated using (true);

-- ------------------------------------------------------------------ share my ride
create table if not exists public.trip_shares (
  token      text primary key default encode(extensions.gen_random_bytes(16), 'hex'),
  booking_id text not null references public.bookings (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked    boolean not null default false,
  lat        double precision,
  lng        double precision,
  located_at timestamptz
);
create index if not exists trip_shares_booking_idx on public.trip_shares (booking_id);
alter table public.trip_shares enable row level security;
drop policy if exists trip_shares_read on public.trip_shares;
create policy trip_shares_read on public.trip_shares for select to authenticated using (user_id = auth.uid());

create or replace function public.share_trip(p_booking_id text)
returns public.trip_shares
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  s public.trip_shares;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found or b.user_id <> auth.uid() then raise exception 'Booking not found.' using errcode = 'P0003'; end if;
  if b.status not in ('confirmed', 'requested', 'accepted') then raise exception 'Only upcoming trips can be shared.'; end if;
  select * into s from public.trip_shares where booking_id = b.id and not revoked and expires_at > now() order by created_at desc limit 1;
  if found then return s; end if;
  insert into public.trip_shares (booking_id, user_id, expires_at)
  values (b.id, b.user_id, greatest(b.departure_at, now()) + interval '6 hours')
  returning * into s;
  return s;
end;
$$;

create or replace function public.stop_trip_share(p_booking_id text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.trip_shares set revoked = true where booking_id = p_booking_id and user_id = auth.uid();
end;
$$;

create or replace function public.update_trip_location(p_booking_id text, p_lat double precision, p_lng double precision)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then raise exception 'Invalid location.'; end if;
  update public.trip_shares set lat = p_lat, lng = p_lng, located_at = now()
   where booking_id = p_booking_id and user_id = auth.uid() and not revoked and expires_at > now();
end;
$$;

-- What a trusted contact sees when they open the link: no account needed, and only what keeps the rider safe.
create or replace function public.get_shared_trip(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s public.trip_shares;
  b public.bookings;
  v public.vehicles;
  p public.providers;
  r public.routes;
  ride public.shared_rides;
  pos public.vehicle_positions;
begin
  select * into s from public.trip_shares where token = p_token;
  if not found or s.revoked or s.expires_at < now() then return null; end if;
  select * into b from public.bookings where id = s.booking_id;
  select * into v from public.vehicles where id = b.vehicle_id;
  select * into p from public.providers where id = coalesce(b.provider_id, v.operator_id);
  select * into r from public.routes where id = b.route_id;
  select * into ride from public.shared_rides where id = b.ride_id;
  select * into pos from public.vehicle_positions where vehicle_id = b.vehicle_id and updated_at > now() - interval '5 minutes';
  return jsonb_build_object(
    'passenger', split_part(b.passenger_name, ' ', 1),
    'kind', b.kind,
    'status', b.status,
    'origin', b.origin,
    'destination', b.destination,
    'departure_at', b.departure_at,
    'ticket_code', b.ticket_code,
    'expires_at', s.expires_at,
    'operator', p.name,
    'operator_verified', coalesce(p.status = 'verified', false),
    'vehicle', case when v.id is null then ride.vehicle_label else trim(coalesce(v.model, '') || ' ' || v.plate) end,
    'vehicle_verified', coalesce(v.verification = 'verified', false),
    'driver', coalesce(v.driver_name, ride.host_name),
    'stops', r.stops,
    'rider_lat', s.lat, 'rider_lng', s.lng, 'rider_located_at', s.located_at,
    'vehicle_lat', pos.lat, 'vehicle_lng', pos.lng, 'vehicle_located_at', pos.updated_at
  );
end;
$$;

-- ------------------------------------------------------------------ live vehicle positions
-- Sent by the driver's or conductor's device while a vehicle is in service.
create or replace function public.report_vehicle_position(p_vehicle_id text, p_lat double precision, p_lng double precision,
                                                          p_heading double precision default null, p_speed_kmh double precision default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v public.vehicles;
begin
  select * into v from public.vehicles where id = p_vehicle_id;
  if not found then raise exception 'Vehicle not found.' using errcode = 'P0003'; end if;
  if not (public.manages(v.operator_id) or (v.owner_id is not null and public.manages(v.owner_id))) then
    raise exception 'Your account is not allowed to track this vehicle.' using errcode = '42501';
  end if;
  -- Positions far outside the FCT are almost always a laptop on a VPN, not a bus.
  if p_lat is null or p_lng is null or p_lat not between 8.2 and 9.8 or p_lng not between 6.5 and 8.1 then
    raise exception 'This device is not reporting a location in or near the FCT.';
  end if;
  insert into public.vehicle_positions (vehicle_id, lat, lng, heading, speed_kmh, updated_at, reported_by)
  values (v.id, p_lat, p_lng, p_heading, p_speed_kmh, now(), auth.uid())
  on conflict (vehicle_id) do update
    set lat = excluded.lat, lng = excluded.lng, heading = excluded.heading, speed_kmh = excluded.speed_kmh,
        updated_at = excluded.updated_at, reported_by = excluded.reported_by;
end;
$$;

create or replace function public.stop_vehicle_tracking(p_vehicle_id text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.vehicle_positions where vehicle_id = p_vehicle_id and reported_by = auth.uid();
end;
$$;

-- ------------------------------------------------------------------ wallet top-ups (Paystack)
create table if not exists public.wallet_topups (
  reference  text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  amount     integer not null check (amount between 100 and 50000),
  status     text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  channel    text,
  created_at timestamptz not null default now(),
  paid_at    timestamptz
);
create index if not exists wallet_topups_user_idx on public.wallet_topups (user_id, created_at desc);
alter table public.wallet_topups enable row level security;
drop policy if exists wallet_topups_read on public.wallet_topups;
create policy wallet_topups_read on public.wallet_topups for select to authenticated using (user_id = auth.uid());

-- Step 1 (the rider): reserve a payment reference for an amount.
create or replace function public.start_top_up(p_amount integer)
returns public.wallet_topups
language plpgsql security definer set search_path = public as $$
declare
  t public.wallet_topups;
begin
  if auth.uid() is null then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if p_amount < 100 or p_amount > 50000 then raise exception 'Top up between ₦100 and ₦50,000.'; end if;
  if (select count(*) from public.wallet_topups where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Too many top-up attempts. Try again in an hour.';
  end if;
  insert into public.wallet_topups (reference, user_id, amount)
  values ('TAR-' || upper(encode(extensions.gen_random_bytes(9), 'hex')), auth.uid(), p_amount)
  returning * into t;
  return t;
end;
$$;

-- Step 2 (our server only, after Paystack confirms the payment): credit the wallet once.
-- The server proves itself with a secret whose hash lives in the private settings.
create or replace function public.confirm_top_up(p_secret text, p_reference text, p_amount_kobo bigint, p_channel text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t public.wallet_topups;
  expected text;
begin
  select value into expected from taparide_private.settings where key = 'topup_secret_hash';
  if expected is null or p_secret is null or encode(sha256(convert_to(p_secret, 'utf8')), 'hex') <> expected then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  select * into t from public.wallet_topups where reference = p_reference for update;
  if not found then raise exception 'Unknown payment reference.' using errcode = 'P0003'; end if;
  if t.status = 'paid' then return jsonb_build_object('status', 'paid', 'amount', t.amount, 'credited', false); end if;
  if p_amount_kobo <> t.amount::bigint * 100 then
    update public.wallet_topups set status = 'failed' where reference = t.reference;
    return jsonb_build_object('status', 'failed', 'amount', t.amount, 'credited', false);
  end if;
  update public.wallet_topups set status = 'paid', paid_at = now(), channel = p_channel where reference = t.reference;
  update public.wallets set balance = balance + t.amount where user_id = t.user_id;
  return jsonb_build_object('status', 'paid', 'amount', t.amount, 'credited', true);
end;
$$;

-- Test-money top-up: refused as soon as real payments are switched on.
create or replace function public.top_up(p_amount integer)
returns public.wallets
language plpgsql security definer set search_path = public as $$
declare
  w public.wallets;
begin
  if auth.uid() is null then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if public.payments_live() then raise exception 'Top up with your card or bank to add money.' using errcode = '42501'; end if;
  if p_amount < 100 or p_amount > 50000 then raise exception 'Top up between ₦100 and ₦50,000.'; end if;
  update public.wallets set balance = balance + p_amount where user_id = auth.uid() returning * into w;
  return w;
end;
$$;

-- New sign-ups start with test money only while real payments are off.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, phone, organisation)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(new.email, '@', 1)),
    new.email,
    new.raw_user_meta_data ->> 'phone',
    nullif(new.raw_user_meta_data ->> 'organisation', '')
  );
  insert into public.wallets (user_id, card_number, balance)
  values (new.id, '50610042' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'), case when public.payments_live() then 0 else 2500 end);
  return new;
end;
$$;

-- ------------------------------------------------------------------ grants
revoke insert, update, delete on all tables in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
grant execute on function public.provider_is_verified(text) to anon;
-- Opened by a trusted contact without an account; the token is the key.
grant execute on function public.get_shared_trip(text) to anon;
-- Called by our server with the top-up secret (it has no user session).
grant execute on function public.confirm_top_up(text, text, bigint, text) to anon;
revoke execute on function public.confirm_top_up(text, text, bigint, text) from authenticated;
grant execute on function public.payments_live() to anon;
