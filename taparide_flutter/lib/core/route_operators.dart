import 'models.dart';

/// Who runs vehicles on each corridor today, from public reports (see docs/route-operators.md).
/// Public information only: none of these are Tap A Ride partners and no agreements exist.
/// Mirrored in supabase/migrations/20261118020000_route_operators.sql and supabase/seed.sql (routes.served_by).
const corridorOperators = <String, List<CorridorOperator>>{
  'r01': [
    CorridorOperator(name: 'Pi-CNG & EV high-capacity CNG buses', type: 'CNG bus', note: 'Reported CNG fare ₦500 against ₦1,000 on diesel buses. The buses were handed to the NURTW, RTEAN and NARTO unions; which union runs this route is not published.', source: 'https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/', publisher: 'News Agency of Nigeria', asOf: 'Oct 2026'),
    CorridorOperator(name: 'Diesel commercial buses', type: 'Diesel bus', note: 'About ₦1,000 Kubwa–Berger, as quoted by Pi-CNG & EV. Operators are not named in the report.', source: 'https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/', publisher: 'News Agency of Nigeria', asOf: 'Oct 2026'),
  ],
  'r02': [
    CorridorOperator(name: 'NURTW commercial vehicles from Area 1 park (CNG-converted)', type: 'CNG commercial vehicle', note: 'NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦1,500 → ₦900 to Gwagwalada.', source: 'https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/', publisher: 'Nairametrics', asOf: 'May 2025', uncertain: true),
  ],
  'r03': [
    CorridorOperator(name: 'Abuja Light Rail (FCTA Abuja Rail Mass Transit, trains run by CCECC)', type: 'Light rail', note: 'Yellow Line from Abuja Metro Station to Nnamdi Azikiwe Airport via Kukwaba, Wupa, Idu and Bassanjiwa, about 20 minutes, four trips a day (08:00, 10:00, 15:30, 17:30).', source: 'https://dailytrust.com/?p=1937118', publisher: 'Daily Trust', asOf: 'Aug 2026'),
  ],
  'r04': [
    CorridorOperator(name: 'NURTW commercial vehicles from Area 1 park (CNG-converted)', type: 'CNG commercial vehicle', note: 'NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦1,500 → ₦900 to Bwari/Dutse.', source: 'https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/', publisher: 'Nairametrics', asOf: 'May 2025', uncertain: true),
    CorridorOperator(name: 'Commercial buses from Bwari (informal sector)', type: 'Minibus', note: 'Passengers reported ₦1,800 to Berger and Wuse Market, up from ₦1,300 in late September 2026, with no noticeable relief after the 1 October CNG fare target.', source: 'https://www.legit.ng/business-economy/industry/1734125-operators-release-fares-states-fgs-promises-transport-cuts-passengers-react/', publisher: 'Legit.ng', asOf: 'Oct 2026'),
  ],
  'r05': [
    CorridorOperator(name: 'NURTW commercial vehicles from Area 1 park (CNG-converted)', type: 'CNG commercial vehicle', note: 'NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦700 → ₦420 to Nyanya.', source: 'https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/', publisher: 'Nairametrics', asOf: 'May 2025', uncertain: true),
  ],
  'r06': [
    CorridorOperator(name: 'Commercial buses and taxis (informal sector)', type: 'Minibus / taxi', note: 'About ₦1,000 Lugbe–Berger Roundabout. Fares are often negotiated at the roadside; operators are not named.', source: 'https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/', publisher: 'Trust Radio / Daily Trust', asOf: 'Mar 2026'),
    CorridorOperator(name: 'NURTW commercial vehicles from Area 1 park (CNG-converted)', type: 'CNG commercial vehicle', note: 'NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦700 → ₦420 Area 1–Lugbe.', source: 'https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/', publisher: 'Nairametrics', asOf: 'May 2025', uncertain: true),
  ],
  'r07': [
    CorridorOperator(name: 'NURTW commercial vehicles from Area 1 park (CNG-converted)', type: 'CNG commercial vehicle', note: 'NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦400 → ₦240 to Wuse.', source: 'https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/', publisher: 'Nairametrics', asOf: 'May 2025', uncertain: true),
  ],
  'r08': [
    CorridorOperator(name: 'Commercial buses and taxis (informal sector)', type: 'Minibus / taxi', note: 'About ₦1,700 Nyanya–Jabi Garage. Fares are often negotiated at the roadside; operators are not named.', source: 'https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/', publisher: 'Trust Radio / Daily Trust', asOf: 'Mar 2026'),
    CorridorOperator(name: 'NURTW commercial vehicles from Area 1 park (CNG-converted)', type: 'CNG commercial vehicle', note: 'NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦700 → ₦420 each to Nyanya and to Jabi.', source: 'https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/', publisher: 'Nairametrics', asOf: 'May 2025', uncertain: true),
  ],
  'r09': [
    CorridorOperator(name: 'Commercial buses and taxis (informal sector)', type: 'Minibus / taxi', note: '₦500 → ₦700 Berger Roundabout–Karmo. Fares are often negotiated at the roadside; operators are not named.', source: 'https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/', publisher: 'Trust Radio / Daily Trust', asOf: 'Mar 2026'),
  ],
  'r10': [
    CorridorOperator(name: 'Pi-CNG & EV high-capacity CNG buses', type: 'CNG bus', note: 'Reported CNG fare ₦500 Apo–Nyanya/Mararaba against ₦1,000 on diesel buses. The buses were handed to the NURTW, RTEAN and NARTO unions; which union runs this route is not published.', source: 'https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/', publisher: 'News Agency of Nigeria', asOf: 'Oct 2026'),
    CorridorOperator(name: 'Toyota Coaster buses from Mararaba', type: 'Coaster bus', note: 'Fare into Abuja rose from ₦500 to about ₦700. Operators are not named.', source: 'https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/', publisher: 'Trust Radio / Daily Trust', asOf: 'Mar 2026'),
  ],
  'r11': [
    CorridorOperator(name: 'Pi-CNG & EV high-capacity CNG buses', type: 'CNG bus', note: 'Reported CNG fare ₦700 Berger–Gwagwalada against ₦1,200 on diesel buses. The buses were handed to the NURTW, RTEAN and NARTO unions; which union runs this route is not published.', source: 'https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/', publisher: 'News Agency of Nigeria', asOf: 'Oct 2026'),
    CorridorOperator(name: 'Diesel commercial buses', type: 'Diesel bus', note: 'About ₦1,200 Berger–Gwagwalada, as quoted by Pi-CNG & EV. Operators are not named in the report.', source: 'https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/', publisher: 'News Agency of Nigeria', asOf: 'Oct 2026'),
  ],
  'r12': [
    CorridorOperator(name: 'Commercial buses and taxis (informal sector)', type: 'Minibus / taxi', note: '₦1,500 → about ₦1,800 Berger Roundabout–Zuba. Fares are often negotiated at the roadside; operators are not named.', source: 'https://trustradio.com.ng/en/fuel-hike-how-abuja-residents-spend-minutes-bargaining-for-affordable-rides/', publisher: 'Trust Radio / Daily Trust', asOf: 'Mar 2026'),
    CorridorOperator(name: 'NURTW commercial vehicles from Area 1 park (CNG-converted)', type: 'CNG commercial vehicle', note: 'NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦1,500 → ₦900 Area 1–Zuba.', source: 'https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/', publisher: 'Nairametrics', asOf: 'May 2025', uncertain: true),
  ],
  'r13': [
    CorridorOperator(name: 'NURTW commercial vehicles from Area 1 park (CNG-converted)', type: 'CNG commercial vehicle', note: 'NURTW (Garki branch) and the Presidential CNG Initiative enforced a 40% fare cut on CNG vehicles from Area 1: ₦500 → ₦300 Area 1–Apo.', source: 'https://nairametrics.com/2025/05/02/p-cngi-enforces-40-fare-reduction-on-cng-commercial-vehicles-in-abuja/', publisher: 'Nairametrics', asOf: 'May 2025', uncertain: true),
  ],
  'r14': [
    CorridorOperator(name: 'Abuja Light Rail (FCTA Abuja Rail Mass Transit, trains run by CCECC)', type: 'Light rail', note: 'Yellow Line from Abuja Metro Station to Nnamdi Azikiwe Airport via Kukwaba, Wupa, Idu and Bassanjiwa, about 20 minutes, four trips a day (08:00, 10:00, 15:30, 17:30).', source: 'https://dailytrust.com/?p=1937118', publisher: 'Daily Trust', asOf: 'Aug 2026'),
  ],
  'r15': [
    CorridorOperator(name: 'Pi-CNG & EV high-capacity CNG buses', type: 'CNG bus', note: 'Reported CNG fare ₦500 against ₦1,000 on diesel buses. The buses were handed to the NURTW, RTEAN and NARTO unions; which union runs this route is not published.', source: 'https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/', publisher: 'News Agency of Nigeria', asOf: 'Oct 2026'),
    CorridorOperator(name: 'Diesel commercial buses', type: 'Diesel bus', note: 'About ₦1,000 Kubwa–Berger, as quoted by Pi-CNG & EV. Operators are not named in the report.', source: 'https://nannews.ng/october-1-cng-ev-interventions-reduce-transport-fares-across-states-pi-cng-ev/', publisher: 'News Agency of Nigeria', asOf: 'Oct 2026'),
  ],
};

/// Attaches [corridorOperators] to routes that don't carry their own `servedBy` list.
List<TransitRoute> withCorridorOperators(List<TransitRoute> routes) => [
      for (final r in routes) r.servedBy.isNotEmpty || !corridorOperators.containsKey(r.id) ? r : r.copyWith(servedBy: corridorOperators[r.id]),
    ];
