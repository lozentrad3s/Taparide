-- Drivers complete car rides from their dashboard: the booking completes,
-- the car is available again and the fare is added to its monthly earnings.

create or replace function public.complete_ride(p_booking_id text)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0003'; end if;
  if b.kind <> 'electric' or b.provider_id is null then
    raise exception 'Only car rides are completed by the driver.';
  end if;
  if not public.manages(b.provider_id) then
    raise exception 'Your account is not allowed to complete this ride.' using errcode = '42501';
  end if;
  if b.status <> 'confirmed' then raise exception 'This ride is not in progress.'; end if;

  update public.vehicles
     set status = 'active', month_earnings = month_earnings + b.fare
   where id = b.vehicle_id;
  update public.bookings set status = 'completed' where id = b.id returning * into b;
  perform public.log_action('Completed ride', b.origin || ' → ' || b.destination);
  return b;
end;
$$;

grant execute on function public.complete_ride(text) to authenticated;
