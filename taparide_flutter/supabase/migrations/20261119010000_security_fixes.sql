-- Fixes from the 19 Nov 2026 security test (SECURITY-PENTEST-2026-11-19.md).
-- C1  test top-ups can't add money once real payments are on (payments_live is set by 20261119000000);
--     the old demo top-up is also closed to signed-in users.
-- H2  the free ride is paid once per phone number, not once per email.
-- M1  create_event and offer_event_bus use my_role(), so admins must pass the two-step code.
-- M2  log_action can only be called from inside our own functions.
-- M3  anonymous visitors can only run the functions the public website/app need; everything else
--     needs a signed-in user. count_ad_impressions counts signed-in riders only.

-- ------------------------------------------------------------------ C1
revoke execute on function public.top_up(integer) from public, anon, authenticated;
revoke execute on function public.claim_ad_reward(text) from public, anon, authenticated;

-- ------------------------------------------------------------------ H2
create or replace function public.credit_waitlist_ride() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if new.email is null or new.email_confirmed_at is null then return new; end if;
  update public.waitlist l set credited_user = new.id, credited_at = now()
  where lower(l.email) = lower(new.email) and l.credited_user is null
    and l.id <= (select coalesce(max(id), 0) from (select id from public.waitlist order by id limit public.waitlist_free_ride_cap()) firsts)
    -- One free ride per phone number: a second email with the same number gets none.
    and not exists (
      select 1 from public.waitlist o
      where o.id <> l.id and o.credited_user is not null
        and public._phone_key(o.phone) is not null and public._phone_key(o.phone) = public._phone_key(l.phone))
  returning l.id into v_id;
  if v_id is not null then
    update public.wallets set balance = balance + public.waitlist_free_ride(), ride_credit = ride_credit + public.waitlist_free_ride() where user_id = new.id;
  end if;
  return new;
end;
$$;

-- ------------------------------------------------------------------ M1
-- Rewrites the role checks inside the two functions (bodies otherwise unchanged).
do $$
declare
  f regprocedure;
  def text;
begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('create_event', 'offer_event_bus')
  loop
    def := pg_get_functiondef(f);
    def := replace(def, 'me.role not in', 'public.my_role() not in');
    def := replace(def, 'me.role = ''', 'public.my_role() = ''');
    execute def;
  end loop;
end;
$$;

-- ------------------------------------------------------------------ M2
revoke execute on function public.log_action(text, text) from public, anon, authenticated;

-- ------------------------------------------------------------------ M3
create or replace function public.count_ad_impressions(p_ids text[]) returns void
language sql security definer set search_path = public as $$
  update public.ads set impressions = impressions + 1
  where auth.uid() is not null and id = any (p_ids[1:5]) and active;
$$;

do $$
declare
  f record;
begin
  -- Functions that only had the default "everyone may run it" grant: keep them for signed-in
  -- users, take them away from everyone else.
  for f in
    select p.oid::regprocedure sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'))
      and p.proname not in ('log_action', 'top_up', 'claim_ad_reward')
      and not p.proname like '\_%'
  loop
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f'
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
  -- Row-level security policies call some helpers; whoever reads a table must be able to run them.
  for f in
    select distinct p.oid::regprocedure sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and exists (select 1 from pg_policies pol
                  where coalesce(pol.qual, '') ~ ('\m' || p.proname || '\s*\(') or coalesce(pol.with_check, '') ~ ('\m' || p.proname || '\s*\('))
  loop
    execute format('grant execute on function %s to anon, authenticated', f.sig);
  end loop;
end;
$$;
alter default privileges in schema public revoke execute on functions from public, anon;

-- What signed-out visitors (website, shared-trip links, payment callbacks) may run.
grant execute on function
  public.get_shared_trip(text),
  public.confirm_top_up(text, text, bigint, text),
  public.payments_live(),
  public.join_waitlist(text, text, text, text, text, text, text, text),
  public.waitlist_status(text),
  public.event_seat_demand(text),
  public.waitlist_event(text),
  public.waitlist_free_ride(),
  public.waitlist_free_ride_cap(),
  public.reserve_event_pass(text, text, text, text, text, date[], text),
  public.daily_summary(text),
  public.release_due_payouts()
to anon;
