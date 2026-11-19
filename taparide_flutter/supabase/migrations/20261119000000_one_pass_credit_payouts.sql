-- 1. Abuja Tech Week: ONE personal pass per person, valid on every day they ride (default: all three).
--    Name, WhatsApp number and pick-up point are required; one WhatsApp number holds one pass.
--    Admins can edit, cancel, mark people contacted and remove duplicate sign-ups.
-- 2. The free ₦1,000 is "ride credit": spent first, shown apart from the wallet balance.
-- 3. Tap to pay: fares go into a hold and are released to the operator's collection wallet after the
--    trip (or refunded to the rider if it is cancelled first).
-- 4. Event organisers see seat bookings (counts by day, pick-up point and time; no personal data).
-- 5. A daily summary for the founders (called by the server with the server secret).

-- ------------------------------------------------------------------ 1. one pass per person
alter table public.waitlist add column if not exists contacted_at timestamptz;
alter table public.waitlist add column if not exists admin_note text;

/** Last 10 digits: 0803 123 4567, +234 803 123 4567 and 2348031234567 are the same number. */
create or replace function public._phone_key(p text) returns text language sql immutable as $$
  select nullif(right(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 10), '')
$$;
create index if not exists waitlist_phone_key on public.waitlist (public._phone_key(phone));

create or replace function public._event_pass_code() returns text
language plpgsql volatile set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := 'TW-';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.event_seat_requests where ticket_code = c);
  end loop;
  return c;
end;
$$;

-- The same pass ID now appears on each day row of one person's pass.
drop index if exists public.event_seat_requests_ticket;
create unique index if not exists event_seat_requests_ticket_day on public.event_seat_requests (ticket_code, day);

-- Existing seats: one pass per person (their first pass ID), valid on all event days.
update public.event_seat_requests s set ticket_code = f.code, updated_at = now()
from (
  select distinct on (waitlist_id, event_slug) waitlist_id, event_slug, ticket_code code
  from public.event_seat_requests order by waitlist_id, event_slug, created_at, id
) f
where s.waitlist_id = f.waitlist_id and s.event_slug = f.event_slug and s.ticket_code is distinct from f.code;

insert into public.event_seat_requests (waitlist_id, event_slug, day, area, slot, ticket_code)
select f.waitlist_id, f.event_slug, d.day::date, f.area, f.slot, f.ticket_code
from (
  select distinct on (waitlist_id, event_slug) waitlist_id, event_slug, area, slot, ticket_code
  from public.event_seat_requests order by waitlist_id, event_slug, created_at, id
) f
cross join lateral jsonb_array_elements_text(public.waitlist_event(f.event_slug) -> 'days') d(day)
where public.waitlist_event(f.event_slug) is not null
on conflict (waitlist_id, event_slug, day) do nothing;

/** One person's pass for one event, or null. */
create or replace function public._event_pass(p_waitlist bigint, p_event text) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when count(*) = 0 then null else jsonb_build_object(
    'code', min(s.ticket_code), 'event', p_event, 'name', min(w.name),
    'days', jsonb_agg(s.day order by s.day), 'area', min(s.area), 'slot', min(s.slot))
  end
  from public.event_seat_requests s join public.waitlist w on w.id = s.waitlist_id
  where s.waitlist_id = p_waitlist and s.event_slug = p_event
$$;

-- Private view for the person themself: now also their passes, one per event.
create or replace function public._waitlist_private(w public.waitlist) returns jsonb
language sql stable security definer set search_path = public as $$
  select public._waitlist_summary(w) || jsonb_build_object(
    'access', w.access_key,
    'name', w.name,
    'email', w.email,
    'seats', coalesce((
      select jsonb_agg(jsonb_build_object('event', s.event_slug, 'day', s.day, 'area', s.area, 'slot', s.slot, 'ticket', s.ticket_code) order by s.day)
      from public.event_seat_requests s where s.waitlist_id = w.id), '[]'::jsonb),
    'passes', coalesce((
      select jsonb_agg(public._event_pass(w.id, e.event_slug))
      from (select distinct event_slug from public.event_seat_requests where waitlist_id = w.id) e), '[]'::jsonb)
  )
$$;

/** Book (or change) a person's free event-bus pass. [p_days] null = every day of the event. */
create or replace function public.reserve_event_pass(
  p_access text, p_event text, p_area text, p_name text, p_phone text,
  p_days date[] default null, p_slot text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  w public.waitlist;
  ev jsonb := public.waitlist_event(p_event);
  v_days date[];
  v_slot text;
  v_name text := nullif(regexp_replace(left(trim(coalesce(p_name, '')), 80), '\s+', ' ', 'g'), '');
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
  v_code text;
  d date;
  other text;
begin
  if ev is null then raise exception 'This event is not taking seat requests.' using errcode = 'P0002'; end if;
  select * into w from public.waitlist where access_key = coalesce(p_access, '') and length(coalesce(p_access, '')) >= 20;
  if not found then raise exception 'Join the waitlist first, then pick your seat.' using errcode = 'P0002'; end if;

  if v_name is null or array_length(regexp_split_to_array(v_name, ' '), 1) < 2 then
    raise exception 'Enter your first and last name for the boarding list.' using errcode = '22023';
  end if;
  if v_phone is null or length(public._phone_key(v_phone)) < 10 or length(v_phone) > 15 then
    raise exception 'Enter your WhatsApp number, e.g. 0803 123 4567.' using errcode = '22023';
  end if;
  if p_area is null or not (ev -> 'areas') ? p_area then raise exception 'Pick a pick-up point from the list.' using errcode = '22023'; end if;
  v_slot := coalesce(nullif(p_slot, ''), ev -> 'slots' ->> 0);
  if not (ev -> 'slots') ? v_slot then raise exception 'Pick one of the departure times.' using errcode = '22023'; end if;

  v_days := coalesce(nullif(p_days, '{}'), array(select x::date from jsonb_array_elements_text(ev -> 'days') x));
  foreach d in array v_days loop
    if not (ev -> 'days') ? d::text then raise exception 'Pick days of the event only.' using errcode = '22023'; end if;
  end loop;

  -- One pass per person: the same WhatsApp number can't hold a second pass under another email.
  select o.email into other
  from public.waitlist o
  where o.id <> w.id and public._phone_key(o.phone) = public._phone_key(v_phone)
    and exists (select 1 from public.event_seat_requests s where s.waitlist_id = o.id and s.event_slug = p_event)
  limit 1;
  if other is not null then
    raise exception 'This WhatsApp number already has a free bus pass. One pass covers every day: use the email you booked with to see it, or message us on WhatsApp.'
      using errcode = '23505';
  end if;

  update public.waitlist set name = v_name, phone = v_phone where id = w.id returning * into w;

  select ticket_code into v_code from public.event_seat_requests where waitlist_id = w.id and event_slug = p_event order by created_at limit 1;
  v_code := coalesce(v_code, public._event_pass_code());

  delete from public.event_seat_requests where waitlist_id = w.id and event_slug = p_event and not (day = any (v_days));
  foreach d in array v_days loop
    insert into public.event_seat_requests (waitlist_id, event_slug, day, area, slot, ticket_code)
    values (w.id, p_event, d, p_area, v_slot, v_code)
    on conflict (waitlist_id, event_slug, day) do update
      set area = excluded.area, slot = excluded.slot, ticket_code = excluded.ticket_code, updated_at = now();
  end loop;

  return jsonb_build_object(
    'pass', public._event_pass(w.id, p_event),
    'riders', (select count(*) from public.event_seat_requests where event_slug = p_event and day = v_days[1] and area = p_area and slot = v_slot),
    'summary', public._waitlist_private(w));
end;
$$;

-- The one-day version skipped the duplicate check; only the new one is open to the website.
revoke execute on function public.reserve_event_seat(text, text, date, text, text, text, text) from public, anon, authenticated;

-- Admin list: contacted status, note, passes and possible duplicates (same number or same name).
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
      'created_at', w.created_at, 'credited_at', w.credited_at, 'contacted_at', w.contacted_at, 'note', w.admin_note,
      'dup_phone', public._phone_key(w.phone) is not null and exists (select 1 from public.waitlist o where o.id <> w.id and public._phone_key(o.phone) = public._phone_key(w.phone)),
      'dup_name', w.name is not null and exists (select 1 from public.waitlist o where o.id <> w.id and lower(o.name) = lower(w.name)),
      'seats', coalesce((
        select jsonb_agg(jsonb_build_object('event', s.event_slug, 'day', s.day, 'area', s.area, 'slot', s.slot, 'ticket', s.ticket_code, 'created_at', s.created_at) order by s.day)
        from public.event_seat_requests s where s.waitlist_id = w.id), '[]'::jsonb)
    ) order by w.created_at desc)
    from public.waitlist w), '[]'::jsonb);
end;
$$;

create or replace function public._require_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.my_role(), '') <> 'admin' then
    raise exception 'Only platform admins can do this.' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.admin_set_contacted(p_id bigint, p_contacted boolean, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._require_admin();
  update public.waitlist set
    contacted_at = case when p_contacted then coalesce(contacted_at, now()) end,
    admin_note = coalesce(nullif(left(trim(coalesce(p_note, '')), 300), ''), admin_note)
  where id = p_id;
  if not found then raise exception 'That sign-up no longer exists.' using errcode = 'P0003'; end if;
end;
$$;

create or replace function public.admin_update_event_pass(
  p_id bigint, p_event text, p_area text, p_days date[], p_name text default null, p_phone text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  ev jsonb := public.waitlist_event(p_event);
  v_code text;
  d date;
begin
  perform public._require_admin();
  if ev is null then raise exception 'Unknown event.' using errcode = 'P0003'; end if;
  if not exists (select 1 from public.waitlist where id = p_id) then raise exception 'That sign-up no longer exists.' using errcode = 'P0003'; end if;
  if p_area is null or not (ev -> 'areas') ? p_area then raise exception 'Pick a pick-up point from the list.' using errcode = '22023'; end if;
  if p_days is null or array_length(p_days, 1) is null then raise exception 'Pick at least one day.' using errcode = '22023'; end if;
  foreach d in array p_days loop
    if not (ev -> 'days') ? d::text then raise exception 'Pick days of the event only.' using errcode = '22023'; end if;
  end loop;
  update public.waitlist set
    name = coalesce(nullif(left(trim(coalesce(p_name, '')), 80), ''), name),
    phone = coalesce(nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), ''), phone)
  where id = p_id;
  select ticket_code into v_code from public.event_seat_requests where waitlist_id = p_id and event_slug = p_event order by created_at limit 1;
  v_code := coalesce(v_code, public._event_pass_code());
  delete from public.event_seat_requests where waitlist_id = p_id and event_slug = p_event and not (day = any (p_days));
  foreach d in array p_days loop
    insert into public.event_seat_requests (waitlist_id, event_slug, day, area, slot, ticket_code)
    values (p_id, p_event, d, p_area, ev -> 'slots' ->> 0, v_code)
    on conflict (waitlist_id, event_slug, day) do update set area = excluded.area, ticket_code = excluded.ticket_code, updated_at = now();
  end loop;
  perform public.log_action('Changed bus pass', v_code);
  return public._event_pass(p_id, p_event);
end;
$$;

create or replace function public.admin_cancel_event_pass(p_id bigint, p_event text) returns void
language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  perform public._require_admin();
  delete from public.event_seat_requests where waitlist_id = p_id and event_slug = p_event returning ticket_code into v_code;
  if v_code is null then raise exception 'That person has no pass for this event.' using errcode = 'P0003'; end if;
  perform public.log_action('Cancelled bus pass', v_code);
end;
$$;

/** Removes a duplicate sign-up (and its passes). Refused once the free ride was paid to an account. */
create or replace function public.admin_remove_signup(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare w public.waitlist;
begin
  perform public._require_admin();
  select * into w from public.waitlist where id = p_id;
  if not found then raise exception 'That sign-up no longer exists.' using errcode = 'P0003'; end if;
  if w.credited_user is not null then raise exception 'This sign-up already received its free ride in an account; it can''t be removed.' using errcode = '22023'; end if;
  update public.waitlist set referred_by = null where referred_by = w.code;
  if w.referred_by is not null then update public.waitlist set referrals = greatest(referrals - 1, 0) where code = w.referred_by; end if;
  delete from public.waitlist where id = p_id;
  perform public.log_action('Removed duplicate sign-up', 'waitlist #' || p_id);
end;
$$;

-- ------------------------------------------------------------------ 2. ride credit
alter table public.wallets add column if not exists ride_credit integer not null default 0;
do $$ begin
  alter table public.wallets add constraint wallets_ride_credit_check check (ride_credit >= 0 and ride_credit <= balance);
exception when duplicate_object then null; end $$;

-- Spending takes ride credit first; the credit never exceeds what is in the wallet.
create or replace function public._wallet_credit_first() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.balance < old.balance and new.ride_credit = old.ride_credit then
    new.ride_credit := greatest(0, old.ride_credit - (old.balance - new.balance));
  end if;
  if new.ride_credit > new.balance then new.ride_credit := new.balance; end if;
  if new.ride_credit < 0 then new.ride_credit := 0; end if;
  return new;
end;
$$;
drop trigger if exists wallet_credit_first on public.wallets;
create trigger wallet_credit_first before update on public.wallets for each row execute function public._wallet_credit_first();

-- The free ride arrives as ride credit.
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
    update public.wallets set balance = balance + public.waitlist_free_ride(), ride_credit = ride_credit + public.waitlist_free_ride() where user_id = new.id;
  end if;
  return new;
end;
$$;

-- People already credited: their free ride becomes ride credit (up to what is still in the wallet).
update public.wallets wl set ride_credit = least(wl.balance, public.waitlist_free_ride())
from public.waitlist l where l.credited_user = wl.user_id and wl.ride_credit = 0;

-- Real payments are on (Bachs live key): new accounts no longer get ₦2,500 of test money, and
-- test money already in wallets is removed. Kept: ride credit and anything actually paid in.
insert into taparide_private.settings (key, value) values ('payments_live', 'true')
on conflict (key) do update set value = 'true';
update public.wallets w set balance = least(w.balance, w.ride_credit + coalesce((
  select sum(t.amount) from public.wallet_topups t where t.user_id = w.user_id and t.status = 'paid'), 0))
where w.balance > w.ride_credit + coalesce((
  select sum(t.amount) from public.wallet_topups t where t.user_id = w.user_id and t.status = 'paid'), 0);

-- No sponsored ads yet: "watch an ad, earn ₦50" is switched off (house ads stay, with no reward).
update public.ads set reward = 0 where coalesce(reward, 0) > 0;

-- ------------------------------------------------------------------ 3. tap to pay: holds and collection wallets
create table if not exists public.collection_wallets (
  provider_id text primary key references public.providers (id) on delete cascade,
  available   integer not null default 0 check (available >= 0),
  paid_out    integer not null default 0 check (paid_out >= 0),
  updated_at  timestamptz not null default now()
);
alter table public.collection_wallets enable row level security;
drop policy if exists collection_wallets_read on public.collection_wallets;
create policy collection_wallets_read on public.collection_wallets for select
  using (public.my_role() in ('admin', 'government') or provider_id = public.my_provider());

create table if not exists public.payouts (
  id          bigint generated always as identity primary key,
  booking_id  text not null unique references public.bookings (id) on delete cascade,
  provider_id text not null references public.providers (id) on delete cascade,
  amount      integer not null check (amount > 0),
  status      text not null default 'held' check (status in ('held', 'released', 'refunded')),
  release_at  timestamptz not null,
  created_at  timestamptz not null default now(),
  settled_at  timestamptz
);
create index if not exists payouts_due_idx on public.payouts (status, release_at);
create index if not exists payouts_provider_idx on public.payouts (provider_id, created_at desc);
alter table public.payouts enable row level security;
drop policy if exists payouts_read on public.payouts;
create policy payouts_read on public.payouts for select
  using (public.my_role() in ('admin', 'government') or provider_id = public.my_provider());

-- Every operator, fleet owner and private driver gets a collection wallet automatically.
create or replace function public._provider_collection_wallet() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.collection_wallets (provider_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists provider_collection_wallet on public.providers;
create trigger provider_collection_wallet after insert on public.providers for each row execute function public._provider_collection_wallet();
insert into public.collection_wallets (provider_id) select id from public.providers on conflict do nothing;

-- A paid booking (tap card / QR) holds the fare for its operator until the trip is over;
-- cancelling or declining before then refunds the rider (the booking functions do that) and voids the hold.
-- Tag Along hosts are paid by complete_ride, so those bookings are left alone here.
create or replace function public._booking_payout() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.provider_id is null or coalesce(new.fare, 0) <= 0 or new.payment_method not in ('tap_card', 'qr') or new.kind = 'tag_along' then
    return new;
  end if;
  if tg_op = 'INSERT' and new.status in ('confirmed', 'requested', 'accepted') then
    insert into public.payouts (booking_id, provider_id, amount, release_at)
    values (new.id, new.provider_id, new.fare, greatest(new.departure_at, now()) + interval '45 minutes')
    on conflict (booking_id) do nothing;
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status in ('cancelled', 'declined') then
      update public.payouts set status = 'refunded', settled_at = now() where booking_id = new.id and status = 'held';
    elsif new.status = 'completed' then
      update public.payouts set release_at = now() where booking_id = new.id and status = 'held';
      perform public.release_due_payouts();
    end if;
  end if;
  return new;
end;
$$;

/** Moves every hold that is due into its operator's collection wallet. Safe to call any time. */
create or replace function public.release_due_payouts() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with due as (
    update public.payouts set status = 'released', settled_at = now()
    where status = 'held' and release_at <= now()
    returning provider_id, amount
  ), sums as (select provider_id, sum(amount)::int amt, count(*) c from due group by provider_id),
  credited as (
    insert into public.collection_wallets as cw (provider_id, available)
    select provider_id, amt from sums
    on conflict (provider_id) do update set available = cw.available + excluded.available, updated_at = now()
    returning 1
  )
  select coalesce(sum(c), 0)::int into n from sums, (select count(*) from credited) _;
  return n;
end;
$$;

drop trigger if exists booking_payout on public.bookings;
create trigger booking_payout after insert or update of status on public.bookings for each row execute function public._booking_payout();

/** The signed-in operator's collection wallet: available, still held, and the latest payments. */
create or replace function public.my_collection_wallet() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_provider text := public.my_provider();
begin
  if v_provider is null then raise exception 'Only partner accounts have a collection wallet.' using errcode = '42501'; end if;
  perform public.release_due_payouts();
  return jsonb_build_object(
    'available', coalesce((select available from public.collection_wallets where provider_id = v_provider), 0),
    'paid_out', coalesce((select paid_out from public.collection_wallets where provider_id = v_provider), 0),
    'held', coalesce((select sum(amount) from public.payouts where provider_id = v_provider and status = 'held'), 0),
    'recent', coalesce((
      select jsonb_agg(jsonb_build_object('booking', p.booking_id, 'amount', p.amount, 'status', p.status, 'release_at', p.release_at, 'created_at', p.created_at, 'title', b.title) order by p.created_at desc)
      from (select * from public.payouts where provider_id = v_provider order by created_at desc limit 20) p
      join public.bookings b on b.id = p.booking_id), '[]'::jsonb));
end;
$$;

/** Money overview for the master admin. */
create or replace function public.admin_money() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._require_admin();
  perform public.release_due_payouts();
  return jsonb_build_object(
    'wallets', (select jsonb_build_object('count', count(*), 'balance', coalesce(sum(balance), 0), 'ride_credit', coalesce(sum(ride_credit), 0)) from public.wallets),
    'topups', (select jsonb_build_object('paid', count(*) filter (where status = 'paid'), 'paid_amount', coalesce(sum(amount) filter (where status = 'paid'), 0),
                                         'pending', count(*) filter (where status = 'pending'), 'failed', count(*) filter (where status = 'failed')) from public.wallet_topups),
    'payouts', (select jsonb_build_object('held', coalesce(sum(amount) filter (where status = 'held'), 0), 'released', coalesce(sum(amount) filter (where status = 'released'), 0),
                                          'refunded', coalesce(sum(amount) filter (where status = 'refunded'), 0)) from public.payouts),
    'collection', coalesce((
      select jsonb_agg(jsonb_build_object('provider', p.name, 'kind', p.kind, 'available', c.available, 'paid_out', c.paid_out) order by c.available desc)
      from public.collection_wallets c join public.providers p on p.id = c.provider_id where c.available > 0 or c.paid_out > 0), '[]'::jsonb),
    'recent_topups', coalesce((
      select jsonb_agg(jsonb_build_object('reference', t.reference, 'amount', t.amount, 'status', t.status, 'channel', t.channel, 'created_at', t.created_at, 'name', pr.full_name) order by t.created_at desc)
      from (select * from public.wallet_topups order by created_at desc limit 25) t left join public.profiles pr on pr.id = t.user_id), '[]'::jsonb));
end;
$$;

-- Release holds every 10 minutes where pg_cron is available (Supabase). Everywhere else the
-- dashboards release due holds whenever they are opened.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'taparide-release-payouts';
  perform cron.schedule('taparide-release-payouts', '*/10 * * * *', 'select public.release_due_payouts()');
exception when others then
  raise notice 'pg_cron not available (%); holds are released when dashboards open.', sqlerrm;
end;
$$;

-- ------------------------------------------------------------------ 4. event organisers
alter table public.events add column if not exists seat_slug text;
update public.events set seat_slug = 'abuja-tech-week-2026' where id = 'ev_techweek' and seat_slug is null;

/** Free-bus bookings for the events the signed-in organiser runs: people per day, pick-up point and time. */
create or replace function public.organiser_seat_bookings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.my_role(), '') not in ('admin', 'event_partner', 'government') then
    raise exception 'Only event organisers can see bookings.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id', e.id, 'title', e.title, 'venue', e.venue, 'starts_at', e.starts_at, 'ends_at', e.ends_at, 'slug', e.seat_slug,
      'config', public.waitlist_event(e.seat_slug),
      'people', (select count(distinct waitlist_id) from public.event_seat_requests where event_slug = e.seat_slug),
      'rows', coalesce((
        select jsonb_agg(jsonb_build_object('day', day, 'area', area, 'slot', slot, 'riders', n) order by day, area)
        from (select day, area, slot, count(*) n from public.event_seat_requests where event_slug = e.seat_slug group by 1, 2, 3) d), '[]'::jsonb),
      'last_booking', (select max(updated_at) from public.event_seat_requests where event_slug = e.seat_slug)
    ) order by e.starts_at)
    from public.events e
    where e.seat_slug is not null
      and (public.my_role() in ('admin', 'government') or e.organiser_id = auth.uid() or (e.provider_id is not null and e.provider_id = public.my_provider()))
  ), '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------------------ 5. daily summary (server only)
create or replace function public.daily_summary(p_secret text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare expected text;
begin
  select value into expected from taparide_private.settings where key = 'topup_secret_hash';
  if expected is null or p_secret is null or encode(sha256(convert_to(p_secret, 'utf8')), 'hex') <> expected then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'signups_total', (select count(*) from public.waitlist),
    'signups_24h', (select count(*) from public.waitlist where created_at > now() - interval '24 hours'),
    'accounts_total', (select count(*) from public.profiles),
    'accounts_24h', (select count(*) from public.profiles where created_at > now() - interval '24 hours'),
    'passes_total', (select count(distinct waitlist_id) from public.event_seat_requests),
    'passes_24h', (select count(distinct waitlist_id) from public.event_seat_requests where created_at > now() - interval '24 hours'),
    'by_point', coalesce((
      select jsonb_agg(jsonb_build_object('day', day, 'area', area, 'riders', n) order by day, n desc)
      from (select day, area, count(*) n from public.event_seat_requests group by 1, 2) d), '[]'::jsonb),
    'applications_waiting', (select count(*) from public.partner_applications where status in ('submitted', 'under_review')),
    'possible_duplicates', (select count(*) from public.waitlist w where public._phone_key(w.phone) is not null
                             and exists (select 1 from public.waitlist o where o.id < w.id and public._phone_key(o.phone) = public._phone_key(w.phone))));
end;
$$;

-- ------------------------------------------------------------------ grants
revoke execute on function public._event_pass_code(), public._event_pass(bigint, text), public._waitlist_private(public.waitlist),
  public._require_admin(), public._wallet_credit_first(), public._provider_collection_wallet(), public._booking_payout() from public, anon, authenticated;
grant execute on function public.reserve_event_pass(text, text, text, text, text, date[], text) to anon, authenticated;
revoke execute on function public.admin_set_contacted(bigint, boolean, text), public.admin_update_event_pass(bigint, text, text, date[], text, text),
  public.admin_cancel_event_pass(bigint, text), public.admin_remove_signup(bigint), public.admin_money(),
  public.my_collection_wallet(), public.organiser_seat_bookings() from public, anon;
grant execute on function public.admin_set_contacted(bigint, boolean, text), public.admin_update_event_pass(bigint, text, text, date[], text, text),
  public.admin_cancel_event_pass(bigint, text), public.admin_remove_signup(bigint), public.admin_money(),
  public.my_collection_wallet(), public.organiser_seat_bookings() to authenticated;
grant execute on function public.release_due_payouts() to anon, authenticated;
revoke execute on function public.daily_summary(text) from public, authenticated;
grant execute on function public.daily_summary(text) to anon;
grant select on public.collection_wallets, public.payouts to authenticated;
