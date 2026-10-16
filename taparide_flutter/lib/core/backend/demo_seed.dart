import '../models.dart';

/// Illustrative demo data for Abuja. Organisations, people and figures are fictional
/// (labelled "Demo data" in the UI); places and coordinates are real.
abstract final class DemoSeed {
  static const password = 'Ride2026!';

  static const pMetro = 'p_metro';
  static const pGreenFleet = 'p_greenfleet';
  static const pNaviRide = 'p_naviride';
  static const pRail = 'p_rail';
  static const pAirport = 'p_airport';
  static const pKubwa = 'p_kubwa';
  static const pNyanya = 'p_nyanya';
  static const pKeke = 'p_keke';

  static const uAisha = 'u_aisha';

  /// Sign-in shortcuts shown on the login screen in demo mode.
  static const demoAccounts = <(String, String, UserRole)>[
    ('Aisha Bello', 'aisha@taparide.demo', UserRole.passenger),
    ('Ibrahim Musa · Abuja Metro Bus Co.', 'ops@abujametro.demo', UserRole.operator),
    ('Chiamaka Obi · GreenFleet Logistics', 'fleet@greenfleet.demo', UserRole.fleetOwner),
    ('Tunde Bello · NaviRide Electric', 'ev@naviride.demo', UserRole.operator),
    ('Fatima Lawal · FCTA Transport', 'transport@fcta.demo', UserRole.government),
    ('Daniel Adeyemi · Platform admin', 'admin@taparide.demo', UserRole.admin),
  ];

  static List<AppUser> users() => [
        AppUser(id: uAisha, fullName: 'Aisha Bello', email: 'aisha@taparide.demo', phone: '+234 803 000 1122', role: UserRole.passenger, organisation: 'Federal Secretariat', createdAt: DateTime(2026, 8, 14)),
        AppUser(id: 'u_ops', fullName: 'Ibrahim Musa', email: 'ops@abujametro.demo', phone: '+234 809 000 3344', role: UserRole.operator, providerId: pMetro, createdAt: DateTime(2026, 7, 2)),
        AppUser(id: 'u_fleet', fullName: 'Chiamaka Obi', email: 'fleet@greenfleet.demo', phone: '+234 812 000 5566', role: UserRole.fleetOwner, providerId: pGreenFleet, createdAt: DateTime(2026, 7, 9)),
        AppUser(id: 'u_ev', fullName: 'Tunde Bello', email: 'ev@naviride.demo', phone: '+234 815 000 7788', role: UserRole.operator, providerId: pNaviRide, createdAt: DateTime(2026, 8, 3)),
        AppUser(id: 'u_fcta', fullName: 'Fatima Lawal', email: 'transport@fcta.demo', phone: '+234 806 000 9900', role: UserRole.government, organisation: 'FCTA Transport Secretariat', createdAt: DateTime(2026, 6, 20)),
        AppUser(id: 'u_admin', fullName: 'Daniel Adeyemi', email: 'admin@taparide.demo', phone: '+234 701 000 1212', role: UserRole.admin, createdAt: DateTime(2026, 6, 1)),
        AppUser(id: 'u_emeka', fullName: 'Emeka Nwosu', email: 'emeka@taparide.demo', role: UserRole.passenger, organisation: 'Banex Plaza offices', createdAt: DateTime(2026, 9, 2)),
        AppUser(id: 'u_zainab', fullName: 'Zainab Yusuf', email: 'zainab@taparide.demo', role: UserRole.passenger, organisation: 'Jabi tech hub', createdAt: DateTime(2026, 9, 11)),
      ];

  static List<TransportProvider> providers() => [
        TransportProvider(id: pMetro, name: 'Abuja Metro Bus Co.', kind: ProviderKind.busOperator, status: Verification.verified, area: 'Wuse · Central Area', contactName: 'Ibrahim Musa', contactEmail: 'ops@abujametro.demo', joinedAt: DateTime(2026, 7, 2), description: 'City bus operator running 12 fixed-fare routes across the FCT.'),
        TransportProvider(id: pGreenFleet, name: 'GreenFleet Logistics', kind: ProviderKind.fleetOwner, status: Verification.verified, area: 'Jabi', contactName: 'Chiamaka Obi', contactEmail: 'fleet@greenfleet.demo', joinedAt: DateTime(2026, 7, 9), description: 'Owns 24 buses leased to Abuja Metro Bus Co.'),
        TransportProvider(id: pNaviRide, name: 'NaviRide Electric', kind: ProviderKind.electric, status: Verification.verified, area: 'Maitama', contactName: 'Tunde Bello', contactEmail: 'ev@naviride.demo', joinedAt: DateTime(2026, 8, 3), description: 'On-demand electric cars with verified drivers.'),
        TransportProvider(id: pRail, name: 'Capital Metro Rail Services', kind: ProviderKind.rail, status: Verification.verified, area: 'Central Area', contactName: 'Kemi Adebayo', contactEmail: 'rail@capitalmetro.demo', joinedAt: DateTime(2026, 7, 20), description: 'Operates metro rail services between Central Station and Idu.'),
        TransportProvider(id: pAirport, name: 'FCT Airport E-Shuttle', kind: ProviderKind.shuttle, status: Verification.verified, area: 'Airport Road', contactName: 'Sani Garba', contactEmail: 'shuttle@airporteshuttle.demo', joinedAt: DateTime(2026, 8, 18), description: 'Electric airport shuttle to the city centre.'),
        TransportProvider(id: pKubwa, name: 'Kubwa Express Shuttles', kind: ProviderKind.shuttle, status: Verification.pending, area: 'Kubwa', contactName: 'Peter Ojo', contactEmail: 'hello@kubwaexpress.demo', joinedAt: DateTime(2026, 10, 9), description: 'Minibus commuter service applying to join the platform.'),
        TransportProvider(id: pNyanya, name: 'Nyanya Commuter Union', kind: ProviderKind.busOperator, status: Verification.pending, area: 'Nyanya · AYA', contactName: 'Musa Danjuma', contactEmail: 'office@nyanyacommuters.demo', joinedAt: DateTime(2026, 10, 12), description: 'Union of minibus owners on the Nyanya corridor.'),
        TransportProvider(id: pKeke, name: 'City Keke Cooperative', kind: ProviderKind.tricycle, status: Verification.suspended, area: 'Garki', contactName: 'Blessing Udo', contactEmail: 'coop@citykeke.demo', joinedAt: DateTime(2026, 8, 25), description: 'Electric tricycle pilot. Suspended pending permit renewal.'),
      ];

  static List<String> _every(int fromHour, int toHour, int stepMin) => [
        for (var m = fromHour * 60; m <= toHour * 60; m += stepMin) '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
      ];

  static const _wuse = RouteStop('Wuse', 9.0643, 7.4686);
  static const _banex = RouteStop('Banex Junction', 9.0790, 7.4801);
  static const _maitama = RouteStop('Maitama', 9.0882, 7.4934);
  static const _central = RouteStop('Central Area', 9.0556, 7.4914);
  static const _utako = RouteStop('Utako', 9.0703, 7.4400);
  static const _jabi = RouteStop('Jabi', 9.0705, 7.4250);
  static const _lifeCamp = RouteStop('Life Camp', 9.0814, 7.4055);
  static const _gwarinpa = RouteStop('Gwarinpa', 9.1099, 7.4083);
  static const _kubwa = RouteStop('Kubwa', 9.1548, 7.3227);
  static const _dutse = RouteStop('Dutse Junction', 9.1305, 7.3640);
  static const _berger = RouteStop('Berger', 9.0679, 7.4560);
  static const _nyanya = RouteStop('Nyanya', 9.0213, 7.5616);
  static const _aya = RouteStop('AYA', 9.0430, 7.5170);
  static const _area1 = RouteStop('Area 1', 9.0272, 7.4842);
  static const _lugbe = RouteStop('Lugbe', 8.9800, 7.3750);
  static const _airportJn = RouteStop('Airport Junction', 8.9960, 7.4080);
  static const _garki = RouteStop('Garki', 9.0310, 7.4890);
  static const _asokoro = RouteStop('Asokoro', 9.0420, 7.5250);
  static const _karu = RouteStop('Karu', 9.0170, 7.5480);
  static const _lokogoma = RouteStop('Lokogoma', 8.9920, 7.4590);
  static const _apo = RouteStop('Apo', 9.0040, 7.4930);

  static List<TransitRoute> routes() => [
        TransitRoute(id: 'r01', providerId: pMetro, code: 'R01', stops: const [_wuse, _banex, _maitama], fare: 500, durationMin: 20, mode: TransitMode.bus, departures: _every(6, 21, 30), monthlyTrips: 42800),
        TransitRoute(id: 'r02', providerId: pMetro, code: 'R02', stops: const [_central, _utako, _jabi, _lifeCamp, _gwarinpa], fare: 700, durationMin: 25, mode: TransitMode.bus, departures: _every(6, 21, 15), monthlyTrips: 38450),
        TransitRoute(id: 'r03', providerId: pRail, code: 'MR1', name: 'Abuja Metro Rail', stops: const [RouteStop('Central Station', 9.0441, 7.4868), RouteStop('Kukwaba', 9.0395, 7.4380), RouteStop('Idu', 9.0480, 7.3480)], fare: 600, durationMin: 15, mode: TransitMode.rail, departures: _every(6, 20, 20), monthlyTrips: 27400),
        TransitRoute(id: 'r04', providerId: pMetro, code: 'R04', stops: const [_kubwa, _dutse, _gwarinpa, _berger, _central], fare: 800, durationMin: 35, mode: TransitMode.bus, departures: _every(5, 20, 20), monthlyTrips: 31200),
        TransitRoute(id: 'r05', providerId: pMetro, code: 'R05', stops: const [_nyanya, _aya, _area1, _central], fare: 600, durationMin: 30, mode: TransitMode.bus, departures: _every(5, 21, 20), monthlyTrips: 29600),
        TransitRoute(id: 'r06', providerId: pMetro, code: 'R06', stops: const [_lugbe, _airportJn, _area1], fare: 550, durationMin: 30, mode: TransitMode.bus, departures: _every(6, 20, 30), monthlyTrips: 21300),
        TransitRoute(id: 'r07', providerId: pMetro, code: 'R07', stops: const [_wuse, _berger, _central], fare: 450, durationMin: 15, mode: TransitMode.bus, departures: _every(6, 21, 30), monthlyTrips: 18900),
        TransitRoute(id: 'r08', providerId: pMetro, code: 'R08', stops: const [_jabi, _utako, _wuse], fare: 400, durationMin: 15, mode: TransitMode.bus, departures: _every(6, 20, 30), monthlyTrips: 15200),
        TransitRoute(id: 'r09', providerId: pMetro, code: 'R09', stops: const [_garki, _central, _maitama], fare: 450, durationMin: 18, mode: TransitMode.bus, departures: _every(6, 20, 30), monthlyTrips: 12800),
        TransitRoute(id: 'r10', providerId: pMetro, code: 'R10', stops: const [_asokoro, _garki, _central], fare: 400, durationMin: 15, mode: TransitMode.bus, departures: _every(6, 20, 45), monthlyTrips: 9400),
        TransitRoute(id: 'r11', providerId: pMetro, code: 'R11', stops: const [_karu, _nyanya, _aya, _area1], fare: 650, durationMin: 32, mode: TransitMode.bus, departures: _every(5, 20, 30), monthlyTrips: 17600),
        TransitRoute(id: 'r12', providerId: pMetro, code: 'R12', stops: const [_gwarinpa, _lifeCamp, _berger, _wuse], fare: 650, durationMin: 28, mode: TransitMode.bus, departures: _every(6, 20, 30), monthlyTrips: 14100),
        TransitRoute(id: 'r13', providerId: pMetro, code: 'R13', stops: const [_lokogoma, _apo, _garki, _central], fare: 550, durationMin: 25, mode: TransitMode.bus, departures: _every(6, 20, 40), monthlyTrips: 8800),
        TransitRoute(id: 'r14', providerId: pAirport, code: 'E01', name: 'Airport E-Shuttle', stops: const [RouteStop('Nnamdi Azikiwe Airport', 9.0068, 7.2632), _lugbe, _central], fare: 3000, durationMin: 40, mode: TransitMode.shuttle, departures: _every(6, 22, 60), monthlyTrips: 6200),
        TransitRoute(id: 'r15', providerId: pKubwa, code: 'K01', stops: const [_kubwa, _dutse, _berger, _wuse], fare: 750, durationMin: 35, mode: TransitMode.bus, departures: _every(6, 19, 30), monthlyTrips: 0),
      ];

  static List<Vehicle> vehicles() {
    const earningsByPlate = {'ABJ 021': 540000, 'ABJ 015': 480000, 'ABJ 010': 520000, 'ABJ 007': 465000, 'ABJ 019': 498000};
    const drivers = ['Sule Adamu', 'John Akpan', 'Grace Eze', 'Bala Shehu', 'Kelechi Obi', 'Hauwa Aliyu', 'Femi Ade', 'Nnamdi Ike', 'Rose Okon', 'Aliyu Wada', 'Joy Nweke', 'Usman Bako'];
    final list = <Vehicle>[];
    for (var i = 1; i <= 24; i++) {
      final plate = 'ABJ ${i.toString().padLeft(3, '0')}';
      list.add(Vehicle(
        id: 'v_abj${i.toString().padLeft(3, '0')}',
        operatorId: pMetro,
        ownerId: pGreenFleet,
        plate: plate,
        kind: VehicleKind.bus,
        model: 'City bus · CNG',
        capacity: 48,
        status: i == 17 ? VehicleStatus.maintenance : i == 23 ? VehicleStatus.inactive : (i % 3 == 0 ? VehicleStatus.onTrip : VehicleStatus.active),
        verification: Verification.verified,
        area: const ['Wuse', 'Central Area', 'Gwarinpa', 'Kubwa', 'Nyanya'][i % 5],
        monthEarnings: earningsByPlate[plate] ?? 380000 + (i * 7919) % 160000,
        driverName: drivers[i % drivers.length],
      ));
    }
    for (var i = 101; i <= 112; i++) {
      list.add(Vehicle(
        id: 'v_abj$i',
        operatorId: pMetro,
        plate: 'ABJ $i',
        kind: VehicleKind.bus,
        model: 'City bus · diesel',
        capacity: 42,
        status: i % 4 == 0 ? VehicleStatus.onTrip : VehicleStatus.active,
        verification: Verification.verified,
        area: const ['Lugbe', 'Area 1', 'Garki', 'Jabi'][i % 4],
        monthEarnings: 350000 + (i * 6151) % 120000,
        driverName: drivers[(i + 5) % drivers.length],
      ));
    }
    list.addAll(const [
      Vehicle(id: 'v_amr1', operatorId: pRail, plate: 'AMR T01', kind: VehicleKind.train, model: 'Metro trainset', capacity: 560, status: VehicleStatus.onTrip, verification: Verification.verified, area: 'Central Station', monthEarnings: 9800000),
      Vehicle(id: 'v_amr2', operatorId: pRail, plate: 'AMR T02', kind: VehicleKind.train, model: 'Metro trainset', capacity: 560, status: VehicleStatus.active, verification: Verification.verified, area: 'Idu depot', monthEarnings: 9150000),
      Vehicle(id: 'v_es01', operatorId: pAirport, plate: 'FCT ES 01', kind: VehicleKind.evShuttle, model: 'Electric shuttle · 22 seats', capacity: 22, status: VehicleStatus.onTrip, verification: Verification.verified, area: 'Airport Road', monthEarnings: 1450000, batteryPct: 71, rangeKm: 180, driverName: 'Sani Garba'),
      Vehicle(id: 'v_es02', operatorId: pAirport, plate: 'FCT ES 02', kind: VehicleKind.evShuttle, model: 'Electric shuttle · 22 seats', capacity: 22, status: VehicleStatus.charging, verification: Verification.verified, area: 'Airport Road depot', monthEarnings: 1310000, batteryPct: 34, rangeKm: 85, driverName: 'Ruth Danladi'),
      Vehicle(id: 'v_es03', operatorId: pAirport, plate: 'FCT ES 03', kind: VehicleKind.evShuttle, model: 'Electric shuttle · 22 seats', capacity: 22, status: VehicleStatus.active, verification: Verification.verified, area: 'Central Area', monthEarnings: 1280000, batteryPct: 88, rangeKm: 225, driverName: 'Ahmed Idris'),
      Vehicle(id: 'v_nav201', operatorId: pNaviRide, plate: 'NAV 201', kind: VehicleKind.evCar, model: 'Hyundai Kona Electric', capacity: 4, status: VehicleStatus.active, verification: Verification.verified, area: 'Maitama', monthEarnings: 610000, batteryPct: 82, rangeKm: 330, baseFare: 1200, perKmFare: 180, driverName: 'Kunle Adewale'),
      Vehicle(id: 'v_nav202', operatorId: pNaviRide, plate: 'NAV 202', kind: VehicleKind.evCar, model: 'Hyundai Kona Electric', capacity: 4, status: VehicleStatus.active, verification: Verification.verified, area: 'Wuse 2', monthEarnings: 585000, batteryPct: 64, rangeKm: 255, baseFare: 1200, perKmFare: 180, driverName: 'Esther John'),
      Vehicle(id: 'v_nav203', operatorId: pNaviRide, plate: 'NAV 203', kind: VehicleKind.evCar, model: 'BYD Atto 3', capacity: 4, status: VehicleStatus.onTrip, verification: Verification.verified, area: 'Central Area', monthEarnings: 640000, batteryPct: 57, rangeKm: 240, baseFare: 1300, perKmFare: 190, driverName: 'Musa Lawal'),
      Vehicle(id: 'v_nav204', operatorId: pNaviRide, plate: 'NAV 204', kind: VehicleKind.evCar, model: 'BYD Atto 3', capacity: 4, status: VehicleStatus.active, verification: Verification.verified, area: 'Jabi', monthEarnings: 552000, batteryPct: 91, rangeKm: 380, baseFare: 1300, perKmFare: 190, driverName: 'Ifeoma Chukwu'),
      Vehicle(id: 'v_nav205', operatorId: pNaviRide, plate: 'NAV 205', kind: VehicleKind.evCar, model: 'Hyundai Kona Electric', capacity: 4, status: VehicleStatus.charging, verification: Verification.verified, area: 'Maitama EV Hub', monthEarnings: 498000, batteryPct: 22, rangeKm: 80, baseFare: 1200, perKmFare: 180, driverName: 'Paul Etim'),
      Vehicle(id: 'v_nav206', operatorId: pNaviRide, plate: 'NAV 206', kind: VehicleKind.evCar, model: 'Kia Niro EV', capacity: 4, status: VehicleStatus.active, verification: Verification.pending, area: 'Garki', monthEarnings: 0, batteryPct: 76, rangeKm: 300, baseFare: 1250, perKmFare: 185, driverName: 'Amina Sule'),
      Vehicle(id: 'v_kek301', operatorId: pKeke, plate: 'KEK 301', kind: VehicleKind.evKeke, model: 'Electric keke', capacity: 3, status: VehicleStatus.inactive, verification: Verification.pending, area: 'Garki', monthEarnings: 0, batteryPct: 45, rangeKm: 70),
      Vehicle(id: 'v_kek302', operatorId: pKeke, plate: 'KEK 302', kind: VehicleKind.evKeke, model: 'Electric keke', capacity: 3, status: VehicleStatus.inactive, verification: Verification.pending, area: 'Garki', monthEarnings: 0, batteryPct: 60, rangeKm: 90),
      Vehicle(id: 'v_kbx401', operatorId: pKubwa, plate: 'KBX 401', kind: VehicleKind.minibus, model: 'Minibus · 18 seats', capacity: 18, status: VehicleStatus.active, verification: Verification.pending, area: 'Kubwa', monthEarnings: 0),
      Vehicle(id: 'v_kbx402', operatorId: pKubwa, plate: 'KBX 402', kind: VehicleKind.minibus, model: 'Minibus · 18 seats', capacity: 18, status: VehicleStatus.active, verification: Verification.pending, area: 'Kubwa', monthEarnings: 0),
      Vehicle(id: 'v_nyc501', operatorId: pNyanya, plate: 'NYC 501', kind: VehicleKind.minibus, model: 'Minibus · 18 seats', capacity: 18, status: VehicleStatus.active, verification: Verification.pending, area: 'Nyanya', monthEarnings: 0),
    ]);
    return list;
  }

  static const chargingStations = <ChargingStation>[
    ChargingStation(id: 'cs1', name: 'Maitama EV Hub', area: 'Maitama', ports: 6, available: 4, operatorId: pNaviRide),
    ChargingStation(id: 'cs2', name: 'Central Area Park & Charge', area: 'Central Area', ports: 8, available: 3, operatorId: pNaviRide),
    ChargingStation(id: 'cs3', name: 'Jabi Lake chargers', area: 'Jabi', ports: 4, available: 1, operatorId: pNaviRide),
    ChargingStation(id: 'cs4', name: 'Airport Road depot', area: 'Airport Road', ports: 10, available: 6, operatorId: pAirport),
  ];

  /// Tag Along rides relative to [now] (always later today or tomorrow).
  static List<SharedRide> sharedRides(DateTime now) {
    DateTime at(int h, int m) {
      final t = DateTime(now.year, now.month, now.day, h, m);
      return t.isAfter(now.add(const Duration(minutes: 20))) ? t : t.add(const Duration(days: 1));
    }

    return [
      SharedRide(id: 'seed_ride1', hostId: 'u_host1', hostName: 'Amaka Eze', hostOrg: 'Federal Secretariat', hostVerified: true, origin: 'Wuse 2', destination: 'Gwarinpa', departAt: at(17, 30), seatsTotal: 3, seatsTaken: 1, costShare: 1200, vehicleLabel: 'Toyota Corolla · silver', note: 'Leaving from the Federal Secretariat car park.'),
      SharedRide(id: 'seed_ride2', hostId: 'u_host2', hostName: 'Yusuf Abdullahi', hostOrg: 'Central Business District office', hostVerified: true, origin: 'Central Area', destination: 'Lugbe', departAt: at(17, 50), seatsTotal: 3, seatsTaken: 0, costShare: 1500, vehicleLabel: 'Honda Accord · black'),
      SharedRide(id: 'seed_ride3', hostId: 'u_host3', hostName: 'Halima Sani', hostOrg: 'Maitama district office', hostVerified: true, origin: 'Maitama', destination: 'Jabi', departAt: at(18, 10), seatsTotal: 2, seatsTaken: 1, costShare: 850, vehicleLabel: 'Kia Rio · white'),
      SharedRide(id: 'seed_ride4', hostId: 'u_zainab', hostName: 'Zainab Yusuf', hostOrg: 'Jabi tech hub', hostVerified: true, origin: 'Jabi', destination: 'Kubwa', departAt: at(18, 30), seatsTotal: 4, seatsTaken: 2, costShare: 1100, vehicleLabel: 'Toyota Sienna · grey'),
    ];
  }

  static List<Booking> bookings(DateTime now) {
    DateTime daysAgo(int d, int h, int m) => DateTime(now.year, now.month, now.day - d, h, m);
    final today = DateTime(now.year, now.month, now.day);
    Booking b(String id, String user, String name, String routeId, String origin, String destination, DateTime at, int fare, String vehicle, BookingStatus status, {String seat = 'S12'}) => Booking(
          id: id,
          userId: user,
          passengerName: name,
          kind: BookingKind.transit,
          status: status,
          origin: origin,
          destination: destination,
          departureAt: at,
          fare: fare,
          paymentMethod: PaymentMethod.tapCard,
          ticketCode: 'TR-${id.toUpperCase().substring(id.length - 4)}',
          createdAt: at.subtract(const Duration(hours: 2)),
          seat: seat,
          routeId: routeId,
          vehicleId: vehicle,
          providerId: routeId == 'r03' ? pRail : pMetro,
        );

    return [
      b('bk_seed01', uAisha, 'Aisha Bello', 'r01', 'Wuse', 'Maitama', daysAgo(1, 8, 0), 500, 'v_abj021', BookingStatus.completed, seat: 'S08'),
      b('bk_seed02', uAisha, 'Aisha Bello', 'r02', 'Central Area', 'Gwarinpa', daysAgo(3, 17, 45), 700, 'v_abj015', BookingStatus.completed, seat: 'S21'),
      b('bk_seed03', uAisha, 'Aisha Bello', 'r03', 'Central Station', 'Idu', daysAgo(6, 9, 20), 600, 'v_amr1', BookingStatus.completed, seat: 'C3'),
      b('bk_seed04', 'u_emeka', 'Emeka Nwosu', 'r01', 'Wuse', 'Maitama', today.add(const Duration(hours: 8)), 500, 'v_abj021', BookingStatus.confirmed, seat: 'S14'),
      b('bk_seed05', 'u_zainab', 'Zainab Yusuf', 'r02', 'Central Area', 'Gwarinpa', today.add(const Duration(hours: 7, minutes: 45)), 700, 'v_abj015', BookingStatus.confirmed, seat: 'S03'),
      b('bk_seed06', 'u_emeka', 'Emeka Nwosu', 'r05', 'Nyanya', 'Central Area', today.add(const Duration(hours: 6, minutes: 40)), 600, 'v_abj010', BookingStatus.confirmed, seat: 'S30'),
      b('bk_seed07', 'u_zainab', 'Zainab Yusuf', 'r04', 'Kubwa', 'Central Area', today.add(const Duration(hours: 7)), 800, 'v_abj007', BookingStatus.confirmed, seat: 'S17'),
    ];
  }

  static List<AuditEntry> audit(DateTime now) => [
        AuditEntry(id: 'a1', at: now.subtract(const Duration(days: 2, hours: 3)), actorName: 'Fatima Lawal', actorRole: UserRole.government, action: 'Verified vehicle', target: 'Bus #ABJ 024'),
        AuditEntry(id: 'a2', at: now.subtract(const Duration(days: 3, hours: 6)), actorName: 'Daniel Adeyemi', actorRole: UserRole.admin, action: 'Suspended provider', target: 'City Keke Cooperative · permits expired'),
        AuditEntry(id: 'a3', at: now.subtract(const Duration(days: 5, hours: 1)), actorName: 'Ibrahim Musa', actorRole: UserRole.operator, action: 'Updated fare', target: 'R01 Wuse – Maitama → ₦500'),
        AuditEntry(id: 'a4', at: now.subtract(const Duration(days: 9)), actorName: 'Daniel Adeyemi', actorRole: UserRole.admin, action: 'Approved provider', target: 'NaviRide Electric'),
      ];

  /// FCTA register totals in the mockup: 1,204 verified vehicles and 32 active routes.
  /// The part not covered by platform data is stored as the off-platform remainder.
  static final baselines = MetricBaselines(
    operatorProviderId: pMetro,
    fleetProviderId: pGreenFleet,
    operatorTrips: 482,
    operatorTripsDelta: 12,
    operatorRevenue: 13429000,
    operatorRevenueDelta: 18,
    operatorActiveDrivers: 42,
    fleetRevenue: 12480000,
    fleetRevenueDelta: 22,
    fleetEarnings: [
      VehicleEarning(plate: 'ABJ 021', amount: 540000, date: DateTime(2026, 9, 27)),
      VehicleEarning(plate: 'ABJ 015', amount: 480000, date: DateTime(2026, 9, 27)),
      VehicleEarning(plate: 'ABJ 010', amount: 520000, date: DateTime(2026, 9, 26)),
      VehicleEarning(plate: 'ABJ 007', amount: 465000, date: DateTime(2026, 9, 26)),
      VehicleEarning(plate: 'ABJ 019', amount: 498000, date: DateTime(2026, 9, 25)),
    ],
    ridershipByDay: const [29850, 32400, 34120, 35760, 38940, 41230, 36272],
    ridershipDelta: 14,
    verifiedOffPlatform: 1204 - vehicles().where((v) => v.verification == Verification.verified).length,
    verifiedDelta: 8,
    routesOffPlatform: 32 - routes().where((r) => r.active && const {pMetro, pRail, pAirport}.contains(r.providerId)).length,
    activeRoutesDelta: 6,
  );
}
