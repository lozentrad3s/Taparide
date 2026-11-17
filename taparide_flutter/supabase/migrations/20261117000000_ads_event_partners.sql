-- Header ads with watch-to-earn ride credit; partner-only events with tickets and
-- event buses that registered operators offer and riders fill by preferred time.

-- ------------------------------------------------------------------ roles and kinds
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('passenger', 'operator', 'fleet_owner', 'government', 'admin', 'event_partner'));

alter table public.providers drop constraint if exists providers_kind_check;
alter table public.providers add constraint providers_kind_check
  check (kind in ('bus_operator', 'fleet_owner', 'rail', 'electric', 'shuttle', 'tricycle', 'private_driver', 'event_organiser'));

alter table public.bookings drop constraint if exists bookings_kind_check;
alter table public.bookings add constraint bookings_kind_check
  check (kind in ('transit', 'electric', 'tag_along', 'event_bus', 'event_ticket'));

-- ------------------------------------------------------------------ ads
create table if not exists public.ads (
  id          text primary key default 'ad_' || substr(md5(random()::text), 1, 10),
  sponsor     text not null,
  headline    text not null check (char_length(headline) between 3 and 80),
  body        text not null default '',
  cta_label   text not null default 'Learn more',
  cta_link    text,
  colour      text not null default '#0B5D3B',
  icon        text not null default 'campaign',
  reward      integer not null default 50 check (reward between 0 and 500),
  seconds     integer not null default 15 check (seconds between 5 and 60),
  house       boolean not null default false,
  active      boolean not null default true,
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,
  impressions integer not null default 0,
  views       integer not null default 0,
  created_at  timestamptz not null default now()
);
alter table public.ads enable row level security;
drop policy if exists ads_read on public.ads;
create policy ads_read on public.ads for select to authenticated
  using ((active and starts_at <= now() and (ends_at is null or ends_at > now())) or public.is_staff());

create table if not exists public.ad_views (
  id          text primary key default 'av_' || substr(md5(random()::text), 1, 12),
  ad_id       text not null references public.ads (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  started_at  timestamptz not null default now(),
  rewarded_at timestamptz,
  reward      integer not null default 0
);
create index if not exists ad_views_user_idx on public.ad_views (user_id, started_at desc);
alter table public.ad_views enable row level security;
drop policy if exists ad_views_read on public.ad_views;
create policy ad_views_read on public.ad_views for select to authenticated using (user_id = auth.uid() or public.is_staff());

-- Rewards per rider per day.
create or replace function public.ad_rewards_left() returns integer
language sql stable security definer set search_path = public as $$
  select greatest(0, 3 - (select count(*)::int from public.ad_views
                           where user_id = auth.uid() and rewarded_at is not null and rewarded_at > date_trunc('day', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos'))
$$;

-- The clock starts on the server, so the reward can't be claimed before the ad has played.
create or replace function public.start_ad_view(p_ad_id text)
returns public.ad_views
language plpgsql security definer set search_path = public as $$
declare
  a public.ads;
  v public.ad_views;
begin
  if auth.uid() is null then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  select * into a from public.ads where id = p_ad_id and active;
  if not found then raise exception 'This ad has ended.' using errcode = 'P0003'; end if;
  if (select count(*) from public.ad_views where user_id = auth.uid() and started_at > now() - interval '1 hour') >= 30 then
    raise exception 'Too many ads in a row. Try again later.';
  end if;
  update public.ads set views = views + 1 where id = a.id;
  insert into public.ad_views (ad_id, user_id) values (a.id, auth.uid()) returning * into v;
  return v;
end;
$$;

create or replace function public.claim_ad_reward(p_view_id text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v public.ad_views;
  a public.ads;
  w public.wallets;
  credit integer;
begin
  select * into v from public.ad_views where id = p_view_id and user_id = auth.uid() for update;
  if not found then raise exception 'Ad view not found.' using errcode = 'P0003'; end if;
  if v.rewarded_at is not null then raise exception 'You already earned this reward.'; end if;
  select * into a from public.ads where id = v.ad_id;
  if now() - v.started_at < make_interval(secs => a.seconds - 1) then raise exception 'Watch the whole ad to earn the reward.'; end if;
  credit := case when public.ad_rewards_left() > 0 then a.reward else 0 end;
  update public.ad_views set rewarded_at = now(), reward = credit where id = v.id;
  update public.wallets set balance = balance + credit where user_id = auth.uid() returning * into w;
  return jsonb_build_object('reward', credit, 'balance', w.balance, 'left', public.ad_rewards_left());
end;
$$;

create or replace function public.count_ad_impressions(p_ids text[]) returns void
language sql security definer set search_path = public as $$
  update public.ads set impressions = impressions + 1 where id = any (p_ids) and active;
$$;

-- House ads until paying advertisers are signed (labelled as Tap A Ride's own).
insert into public.ads (id, sponsor, headline, body, cta_label, cta_link, colour, icon, reward, seconds, house) values
  ('ad_advertise', 'Tap A Ride', 'Your brand here, in front of Abuja commuters', 'Reach riders on every trip without interrupting them. Ask about header slots and sponsored rides.', 'Advertise with us', 'mailto:hello@taparide.app', '#0B5D3B', 'campaign', 50, 15, true),
  ('ad_ev', 'Tap A Ride Electric', 'Go electric this week', 'Verified electric cars across Maitama, Wuse and Jabi. Quiet, clean and fixed fares.', 'Book an EV', '/ev', '#0E7C66', 'electric_car', 50, 15, true),
  ('ad_events', 'Tap A Ride Events', 'Event buses: skip the parking', 'Book a seat on a bus to the stadium or the conference centre and ride back together.', 'See events', '/events', '#1F3A8A', 'celebration', 50, 15, true)
on conflict (id) do nothing;

-- ------------------------------------------------------------------ events: partners only, with tickets
alter table public.events add column if not exists provider_id text references public.providers (id);
alter table public.events add column if not exists ticket_price integer not null default 0 check (ticket_price between 0 and 500000);
alter table public.events add column if not exists tickets_total integer not null default 0 check (tickets_total >= 0);
alter table public.events add column if not exists tickets_sold integer not null default 0 check (tickets_sold >= 0);
alter table public.events add column if not exists sponsored boolean not null default false;
alter table public.events add column if not exists ticket_link text;

-- Only partner and sponsored events are public; earlier member-listed events leave the list.
update public.events set status = 'removed' where status = 'listed' and provider_id is null and not sponsored;

drop policy if exists events_read on public.events;
create policy events_read on public.events for select to authenticated
  using (status = 'listed' or public.is_staff() or provider_id = public.my_provider());

drop function if exists public.create_event(text, text, text, timestamptz, timestamptz, text, text, double precision, double precision);
create or replace function public.create_event(p_title text, p_venue text, p_area text, p_starts_at timestamptz, p_ends_at timestamptz default null,
                                               p_category text default 'community', p_description text default '',
                                               p_lat double precision default null, p_lng double precision default null,
                                               p_ticket_price integer default 0, p_tickets_total integer default 0, p_ticket_link text default null)
returns public.events
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  org public.providers;
  e  public.events;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if me.role not in ('event_partner', 'admin') then
    raise exception 'Only event partners can list events. Apply as an event partner to post yours.' using errcode = '42501';
  end if;
  if me.role = 'event_partner' then
    select * into org from public.providers where id = me.provider_id;
    if not found or org.status <> 'verified' then raise exception 'Your organisation is not verified yet.' using errcode = '42501'; end if;
  end if;
  if p_starts_at < now() then raise exception 'Choose a start time later than now.'; end if;
  if p_ends_at is not null and p_ends_at < p_starts_at then raise exception 'The event cannot end before it starts.'; end if;
  if coalesce(p_ticket_price, 0) > 0 and coalesce(p_tickets_total, 0) < 1 then raise exception 'Set how many tickets are for sale.'; end if;
  insert into public.events (title, venue, area, lat, lng, starts_at, ends_at, category, description, organiser_id, organiser_name,
                             provider_id, ticket_price, tickets_total, sponsored, ticket_link)
  values (trim(p_title), trim(p_venue), coalesce(nullif(trim(p_area), ''), 'Abuja'), p_lat, p_lng, p_starts_at, p_ends_at,
          coalesce(p_category, 'community'), trim(coalesce(p_description, '')), me.id, coalesce(org.name, me.organisation, me.full_name),
          me.provider_id, greatest(coalesce(p_ticket_price, 0), 0), greatest(coalesce(p_tickets_total, 0), 0), me.role = 'admin', nullif(trim(p_ticket_link), ''))
  returning * into e;
  perform public.log_action('Listed event', e.title);
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
  if not public.is_staff() and (e.provider_id is null or e.provider_id is distinct from public.my_provider() or public.my_role() <> 'event_partner') then
    raise exception 'Your account is not allowed to remove this event.' using errcode = '42501';
  end if;
  update public.events set status = 'removed' where id = e.id returning * into e;
  -- Riders get their money back for tickets and buses to a removed event.
  update public.wallets w set balance = w.balance + b.fare
    from public.bookings b
   where b.event_id = e.id and b.status in ('confirmed', 'requested') and b.payment_method <> 'split_cost' and w.user_id = b.user_id;
  update public.bookings set status = 'cancelled' where event_id = e.id and status in ('confirmed', 'requested');
  update public.event_buses set status = 'cancelled' where event_id = e.id;
  perform public.log_action('Removed event', e.title);
  return e;
end;
$$;

-- ------------------------------------------------------------------ event buses
alter table public.bookings add column if not exists event_id text references public.events (id);
alter table public.bookings add column if not exists event_bus_id text;

create table if not exists public.event_buses (
  id            text primary key default 'eb_' || substr(md5(random()::text), 1, 10),
  event_id      text not null references public.events (id) on delete cascade,
  provider_id   text not null references public.providers (id),
  provider_name text not null,
  vehicle_id    text references public.vehicles (id),
  vehicle_label text not null default '',
  origin        text not null,
  fare          integer not null check (fare between 100 and 20000),
  capacity      integer not null check (capacity between 4 and 90),
  min_riders    integer not null default 10 check (min_riders >= 1),
  slots         timestamptz[] not null,
  seats_by_slot jsonb not null default '{}',
  confirmed_at  timestamptz,
  status        text not null default 'open' check (status in ('open', 'confirmed', 'cancelled')),
  created_at    timestamptz not null default now()
);
create index if not exists event_buses_event_idx on public.event_buses (event_id);
alter table public.event_buses enable row level security;
drop policy if exists event_buses_read on public.event_buses;
create policy event_buses_read on public.event_buses for select to authenticated using (true);

alter table public.bookings drop constraint if exists bookings_event_bus_fk;
alter table public.bookings add constraint bookings_event_bus_fk foreign key (event_bus_id) references public.event_buses (id);

-- Event partners see tickets and bus seats for their events; operators see seats on their buses.
drop policy if exists bookings_read on public.bookings;
create policy bookings_read on public.bookings for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_staff()
    or (public.my_role() = 'operator' and provider_id = public.my_provider())
    or (public.my_role() = 'fleet_owner' and vehicle_id in (select id from public.vehicles where owner_id = public.my_provider()))
    or (ride_id is not null and ride_id in (select id from public.shared_rides where host_id = auth.uid()::text))
    or (public.my_role() = 'event_partner' and event_id in (select id from public.events where provider_id = public.my_provider()))
  );

create or replace function public.slot_key(p timestamptz) returns text
language sql immutable as $$ select to_char(p at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') $$;

-- A registered bus operator puts a bus on an event: where it leaves from, the fare and the times riders can pick.
create or replace function public.offer_event_bus(p_event_id text, p_origin text, p_fare integer, p_capacity integer, p_min_riders integer,
                                                  p_slots timestamptz[], p_vehicle_id text default null)
returns public.event_buses
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  org public.providers;
  e public.events;
  v public.vehicles;
  b public.event_buses;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found or me.role not in ('operator', 'admin') or (me.role = 'operator' and me.provider_id is null) then
    raise exception 'Only registered bus operators can run event buses.' using errcode = '42501';
  end if;
  select * into org from public.providers where id = coalesce(me.provider_id, 'p_metro');
  if org.status <> 'verified' then raise exception 'Your company is not verified yet.' using errcode = '42501'; end if;
  if org.kind not in ('bus_operator', 'shuttle', 'electric') then raise exception 'Event buses need a bus, shuttle or electric fleet operator.' using errcode = '42501'; end if;
  select * into e from public.events where id = p_event_id and status = 'listed';
  if not found then raise exception 'Event not found.' using errcode = 'P0003'; end if;
  if p_slots is null or array_length(p_slots, 1) is null then raise exception 'Add at least one departure time.'; end if;
  if array_length(p_slots, 1) > 4 then raise exception 'Offer up to 4 departure times.'; end if;
  if exists (select 1 from unnest(p_slots) s where s < now() or s > e.starts_at) then
    raise exception 'Departure times must be before the event starts.';
  end if;
  if p_vehicle_id is not null then
    select * into v from public.vehicles where id = p_vehicle_id and operator_id = org.id;
    if not found or v.verification <> 'verified' then raise exception 'Pick one of your verified vehicles.'; end if;
  end if;
  insert into public.event_buses (event_id, provider_id, provider_name, vehicle_id, vehicle_label, origin, fare, capacity, min_riders, slots)
  values (e.id, org.id, org.name, v.id, coalesce(v.model || ' · ' || v.plate, ''), trim(p_origin), p_fare,
          coalesce(v.capacity, p_capacity), least(greatest(p_min_riders, 1), coalesce(v.capacity, p_capacity)), p_slots)
  returning * into b;
  perform public.log_action('Offered event bus', e.title || ' from ' || b.origin);
  return b;
end;
$$;

-- A rider books a seat and picks the time that suits them. The fare is held until the operator confirms a time.
create or replace function public.book_event_bus(p_bus_id text, p_slot timestamptz, p_method text default 'tap_card')
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  b public.event_buses;
  e public.events;
  bk public.bookings;
  key text;
  taken integer;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  select * into b from public.event_buses where id = p_bus_id for update;
  if not found or b.status = 'cancelled' then raise exception 'This bus is no longer running.' using errcode = 'P0003'; end if;
  select * into e from public.events where id = b.event_id and status = 'listed';
  if not found then raise exception 'This event has been removed.' using errcode = 'P0003'; end if;
  if b.status = 'confirmed' then p_slot := b.confirmed_at; end if;
  if not (p_slot = any (b.slots)) then raise exception 'Pick one of the departure times offered.'; end if;
  if p_slot < now() then raise exception 'That departure has already left.'; end if;
  if exists (select 1 from public.bookings where user_id = me.id and event_bus_id = b.id and status in ('confirmed', 'requested')) then
    raise exception 'You already have a seat on this bus.';
  end if;
  key := public.slot_key(p_slot);
  taken := coalesce((b.seats_by_slot ->> key)::int, 0);
  if taken >= b.capacity then raise exception 'That departure is full. Pick another time.'; end if;
  update public.wallets set balance = balance - b.fare where user_id = me.id and balance >= b.fare;
  if not found then raise exception 'Your tap card balance is too low for this fare. Top up and try again.' using errcode = 'P0002'; end if;
  update public.event_buses set seats_by_slot = jsonb_set(seats_by_slot, array[key], to_jsonb(taken + 1)) where id = b.id;
  insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare, payment_method,
                               ticket_code, title, seat, vehicle_id, provider_id, event_id, event_bus_id)
  values (me.id, me.full_name, 'event_bus', case when b.status = 'confirmed' then 'confirmed' else 'requested' end,
          b.origin, e.venue, p_slot, b.fare, coalesce(p_method, 'tap_card'),
          'EB-' || upper(substr(md5(random()::text), 1, 6)), e.title, 'S' || lpad((taken + 1)::text, 2, '0'), b.vehicle_id, b.provider_id, e.id, b.id)
  returning * into bk;
  return bk;
end;
$$;

-- The operator fixes the departure (usually the most popular time). Every rider on the bus moves to it.
create or replace function public.confirm_event_bus(p_bus_id text, p_slot timestamptz)
returns public.event_buses
language plpgsql security definer set search_path = public as $$
declare
  b public.event_buses;
  total integer;
begin
  select * into b from public.event_buses where id = p_bus_id for update;
  if not found then raise exception 'Bus not found.' using errcode = 'P0003'; end if;
  if not public.manages(b.provider_id) then raise exception 'Only the bus operator can confirm this bus.' using errcode = '42501'; end if;
  if not (p_slot = any (b.slots)) then raise exception 'Pick one of the offered times.'; end if;
  select count(*) into total from public.bookings where event_bus_id = b.id and status in ('requested', 'confirmed');
  if total > b.capacity then raise exception 'More riders than seats: add a second bus first.'; end if;
  update public.bookings set departure_at = p_slot, status = 'confirmed' where event_bus_id = b.id and status in ('requested', 'confirmed');
  update public.event_buses set status = 'confirmed', confirmed_at = p_slot,
         seats_by_slot = jsonb_build_object(public.slot_key(p_slot), total)
   where id = b.id returning * into b;
  perform public.log_action('Confirmed event bus', b.origin || ' at ' || to_char(p_slot at time zone 'Africa/Lagos', 'HH24:MI'));
  return b;
end;
$$;

create or replace function public.cancel_event_bus(p_bus_id text)
returns public.event_buses
language plpgsql security definer set search_path = public as $$
declare
  b public.event_buses;
begin
  select * into b from public.event_buses where id = p_bus_id for update;
  if not found then raise exception 'Bus not found.' using errcode = 'P0003'; end if;
  if not public.manages(b.provider_id) then raise exception 'Only the bus operator can cancel this bus.' using errcode = '42501'; end if;
  update public.wallets w set balance = w.balance + bk.fare
    from public.bookings bk where bk.event_bus_id = b.id and bk.status in ('requested', 'confirmed') and w.user_id = bk.user_id;
  update public.bookings set status = 'cancelled' where event_bus_id = b.id and status in ('requested', 'confirmed');
  update public.event_buses set status = 'cancelled', seats_by_slot = '{}' where id = b.id returning * into b;
  perform public.log_action('Cancelled event bus', b.origin);
  return b;
end;
$$;

-- Event tickets sold through Tap A Ride.
create or replace function public.buy_event_ticket(p_event_id text, p_method text default 'tap_card')
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  e public.events;
  bk public.bookings;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  select * into e from public.events where id = p_event_id and status = 'listed' for update;
  if not found then raise exception 'Event not found.' using errcode = 'P0003'; end if;
  if e.starts_at < now() then raise exception 'This event has started.'; end if;
  if e.tickets_total = 0 then raise exception 'Tickets for this event are not sold on Tap A Ride.'; end if;
  if e.tickets_sold >= e.tickets_total then raise exception 'Sold out.'; end if;
  if (select count(*) from public.bookings where user_id = me.id and event_id = e.id and kind = 'event_ticket' and status = 'confirmed') >= 4 then
    raise exception 'You can hold up to 4 tickets for one event.';
  end if;
  if e.ticket_price > 0 then
    update public.wallets set balance = balance - e.ticket_price where user_id = me.id and balance >= e.ticket_price;
    if not found then raise exception 'Your tap card balance is too low for this ticket. Top up and try again.' using errcode = 'P0002'; end if;
  end if;
  update public.events set tickets_sold = tickets_sold + 1 where id = e.id;
  insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare, payment_method,
                               ticket_code, title, seat, provider_id, event_id)
  values (me.id, me.full_name, 'event_ticket', 'confirmed', e.venue, e.venue, e.starts_at, e.ticket_price, coalesce(p_method, 'tap_card'),
          'ET-' || upper(substr(md5(random()::text), 1, 6)), e.title, 'Entry', e.provider_id, e.id)
  returning * into bk;
  return bk;
end;
$$;

-- Cancelling: event buses and tickets free their seat and refund before departure.
create or replace function public.cancel_booking(p_booking_id text)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  key text;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0003'; end if;
  if b.user_id <> auth.uid() then raise exception 'Your account is not allowed to cancel this booking.' using errcode = '42501'; end if;
  if b.status not in ('confirmed', 'requested', 'accepted') then raise exception 'This booking can no longer be cancelled.'; end if;

  if b.payment_method <> 'split_cost' and b.departure_at > now() and b.kind <> 'tag_along' then
    update public.wallets set balance = balance + b.fare where user_id = b.user_id;
  end if;
  if b.kind = 'electric' and b.vehicle_id is not null then
    update public.vehicles set status = 'active' where id = b.vehicle_id;
  end if;
  if b.kind = 'tag_along' and b.status = 'accepted' then
    update public.shared_rides set seats_taken = greatest(0, seats_taken - 1) where id = b.ride_id;
    if b.departure_at > now() then update public.wallets set balance = balance + b.fare where user_id = b.user_id; end if;
  end if;
  if b.kind = 'event_bus' and b.event_bus_id is not null then
    key := public.slot_key(b.departure_at);
    update public.event_buses
       set seats_by_slot = jsonb_set(seats_by_slot, array[key], to_jsonb(greatest(0, coalesce((seats_by_slot ->> key)::int, 0) - 1)))
     where id = b.event_bus_id;
  end if;
  if b.kind = 'event_ticket' and b.event_id is not null then
    update public.events set tickets_sold = greatest(0, tickets_sold - 1) where id = b.event_id;
  end if;
  update public.trip_shares set revoked = true where booking_id = b.id;
  update public.bookings set status = 'cancelled' where id = b.id returning * into b;
  return b;
end;
$$;

grant execute on function public.ad_rewards_left(), public.start_ad_view(text), public.claim_ad_reward(text), public.count_ad_impressions(text[]),
  public.offer_event_bus(text, text, integer, integer, integer, timestamptz[], text), public.book_event_bus(text, timestamptz, text),
  public.confirm_event_bus(text, timestamptz), public.cancel_event_bus(text), public.buy_event_ticket(text, text) to authenticated;
