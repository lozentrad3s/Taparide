-- Tap A Ride · partner registration (private drivers, fleet owners, operators, EV operators)
-- Requirements for a private partner: verified driver's licence, verified vehicle with its original
-- chassis (VIN) and plate number, full name, email and contact details. Documents are stored in a
-- private bucket; an AI pre-check result is saved with the application; FCTA/admins decide.

-- New provider / vehicle kinds.
alter table public.providers drop constraint if exists providers_kind_check;
alter table public.providers add constraint providers_kind_check
  check (kind in ('bus_operator', 'fleet_owner', 'rail', 'electric', 'shuttle', 'tricycle', 'private_driver'));
alter table public.vehicles drop constraint if exists vehicles_kind_check;
alter table public.vehicles add constraint vehicles_kind_check
  check (kind in ('bus', 'minibus', 'train', 'ev_car', 'ev_shuttle', 'ev_keke', 'car'));

create table public.partner_applications (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users (id) on delete cascade,
  partner_type      text not null check (partner_type in ('private_driver', 'fleet_owner', 'bus_operator', 'ev_operator', 'government_agency')),
  status            text not null default 'submitted' check (status in ('submitted', 'under_review', 'approved', 'rejected', 'needs_changes')),
  full_name         text not null,
  email             text not null,
  phone             text not null,
  date_of_birth     date not null,
  address           text not null,
  area              text not null,
  company_name      text,
  rc_number         text,
  tin               text,
  fleet_size        integer check (fleet_size is null or fleet_size between 1 and 10000),
  contact_role      text,
  nin               text,
  next_of_kin_name  text,
  next_of_kin_phone text,
  -- Private drivers: licence and their vehicle. Organisations leave these empty and register their fleet later.
  licence_number    text,
  licence_class     text,
  licence_expiry    date,
  vehicle_make      text,
  vehicle_model     text,
  vehicle_year      integer check (vehicle_year is null or vehicle_year between 1980 and 2100),
  vehicle_colour    text,
  plate_number      text,
  chassis_number    text check (chassis_number is null or chassis_number ~ '^[A-HJ-NPR-Z0-9]{17}$'),
  engine_number     text,
  seats             integer check (seats is null or seats between 1 and 80),
  documents         jsonb not null default '[]',
  ai_check          jsonb,
  reviewer_note     text,
  reviewed_by       text,
  reviewed_at       timestamptz,
  provider_id       text references public.providers (id),
  vehicle_id        text references public.vehicles (id),
  created_at        timestamptz not null default now()
);
create index partner_applications_user_idx on public.partner_applications (user_id, created_at desc);
create unique index partner_applications_open_chassis on public.partner_applications (chassis_number) where status <> 'rejected' and chassis_number is not null;

alter table public.partner_applications enable row level security;
create policy applications_read on public.partner_applications for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
revoke insert, update, delete on public.partner_applications from anon, authenticated;

-- ------------------------------------------------------------------ document storage (private)

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('partner-docs', 'partner-docs', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

-- Applicants write and read inside their own folder (<user id>/...); FCTA and admins read everything.
create policy partner_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'partner-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy partner_docs_update on storage.objects for update to authenticated
  using (bucket_id = 'partner-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy partner_docs_read on storage.objects for select to authenticated
  using (bucket_id = 'partner-docs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff()));

-- ------------------------------------------------------------------ actions

create or replace function public.submit_partner_application(p_application jsonb)
returns public.partner_applications
language plpgsql security definer set search_path = public as $$
declare
  a        public.partner_applications;
  v_chassis text := upper(regexp_replace(coalesce(p_application ->> 'chassis_number', ''), '[\s-]', '', 'g'));
  v_plate   text := upper(trim(coalesce(p_application ->> 'plate_number', '')));
  v_docs    jsonb := coalesce(p_application -> 'documents', '[]');
  v_org     boolean := coalesce(p_application ->> 'partner_type', '') <> 'private_driver';
begin
  if auth.uid() is null then raise exception 'Please sign in to apply.' using errcode = '42501'; end if;
  if exists (select 1 from public.partner_applications where user_id = auth.uid() and status in ('submitted', 'under_review')) then
    raise exception 'You already have an application under review.';
  end if;

  if v_org then
    -- Organisations: CAC registration, fleet size and compliance documents.
    if upper(regexp_replace(coalesce(p_application ->> 'rc_number', ''), '[\s-]', '', 'g')) !~ '^(RC|BN|IT)?[0-9]{4,8}$' then
      raise exception 'Enter the CAC registration number, e.g. RC 1234567.';
    end if;
    if coalesce((p_application ->> 'fleet_size')::int, 0) < 1 then raise exception 'Enter how many vehicles you run.'; end if;
    if not (v_docs @> '[{"slot":"cac_certificate"}]' and v_docs @> '[{"slot":"operating_permit"}]' and v_docs @> '[{"slot":"insurance"}]') then
      raise exception 'Upload the CAC certificate, FCT operating permit and insurance certificate.';
    end if;
    v_chassis := null;
    v_plate := null;
  else
    if v_chassis !~ '^[A-HJ-NPR-Z0-9]{17}$' then raise exception 'A chassis number (VIN) has 17 letters and numbers, never I, O or Q.'; end if;
    if regexp_replace(v_plate, '[\s-]', '', 'g') !~ '^[A-Z]{2,3}[0-9]{2,4}[A-Z]{0,3}$' then raise exception 'Enter the plate number as printed, e.g. ABJ 123 AB.'; end if;
    if (p_application ->> 'licence_expiry')::date <= current_date then raise exception 'Your driver''s licence has expired. Renew it before applying.'; end if;
    if not (v_docs @> '[{"slot":"licence_front"}]' and v_docs @> '[{"slot":"proof_of_ownership"}]' and v_docs @> '[{"slot":"vehicle_photo"}]') then
      raise exception 'Upload your licence, proof of ownership and a vehicle photo.';
    end if;
    if exists (select 1 from public.vehicles where upper(regexp_replace(plate, '[\s-]', '', 'g')) = regexp_replace(v_plate, '[\s-]', '', 'g'))
       or exists (select 1 from public.partner_applications where chassis_number = v_chassis and status <> 'rejected' and user_id <> auth.uid()) then
      raise exception 'This plate or chassis number is already registered on Tap A Ride.';
    end if;
  end if;

  insert into public.partner_applications (
    user_id, partner_type, full_name, email, phone, date_of_birth, address, area, company_name, rc_number, tin, fleet_size, contact_role, nin,
    next_of_kin_name, next_of_kin_phone, licence_number, licence_class, licence_expiry,
    vehicle_make, vehicle_model, vehicle_year, vehicle_colour, plate_number, chassis_number, engine_number,
    seats, documents, ai_check)
  values (
    auth.uid(), p_application ->> 'partner_type', trim(p_application ->> 'full_name'), trim(p_application ->> 'email'),
    trim(p_application ->> 'phone'), (p_application ->> 'date_of_birth')::date, trim(p_application ->> 'address'),
    p_application ->> 'area', nullif(trim(p_application ->> 'company_name'), ''),
    nullif(upper(regexp_replace(coalesce(p_application ->> 'rc_number', ''), '[\s-]', '', 'g')), ''), nullif(trim(p_application ->> 'tin'), ''),
    (p_application ->> 'fleet_size')::int, nullif(trim(p_application ->> 'contact_role'), ''), nullif(trim(p_application ->> 'nin'), ''),
    nullif(trim(p_application ->> 'next_of_kin_name'), ''), nullif(trim(p_application ->> 'next_of_kin_phone'), ''),
    case when v_org then null else upper(trim(p_application ->> 'licence_number')) end,
    case when v_org then null else p_application ->> 'licence_class' end,
    case when v_org then null else (p_application ->> 'licence_expiry')::date end,
    case when v_org then null else trim(p_application ->> 'vehicle_make') end,
    case when v_org then null else trim(p_application ->> 'vehicle_model') end,
    case when v_org then null else (p_application ->> 'vehicle_year')::int end,
    case when v_org then null else trim(p_application ->> 'vehicle_colour') end,
    v_plate, v_chassis, nullif(upper(trim(p_application ->> 'engine_number')), ''),
    case when v_org then null else (p_application ->> 'seats')::int end, v_docs, p_application -> 'ai_check')
  returning * into a;
  return a;
end;
$$;

create or replace function public.review_partner_application(p_id uuid, p_decision text, p_note text default '')
returns public.partner_applications
language plpgsql security definer set search_path = public as $$
declare
  a       public.partner_applications;
  me      public.profiles;
  v_prov  text;
  v_veh   text;
  v_kind  text;
begin
  if not public.is_staff() then raise exception 'Your account is not allowed to review partner applications.' using errcode = '42501'; end if;
  if p_decision not in ('under_review', 'approved', 'rejected', 'needs_changes') then raise exception 'Unknown decision.'; end if;
  select * into a from public.partner_applications where id = p_id for update;
  if not found then raise exception 'Application not found.' using errcode = 'P0003'; end if;
  if a.status = 'approved' then raise exception 'This application is already approved.'; end if;
  if p_decision in ('rejected', 'needs_changes') and coalesce(trim(p_note), '') = '' then
    raise exception 'Tell the applicant what to fix or why it was not approved.';
  end if;
  select * into me from public.profiles where id = auth.uid();

  if p_decision = 'approved' then
    insert into public.providers (name, kind, status, area, contact_name, contact_email, description)
    values (coalesce(nullif(a.company_name, ''), a.full_name),
            case a.partner_type when 'private_driver' then 'private_driver' when 'fleet_owner' then 'fleet_owner'
                                when 'ev_operator' then 'electric' else 'bus_operator' end,
            'verified', a.area, a.full_name, a.email, 'Approved through partner registration.')
    returning id into v_prov;

    if a.partner_type = 'private_driver' then
    v_kind := case
      when a.partner_type = 'ev_operator' then 'ev_car'
      when a.seats > 18 then 'bus'
      when a.seats > 8 then 'minibus'
      else 'car' end;
    insert into public.vehicles (operator_id, plate, kind, model, capacity, status, verification, area, driver_name,
                                 base_fare, per_km_fare, battery_pct, range_km)
    values (v_prov, a.plate_number, v_kind, a.vehicle_make || ' ' || a.vehicle_model, a.seats, 'active', 'verified', a.area, a.full_name,
            1000, 150, case when v_kind = 'ev_car' then 100 end, case when v_kind = 'ev_car' then 300 end)
    returning id into v_veh;
    end if;

    update public.profiles
       set role = case when a.partner_type = 'fleet_owner' then 'fleet_owner' else 'operator' end,
           provider_id = v_prov,
           verified = true
     where id = a.user_id;
  end if;

  update public.partner_applications
     set status = p_decision, reviewer_note = nullif(trim(p_note), ''), reviewed_by = coalesce(me.full_name, 'Reviewer'),
         reviewed_at = now(), provider_id = coalesce(v_prov, provider_id), vehicle_id = coalesce(v_veh, vehicle_id)
   where id = a.id
  returning * into a;

  perform public.log_action(case p_decision when 'approved' then 'Approved partner application'
                                            when 'rejected' then 'Rejected partner application'
                                            when 'needs_changes' then 'Requested changes to partner application'
                                            else 'Opened partner application for review' end,
                            a.full_name || ' · ' || coalesce(a.plate_number, a.rc_number, ''));
  return a;
end;
$$;

-- Riders can book verified private cars as well as electric cars.
create or replace function public.book_electric(p_vehicle_id text, p_pickup text, p_dropoff text, p_fare integer, p_method text)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  me public.profiles;
  v  public.vehicles;
  b  public.bookings;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception 'Your session has ended. Please sign in again.' using errcode = '42501'; end if;
  select * into v from public.vehicles where id = p_vehicle_id for update;
  if not found then raise exception 'That vehicle is no longer listed.' using errcode = 'P0003'; end if;
  if v.kind not in ('ev_car', 'car') or v.verification <> 'verified' or not public.provider_is_verified(v.operator_id) then
    raise exception 'Only verified cars can be booked.';
  end if;
  if v.status <> 'active' then raise exception 'This vehicle was just taken. Choose another one.'; end if;
  if p_fare < coalesce(v.base_fare, 0) then raise exception 'The fare estimate is out of date. Refresh and try again.'; end if;
  update public.wallets set balance = balance - p_fare where user_id = me.id and balance >= p_fare;
  if not found then raise exception 'Your tap card balance is too low for this fare. Top up and try again.' using errcode = 'P0002'; end if;
  update public.vehicles set status = 'on_trip' where id = v.id;
  insert into public.bookings (user_id, passenger_name, kind, status, origin, destination, departure_at, fare,
                               payment_method, ticket_code, title, vehicle_id, provider_id)
  values (me.id, me.full_name, 'electric', 'confirmed', p_pickup, p_dropoff, now() + interval '6 minutes', p_fare,
          p_method, 'EV-' || upper(substr(md5(random()::text), 1, 6)), v.model || ' · ' || v.plate, v.id, v.operator_id)
  returning * into b;
  return b;
end;
$$;

revoke execute on function public.submit_partner_application(jsonb) from public, anon;
revoke execute on function public.review_partner_application(uuid, text, text) from public, anon;
grant execute on function public.submit_partner_application(jsonb) to authenticated;
grant execute on function public.review_partner_application(uuid, text, text) to authenticated;
