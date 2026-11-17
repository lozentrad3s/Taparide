-- Website waitlist, invite links, free first ride and event-bus seat requests (Abuja Tech Week).
-- Everything is reached through the security-definer functions at the bottom; the tables
-- themselves have row level security on and no policies, so nobody can read the list directly.

create table if not exists public.waitlist (
  id bigint generated always as identity primary key,
  email text not null,
  name text,
  phone text,
  area text,
  role text not null default 'rider'
    check (role in ('rider', 'driver', 'operator', 'ev_owner', 'event_organiser', 'other')),
  code text not null unique,
  referred_by text references public.waitlist (code) on delete set null,
  referrals int not null default 0,
  source text,
  created_at timestamptz not null default now(),
  -- The free first ride is paid once, to the account that confirms this email.
  credited_user uuid references auth.users (id) on delete set null,
  credited_at timestamptz
);
create unique index if not exists waitlist_email_key on public.waitlist (lower(email));
create index if not exists waitlist_rank_idx on public.waitlist (referrals desc, id);
alter table public.waitlist enable row level security;

create table if not exists public.event_seat_requests (
  id bigint generated always as identity primary key,
  waitlist_id bigint not null references public.waitlist (id) on delete cascade,
  event_slug text not null,
  day date not null,
  area text not null,
  slot text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (waitlist_id, event_slug, day)
);
create index if not exists event_seat_requests_event_idx on public.event_seat_requests (event_slug, day, area, slot);
alter table public.event_seat_requests enable row level security;

-- ------------------------------------------------------------------ settings
-- One free ride of up to ₦1,000, for the first 5,000 people who join and then open an account.
create or replace function public.waitlist_free_ride() returns int language sql immutable as $$ select 1000 $$;
create or replace function public.waitlist_free_ride_cap() returns int language sql immutable as $$ select 5000 $$;

-- Event buses the website takes seat requests for, with their days, areas and departure times.
create or replace function public.waitlist_event(p_slug text) returns jsonb language sql immutable as $$
  select case p_slug
    when 'abuja-tech-week-2026' then jsonb_build_object(
      'days', jsonb_build_array('2026-11-24', '2026-11-25', '2026-11-26'),
      'slots', jsonb_build_array('07:00', '08:00', '09:00'),
      'areas', jsonb_build_array('Kubwa', 'Gwarinpa', 'Lugbe', 'Nyanya', 'Karu', 'Lokogoma', 'Life Camp', 'Jabi', 'Wuse', 'Maitama', 'Garki', 'Gwagwalada', 'Bwari', 'Kuje'),
      'seats_per_bus', 14)
  end
$$;

-- ------------------------------------------------------------------ helpers
create or replace function public._waitlist_summary(w public.waitlist) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', w.code,
    'referrals', w.referrals,
    'position', (select count(*) + 1 from public.waitlist o where o.referrals > w.referrals or (o.referrals = w.referrals and o.id < w.id)),
    'total', (select count(*) from public.waitlist),
    'free_ride', public.waitlist_free_ride(),
    'free_ride_left', (select count(*) from public.waitlist where id <= w.id) <= public.waitlist_free_ride_cap(),
    'seats', coalesce((
      select jsonb_agg(jsonb_build_object('event', s.event_slug, 'day', s.day, 'area', s.area, 'slot', s.slot) order by s.day)
      from public.event_seat_requests s where s.waitlist_id = w.id), '[]'::jsonb)
  )
$$;

create or replace function public._waitlist_code() returns text
language plpgsql volatile set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.waitlist where code = c);
  end loop;
  return c;
end;
$$;

-- ------------------------------------------------------------------ public functions
-- Join (or look up) the waitlist. Joining again with the same email returns the same place.
create or replace function public.join_waitlist(
  p_email text, p_name text default null, p_phone text default null, p_area text default null,
  p_ref text default null, p_role text default 'rider', p_source text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  w public.waitlist;
  v_email text := lower(trim(coalesce(p_email, '')));
  v_name text := nullif(left(trim(coalesce(p_name, '')), 80), '');
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
  v_area text := nullif(left(trim(coalesce(p_area, '')), 40), '');
  v_ref text := upper(nullif(trim(coalesce(p_ref, '')), ''));
  v_role text := coalesce(nullif(p_role, ''), 'rider');
begin
  if length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then
    raise exception 'Enter a valid email address.' using errcode = '22023';
  end if;
  if v_phone is not null and (length(v_phone) < 10 or length(v_phone) > 15) then
    raise exception 'Enter a valid phone number, e.g. 0803 123 4567.' using errcode = '22023';
  end if;
  if v_role not in ('rider', 'driver', 'operator', 'ev_owner', 'event_organiser', 'other') then
    v_role := 'other';
  end if;

  select * into w from public.waitlist where lower(email) = v_email;
  if found then
    -- Fill in details given later, never overwrite ones already given.
    update public.waitlist set
      name = coalesce(name, v_name), phone = coalesce(phone, v_phone), area = coalesce(area, v_area)
    where id = w.id returning * into w;
    return public._waitlist_summary(w) || jsonb_build_object('existing', true);
  end if;

  if v_ref is not null and not exists (select 1 from public.waitlist where code = v_ref) then
    v_ref := null;
  end if;

  insert into public.waitlist (email, name, phone, area, role, code, referred_by, source)
  values (v_email, v_name, v_phone, v_area, v_role, public._waitlist_code(), v_ref, left(p_source, 40))
  returning * into w;

  if v_ref is not null then
    update public.waitlist set referrals = referrals + 1 where code = v_ref;
  end if;
  return public._waitlist_summary(w) || jsonb_build_object('existing', false);
end;
$$;

-- Place in line for an invite code (shown on the website after joining).
create or replace function public.waitlist_status(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w public.waitlist;
begin
  select * into w from public.waitlist where code = upper(trim(coalesce(p_code, '')));
  if not found then raise exception 'We could not find that code.' using errcode = 'P0002'; end if;
  return public._waitlist_summary(w);
end;
$$;

-- Ask for a seat on an event bus: one request per person per event day, changeable.
create or replace function public.request_event_seat(p_code text, p_event text, p_day date, p_area text, p_slot text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  w public.waitlist;
  ev jsonb := public.waitlist_event(p_event);
  v_riders int;
begin
  if ev is null then raise exception 'This event is not taking seat requests.' using errcode = 'P0002'; end if;
  select * into w from public.waitlist where code = upper(trim(coalesce(p_code, '')));
  if not found then raise exception 'Join the waitlist first, then pick your seat.' using errcode = 'P0002'; end if;
  if not (ev -> 'days') ? p_day::text then raise exception 'Pick one of the event days.' using errcode = '22023'; end if;
  if not (ev -> 'areas') ? p_area then raise exception 'Pick an area from the list.' using errcode = '22023'; end if;
  if not (ev -> 'slots') ? p_slot then raise exception 'Pick one of the departure times.' using errcode = '22023'; end if;

  insert into public.event_seat_requests (waitlist_id, event_slug, day, area, slot)
  values (w.id, p_event, p_day, p_area, p_slot)
  on conflict (waitlist_id, event_slug, day) do update set area = excluded.area, slot = excluded.slot, updated_at = now();

  select count(*) into v_riders from public.event_seat_requests
  where event_slug = p_event and day = p_day and area = p_area and slot = p_slot;
  return jsonb_build_object('day', p_day, 'area', p_area, 'slot', p_slot, 'riders', v_riders,
    'seats_per_bus', (ev ->> 'seats_per_bus')::int) || jsonb_build_object('summary', public._waitlist_summary(w));
end;
$$;

-- How many seats are requested, by day, area and time. Counts only: no names.
create or replace function public.event_seat_demand(p_event text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'event', p_event,
    'config', public.waitlist_event(p_event),
    'seats_per_bus', (public.waitlist_event(p_event) ->> 'seats_per_bus')::int,
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object('day', day, 'area', area, 'slot', slot, 'riders', n) order by n desc)
      from (select day, area, slot, count(*) n from public.event_seat_requests where event_slug = p_event group by 1, 2, 3) d
    ), '[]'::jsonb),
    'total', (select count(*) from public.event_seat_requests where event_slug = p_event)
  )
  where public.waitlist_event(p_event) is not null
$$;

-- ------------------------------------------------------------------ free first ride
-- When someone opens an account with (and confirms) an email that is on the waitlist,
-- their wallet gets the free ride once. Runs after on_auth_user_created, which makes the wallet.
create or replace function public.credit_waitlist_ride() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if new.email is null or new.email_confirmed_at is null then return new; end if;
  update public.waitlist set credited_user = new.id, credited_at = now()
  where lower(email) = lower(new.email) and credited_user is null
    and id <= (select coalesce(max(id), 0) from (select id from public.waitlist order by id limit public.waitlist_free_ride_cap()) firsts)
  returning id into v_id;
  if v_id is not null then
    update public.wallets set balance = balance + public.waitlist_free_ride() where user_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_waitlist_credit on auth.users;
create trigger on_auth_user_waitlist_credit
  after insert or update of email_confirmed_at on auth.users
  for each row execute function public.credit_waitlist_ride();

-- ------------------------------------------------------------------ grants
revoke all on public.waitlist, public.event_seat_requests from anon, authenticated;
revoke execute on function public._waitlist_summary(public.waitlist), public._waitlist_code(), public.credit_waitlist_ride() from public, anon, authenticated;
grant execute on function public.join_waitlist(text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.waitlist_status(text) to anon, authenticated;
grant execute on function public.request_event_seat(text, text, date, text, text) to anon, authenticated;
grant execute on function public.event_seat_demand(text) to anon, authenticated;
grant execute on function public.waitlist_event(text), public.waitlist_free_ride(), public.waitlist_free_ride_cap() to anon, authenticated;
