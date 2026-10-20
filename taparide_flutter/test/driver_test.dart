import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taparide_flutter/core/api_client.dart';
import 'package:taparide_flutter/core/backend/backend.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/fleet_positions.dart';
import 'package:taparide_flutter/core/models.dart';
import 'package:taparide_flutter/shared/download/download.dart';

import 'test_support.dart';

void main() {
  test('a private driver completes a ride and the fare counts towards earnings', () async {
    final (state, backend) = await freshState();
    await state.signIn(email: 'grace@taparide.demo', password: DemoSeed.password, portal: Portal.partner);
    final car = state.vehicles.firstWhere((v) => v.id == 'v_grace_car');
    expect(car.status, VehicleStatus.onTrip);
    final ride = state.partnerBookings.firstWhere((b) => b.id == 'bk_ride01');
    expect(ride.status, BookingStatus.confirmed);

    await state.completeRide(ride);
    final after = state.vehicles.firstWhere((v) => v.id == 'v_grace_car');
    expect(after.status, VehicleStatus.active, reason: 'the car is free for the next rider');
    expect(after.monthEarnings, car.monthEarnings + ride.fare);
    expect(state.partnerBookings.firstWhere((b) => b.id == ride.id).status, BookingStatus.completed);
    await expectLater(() => state.completeRide(ride), throwsA(isA<BackendException>()), reason: 'already completed');
    await state.signOut();

    await state.signIn(email: 'ops@abujametro.demo', password: DemoSeed.password, portal: Portal.partner);
    await expectLater(() => backend.completeRide('bk_ride02'), throwsA(isA<BackendException>()), reason: 'another operator cannot complete her rides');
  });

  test('fleet positions stay on the route and are deterministic', () async {
    final (state, _) = await freshState();
    await state.signIn(email: 'admin@taparide.demo', password: DemoSeed.password, portal: Portal.partner);
    final now = DateTime(2026, 10, 20, 8, 30);
    final metro = [for (final v in state.vehicles) if (v.operatorId == DemoSeed.pMetro) v];
    final a = FleetPositions.estimate(vehicles: metro, routes: state.routes, now: now);
    final b = FleetPositions.estimate(vehicles: metro, routes: state.routes, now: now);
    expect(a.length, metro.length);
    expect([for (final p in a) p.point], [for (final p in b) p.point]);
    for (final p in a) {
      expect(p.point.latitude, inInclusiveRange(8.9, 9.3), reason: 'inside the FCT');
      expect(p.point.longitude, inInclusiveRange(7.2, 7.7));
    }
    final stops = state.routeById('r01')!.stops;
    expect(FleetPositions.along(stops, 0).latitude, stops.first.lat);
    expect(FleetPositions.along(stops, 1).latitude, closeTo(stops.last.lat, 1e-9));
  });

  test('polyline decoding handles negative steps (Google encoded polyline, precision 5)', () {
    // Reference example from the format's documentation.
    final pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(pts.length, 3);
    expect(pts[0].latitude, closeTo(38.5, 1e-9));
    expect(pts[0].longitude, closeTo(-120.2, 1e-9));
    expect(pts[1].latitude, closeTo(40.7, 1e-9));
    expect(pts[2].longitude, closeTo(-126.453, 1e-9));
  });

  test('CSV export escapes commas and quotes', () {
    expect(toCsv([
      ['a', 'b,c', 'say "hi"'],
      [1, null],
    ]), 'a,"b,c","say ""hi"""\r\n1,');
  });

  testWidgets('the driver dashboard shows the current ride and goes online', (tester) async {
    final state = await pumpApp(tester, size: const Size(1440, 1000));
    await tester.runAsync(() => state.signIn(email: 'grace@taparide.demo', password: DemoSeed.password, portal: Portal.partner));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/portal/operator');
    await tester.pumpAndSettle();
    expect(find.text('Driver dashboard'), findsWidgets, reason: 'page title and sidebar');
    expect(find.text('Routes & fares'), findsNothing, reason: 'drivers have no routes to manage');
    expect(find.text('Current ride'), findsOneWidget);
    expect(find.text('Complete ride'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
