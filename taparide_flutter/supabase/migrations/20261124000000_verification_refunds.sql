-- 1. Riders complete verification in the app (NIN, date of birth, phone, home area, emergency
--    contact). An admin approves it in the dashboard; then the account shows "Verified".
--    Riders can edit their details, except email, and except NIN and date of birth once submitted.
-- 2. Refunds: a rider asks for a refund on a paid booking; an admin approves (money back to the
--    wallet, the operator's hold voided or taken back) or declines. Admins can also refund directly.
-- 3. Clean-up: the old ₦1,000 still in 7 wallets is removed (no money has ever been paid in).

-- ------------------------------------------------------------------ 3. clean-up
update public.wallets w set balance = 0, ride_credit = 0
where w.balance > 0
  and not exists (select 1 from public.wallet_topups t where t.user_id = w.user_id and t.status = 'paid');

-- ------------------------------------------------------------------ 1. verification and profile
alter table public.profiles add column if not exists nin text;
alter table public.profiles add column if not exists date_of_birth date;
alter table public.profiles add column if not exists home_area text;
alter table public.profiles add column if not exists emergency_name text;
alter table public.profiles add column if not exists emergency_phone text;
alter table public.profiles add column if not exists verification_status text not null default 'unverified';
alter table public.profiles add column if not exists verification_note text;
alter table public.profiles add column if not exists verification_submitted_at timestamptz;
alter table public.profiles add column if not exists verified_at timestamptz;
do $$ begin
  alter table public.profiles add constraint profiles_verification_status_check
    check (verification_status in ('unverified', 'pending', 'verified', 'rejected'));
exception when duplicate_object then null; end $$;
update public.profiles set verification_status = 'verified', verified_at = coalesce(verified_at, now()) where verified and verification_status = 'unverified';
create unique index if not exists profiles_nin_key on public.profiles (nin) where nin is not null;

/** Edits the signed-in person's own details. Email can't change here; NIN and date of birth are set by verification. */
create or replace function public.update_my_profile(
  p_full_name text, p_phone text, p_home_area text default null,
  p_emergency_name text default null, p_emergency_phone text default null
) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  v_name text := nullif(regexp_replace(left(trim(coalesce(p_full_name, '')), 80), '\s+', ' ', 'g'), '');
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
  v_ephone text := nullif(regexp_replace(coalesce(p_emergency_phone, ''), '[^0-9+]', '', 'g'), '');
begin
  if auth.uid() is null then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  if v_name is null or array_length(regexp_split_to_array(v_name, ' '), 1) < 2 then
    raise exception 'Enter your first and last name.' using errcode = '22023';
  end if;
  if v_phone is not null and (length(public._phone_key(v_phone)) < 10 or length(v_phone) > 15) then
    raise exception 'Enter a valid phone number, e.g. 0803 123 4567.' using errcode = '22023';
  end if;
  if v_ephone is not null and (length(public._phone_key(v_ephone)) < 10 or length(v_ephone) > 15) then
    raise exception 'Enter a valid emergency contact number.' using errcode = '22023';
  end if;
  select * into me from public.profiles where id = auth.uid();
  -- A verified name can't be swapped for someone else's: changing it sends the account back for review.
  update public.profiles set
    full_name = v_name,
    phone = v_phone,
    home_area = nullif(left(trim(coalesce(p_home_area, '')), 60), ''),
    emergency_name = nullif(left(trim(coalesce(p_emergency_name, '')), 80), ''),
    emergency_phone = v_ephone,
    verification_status = case when me.verification_status = 'verified' and lower(me.full_name) <> lower(v_name) then 'pending' else me.verification_status end,
    verified = case when me.verification_status = 'verified' and lower(me.full_name) <> lower(v_name) and me.role = 'passenger' then false else me.verified end
  where id = auth.uid()
  returning * into me;
  return me;
end;
$$;

/** Sends the rider's verification for review. NIN (11 digits) and date of birth can only be set once. */
create or replace function public.submit_verification(p_nin text, p_date_of_birth date, p_phone text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  v_nin text := regexp_replace(coalesce(p_nin, ''), '\D', '', 'g');
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
begin
  if auth.uid() is null then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  select * into me from public.profiles where id = auth.uid();
  if me.verification_status in ('pending', 'verified') then
    raise exception 'Your verification is already %.', case when me.verification_status = 'pending' then 'being reviewed' else 'complete' end using errcode = '22023';
  end if;
  if length(v_nin) <> 11 then raise exception 'Your NIN has 11 digits.' using errcode = '22023'; end if;
  if me.nin is not null and me.nin <> v_nin then raise exception 'Your NIN is already on file; contact support to change it.' using errcode = '22023'; end if;
  if exists (select 1 from public.profiles where nin = v_nin and id <> me.id) then
    raise exception 'This NIN is already used by another account.' using errcode = '23505';
  end if;
  if p_date_of_birth is null or p_date_of_birth > (current_date - interval '16 years') or p_date_of_birth < date '1920-01-01' then
    raise exception 'Enter your date of birth (you must be 16 or older).' using errcode = '22023';
  end if;
  if v_phone is null or length(public._phone_key(v_phone)) < 10 then raise exception 'Enter your phone number.' using errcode = '22023'; end if;
  update public.profiles set
    nin = v_nin, date_of_birth = coalesce(date_of_birth, p_date_of_birth), phone = v_phone,
    verification_status = 'pending', verification_note = null, verification_submitted_at = now()
  where id = me.id returning * into me;
  return me;
end;
$$;

/** Riders waiting for (or done with) verification, for admins. */
create or replace function public.admin_rider_verifications(p_status text default 'pending') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id, 'name', p.full_name, 'email', p.email, 'phone', p.phone, 'nin', p.nin, 'date_of_birth', p.date_of_birth,
      'home_area', p.home_area, 'emergency_name', p.emergency_name, 'emergency_phone', p.emergency_phone,
      'status', p.verification_status, 'note', p.verification_note, 'submitted_at', p.verification_submitted_at,
      'verified_at', p.verified_at, 'created_at', p.created_at,
      'phone_shared', exists (select 1 from public.profiles o where o.id <> p.id and public._phone_key(o.phone) = public._phone_key(p.phone))
    ) order by p.verification_submitted_at desc nulls last, p.created_at desc)
    from public.profiles p
    where p.role = 'passenger' and (p_status is null or p_status = 'all' or p.verification_status = p_status)
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_review_verification(p_user uuid, p_approve boolean, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare who text;
begin
  perform public._require_admin();
  update public.profiles set
    verification_status = case when p_approve then 'verified' else 'rejected' end,
    verified = p_approve,
    verified_at = case when p_approve then now() else null end,
    verification_note = nullif(left(trim(coalesce(p_note, '')), 300), '')
  where id = p_user and role = 'passenger' and verification_status in ('pending', 'rejected', 'verified')
  returning full_name into who;
  if who is null then raise exception 'That rider has no verification to review.' using errcode = 'P0003'; end if;
  perform public.log_action(case when p_approve then 'Verified rider' else 'Declined rider verification' end, who);
end;
$$;

-- ------------------------------------------------------------------ 2. refunds
alter table public.bookings add column if not exists refunded_at timestamptz;

create table if not exists public.refund_requests (
  id          bigint generated always as identity primary key,
  booking_id  text not null references public.bookings (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  amount      integer not null check (amount > 0),
  reason      text not null,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  admin_note  text,
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz
);
create unique index if not exists refund_requests_open on public.refund_requests (booking_id) where status = 'pending';
alter table public.refund_requests enable row level security;
drop policy if exists refund_requests_read on public.refund_requests;
create policy refund_requests_read on public.refund_requests for select
  using (user_id = auth.uid() or public.my_role() = 'admin');
grant select on public.refund_requests to authenticated;

/** Money back for one booking: wallet credited, booking cancelled, operator hold voided or taken back. */
create or replace function public._refund_booking(p_booking text) returns integer
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  p public.payouts;
begin
  select * into b from public.bookings where id = p_booking for update;
  if not found then raise exception 'That booking no longer exists.' using errcode = 'P0003'; end if;
  if b.refunded_at is not null then raise exception 'This booking was already refunded.' using errcode = '22023'; end if;
  if coalesce(b.fare, 0) <= 0 or b.payment_method not in ('tap_card', 'qr') then
    raise exception 'This booking was free or paid outside the wallet; there is nothing to refund here.' using errcode = '22023';
  end if;
  -- A booking cancelled earlier through the normal flow was already refunded by that flow.
  if b.status in ('cancelled', 'declined') then raise exception 'This booking was cancelled and its fare already returned.' using errcode = '22023'; end if;
  select * into p from public.payouts where booking_id = b.id for update;
  if found and p.status = 'released' then
    update public.collection_wallets set available = greatest(available - p.amount, 0), updated_at = now() where provider_id = p.provider_id;
    update public.payouts set status = 'refunded', settled_at = now() where id = p.id;
  end if;
  update public.wallets set balance = balance + b.fare where user_id = b.user_id;
  update public.bookings set status = 'cancelled', refunded_at = now() where id = b.id; -- voids a held payout (trigger)
  return b.fare;
end;
$$;

/** A rider asks for their money back on a paid booking (within 14 days). */
create or replace function public.request_refund(p_booking text, p_reason text) returns public.refund_requests
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  r public.refund_requests;
  v_reason text := nullif(left(trim(coalesce(p_reason, '')), 500), '');
begin
  if auth.uid() is null then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  select * into b from public.bookings where id = p_booking and user_id = auth.uid();
  if not found then raise exception 'That booking isn''t on your account.' using errcode = 'P0003'; end if;
  if v_reason is null or length(v_reason) < 5 then raise exception 'Tell us briefly what went wrong.' using errcode = '22023'; end if;
  if b.refunded_at is not null or b.status in ('cancelled', 'declined') then raise exception 'This booking has already been refunded.' using errcode = '22023'; end if;
  if coalesce(b.fare, 0) <= 0 or b.payment_method not in ('tap_card', 'qr') then raise exception 'This booking was free; there is nothing to refund.' using errcode = '22023'; end if;
  if b.created_at < now() - interval '14 days' then raise exception 'Refunds can be requested up to 14 days after booking.' using errcode = '22023'; end if;
  if exists (select 1 from public.refund_requests where booking_id = b.id and status = 'pending') then
    raise exception 'You already asked for a refund on this booking; we''ll get back to you.' using errcode = '23505';
  end if;
  insert into public.refund_requests (booking_id, user_id, amount, reason) values (b.id, auth.uid(), b.fare, v_reason) returning * into r;
  return r;
end;
$$;

create or replace function public.admin_refund_requests(p_status text default 'pending') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'booking', r.booking_id, 'amount', r.amount, 'reason', r.reason, 'status', r.status, 'note', r.admin_note,
      'created_at', r.created_at, 'reviewed_at', r.reviewed_at,
      'rider', pr.full_name, 'email', pr.email, 'phone', pr.phone,
      'title', b.title, 'kind', b.kind, 'departure_at', b.departure_at, 'booking_status', b.status, 'ticket', b.ticket_code,
      'operator', (select name from public.providers where id = b.provider_id)
    ) order by r.created_at desc)
    from public.refund_requests r
    join public.bookings b on b.id = r.booking_id
    left join public.profiles pr on pr.id = r.user_id
    where p_status is null or p_status = 'all' or r.status = p_status
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_review_refund(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.refund_requests;
  amt integer := 0;
begin
  perform public._require_admin();
  select * into r from public.refund_requests where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'That refund request was already handled.' using errcode = '22023'; end if;
  if p_approve then amt := public._refund_booking(r.booking_id); end if;
  update public.refund_requests set status = case when p_approve then 'approved' else 'declined' end,
    admin_note = nullif(left(trim(coalesce(p_note, '')), 300), ''), reviewed_at = now()
  where id = r.id;
  perform public.log_action(case when p_approve then 'Approved refund' else 'Declined refund' end, r.booking_id);
  return jsonb_build_object('status', case when p_approve then 'approved' else 'declined' end, 'amount', amt);
end;
$$;

/** Admin refund without a request (e.g. a bus that never came). */
create or replace function public.admin_refund_booking(p_booking text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare amt integer;
begin
  perform public._require_admin();
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'Give a reason for the refund.' using errcode = '22023'; end if;
  amt := public._refund_booking(p_booking);
  update public.refund_requests set status = 'approved', admin_note = left(p_reason, 300), reviewed_at = now() where booking_id = p_booking and status = 'pending';
  perform public.log_action('Refunded booking', p_booking);
  return jsonb_build_object('status', 'approved', 'amount', amt);
end;
$$;

-- ------------------------------------------------------------------ grants
revoke execute on function public._refund_booking(text) from public, anon, authenticated;
revoke execute on function public.update_my_profile(text, text, text, text, text), public.submit_verification(text, date, text),
  public.admin_rider_verifications(text), public.admin_review_verification(uuid, boolean, text),
  public.request_refund(text, text), public.admin_refund_requests(text), public.admin_review_refund(bigint, boolean, text),
  public.admin_refund_booking(text, text) from public, anon;
grant execute on function public.update_my_profile(text, text, text, text, text), public.submit_verification(text, date, text),
  public.admin_rider_verifications(text), public.admin_review_verification(uuid, boolean, text),
  public.request_refund(text, text), public.admin_refund_requests(text), public.admin_review_refund(bigint, boolean, text),
  public.admin_refund_booking(text, text) to authenticated;

-- ------------------------------------------------------------------ copy
-- "Events" are called "Event rides" everywhere riders see them.
update public.ads set cta_label = 'See event rides' where id = 'ad_events' and cta_label = 'See events';
