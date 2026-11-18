-- Personal free-bus passes for Abuja Tech Week, and a private key for each sign-up.
--
-- 1. Every seat request gets a unique pass ID (e.g. TW24-K7P2QX) issued to the registered name.
--    Boarding staff check the pass ID and the name against the boarding list (and a photo ID),
--    so a shared screenshot doesn't get a second person on the bus.
-- 2. The public invite code (shared on WhatsApp) no longer unlocks anything: seats and passes need
--    the private access key returned only to the person who joined (kept in their browser).

alter table public.waitlist add column if not exists access_key text;
update public.waitlist set access_key = encode(extensions.gen_random_bytes(18), 'hex') where access_key is null;
alter table public.waitlist alter column access_key set default encode(extensions.gen_random_bytes(18), 'hex');
alter table public.waitlist alter column access_key set not null;
create unique index if not exists waitlist_access_key on public.waitlist (access_key);

alter table public.event_seat_requests add column if not exists ticket_code text;

create or replace function public._seat_ticket_code(p_day date) returns text
language plpgsql volatile set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := 'TW' || to_char(p_day, 'DD') || '-';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.event_seat_requests where ticket_code = c);
  end loop;
  return c;
end;
$$;

update public.event_seat_requests set ticket_code = public._seat_ticket_code(day) where ticket_code is null;
create unique index if not exists event_seat_requests_ticket on public.event_seat_requests (ticket_code);

create or replace function public._seat_ticket_default() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.ticket_code is null then new.ticket_code := public._seat_ticket_code(new.day); end if;
  return new;
end;
$$;
drop trigger if exists event_seat_ticket on public.event_seat_requests;
create trigger event_seat_ticket before insert on public.event_seat_requests for each row execute function public._seat_ticket_default();

-- Public summary (by invite code): place in line and invites only; nothing about seats or passes.
create or replace function public._waitlist_summary(w public.waitlist) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', w.code,
    'referrals', w.referrals,
    'position', (select count(*) + 1 from public.waitlist o where o.referrals > w.referrals or (o.referrals = w.referrals and o.id < w.id)),
    'total', (select count(*) from public.waitlist),
    'free_ride', public.waitlist_free_ride(),
    'free_ride_left', (select count(*) from public.waitlist where id <= w.id) <= public.waitlist_free_ride_cap(),
    'seats', '[]'::jsonb
  )
$$;

-- Private view for the person themself: their seats with pass IDs, and their access key.
create or replace function public._waitlist_private(w public.waitlist) returns jsonb
language sql stable security definer set search_path = public as $$
  select public._waitlist_summary(w) || jsonb_build_object(
    'access', w.access_key,
    'name', w.name,
    'seats', coalesce((
      select jsonb_agg(jsonb_build_object('event', s.event_slug, 'day', s.day, 'area', s.area, 'slot', s.slot, 'ticket', s.ticket_code) order by s.day)
      from public.event_seat_requests s where s.waitlist_id = w.id), '[]'::jsonb)
  )
$$;

-- join_waitlist now hands back the private view (it is the person's own sign-up).
create or replace function public.join_waitlist(
  p_email text, p_name text default null, p_phone text default null, p_area text default null,
  p_ref text default null, p_role text default 'rider', p_source text default null, p_terms text default null
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
  if v_role not in ('rider', 'driver', 'operator', 'ev_owner', 'event_organiser', 'other') then v_role := 'other'; end if;

  select * into w from public.waitlist where lower(email) = v_email;
  if found then
    update public.waitlist set
      name = coalesce(name, v_name), phone = coalesce(phone, v_phone), area = coalesce(area, v_area),
      terms_version = coalesce(left(p_terms, 10), terms_version),
      terms_accepted_at = case when p_terms is not null then now() else terms_accepted_at end
    where id = w.id returning * into w;
    return public._waitlist_private(w) || jsonb_build_object('existing', true);
  end if;

  if v_ref is not null and not exists (select 1 from public.waitlist where code = v_ref) then v_ref := null; end if;
  insert into public.waitlist (email, name, phone, area, role, code, referred_by, source, terms_version, terms_accepted_at)
  values (v_email, v_name, v_phone, v_area, v_role, public._waitlist_code(), v_ref, left(p_source, 40), left(p_terms, 10), case when p_terms is not null then now() end)
  returning * into w;
  if v_ref is not null then update public.waitlist set referrals = referrals + 1 where code = v_ref; end if;
  return public._waitlist_private(w) || jsonb_build_object('existing', false);
end;
$$;

-- Reserve a seat with the private key; returns the personal pass.
create or replace function public.reserve_event_seat(
  p_access text, p_event text, p_day date, p_area text, p_slot text, p_name text default null, p_phone text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  w public.waitlist;
  ev jsonb := public.waitlist_event(p_event);
  s public.event_seat_requests;
  v_riders int;
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
begin
  if ev is null then raise exception 'This event is not taking seat requests.' using errcode = 'P0002'; end if;
  select * into w from public.waitlist where access_key = coalesce(p_access, '') and length(coalesce(p_access, '')) >= 20;
  if not found then raise exception 'Join the waitlist first, then pick your seat.' using errcode = 'P0002'; end if;
  if not (ev -> 'days') ? p_day::text then raise exception 'Pick one of the event days.' using errcode = '22023'; end if;
  if not (ev -> 'areas') ? p_area then raise exception 'Pick a pick-up point from the list.' using errcode = '22023'; end if;
  if not (ev -> 'slots') ? p_slot then raise exception 'Pick one of the departure times.' using errcode = '22023'; end if;
  if v_phone is not null and (length(v_phone) < 10 or length(v_phone) > 15) then
    raise exception 'Enter a valid phone number, e.g. 0803 123 4567.' using errcode = '22023';
  end if;
  update public.waitlist set
    name = coalesce(nullif(left(trim(coalesce(p_name, '')), 80), ''), name),
    phone = coalesce(v_phone, phone)
  where id = w.id returning * into w;
  if w.name is null then raise exception 'Enter your full name for the boarding list.' using errcode = '22023'; end if;

  insert into public.event_seat_requests (waitlist_id, event_slug, day, area, slot)
  values (w.id, p_event, p_day, p_area, p_slot)
  on conflict (waitlist_id, event_slug, day) do update set area = excluded.area, slot = excluded.slot, updated_at = now()
  returning * into s;

  select count(*) into v_riders from public.event_seat_requests where event_slug = p_event and day = p_day and area = p_area and slot = p_slot;
  return jsonb_build_object(
    'ticket', jsonb_build_object('code', s.ticket_code, 'name', w.name, 'event', p_event, 'day', s.day, 'area', s.area, 'slot', s.slot),
    'riders', v_riders,
    'summary', public._waitlist_private(w));
end;
$$;

-- The old invite-code version can no longer be used from outside.
revoke execute on function public.request_event_seat(text, text, date, text, text, text, text) from public, anon, authenticated;

-- Admin view: pass IDs on the boarding lists.
create or replace function public.admin_waitlist() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.my_role(), '') <> 'admin' then
    raise exception 'Only platform admins can see the waitlist.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', w.id, 'email', w.email, 'name', w.name, 'phone', w.phone, 'area', w.area, 'role', w.role,
      'code', w.code, 'referred_by', w.referred_by, 'referrals', w.referrals, 'source', w.source, 'terms_version', w.terms_version,
      'created_at', w.created_at, 'credited_at', w.credited_at,
      'seats', coalesce((
        select jsonb_agg(jsonb_build_object('event', s.event_slug, 'day', s.day, 'area', s.area, 'slot', s.slot, 'ticket', s.ticket_code, 'created_at', s.created_at) order by s.day)
        from public.event_seat_requests s where s.waitlist_id = w.id), '[]'::jsonb)
    ) order by w.created_at desc)
    from public.waitlist w), '[]'::jsonb);
end;
$$;

revoke execute on function public._seat_ticket_code(date), public._seat_ticket_default(), public._waitlist_private(public.waitlist) from public, anon, authenticated;
grant execute on function public.reserve_event_seat(text, text, date, text, text, text, text) to anon, authenticated;
