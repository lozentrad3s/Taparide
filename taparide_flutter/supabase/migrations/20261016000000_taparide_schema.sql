-- Tap A Ride · Abuja Smart Mobility Platform
-- Schema, row-level security and server-side actions.
--
-- Reads go through tables protected by RLS. Every write goes through a
-- SECURITY DEFINER function below that re-checks the caller's role, so the
-- rules hold no matter which client calls the API.
--
-- Error codes the app understands:
--   42501 permission denied · P0001 validation · P0002 insufficient funds · P0003 not found

-- ------------------------------------------------------------------ tables

create table public.providers (
  id            text primary key default 'p_' || substr(md5(random()::text), 1, 10),
  name          text not null,
  kind          text not null check (kind in ('bus_operator', 'fleet_owner', 'rail', 'electric', 'shuttle', 'tricycle')),
  status        text not null default 'pending' check (status in ('verified', 'pending', 'suspended')),
  area          text not null default 'FCT',
  contact_name  text not null default '',
  contact_email text not null default '',
  joined_at     timestamptz not null default now(),
  description   text not null default ''
);

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  full_name    text not null,
  email        text not null,
  phone        text,
  role         text not null default 'passenger' check (role in ('passenger', 'operator', 'fleet_owner', 'government', 'admin')),
  provider_id  text references public.providers (id),
  organisation text,
  verified     boolean not null default false,
  created_at   timestamptz not null default now()
);

create table public.routes (
  id            text primary key,
  provider_id   text not null references public.providers (id),
  code          text not null,
  name          text,
  stops         jsonb not null,
  fare          integer not null check (fare between 100 and 20000),
  duration_min  integer not null,
  mode          text not null check (mode in ('bus', 'rail', 'shuttle')),
  departures    text[] not null default '{}',
  monthly_trips integer not null default 0,
  active        boolean not null default true
);

create table public.vehicles (
  id             text primary key default 'v_' || substr(md5(random()::text), 1, 10),
  operator_id    text not null references public.providers (id),
  owner_id       text references public.providers (id),
  plate          text not null unique,
  kind           text not null check (kind in ('bus', 'minibus', 'train', 'ev_car', 'ev_shuttle', 'ev_keke')),
  model          text not null,
  capacity       integer not null check (capacity > 0),
  status         text not null default 'inactive' check (status in ('active', 'on_trip', 'charging', 'maintenance', 'inactive')),
  verification   text not null default 'pending' check (verification in ('verified', 'pending', 'suspended')),
  area           text not null default 'FCT',
  month_earnings integer not null default 0,
  driver_name    text,
  battery_pct    integer,
  range_km       integer,
  base_fare      integer,
  per_km_fare    integer
);

create table public.charging_stations (
  id          text primary key,
  name        text not null,
  area        text not null,
  ports       integer not null,
  available   integer not null,
  operator_id text references public.providers (id)
);

create table public.shared_rides (
  id            text primary key default 'ride_' || substr(md5(random()::text), 1, 10),
  host_id       text not null,
  host_name     text not null,
  host_org      text not null default '',
  host_verified boolean not null default false,
  origin        text not null,
  destination   text not null,
  depart_at     timestamptz not null,
  seats_total   integer not null check (seats_total between 1 and 6),
  seats_taken   integer not null default 0,
  cost_share    integer not null check (cost_share >= 0),
  vehicle_label text not null default '',
  note          text not null default ''
);

create table public.bookings (
  id             text primary key default 'bk_' || substr(md5(random()::text), 1, 12),
  user_id        uuid not null references auth.users (id) on delete cascade,
  passenger_name text not null,
  kind           text not null check (kind in ('transit', 'electric', 'tag_along')),
  status         text not null check (status in ('confirmed', 'requested', 'accepted', 'completed', 'cancelled', 'declined')),
  origin         text not null,
  destination    text not null,
  departure_at   timestamptz not null,
  fare           integer not null,
  payment_method text not null check (payment_method in ('tap_card', 'qr', 'split_cost')),
  ticket_code    text not null,
  created_at     timestamptz not null default now(),
  title          text,
  seat           text,
  route_id       text references public.routes (id),
  vehicle_id     text references public.vehicles (id),
  ride_id        text references public.shared_rides (id),
  provider_id    text references public.providers (id)
);
create index bookings_user_idx on public.bookings (user_id, departure_at desc);
create index bookings_provider_idx on public.bookings (provider_id, created_at desc);

create table public.wallets (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  card_number text not null,
  balance     integer not null default 0 check (balance >= 0)
);

create table public.audit_log (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  actor_name text not null,
  actor_role text not null,
  action     text not null,
  target     text not null
);

-- Figures that pre-date live platform data (illustrative demo baselines).
create table public.metric_baselines (
  id   integer primary key check (id = 1),
  data jsonb not null
);

-- ------------------------------------------------------------------ helpers

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.my_provider() returns text
language sql stable security definer set search_path = public as $$
  select provider_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('government', 'admin'), false)
$$;

create or replace function public.provider_is_verified(p_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.providers where id = p_id and status = 'verified')
$$;

create or replace function public.manages(p_provider text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_role() = 'admin'
      or (public.my_role() in ('operator', 'fleet_owner') and public.my_provider() = p_provider)
$$;

create or replace function public.log_action(p_action text, p_target text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (actor_name, actor_role, action, target)
  select coalesce(full_name, 'System'), coalesce(role, 'admin'), p_action, p_target
  from public.profiles where id = auth.uid();
end;
$$;

-- New sign-ups become passengers with a starter tap-card balance (demo only).
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
  values (new.id, '50610042' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'), 2500);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------------ row-level security

alter table public.providers enable row level security;
alter table public.profiles enable row level security;
alter table public.routes enable row level security;
alter table public.vehicles enable row level security;
alter table public.charging_stations enable row level security;
alter table public.shared_rides enable row level security;
alter table public.bookings enable row level security;
alter table public.wallets enable row level security;
alter table public.audit_log enable row level security;
alter table public.metric_baselines enable row level security;

create policy providers_read on public.providers for select to authenticated
  using (status = 'verified' or public.is_staff() or id = public.my_provider());

create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.my_role() = 'admin');

create policy routes_public_read on public.routes for select to anon
  using (active and public.provider_is_verified(provider_id));
create policy routes_read on public.routes for select to authenticated
  using ((active and public.provider_is_verified(provider_id)) or public.is_staff() or provider_id = public.my_provider());

create policy vehicles_read on public.vehicles for select to authenticated
  using (
    (verification = 'verified' and public.provider_is_verified(operator_id))
    or public.is_staff()
    or operator_id = public.my_provider()
    or owner_id = public.my_provider()
  );

create policy stations_read on public.charging_stations for select to authenticated using (true);
create policy rides_read on public.shared_rides for select to authenticated using (true);

create policy bookings_read on public.bookings for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_staff()
    or (public.my_role() = 'operator' and provider_id = public.my_provider())
    or (public.my_role() = 'fleet_owner' and vehicle_id in (select id from public.vehicles where owner_id = public.my_provider()))
  );

create policy wallets_read on public.wallets for select to authenticated using (user_id = auth.uid());
create policy audit_read on public.audit_log for select to authenticated using (public.is_staff());
create policy baselines_read on public.metric_baselines for select to authenticated using (true);

-- No insert/update/delete policies: all writes go through the functions below.
revoke insert, update, delete on all tables in schema public from anon, authenticated;

-- ------------------------------------------------------------------ rider actions

create or replace function public.book_transit(p_route_id text, p_departure timestamptz, p_method text)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  r  public.routes;
  v  public.vehicles;
  b  public.bookings;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if p_method not in ('tap_card', 'qr') then raise exception 'Choose tap card or QR to pay.'; end if;

  select * into r from public.routes where id = p_route_id;
  if not found or not r.active or not public.provider_is_verified(r.provider_id) then
    raise exception 'This route is not taking bookings right now.';
  end if;
  if p_departure < now() then raise exception 'That departure has already left. Pick a later time.'; end if;
  if exists (select 1 from public.bookings where user_id = me.id and route_id = r.id and departure_at = p_departure
             and status in ('confirmed', 'requested', 'accepted')) then
    raise exception 'You already have a seat on this departure.';
  end if;

  update public.wallets set balance = balance - r.fare where user_id = me.id and balance >= r.fare;
  if not found then
    raise exception 'Your tap card balance is too low for this fare. Top up and try again.' using errcode = 'P0002';
  end if;

  select * into v from public.vehicles
   where operator_id = r.provider_id and verification = 'verified' and status in ('active', 'on_trip')
   order by random() limit 1;

  insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare,
                               payment_method, ticket_code, title, seat, route_id, vehicle_id, provider_id)
  values (me.id, me.full_name, 'transit', 'confirmed',
          r.stops -> 0 ->> 'name', r.stops -> (jsonb_array_length(r.stops) - 1) ->> 'name',
          p_departure, r.fare, p_method, 'TR-' || upper(substr(md5(random()::text), 1, 6)), r.name,
          'S' || lpad((1 + floor(random() * coalesce(v.capacity, 40)))::int::text, 2, '0'),
          r.id, v.id, r.provider_id)
  returning * into b;
  return b;
end;
$$;

create or replace function public.book_electric(p_vehicle_id text, p_pickup text, p_dropoff text, p_fare integer, p_method text)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  v  public.vehicles;
  b  public.bookings;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;

  select * into v from public.vehicles where id = p_vehicle_id for update;
  if not found then raise exception 'That vehicle is no longer listed.' using errcode = 'P0003'; end if;
  if v.kind not in ('ev_car', 'ev_shuttle', 'ev_keke') or v.verification <> 'verified' or not public.provider_is_verified(v.operator_id) then
    raise exception 'Only verified electric vehicles can be booked.';
  end if;
  if v.status <> 'active' then raise exception 'This vehicle was just taken. Choose another one.'; end if;
  if p_fare < coalesce(v.base_fare, 0) then raise exception 'The fare estimate is out of date. Refresh and try again.'; end if;

  update public.wallets set balance = balance - p_fare where user_id = me.id and balance >= p_fare;
  if not found then
    raise exception 'Your tap card balance is too low for this fare. Top up and try again.' using errcode = 'P0002';
  end if;
  update public.vehicles set status = 'on_trip' where id = v.id;

  insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare,
                               payment_method, ticket_code, title, vehicle_id, provider_id)
  values (me.id, me.full_name, 'electric', 'confirmed', p_pickup, p_dropoff, now() + interval '6 minutes', p_fare,
          p_method, 'EV-' || upper(substr(md5(random()::text), 1, 6)), v.model || ' · ' || v.plate, v.id, v.operator_id)
  returning * into b;
  return b;
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
  if not found then raise exception 'This ride has been withdrawn by the host.' using errcode = 'P0003'; end if;
  if r.host_id = me.id::text then raise exception 'You are hosting this ride.'; end if;
  if r.seats_taken >= r.seats_total then raise exception 'This ride is full.'; end if;
  if exists (select 1 from public.bookings where user_id = me.id and ride_id = r.id and status in ('requested', 'accepted')) then
    raise exception 'You have already asked to join this ride.';
  end if;

  insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare,
                               payment_method, ticket_code, title, ride_id)
  values (me.id, me.full_name, 'tag_along', 'requested', r.origin, r.destination, r.depart_at, r.cost_share,
          'split_cost', 'TA-' || upper(substr(md5(random()::text), 1, 6)), 'With ' || r.host_name, r.id)
  returning * into b;
  return b;
end;
$$;

-- Demo behaviour: hosts accept join requests automatically after a few seconds.
-- Replace with a host-side accept/decline flow before launch.
create or replace function public.settle_tag_along_requests()
returns void
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
begin
  for b in
    select * from public.bookings
     where user_id = auth.uid() and kind = 'tag_along' and status = 'requested' and created_at < now() - interval '6 seconds'
  loop
    update public.shared_rides set seats_taken = seats_taken + 1 where id = b.ride_id and seats_taken < seats_total;
    if found then
      update public.bookings set status = 'accepted' where id = b.id;
    else
      update public.bookings set status = 'declined' where id = b.id;
    end if;
  end loop;
end;
$$;

create or replace function public.offer_shared_ride(p_origin text, p_destination text, p_depart_at timestamptz, p_seats integer,
                                                    p_cost_share integer, p_vehicle_label text, p_note text default '')
returns public.shared_rides
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  r  public.shared_rides;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if p_depart_at < now() then raise exception 'Choose a departure time later than now.'; end if;
  insert into public.shared_rides (host_id, host_name, host_org, host_verified, origin, destination, depart_at,
                                   seats_total, cost_share, vehicle_label, note)
  values (me.id::text, me.full_name, coalesce(me.organisation, 'Tap A Ride member'), me.verified, trim(p_origin), trim(p_destination),
          p_depart_at, p_seats, p_cost_share, trim(p_vehicle_label), trim(coalesce(p_note, '')))
  returning * into r;
  return r;
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
  end if;
  update public.bookings set status = 'cancelled' where id = b.id returning * into b;
  return b;
end;
$$;

-- Demo top-up. In production a payment provider's webhook credits the wallet instead.
create or replace function public.top_up(p_amount integer)
returns public.wallets
language plpgsql security definer set search_path = public as $$
declare
  w public.wallets;
begin
  if auth.uid() is null then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if p_amount < 100 or p_amount > 50000 then raise exception 'Top up between ₦100 and ₦50,000.'; end if;
  update public.wallets set balance = balance + p_amount where user_id = auth.uid() returning * into w;
  return w;
end;
$$;

-- ------------------------------------------------------------------ partner actions

create or replace function public.set_provider_status(p_provider_id text, p_status text)
returns public.providers
language plpgsql security definer set search_path = public as $$
declare
  p public.providers;
begin
  if not public.is_staff() then raise exception 'Your account is not allowed to approve or suspend providers.' using errcode = '42501'; end if;
  if p_status = 'suspended' and public.my_role() <> 'admin' then
    raise exception 'Only platform admins can suspend providers.' using errcode = '42501';
  end if;
  update public.providers set status = p_status where id = p_provider_id returning * into p;
  if not found then raise exception 'Provider not found.' using errcode = 'P0003'; end if;
  perform public.log_action(case p_status when 'verified' then 'Approved provider' when 'suspended' then 'Suspended provider' else 'Returned provider to review' end, p.name);
  return p;
end;
$$;

create or replace function public.set_vehicle_verification(p_vehicle_id text, p_status text)
returns public.vehicles
language plpgsql security definer set search_path = public as $$
declare
  v public.vehicles;
begin
  if not public.is_staff() then raise exception 'Your account is not allowed to verify vehicles.' using errcode = '42501'; end if;
  update public.vehicles set verification = p_status where id = p_vehicle_id returning * into v;
  if not found then raise exception 'Vehicle not found.' using errcode = 'P0003'; end if;
  perform public.log_action(case p_status when 'verified' then 'Verified vehicle' when 'suspended' then 'Rejected vehicle' else 'Flagged vehicle for review' end, v.plate);
  return v;
end;
$$;

create or replace function public.set_vehicle_status(p_vehicle_id text, p_status text)
returns public.vehicles
language plpgsql security definer set search_path = public as $$
declare
  v public.vehicles;
begin
  select * into v from public.vehicles where id = p_vehicle_id;
  if not found then raise exception 'Vehicle not found.' using errcode = 'P0003'; end if;
  if not (public.manages(v.operator_id) or (v.owner_id is not null and public.manages(v.owner_id))) then
    raise exception 'Your account is not allowed to change this vehicle.' using errcode = '42501';
  end if;
  update public.vehicles set status = p_status where id = v.id returning * into v;
  perform public.log_action('Set vehicle status to ' || replace(p_status, '_', ' '), v.plate);
  return v;
end;
$$;

create or replace function public.update_route_fare(p_route_id text, p_fare integer)
returns public.routes
language plpgsql security definer set search_path = public as $$
declare
  r public.routes;
begin
  select * into r from public.routes where id = p_route_id;
  if not found then raise exception 'Route not found.' using errcode = 'P0003'; end if;
  if not public.manages(r.provider_id) or public.my_role() = 'fleet_owner' then
    raise exception 'Your account is not allowed to change fares on this route.' using errcode = '42501';
  end if;
  if p_fare < 100 or p_fare > 20000 then raise exception 'Fares must be between ₦100 and ₦20,000.'; end if;
  update public.routes set fare = p_fare where id = r.id returning * into r;
  perform public.log_action('Updated fare', r.code || ' → ₦' || p_fare);
  return r;
end;
$$;

create or replace function public.register_vehicle(p_operator_id text, p_kind text, p_plate text, p_model text, p_capacity integer, p_owner_id text default null)
returns public.vehicles
language plpgsql security definer set search_path = public as $$
declare
  v public.vehicles;
  electric boolean := p_kind in ('ev_car', 'ev_shuttle', 'ev_keke');
begin
  if not (public.manages(p_operator_id) or (p_owner_id is not null and public.manages(p_owner_id))) then
    raise exception 'Your account is not allowed to register vehicles for this provider.' using errcode = '42501';
  end if;
  if exists (select 1 from public.vehicles where upper(plate) = upper(trim(p_plate))) then
    raise exception 'A vehicle with this plate is already registered.';
  end if;
  insert into public.vehicles (operator_id, owner_id, plate, kind, model, capacity, battery_pct, range_km, base_fare, per_km_fare)
  values (p_operator_id, p_owner_id, upper(trim(p_plate)), p_kind, trim(p_model), p_capacity,
          case when electric then 100 end, case when electric then 300 end,
          case when p_kind = 'ev_car' then 1200 end, case when p_kind = 'ev_car' then 180 end)
  returning * into v;
  perform public.log_action('Registered vehicle', v.plate);
  return v;
end;
$$;

create or replace function public.set_user_role(p_user_id uuid, p_role text, p_provider_id text default null)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
begin
  if public.my_role() <> 'admin' then raise exception 'Your account is not allowed to change account roles.' using errcode = '42501'; end if;
  if p_user_id = auth.uid() then raise exception 'You cannot change your own role.' using errcode = '42501'; end if;
  if p_role in ('operator', 'fleet_owner') and p_provider_id is null then
    raise exception 'Choose the provider this account belongs to.';
  end if;
  update public.profiles
     set role = p_role,
         provider_id = case when p_role in ('operator', 'fleet_owner') then p_provider_id end
   where id = p_user_id
  returning * into p;
  if not found then raise exception 'Account not found.' using errcode = 'P0003'; end if;
  perform public.log_action('Changed role to ' || p_role, p.full_name);
  return p;
end;
$$;

-- Only signed-in users may call the actions; each one checks the role itself.
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
-- RLS policies evaluate these helpers for anonymous route reads too.
grant execute on function public.provider_is_verified(text) to anon;
