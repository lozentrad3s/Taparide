-- Until full launch, joining on the website earns a "ride reward" with no naira value:
-- no ₦1,000 is added to anyone's wallet. Accounts whose email matches a website sign-up are marked
-- "Ride reward granted" (waitlist.credited_user / credited_at), and the app shows that badge.
-- Ride credit already added is taken back out of wallets (it was never paid for).
-- Also: Google sign-ups get their name from Google's "name" field, and new wallets start at ₦0.

create or replace function public.waitlist_free_ride() returns int language sql immutable as $$ select 0 $$;

-- Matching a confirmed account to its website sign-up marks the reward, without money.
create or replace function public.credit_waitlist_ride() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email is null or new.email_confirmed_at is null then return new; end if;
  update public.waitlist l set credited_user = new.id, credited_at = now()
  where lower(l.email) = lower(new.email) and l.credited_user is null;
  return new;
end;
$$;

-- Existing ride credit (the old ₦1,000) comes out of wallets.
update public.wallets set balance = greatest(balance - ride_credit, 0), ride_credit = 0 where ride_credit > 0;

-- Accounts that already exist and match a sign-up get the badge too.
update public.waitlist l set credited_user = u.id, credited_at = coalesce(l.credited_at, now())
from auth.users u
where l.credited_user is null and u.email_confirmed_at is not null and lower(u.email) = lower(l.email);

/** The signed-in person's sign-up reward. */
create or replace function public.my_signup_reward() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'granted', l.id is not null,
    'at', l.credited_at,
    'label', case when l.id is not null then 'Ride reward granted' else null end)
  from (select 1) one
  left join lateral (
    select id, credited_at from public.waitlist
    where credited_user = auth.uid() or lower(email) = lower((select email from auth.users where id = auth.uid()))
    order by credited_at nulls last limit 1
  ) l on true
$$;
revoke execute on function public.my_signup_reward() from public, anon;
grant execute on function public.my_signup_reward() to authenticated;

-- New accounts (email or Google): name from the form or from Google; wallets start empty.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, phone, organisation)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), nullif(new.raw_user_meta_data ->> 'name', ''), split_part(new.email, '@', 1)),
    new.email,
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    nullif(new.raw_user_meta_data ->> 'organisation', '')
  );
  insert into public.wallets (user_id, card_number, balance)
  values (new.id, '50610042' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'), 0);
  return new;
end;
$$;
