-- Admin accounts are managed by the platform owner directly in the database, never from the app.
-- A shared demo admin can therefore neither demote the master admin nor mint new admins.
create or replace function public.set_user_role(p_user_id uuid, p_role text, p_provider_id text default null)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
begin
  if public.my_role() <> 'admin' then raise exception 'Your account is not allowed to change account roles.' using errcode = '42501'; end if;
  if p_user_id = auth.uid() then raise exception 'You cannot change your own role.' using errcode = '42501'; end if;
  if p_role = 'admin' or exists (select 1 from public.profiles where id = p_user_id and role = 'admin') then
    raise exception 'Admin accounts can only be changed by the platform owner.' using errcode = '42501';
  end if;
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

revoke execute on function public.set_user_role(uuid, text, text) from public, anon;
grant execute on function public.set_user_role(uuid, text, text) to authenticated;
