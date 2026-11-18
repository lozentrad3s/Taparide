-- Drivers employed by fleet owners and bus/EV operators.
--
-- A fleet owner or operator adds a driver (name, phone, email, licence), puts them on one of
-- their own vehicles (optionally a route) and can suspend or reactivate them. The driver signs
-- in to the partner dashboard with that email and sees only their own vehicle, its riders and
-- the event buses it runs. Their profile has role 'fleet_driver' and no provider_id, so the
-- company-wide policies (vehicles, routes, earnings) never match them.
--
-- Error codes: 42501 permission denied · P0001 validation · P0003 not found.

-- ------------------------------------------------------------------ role
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('passenger', 'operator', 'fleet_owner', 'government', 'admin', 'event_partner', 'fleet_driver'));

-- ------------------------------------------------------------------ table
create table if not exists public.fleet_drivers (
  id             text primary key default 'fd_' || substr(md5(random()::text), 1, 10),
  provider_id    text not null references public.providers (id) on delete cascade,
  user_id        uuid references auth.users (id) on delete set null,
  full_name      text not null check (length(trim(full_name)) between 2 and 80),
  phone          text not null,
  email          text not null,
  licence_number text not null,
  vehicle_id     text references public.vehicles (id) on delete set null,
  route_id       text references public.routes (id) on delete set null,
  status         text not null default 'active' check (status in ('active', 'suspended')),
  created_at     timestamptz not null default now()
);
create unique index if not exists fleet_drivers_email_idx on public.fleet_drivers (lower(email));
create unique index if not exists fleet_drivers_user_idx on public.fleet_drivers (user_id) where user_id is not null;
create index if not exists fleet_drivers_provider_idx on public.fleet_drivers (provider_id);
create index if not exists fleet_drivers_vehicle_idx on public.fleet_drivers (vehicle_id);
alter table public.fleet_drivers enable row level security;

-- ------------------------------------------------------------------ helpers
-- The vehicle (and route) the signed-in driver may work on right now: none while suspended.
create or replace function public.my_driver_vehicle() returns text
language sql stable security definer set search_path = public as $$
  select d.vehicle_id from public.fleet_drivers d
   where d.user_id = auth.uid() and d.status = 'active' and public.my_role() = 'fleet_driver'
   limit 1
$$;

create or replace function public.my_driver_route() returns text
language sql stable security definer set search_path = public as $$
  select d.route_id from public.fleet_drivers d
   where d.user_id = auth.uid() and d.status = 'active' and public.my_role() = 'fleet_driver'
   limit 1
$$;

-- Drivers go only on the company's own vehicles (operated or owned), on routes those vehicles run.
create or replace function public._check_driver_assignment(p_provider text, p_vehicle_id text, p_route_id text) returns void
language plpgsql stable security definer set search_path = public as $$
declare
  v public.vehicles;
  r public.routes;
begin
  if p_vehicle_id is null then
    if p_route_id is not null then raise exception 'Pick a vehicle before choosing a route.'; end if;
    return;
  end if;
  select * into v from public.vehicles where id = p_vehicle_id;
  if not found then raise exception 'Vehicle not found.' using errcode = 'P0003'; end if;
  if v.operator_id <> p_provider and v.owner_id is distinct from p_provider then
    raise exception 'You can only assign drivers to your own vehicles.' using errcode = '42501';
  end if;
  if v.verification = 'suspended' then raise exception 'This vehicle is suspended from the register.'; end if;
  if p_route_id is null then return; end if;
  select * into r from public.routes where id = p_route_id;
  if not found then raise exception 'Route not found.' using errcode = 'P0003'; end if;
  if r.provider_id <> v.operator_id and r.provider_id <> p_provider then
    raise exception 'Pick a route this vehicle runs on.';
  end if;
end;
$$;

-- ------------------------------------------------------------------ row-level security
-- Admins see every driver, fleet owners and operators their own company's, a driver only themself.
drop policy if exists fleet_drivers_read on public.fleet_drivers;
create policy fleet_drivers_read on public.fleet_drivers for select to authenticated
  using (
    public.my_role() = 'admin'
    or (public.my_role() in ('operator', 'fleet_owner') and provider_id = public.my_provider())
    or user_id = auth.uid()
  );

-- A driver also reads their assigned vehicle and route (even when not public).
drop policy if exists vehicles_read on public.vehicles;
create policy vehicles_read on public.vehicles for select to authenticated
  using (
    (verification = 'verified' and public.provider_is_verified(operator_id))
    or public.is_staff()
    or operator_id = public.my_provider()
    or owner_id = public.my_provider()
    or id = public.my_driver_vehicle()
  );

drop policy if exists routes_read on public.routes;
create policy routes_read on public.routes for select to authenticated
  using ((active and public.provider_is_verified(provider_id)) or public.is_staff() or provider_id = public.my_provider() or id = public.my_driver_route());

-- Bookings: same as before, plus a driver sees riders on their vehicle and on event buses it runs.
drop policy if exists bookings_read on public.bookings;
create policy bookings_read on public.bookings for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_staff()
    or (public.my_role() = 'operator' and provider_id = public.my_provider())
    or (public.my_role() = 'fleet_owner' and vehicle_id in (select id from public.vehicles where owner_id = public.my_provider()))
    or (ride_id is not null and ride_id in (select id from public.shared_rides where host_id = auth.uid()::text))
    or (public.my_role() = 'event_partner' and event_id in (select id from public.events where provider_id = public.my_provider()))
    or (public.my_role() = 'fleet_driver' and public.my_driver_vehicle() is not null and (
          vehicle_id = public.my_driver_vehicle()
          or event_bus_id in (select id from public.event_buses where vehicle_id = public.my_driver_vehicle())))
  );

-- ------------------------------------------------------------------ managing drivers
create or replace function public.add_fleet_driver(p_full_name text, p_phone text, p_email text, p_licence_number text,
                                                   p_provider_id text default null, p_vehicle_id text default null, p_route_id text default null)
returns public.fleet_drivers
language plpgsql security definer set search_path = public as $$
declare
  v_provider text := coalesce(p_provider_id, public.my_provider());
  v_email    text := lower(trim(coalesce(p_email, '')));
  prov public.providers;
  p    public.profiles;
  d    public.fleet_drivers;
begin
  if v_provider is null or not public.manages(v_provider) then
    raise exception 'Your account is not allowed to add drivers for this company.' using errcode = '42501';
  end if;
  select * into prov from public.providers where id = v_provider;
  if not found then raise exception 'Company not found.' using errcode = 'P0003'; end if;
  if prov.kind in ('private_driver', 'event_organiser') then
    raise exception 'Only fleet owners and bus or EV operators can add drivers.' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then raise exception 'Enter the driver''s full name.'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Enter a valid email address.'; end if;
  if length(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')) < 10 then raise exception 'Enter a valid phone number.'; end if;
  if length(regexp_replace(coalesce(p_licence_number, ''), '[[:space:]]', '', 'g')) < 6 then raise exception 'Enter the driver''s licence number.'; end if;
  if exists (select 1 from public.fleet_drivers where lower(email) = v_email) then
    raise exception 'A driver with this email is already registered.';
  end if;
  perform public._check_driver_assignment(v_provider, p_vehicle_id, p_route_id);

  -- An existing, confirmed passenger account with this email becomes the driver's login.
  select pr.* into p from public.profiles pr join auth.users u on u.id = pr.id
   where lower(pr.email) = v_email and u.email_confirmed_at is not null
   limit 1;
  if p.id is not null and p.role <> 'passenger' then
    raise exception 'This email belongs to another partner account. Use the driver''s personal email.';
  end if;

  insert into public.fleet_drivers (provider_id, user_id, full_name, phone, email, licence_number, vehicle_id, route_id)
  values (v_provider, p.id, trim(p_full_name), trim(p_phone), v_email,
          upper(regexp_replace(trim(p_licence_number), '[[:space:]]+', '', 'g')),
          p_vehicle_id, case when p_vehicle_id is null then null else p_route_id end)
  returning * into d;
  if p.id is not null then
    update public.profiles set role = 'fleet_driver', provider_id = null, organisation = prov.name where id = p.id;
  end if;
  if p_vehicle_id is not null then
    update public.vehicles set driver_name = d.full_name where id = p_vehicle_id;
  end if;
  perform public.log_action('Added driver', d.full_name || ' · ' || prov.name);
  return d;
end;
$$;

create or replace function public.assign_fleet_driver(p_driver_id text, p_vehicle_id text default null, p_route_id text default null)
returns public.fleet_drivers
language plpgsql security definer set search_path = public as $$
declare
  d public.fleet_drivers;
begin
  select * into d from public.fleet_drivers where id = p_driver_id for update;
  if not found then raise exception 'Driver not found.' using errcode = 'P0003'; end if;
  if not public.manages(d.provider_id) then
    raise exception 'Your account is not allowed to manage this driver.' using errcode = '42501';
  end if;
  perform public._check_driver_assignment(d.provider_id, p_vehicle_id, p_route_id);
  update public.fleet_drivers
     set vehicle_id = p_vehicle_id, route_id = case when p_vehicle_id is null then null else p_route_id end
   where id = d.id
  returning * into d;
  if p_vehicle_id is not null then
    update public.vehicles set driver_name = d.full_name where id = p_vehicle_id;
  end if;
  perform public.log_action(case when p_vehicle_id is null then 'Unassigned driver' else 'Assigned driver' end,
                            d.full_name || coalesce(' → ' || (select plate from public.vehicles where id = p_vehicle_id), ''));
  return d;
end;
$$;

create or replace function public.set_fleet_driver_status(p_driver_id text, p_status text)
returns public.fleet_drivers
language plpgsql security definer set search_path = public as $$
declare
  d public.fleet_drivers;
begin
  if p_status not in ('active', 'suspended') then raise exception 'Unknown driver status.'; end if;
  select * into d from public.fleet_drivers where id = p_driver_id for update;
  if not found then raise exception 'Driver not found.' using errcode = 'P0003'; end if;
  if not public.manages(d.provider_id) then
    raise exception 'Your account is not allowed to suspend or reactivate this driver.' using errcode = '42501';
  end if;
  update public.fleet_drivers set status = p_status where id = d.id returning * into d;
  -- A suspended driver's phone stops putting the vehicle on the live map.
  if p_status = 'suspended' and d.user_id is not null then
    delete from public.vehicle_positions where reported_by = d.user_id;
  end if;
  perform public.log_action(case p_status when 'suspended' then 'Suspended driver' else 'Reactivated driver' end, d.full_name);
  return d;
end;
$$;

-- ------------------------------------------------------------------ the driver's own actions
-- accept: a car ride is accepted / a bus rider boards. complete: the rider is dropped off.
create or replace function public.driver_booking_action(p_booking_id text, p_action text)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_vehicle text := public.my_driver_vehicle();
  b public.bookings;
begin
  if coalesce(public.my_role(), '') <> 'fleet_driver' then
    raise exception 'Your account is not allowed to update rides from the driver dashboard.' using errcode = '42501';
  end if;
  if v_vehicle is null then
    raise exception 'You are not assigned to a vehicle right now. Ask your fleet manager.' using errcode = '42501';
  end if;
  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0003'; end if;
  if b.vehicle_id is distinct from v_vehicle
     and not exists (select 1 from public.event_buses e where e.id = b.event_bus_id and e.vehicle_id = v_vehicle) then
    raise exception 'Your account is not allowed to update this booking (it is not on your vehicle).' using errcode = '42501';
  end if;

  if p_action = 'accept' then
    if b.kind = 'event_bus' and b.status = 'requested' then
      raise exception 'This seat is confirmed once the operator fixes the departure time.';
    end if;
    if b.status <> 'confirmed' then raise exception 'This booking is not waiting for you.'; end if;
    update public.bookings set status = 'accepted' where id = b.id returning * into b;
  elsif p_action = 'complete' then
    if b.status not in ('confirmed', 'accepted') then raise exception 'This booking is not in progress.'; end if;
    update public.bookings set status = 'completed' where id = b.id returning * into b;
    if b.kind = 'electric' then
      update public.vehicles set status = 'active', month_earnings = month_earnings + b.fare where id = b.vehicle_id;
    end if;
    perform public.log_action('Completed ride', b.passenger_name || ' · ' || b.origin || ' → ' || b.destination);
  else
    raise exception 'Unknown action.';
  end if;
  return b;
end;
$$;

-- Start or end a trip on the assigned vehicle; ending drops off riders who boarded for a departure that has left.
create or replace function public.driver_set_trip(p_start boolean)
returns public.vehicles
language plpgsql security definer set search_path = public as $$
declare
  v_vehicle text := public.my_driver_vehicle();
  v public.vehicles;
begin
  if coalesce(public.my_role(), '') <> 'fleet_driver' then
    raise exception 'Your account is not allowed to start or end trips.' using errcode = '42501';
  end if;
  if v_vehicle is null then
    raise exception 'You are not assigned to a vehicle right now. Ask your fleet manager.' using errcode = '42501';
  end if;
  select * into v from public.vehicles where id = v_vehicle for update;
  if not found then raise exception 'Vehicle not found.' using errcode = 'P0003'; end if;
  if p_start then
    if v.status in ('maintenance', 'inactive') then
      raise exception 'Your vehicle is marked %. Ask your fleet manager before starting a trip.', replace(v.status, '_', ' ');
    end if;
    update public.vehicles set status = 'on_trip' where id = v.id returning * into v;
  else
    update public.vehicles set status = 'active' where id = v.id returning * into v;
    update public.bookings set status = 'completed'
     where vehicle_id = v.id and status = 'accepted' and departure_at < now() + interval '1 minute';
  end if;
  perform public.log_action(case when p_start then 'Started trip' else 'Ended trip' end, v.plate);
  return v;
end;
$$;

-- Live tracking: the assigned driver may report their vehicle's position too.
create or replace function public.report_vehicle_position(p_vehicle_id text, p_lat double precision, p_lng double precision,
                                                          p_heading double precision default null, p_speed_kmh double precision default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v public.vehicles;
begin
  select * into v from public.vehicles where id = p_vehicle_id;
  if not found then raise exception 'Vehicle not found.' using errcode = 'P0003'; end if;
  if not (public.manages(v.operator_id) or (v.owner_id is not null and public.manages(v.owner_id)) or v.id = public.my_driver_vehicle()) then
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

-- ------------------------------------------------------------------ linking the driver's login
-- When someone confirms an account whose email a fleet added as a driver, that (passenger)
-- account becomes the driver's login. Waiting for confirmation stops anyone claiming a driver
-- slot with an email they don't own. Runs after on_auth_user_created, which makes the profile.
create or replace function public.link_fleet_driver() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  d public.fleet_drivers;
begin
  if new.email is null or new.email_confirmed_at is null then return new; end if;
  select * into d from public.fleet_drivers where lower(email) = lower(new.email) and user_id is null limit 1;
  if not found then return new; end if;
  if not exists (select 1 from public.profiles where id = new.id and role = 'passenger') then return new; end if;
  update public.fleet_drivers set user_id = new.id where id = d.id;
  update public.profiles
     set role = 'fleet_driver', provider_id = null, organisation = (select name from public.providers where id = d.provider_id)
   where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_fleet_driver on auth.users;
create trigger on_auth_user_fleet_driver
  after insert or update of email_confirmed_at on auth.users
  for each row execute function public.link_fleet_driver();

-- ------------------------------------------------------------------ grants
revoke insert, update, delete on public.fleet_drivers from anon, authenticated;
revoke all on public.fleet_drivers from anon;
grant select on public.fleet_drivers to authenticated;
revoke execute on function public._check_driver_assignment(text, text, text), public.link_fleet_driver() from public, anon, authenticated;
revoke execute on function public.my_driver_vehicle(), public.my_driver_route(),
  public.add_fleet_driver(text, text, text, text, text, text, text), public.assign_fleet_driver(text, text, text),
  public.set_fleet_driver_status(text, text), public.driver_booking_action(text, text), public.driver_set_trip(boolean),
  public.report_vehicle_position(text, double precision, double precision, double precision, double precision) from public, anon;
grant execute on function public.my_driver_vehicle(), public.my_driver_route(),
  public.add_fleet_driver(text, text, text, text, text, text, text), public.assign_fleet_driver(text, text, text),
  public.set_fleet_driver_status(text, text), public.driver_booking_action(text, text), public.driver_set_trip(boolean),
  public.report_vehicle_position(text, double precision, double precision, double precision, double precision) to authenticated;
