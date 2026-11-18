-- Tap A Ride demo data (illustrative). Organisations and figures are fictional;
-- places and coordinates are real Abuja locations. Matches lib/core/backend/demo_seed.dart.

create or replace function pg_temp.every(h1 int, h2 int, step int) returns text[] language sql immutable as $$
  select array_agg(to_char(make_time(m / 60, m % 60, 0), 'HH24:MI') order by m) from generate_series(h1 * 60, h2 * 60, step) m
$$;

insert into public.providers (id, name, kind, status, area, contact_name, contact_email, joined_at, description) values
  ('p_metro', 'Abuja Metro Bus Co. (sample)', 'bus_operator', 'verified', 'Wuse · Central Area', 'Ibrahim Musa', 'ops@abujametro.demo', '2026-07-02', 'City bus operator running 12 fixed-fare routes across the FCT.'),
  ('p_greenfleet', 'GreenFleet Logistics (sample)', 'fleet_owner', 'verified', 'Jabi', 'Chiamaka Obi', 'fleet@greenfleet.demo', '2026-07-09', 'Owns 24 buses leased to Abuja Metro Bus Co.'),
  ('p_naviride', 'NaviRide Electric (sample)', 'electric', 'verified', 'Maitama', 'Tunde Bello', 'ev@naviride.demo', '2026-08-03', 'On-demand electric cars with verified drivers.'),
  ('p_rail', 'Capital Metro Rail Services (sample)', 'rail', 'verified', 'Central Area', 'Kemi Adebayo', 'rail@capitalmetro.demo', '2026-07-20', 'Operates metro rail services between Central Station and Idu.'),
  ('p_airport', 'FCT Airport E-Shuttle (sample)', 'shuttle', 'verified', 'Airport Road', 'Sani Garba', 'shuttle@airporteshuttle.demo', '2026-08-18', 'Electric airport shuttle to the city centre.'),
  ('p_kubwa', 'Kubwa Express Shuttles (sample)', 'shuttle', 'pending', 'Kubwa', 'Peter Ojo', 'hello@kubwaexpress.demo', '2026-10-09', 'Minibus commuter service applying to join the platform.'),
  ('p_nyanya', 'Nyanya Commuter Union (sample)', 'bus_operator', 'pending', 'Nyanya · AYA', 'Musa Danjuma', 'office@nyanyacommuters.demo', '2026-10-12', 'Union of minibus owners on the Nyanya corridor.'),
  ('p_keke', 'City Keke Cooperative (sample)', 'tricycle', 'suspended', 'Garki', 'Blessing Udo', 'coop@citykeke.demo', '2026-08-25', 'Electric tricycle pilot. Suspended pending permit renewal.');

insert into public.routes (id, provider_id, code, name, stops, fare, duration_min, mode, departures, monthly_trips, active) values
  ('r01', 'p_metro', 'K01', null, '[{"name":"Kubwa","lat":9.1548,"lng":7.3227},{"name":"Dutse Junction","lat":9.1305,"lng":7.364},{"name":"Gwarinpa Junction","lat":9.0985,"lng":7.414},{"name":"Berger","lat":9.0679,"lng":7.456}]', 500, 35, 'bus', pg_temp.every(5, 21, 15), 42800, true),
  ('r02', 'p_metro', 'A01', null, '[{"name":"Area 1","lat":9.0272,"lng":7.4842},{"name":"Airport Junction","lat":8.996,"lng":7.408},{"name":"Lugbe","lat":8.98,"lng":7.375},{"name":"Gwagwalada","lat":8.942,"lng":7.083}]', 900, 50, 'bus', pg_temp.every(5, 21, 20), 38450, true),
  ('r03', 'p_rail', 'MR1', 'Abuja Metro Rail · Metro Line', '[{"name":"Abuja Metro Station","lat":9.0441,"lng":7.4868},{"name":"Stadium","lat":9.0365,"lng":7.4545},{"name":"Kukwaba","lat":9.0395,"lng":7.438},{"name":"Wupa","lat":9.033,"lng":7.39},{"name":"Idu","lat":9.048,"lng":7.348}]', 500, 25, 'rail', pg_temp.every(6, 20, 30), 27400, true),
  ('r04', 'p_metro', 'A05', null, '[{"name":"Area 1","lat":9.0272,"lng":7.4842},{"name":"Berger","lat":9.0679,"lng":7.456},{"name":"Dutse Junction","lat":9.1305,"lng":7.364},{"name":"Bwari","lat":9.283,"lng":7.381}]', 900, 55, 'bus', pg_temp.every(5, 20, 30), 31200, true),
  ('r05', 'p_metro', 'A02', null, '[{"name":"Area 1","lat":9.0272,"lng":7.4842},{"name":"AYA","lat":9.043,"lng":7.517},{"name":"Nyanya","lat":9.0213,"lng":7.5616}]', 420, 25, 'bus', pg_temp.every(5, 21, 15), 29600, true),
  ('r06', 'p_metro', 'L01', null, '[{"name":"Lugbe","lat":8.98,"lng":7.375},{"name":"Airport Junction","lat":8.996,"lng":7.408},{"name":"Area 1","lat":9.0272,"lng":7.4842},{"name":"Berger","lat":9.0679,"lng":7.456}]', 1000, 40, 'bus', pg_temp.every(6, 20, 30), 21300, true),
  ('r07', 'p_metro', 'A03', null, '[{"name":"Area 1","lat":9.0272,"lng":7.4842},{"name":"Garki","lat":9.031,"lng":7.489},{"name":"Wuse","lat":9.0643,"lng":7.4686}]', 240, 15, 'bus', pg_temp.every(6, 21, 15), 18900, true),
  ('r08', 'p_metro', 'N01', null, '[{"name":"Nyanya","lat":9.0213,"lng":7.5616},{"name":"AYA","lat":9.043,"lng":7.517},{"name":"Area 1","lat":9.0272,"lng":7.4842},{"name":"Berger","lat":9.0679,"lng":7.456},{"name":"Jabi Garage","lat":9.0705,"lng":7.425}]', 1700, 50, 'bus', pg_temp.every(6, 20, 30), 15200, true),
  ('r09', 'p_metro', 'B03', null, '[{"name":"Berger","lat":9.0679,"lng":7.456},{"name":"Jabi Garage","lat":9.0705,"lng":7.425},{"name":"Karmo","lat":9.059,"lng":7.38}]', 700, 25, 'bus', pg_temp.every(6, 20, 30), 12800, true),
  ('r10', 'p_metro', 'A04', null, '[{"name":"Apo","lat":9.004,"lng":7.493},{"name":"Asokoro","lat":9.042,"lng":7.525},{"name":"Nyanya","lat":9.0213,"lng":7.5616},{"name":"Mararaba","lat":9.0236,"lng":7.596}]', 500, 35, 'bus', pg_temp.every(5, 20, 20), 9400, true),
  ('r11', 'p_metro', 'B02', null, '[{"name":"Berger","lat":9.0679,"lng":7.456},{"name":"Airport Junction","lat":8.996,"lng":7.408},{"name":"Lugbe","lat":8.98,"lng":7.375},{"name":"Gwagwalada","lat":8.942,"lng":7.083}]', 700, 55, 'bus', pg_temp.every(5, 20, 30), 17600, true),
  ('r12', 'p_metro', 'B04', null, '[{"name":"Berger","lat":9.0679,"lng":7.456},{"name":"Gwarinpa Junction","lat":9.0985,"lng":7.414},{"name":"Kubwa","lat":9.1548,"lng":7.3227},{"name":"Dei-Dei","lat":9.11,"lng":7.285},{"name":"Zuba","lat":9.1,"lng":7.21}]', 1800, 50, 'bus', pg_temp.every(6, 20, 30), 14100, true),
  ('r13', 'p_metro', 'X13', null, '[{"name":"Apo","lat":9.004,"lng":7.493},{"name":"Garki","lat":9.031,"lng":7.489},{"name":"Area 1","lat":9.0272,"lng":7.4842}]', 400, 20, 'bus', pg_temp.every(6, 20, 40), 0, false),
  ('r14', 'p_rail', 'MR2', 'Abuja Metro Rail · Airport Line', '[{"name":"Idu","lat":9.048,"lng":7.348},{"name":"Bassanjiwa","lat":9.027,"lng":7.295},{"name":"Nnamdi Azikiwe Airport","lat":9.0068,"lng":7.2632}]', 500, 20, 'rail', pg_temp.every(6, 20, 60), 6200, true),
  ('r15', 'p_kubwa', 'K02', null, '[{"name":"Kubwa","lat":9.1548,"lng":7.3227},{"name":"Dutse Junction","lat":9.1305,"lng":7.364},{"name":"Gwarinpa Junction","lat":9.0985,"lng":7.414},{"name":"Berger","lat":9.0679,"lng":7.456}]', 1000, 40, 'bus', pg_temp.every(6, 19, 30), 0, true);

-- Who runs vehicles on each corridor today: public information from news reports, not Tap A Ride partners (docs/route-operators.md).
update public.routes r set served_by = v.served_by::jsonb from (values
  ('r01', '[{"name": "Pi-CNG & EV high-capacity CNG buses", "type": "CNG bus", "note": "Reported CNG fare ₦500 against ₦1,000 on diesel buses. The buses were handed to the NURTW, RTEAN and NARTO unions; which union runs this route is not published.", "source": "https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/", "publisher": "News Agency of Nigeria", "as_of": "Oct 2026"}, {"name": "Diesel commercial buses", "type": "Diesel bus", "note": "About ₦1,000 Kubwa–Berger, as quoted by Pi-CNG & EV. Operators are not named in the report.", "source": "https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/", "publisher": "News Agency of Nigeria", "as_of": "Oct 2026"}]'),
  ('r02', '[{"name": "NURTW commercial vehicles from Area 1 park (CNG-converted)", "type": "CNG commercial vehicle", "note": "NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦1,500 → ₦900 to Gwagwalada.", "source": "https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/", "publisher": "Nairametrics", "as_of": "May 2025", "uncertain": true}]'),
  ('r03', '[{"name": "Abuja Light Rail (FCTA Abuja Rail Mass Transit, trains run by CCECC)", "type": "Light rail", "note": "Yellow Line from Abuja Metro Station to Nnamdi Azikiwe Airport via Kukwaba, Wupa, Idu and Bassanjiwa, about 20 minutes, four trips a day (08:00, 10:00, 15:30, 17:30).", "source": "https://dailytrust.com/?p=1937118", "publisher": "Daily Trust", "as_of": "Aug 2026"}]'),
  ('r04', '[{"name": "NURTW commercial vehicles from Area 1 park (CNG-converted)", "type": "CNG commercial vehicle", "note": "NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦1,500 → ₦900 to Bwari/Dutse.", "source": "https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/", "publisher": "Nairametrics", "as_of": "May 2025", "uncertain": true}, {"name": "Commercial buses from Bwari (informal sector)", "type": "Minibus", "note": "Passengers reported ₦1,800 to Berger and Wuse Market, up from ₦1,300 in late September 2026, with no noticeable relief after the 1 October CNG fare target.", "source": "https://www.legit.ng/business-economy/industry/1734125-operators-release-fares-states-fgs-promises-transport-cuts-passengers-react/", "publisher": "Legit.ng", "as_of": "Oct 2026"}]'),
  ('r05', '[{"name": "NURTW commercial vehicles from Area 1 park (CNG-converted)", "type": "CNG commercial vehicle", "note": "NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦700 → ₦420 to Nyanya.", "source": "https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/", "publisher": "Nairametrics", "as_of": "May 2025", "uncertain": true}]'),
  ('r06', '[{"name": "Commercial buses and taxis (informal sector)", "type": "Minibus / taxi", "note": "About ₦1,000 Lugbe–Berger Roundabout. Fares are often negotiated at the roadside; operators are not named.", "source": "https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/", "publisher": "Trust Radio / Daily Trust", "as_of": "Mar 2026"}, {"name": "NURTW commercial vehicles from Area 1 park (CNG-converted)", "type": "CNG commercial vehicle", "note": "NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦700 → ₦420 Area 1–Lugbe.", "source": "https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/", "publisher": "Nairametrics", "as_of": "May 2025", "uncertain": true}]'),
  ('r07', '[{"name": "NURTW commercial vehicles from Area 1 park (CNG-converted)", "type": "CNG commercial vehicle", "note": "NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦400 → ₦240 to Wuse.", "source": "https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/", "publisher": "Nairametrics", "as_of": "May 2025", "uncertain": true}]'),
  ('r08', '[{"name": "Commercial buses and taxis (informal sector)", "type": "Minibus / taxi", "note": "About ₦1,700 Nyanya–Jabi Garage. Fares are often negotiated at the roadside; operators are not named.", "source": "https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/", "publisher": "Trust Radio / Daily Trust", "as_of": "Mar 2026"}, {"name": "NURTW commercial vehicles from Area 1 park (CNG-converted)", "type": "CNG commercial vehicle", "note": "NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦700 → ₦420 each to Nyanya and to Jabi.", "source": "https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/", "publisher": "Nairametrics", "as_of": "May 2025", "uncertain": true}]'),
  ('r09', '[{"name": "Commercial buses and taxis (informal sector)", "type": "Minibus / taxi", "note": "₦500 → ₦700 Berger Roundabout–Karmo. Fares are often negotiated at the roadside; operators are not named.", "source": "https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/", "publisher": "Trust Radio / Daily Trust", "as_of": "Mar 2026"}]'),
  ('r10', '[{"name": "Pi-CNG & EV high-capacity CNG buses", "type": "CNG bus", "note": "Reported CNG fare ₦500 Apo–Nyanya/Mararaba against ₦1,000 on diesel buses. The buses were handed to the NURTW, RTEAN and NARTO unions; which union runs this route is not published.", "source": "https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/", "publisher": "News Agency of Nigeria", "as_of": "Oct 2026"}, {"name": "Toyota Coaster buses from Mararaba", "type": "Coaster bus", "note": "Fare into Abuja rose from ₦500 to about ₦700. Operators are not named.", "source": "https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/", "publisher": "Trust Radio / Daily Trust", "as_of": "Mar 2026"}]'),
  ('r11', '[{"name": "Pi-CNG & EV high-capacity CNG buses", "type": "CNG bus", "note": "Reported CNG fare ₦700 Berger–Gwagwalada against ₦1,200 on diesel buses. The buses were handed to the NURTW, RTEAN and NARTO unions; which union runs this route is not published.", "source": "https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/", "publisher": "News Agency of Nigeria", "as_of": "Oct 2026"}, {"name": "Diesel commercial buses", "type": "Diesel bus", "note": "About ₦1,200 Berger–Gwagwalada, as quoted by Pi-CNG & EV. Operators are not named in the report.", "source": "https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/", "publisher": "News Agency of Nigeria", "as_of": "Oct 2026"}]'),
  ('r12', '[{"name": "Commercial buses and taxis (informal sector)", "type": "Minibus / taxi", "note": "₦1,500 → about ₦1,800 Berger Roundabout–Zuba. Fares are often negotiated at the roadside; operators are not named.", "source": "https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/", "publisher": "Trust Radio / Daily Trust", "as_of": "Mar 2026"}, {"name": "NURTW commercial vehicles from Area 1 park (CNG-converted)", "type": "CNG commercial vehicle", "note": "NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦1,500 → ₦900 Area 1–Zuba.", "source": "https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/", "publisher": "Nairametrics", "as_of": "May 2025", "uncertain": true}]'),
  ('r13', '[{"name": "NURTW commercial vehicles from Area 1 park (CNG-converted)", "type": "CNG commercial vehicle", "note": "NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦500 → ₦300 Area 1–Apo.", "source": "https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/", "publisher": "Nairametrics", "as_of": "May 2025", "uncertain": true}]'),
  ('r14', '[{"name": "Abuja Light Rail (FCTA Abuja Rail Mass Transit, trains run by CCECC)", "type": "Light rail", "note": "Yellow Line from Abuja Metro Station to Nnamdi Azikiwe Airport via Kukwaba, Wupa, Idu and Bassanjiwa, about 20 minutes, four trips a day (08:00, 10:00, 15:30, 17:30).", "source": "https://dailytrust.com/?p=1937118", "publisher": "Daily Trust", "as_of": "Aug 2026"}]'),
  ('r15', '[{"name": "Pi-CNG & EV high-capacity CNG buses", "type": "CNG bus", "note": "Reported CNG fare ₦500 against ₦1,000 on diesel buses. The buses were handed to the NURTW, RTEAN and NARTO unions; which union runs this route is not published.", "source": "https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/", "publisher": "News Agency of Nigeria", "as_of": "Oct 2026"}, {"name": "Diesel commercial buses", "type": "Diesel bus", "note": "About ₦1,000 Kubwa–Berger, as quoted by Pi-CNG & EV. Operators are not named in the report.", "source": "https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/", "publisher": "News Agency of Nigeria", "as_of": "Oct 2026"}]')
) as v(id, served_by) where r.id = v.id;

-- 24 GreenFleet buses leased to Abuja Metro (22 active, 1 maintenance, 1 inactive).
insert into public.vehicles (id, operator_id, owner_id, plate, kind, model, capacity, status, verification, area, month_earnings, driver_name)
select 'v_abj' || lpad(i::text, 3, '0'), 'p_metro', 'p_greenfleet', 'ABJ ' || lpad(i::text, 3, '0'), 'bus', 'City bus · CNG', 48,
       case when i = 17 then 'maintenance' when i = 23 then 'inactive' when i % 3 = 0 then 'on_trip' else 'active' end,
       'verified', (array['Wuse', 'Central Area', 'Gwarinpa', 'Kubwa', 'Nyanya'])[1 + i % 5],
       case i when 21 then 540000 when 15 then 480000 when 10 then 520000 when 7 then 465000 when 19 then 498000 else 380000 + (i * 7919) % 160000 end,
       (array['Sule Adamu', 'John Akpan', 'Grace Eze', 'Bala Shehu', 'Kelechi Obi', 'Hauwa Aliyu', 'Femi Ade', 'Nnamdi Ike', 'Rose Okon', 'Aliyu Wada', 'Joy Nweke', 'Usman Bako'])[1 + i % 12]
from generate_series(1, 24) i;

-- 12 buses owned by Abuja Metro itself.
insert into public.vehicles (id, operator_id, plate, kind, model, capacity, status, verification, area, month_earnings, driver_name)
select 'v_abj' || i, 'p_metro', 'ABJ ' || i, 'bus', 'City bus · diesel', 42,
       case when i % 4 = 0 then 'on_trip' else 'active' end, 'verified',
       (array['Lugbe', 'Area 1', 'Garki', 'Jabi'])[1 + i % 4], 350000 + (i * 6151) % 120000,
       (array['Sule Adamu', 'John Akpan', 'Grace Eze', 'Bala Shehu', 'Kelechi Obi', 'Hauwa Aliyu', 'Femi Ade', 'Nnamdi Ike', 'Rose Okon', 'Aliyu Wada', 'Joy Nweke', 'Usman Bako'])[1 + (i + 5) % 12]
from generate_series(101, 112) i;

insert into public.vehicles (id, operator_id, plate, kind, model, capacity, status, verification, area, month_earnings, driver_name, battery_pct, range_km, base_fare, per_km_fare) values
  ('v_amr1', 'p_rail', 'AMR T01', 'train', 'Metro trainset', 560, 'on_trip', 'verified', 'Central Station', 9800000, null, null, null, null, null),
  ('v_amr2', 'p_rail', 'AMR T02', 'train', 'Metro trainset', 560, 'active', 'verified', 'Idu depot', 9150000, null, null, null, null, null),
  ('v_es01', 'p_airport', 'FCT ES 01', 'ev_shuttle', 'Electric shuttle · 22 seats', 22, 'on_trip', 'verified', 'Airport Road', 1450000, 'Sani Garba', 71, 180, null, null),
  ('v_es02', 'p_airport', 'FCT ES 02', 'ev_shuttle', 'Electric shuttle · 22 seats', 22, 'charging', 'verified', 'Airport Road depot', 1310000, 'Ruth Danladi', 34, 85, null, null),
  ('v_es03', 'p_airport', 'FCT ES 03', 'ev_shuttle', 'Electric shuttle · 22 seats', 22, 'active', 'verified', 'Central Area', 1280000, 'Ahmed Idris', 88, 225, null, null),
  ('v_nav201', 'p_naviride', 'NAV 201', 'ev_car', 'Hyundai Kona Electric', 4, 'active', 'verified', 'Maitama', 610000, 'Kunle Adewale', 82, 330, 1200, 180),
  ('v_nav202', 'p_naviride', 'NAV 202', 'ev_car', 'Hyundai Kona Electric', 4, 'active', 'verified', 'Wuse 2', 585000, 'Esther John', 64, 255, 1200, 180),
  ('v_nav203', 'p_naviride', 'NAV 203', 'ev_car', 'BYD Atto 3', 4, 'on_trip', 'verified', 'Central Area', 640000, 'Musa Lawal', 57, 240, 1300, 190),
  ('v_nav204', 'p_naviride', 'NAV 204', 'ev_car', 'BYD Atto 3', 4, 'active', 'verified', 'Jabi', 552000, 'Ifeoma Chukwu', 91, 380, 1300, 190),
  ('v_nav205', 'p_naviride', 'NAV 205', 'ev_car', 'Hyundai Kona Electric', 4, 'charging', 'verified', 'Maitama EV Hub', 498000, 'Paul Etim', 22, 80, 1200, 180),
  ('v_nav206', 'p_naviride', 'NAV 206', 'ev_car', 'Kia Niro EV', 4, 'active', 'pending', 'Garki', 0, 'Amina Sule', 76, 300, 1250, 185),
  ('v_kek301', 'p_keke', 'KEK 301', 'ev_keke', 'Electric keke', 3, 'inactive', 'pending', 'Garki', 0, null, 45, 70, null, null),
  ('v_kek302', 'p_keke', 'KEK 302', 'ev_keke', 'Electric keke', 3, 'inactive', 'pending', 'Garki', 0, null, 60, 90, null, null),
  ('v_kbx401', 'p_kubwa', 'KBX 401', 'minibus', 'Minibus · 18 seats', 18, 'active', 'pending', 'Kubwa', 0, null, null, null, null, null),
  ('v_kbx402', 'p_kubwa', 'KBX 402', 'minibus', 'Minibus · 18 seats', 18, 'active', 'pending', 'Kubwa', 0, null, null, null, null, null),
  ('v_nyc501', 'p_nyanya', 'NYC 501', 'minibus', 'Minibus · 18 seats', 18, 'active', 'pending', 'Nyanya', 0, null, null, null, null, null);

insert into public.charging_stations (id, name, area, ports, available, operator_id) values
  ('cs1', 'Maitama EV Hub', 'Maitama', 6, 4, 'p_naviride'),
  ('cs2', 'Central Area Park & Charge', 'Central Area', 8, 3, 'p_naviride'),
  ('cs3', 'Jabi Lake chargers', 'Jabi', 4, 1, 'p_naviride'),
  ('cs4', 'Airport Road depot', 'Airport Road', 10, 6, 'p_airport');

-- Tag Along rides a few hours ahead of whenever the seed runs.
insert into public.shared_rides (id, host_id, host_name, host_org, host_verified, origin, destination, depart_at, seats_total, seats_taken, cost_share, vehicle_label, note) values
  ('seed_ride1', 'u_host1', 'Amaka Eze', 'Federal Secretariat', true, 'Wuse 2', 'Gwarinpa', now() + interval '3 hours', 3, 1, 1200, 'Toyota Corolla · silver', 'Leaving from the Federal Secretariat car park.'),
  ('seed_ride2', 'u_host2', 'Yusuf Abdullahi', 'Central Business District office', true, 'Central Area', 'Lugbe', now() + interval '3 hours 20 minutes', 3, 0, 1500, 'Honda Accord · black', ''),
  ('seed_ride3', 'u_host3', 'Halima Sani', 'Maitama district office', true, 'Maitama', 'Jabi', now() + interval '3 hours 40 minutes', 2, 1, 850, 'Kia Rio · white', ''),
  ('seed_ride4', 'u_host4', 'Zainab Yusuf', 'Jabi tech hub', true, 'Jabi', 'Kubwa', now() + interval '4 hours', 4, 2, 1100, 'Toyota Sienna · grey', '');

-- FCTA register totals in the mockup: 1,204 verified vehicles and 32 active routes.
-- The off-platform remainder is stored; the app adds live platform counts to it.
insert into public.metric_baselines (id, data)
select 1, jsonb_build_object(
  'operator_provider_id', 'p_metro',
  'fleet_provider_id', 'p_greenfleet',
  'operator_trips', 482, 'operator_trips_delta', 12,
  'operator_revenue', 13429000, 'operator_revenue_delta', 18,
  'operator_active_drivers', 42,
  'fleet_revenue', 12480000, 'fleet_revenue_delta', 22,
  'fleet_earnings', jsonb_build_array(
    jsonb_build_object('plate', 'ABJ 021', 'amount', 540000, 'date', '2026-09-27'),
    jsonb_build_object('plate', 'ABJ 015', 'amount', 480000, 'date', '2026-09-27'),
    jsonb_build_object('plate', 'ABJ 010', 'amount', 520000, 'date', '2026-09-26'),
    jsonb_build_object('plate', 'ABJ 007', 'amount', 465000, 'date', '2026-09-26'),
    jsonb_build_object('plate', 'ABJ 019', 'amount', 498000, 'date', '2026-09-25')),
  'ridership_by_day', jsonb_build_array(29850, 32400, 34120, 35760, 38940, 41230, 36272),
  'ridership_delta', 14,
  'verified_off_platform', 1204 - (select count(*) from public.vehicles where verification = 'verified'),
  'verified_delta', 8,
  'routes_off_platform', 32 - (select count(*) from public.routes where active and provider_id in ('p_metro', 'p_rail', 'p_airport')),
  'active_routes_delta', 6);

insert into public.audit_log (at, actor_name, actor_role, action, target) values
  (now() - interval '9 days', 'Daniel Adeyemi', 'admin', 'Approved provider', 'NaviRide Electric'),
  (now() - interval '5 days', 'Ibrahim Musa', 'operator', 'Updated fare', 'R01 Wuse – Maitama → ₦500'),
  (now() - interval '3 days', 'Daniel Adeyemi', 'admin', 'Suspended provider', 'City Keke Cooperative · permits expired'),
  (now() - interval '2 days', 'Fatima Lawal', 'government', 'Verified vehicle', 'Bus #ABJ 024');
