import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taparide_flutter/app/router.dart';
import 'package:taparide_flutter/core/backend/backend.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/fleet_drivers.dart';
import 'package:taparide_flutter/core/models.dart';

import 'test_support.dart';

Matcher _refused(BackendErrorKind kind) => throwsA(isA<BackendException>().having((e) => e.kind, 'kind', kind));

void main() {
  test('a fleet driver sees only their own record, vehicle and riders', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: DemoSeed.fleetDriverEmail, password: DemoSeed.password, portal: Portal.partner);
    expect(state.user!.role, UserRole.fleetDriver);
    expect(homeFor(state.user!), '/portal/driver');
    expect(state.user!.providerId, isNull, reason: 'no company-wide access');

    expect(state.fleetDrivers.map((d) => d.id), ['fd_aliyu'], reason: 'not other drivers, not other fleets');
    expect(state.myDriverRecord?.vehicleId, DemoSeed.fleetDriverVehicle);
    final busIds = {for (final b in state.eventBuses) if (b.vehicleId == DemoSeed.fleetDriverVehicle) b.id};
    expect(busIds, contains('eb_kubwa'));
    expect(state.partnerBookings, isNotEmpty);
    for (final b in state.partnerBookings) {
      expect(b.vehicleId == DemoSeed.fleetDriverVehicle || busIds.contains(b.eventBusId), isTrue, reason: 'only bookings on their vehicle (${b.id})');
    }
    expect(state.partnerBookings.any((b) => b.id == 'bk_ride01'), isFalse, reason: "another company's car ride");
    expect(state.audit, isEmpty);
    expect(state.users, isEmpty);

    // No fleet financials or admin pages, and no management actions.
    await expectLater(backend.fetchAuditLog(), _refused(BackendErrorKind.permission));
    await expectLater(backend.fetchUsers(), _refused(BackendErrorKind.permission));
    await expectLater(backend.addFleetDriver(fullName: 'Someone Else', phone: '08031234567', email: 'x@y.demo', licenceNumber: 'ABC12345', providerId: DemoSeed.pGreenFleet), _refused(BackendErrorKind.permission));
    await expectLater(backend.setFleetDriverStatus('fd_hauwa', FleetDriverStatus.suspended), _refused(BackendErrorKind.permission));
    await expectLater(backend.setVehicleStatus(DemoSeed.fleetDriverVehicle, VehicleStatus.inactive), _refused(BackendErrorKind.permission));
    // Another driver's vehicle can't be tracked; their own can.
    await expectLater(backend.reportVehiclePosition('v_abj015', 9.06, 7.45), _refused(BackendErrorKind.permission));
    await backend.reportVehiclePosition(DemoSeed.fleetDriverVehicle, 9.1, 7.4);
    expect((await backend.fetchVehiclePositions()).map((p) => p.vehicleId), contains(DemoSeed.fleetDriverVehicle));
  });

  test('a driver boards, drops off and runs trips on their own vehicle only', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: DemoSeed.fleetDriverEmail, password: DemoSeed.password, portal: Portal.partner);
    final rider = state.partnerBookings.firstWhere((b) => b.id == 'bk_fd_0001');
    expect(rider.status, BookingStatus.confirmed);

    await state.driverBookingAction(rider, DriverBookingAction.accept);
    expect(state.partnerBookings.firstWhere((b) => b.id == rider.id).status, BookingStatus.accepted);
    await expectLater(state.driverBookingAction(rider, DriverBookingAction.accept), _refused(BackendErrorKind.validation));
    await state.driverBookingAction(rider, DriverBookingAction.complete);
    expect(state.partnerBookings.firstWhere((b) => b.id == rider.id).status, BookingStatus.completed);

    // A held event-bus seat waits for the operator to fix the time.
    await expectLater(backend.driverBookingAction('bk_fd_0008', DriverBookingAction.accept), _refused(BackendErrorKind.validation));
    // Bookings on other vehicles are off limits.
    await expectLater(backend.driverBookingAction('bk_seed05', DriverBookingAction.accept), _refused(BackendErrorKind.permission));

    await state.driverSetTrip(start: true);
    expect(state.vehicleById(DemoSeed.fleetDriverVehicle)!.status, VehicleStatus.onTrip);
    await state.driverSetTrip(start: false);
    expect(state.vehicleById(DemoSeed.fleetDriverVehicle)!.status, VehicleStatus.active);
  });

  test('a fleet owner adds, assigns and suspends drivers, only on their own vehicles', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'fleet@greenfleet.demo', password: DemoSeed.password, portal: Portal.partner);
    expect({for (final d in state.fleetDrivers) d.providerId}, {DemoSeed.pGreenFleet}, reason: "no other company's drivers");
    expect(state.fleetDrivers.any((d) => d.id == 'fd_kelechi'), isFalse);

    // Validation and ownership checks.
    await expectLater(backend.addFleetDriver(fullName: 'A', phone: '08031234567', email: 'a@b.demo', licenceNumber: 'ABC12345'), _refused(BackendErrorKind.validation));
    await expectLater(backend.addFleetDriver(fullName: 'Ada Obi', phone: '08031234567', email: 'ada@greenfleet.demo', licenceNumber: 'ABC12345', vehicleId: 'v_nav201'), _refused(BackendErrorKind.permission), reason: 'NaviRide car');
    await expectLater(backend.addFleetDriver(fullName: 'Ada Obi', phone: '08031234567', email: 'ada@greenfleet.demo', licenceNumber: 'ABC12345', providerId: DemoSeed.pMetro), _refused(BackendErrorKind.permission), reason: 'another company');
    await expectLater(backend.addFleetDriver(fullName: 'Ada Obi', phone: '08031234567', email: 'ops@abujametro.demo', licenceNumber: 'ABC12345'), _refused(BackendErrorKind.validation), reason: 'partner account email');

    final ada = await state.addFleetDriver(fullName: 'Ada Obi', phone: '+234 803 123 4567', email: 'Ada@GreenFleet.demo', licenceNumber: 'abj 55512 dd', vehicleId: 'v_abj002', routeId: 'r05');
    expect(ada.email, 'ada@greenfleet.demo');
    expect(ada.licenceNumber, 'ABJ55512DD');
    expect(state.fleetDrivers.map((d) => d.id), contains(ada.id));
    expect(state.vehicleById('v_abj002')!.driverName, 'Ada Obi');
    await expectLater(backend.addFleetDriver(fullName: 'Ada Again', phone: '08031234567', email: 'ada@greenfleet.demo', licenceNumber: 'ABC12345'), _refused(BackendErrorKind.validation), reason: 'duplicate email');

    // Reassign within the fleet; never onto someone else's vehicle or a route the bus can't run.
    await state.assignFleetDriver(ada, vehicleId: 'v_abj003', routeId: 'r01');
    expect(state.fleetDriverById(ada.id)!.vehicleId, 'v_abj003');
    await expectLater(backend.assignFleetDriver(ada.id, vehicleId: 'v_es01'), _refused(BackendErrorKind.permission));
    await expectLater(backend.assignFleetDriver(ada.id, vehicleId: 'v_abj003', routeId: 'r03'), _refused(BackendErrorKind.validation), reason: 'rail route');
    await expectLater(backend.assignFleetDriver('fd_kelechi', vehicleId: 'v_abj003'), _refused(BackendErrorKind.permission), reason: "Metro's driver");

    await state.setFleetDriverStatus(ada, FleetDriverStatus.suspended);
    expect(state.fleetDriverById(ada.id)!.active, isFalse);
    await state.signOut();

    // The new driver signs in; while suspended they see no riders and can't work.
    await state.signIn(email: 'ada@greenfleet.demo', password: DemoSeed.password, portal: Portal.partner);
    expect(state.user!.role, UserRole.fleetDriver);
    expect(state.partnerBookings, isEmpty);
    await expectLater(backend.driverSetTrip(start: true), _refused(BackendErrorKind.permission));
    await expectLater(backend.reportVehiclePosition('v_abj003', 9.06, 7.45), _refused(BackendErrorKind.permission));
    await state.signOut();

    await state.signIn(email: 'fleet@greenfleet.demo', password: DemoSeed.password, portal: Portal.partner);
    await state.setFleetDriverStatus(state.fleetDriverById(ada.id)!, FleetDriverStatus.active);
    await state.signOut();
    await state.signIn(email: 'ada@greenfleet.demo', password: DemoSeed.password, portal: Portal.partner);
    expect(state.myDriverRecord!.active, isTrue);
    await state.driverSetTrip(start: true);
    expect(state.vehicleById('v_abj003')!.status, VehicleStatus.onTrip);
  });

  test('admins see every driver; operators only their own; passengers none', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: DemoSeed.demoAdminEmail, password: DemoSeed.password, portal: Portal.partner);
    expect(state.fleetDrivers.map((d) => d.id).toSet(), {'fd_aliyu', 'fd_hauwa', 'fd_kelechi'});
    await state.signOut();

    await state.signIn(email: 'ops@abujametro.demo', password: DemoSeed.password, portal: Portal.partner);
    expect(state.fleetDrivers.map((d) => d.id), ['fd_kelechi']);
    await expectLater(backend.setFleetDriverStatus('fd_aliyu', FleetDriverStatus.suspended), _refused(BackendErrorKind.permission));
    await state.signOut();

    await state.signIn(email: 'grace@taparide.demo', password: DemoSeed.password, portal: Portal.partner);
    await expectLater(backend.addFleetDriver(fullName: 'Ada Obi', phone: '08031234567', email: 'ada2@x.demo', licenceNumber: 'ABC12345'), _refused(BackendErrorKind.permission), reason: 'private drivers do not employ drivers');
    await state.signOut();

    await state.signIn(email: 'aisha@taparide.demo', password: DemoSeed.password, portal: Portal.passenger);
    expect(await backend.fetchFleetDrivers(), isEmpty);
  });

  test('route demand grid covers every stop and hour', () async {
    final (state, _) = await freshState();
    await state.signIn(email: DemoSeed.fleetDriverEmail, password: DemoSeed.password, portal: Portal.partner);
    final route = state.routeById(DemoSeed.fleetDriverRoute)!;
    final demand = RouteDemand.build(route: route, bookings: state.partnerBookings);
    expect(demand.cells.length, route.stops.length * demand.hours.length);
    expect(demand.peak, greaterThan(0));
    expect(demand.inHour(8), greaterThan(demand.inHour(12)), reason: 'morning peak');
  });

  for (final size in const [Size(390, 844), Size(1440, 1000)]) {
    testWidgets('the fleet driver dashboard renders at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      final state = await pumpApp(tester, size: size);
      await tester.runAsync(() => state.signIn(email: DemoSeed.fleetDriverEmail, password: DemoSeed.password, portal: Portal.partner));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/portal/driver');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Driver dashboard'), findsWidgets);
      expect(find.text("Today's assignment"), findsOneWidget);
      expect(find.textContaining(RegExp(r'^(Start|End) trip$')), findsOneWidget);
      // Other pages bounce back to the driver's own dashboard.
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/portal/fleet');
      await tester.pumpAndSettle();
      expect(find.text("Today's assignment"), findsOneWidget);
      expect(find.text('Fleet Owner Dashboard'), findsNothing);
      await tester.scrollUntilVisible(find.text('Event rides'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Emeka Nwosu'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a fleet owner manages drivers from the Drivers page', (tester) async {
    final state = await pumpApp(tester, size: const Size(1440, 1000));
    await tester.runAsync(() => state.signIn(email: 'fleet@greenfleet.demo', password: DemoSeed.password, portal: Portal.partner));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/portal/drivers');
    await tester.pumpAndSettle();
    expect(find.text('Aliyu Wada'), findsOneWidget);
    expect(find.text('Kelechi Obi (sample)'), findsNothing);
    await tester.tap(find.text('Add driver').first);
    await tester.pumpAndSettle();
    expect(find.text("Driver's licence number"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
