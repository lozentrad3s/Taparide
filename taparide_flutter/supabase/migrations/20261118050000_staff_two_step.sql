-- Two-step sign-in for platform admins and FCTA staff, enforced by the database.
-- Every role check (policies and functions) goes through my_role(). Admin and government accounts
-- only get their powers when the session passed the authenticator step (JWT claim aal = aal2);
-- until then they are treated as plain riders, so a stolen password alone opens nothing.
-- The app sends these accounts to the two-step screen first (lib/features/auth/two_step_page.dart).
create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select case
    when p.role in ('admin', 'government') and coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then 'passenger'
    else p.role
  end
  from public.profiles p where p.id = auth.uid()
$$;
