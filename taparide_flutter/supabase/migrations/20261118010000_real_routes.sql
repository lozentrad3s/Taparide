-- Real Abuja corridors and reported fares (replaces the sample routes, same ids so bookings keep working).
-- Fares: FG / Pi-CNG statement on CNG bus fares, Trust Radio / Daily Trust and Gazette (2026), FCTA rail notice.
-- Operators confirm their fares before launch; edit them in the dashboard under Routes & fares.
create or replace function pg_temp.every(from_hour int, to_hour int, step_min int) returns text[] language sql as $$
  select array_agg(to_char(make_time(m / 60, m % 60, 0), 'HH24:MI') order by m)
  from generate_series(from_hour * 60, to_hour * 60, step_min) m
$$;

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
  ('r15', 'p_kubwa', 'K02', null, '[{"name":"Kubwa","lat":9.1548,"lng":7.3227},{"name":"Dutse Junction","lat":9.1305,"lng":7.364},{"name":"Gwarinpa Junction","lat":9.0985,"lng":7.414},{"name":"Berger","lat":9.0679,"lng":7.456}]', 1000, 40, 'bus', pg_temp.every(6, 19, 30), 0, true)
on conflict (id) do update set
  provider_id = excluded.provider_id, code = excluded.code, name = excluded.name, stops = excluded.stops,
  fare = excluded.fare, duration_min = excluded.duration_min, mode = excluded.mode, departures = excluded.departures,
  active = excluded.active;
