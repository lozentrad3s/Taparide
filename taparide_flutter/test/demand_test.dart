import 'package:flutter_test/flutter_test.dart';
import 'package:taparide_flutter/core/analytics.dart';
import 'package:taparide_flutter/core/backend/demo_seed.dart';
import 'package:taparide_flutter/core/models.dart';

void main() {
  final now = DateTime(2026, 11, 18, 12);
  final routes = DemoSeed.routes();
  final vehicles = DemoSeed.vehicles();
  final bookings = DemoSeed.bookings(now);

  DemandReport build(String? providerId, {List<Booking>? withBookings}) =>
      Demand.build(scopeName: 'test', routes: Demand.routesFor(providerId, routes, vehicles), bookings: withBookings ?? bookings, now: now);

  test('whole-platform demand covers every active route with riders, busiest first', () {
    final r = build(null);
    final expected = routes.where((x) => x.active && x.monthlyTrips > 0).map((x) => x.id).toSet();
    expect(r.corridors.map((c) => c.route.id).toSet(), expected, reason: 'retired and unused routes are left out');
    for (var i = 1; i < r.corridors.length; i++) {
      expect(r.corridors[i - 1].dailyTrips + r.corridors[i - 1].booked, greaterThanOrEqualTo(r.corridors[i].dailyTrips + r.corridors[i].booked));
    }
    expect(r.corridors.first.route.code, 'K01');
  });

  test('hourly estimates add up to the route volume and only fall on hours with departures', () {
    for (final c in build(null).corridors) {
      final sum = c.estimateByHour.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(c.dailyTrips, 0.01), reason: c.route.code);
      for (var h = 0; h < 24; h++) {
        if (c.departuresByHour[h] == 0) expect(c.estimateByHour[h], 0, reason: '${c.route.code} at $h:00 has no departures');
      }
    }
  });

  test('the busiest hour follows when riders actually book', () {
    final r = build(null);
    // Seed bookings depart between 06:40 and 09:20 and around 17:45, so the peak is a morning hour.
    expect(r.peakHour, inInclusiveRange(6, 9));
    expect(r.peakShare, greaterThan(0.3));
    expect(r.booked, bookings.where((b) => b.kind == BookingKind.transit).length);
  });

  test('with no bookings demand is spread evenly over the timetable', () {
    final r = build(null, withBookings: const []);
    final k01 = r.corridors.firstWhere((c) => c.route.code == 'K01');
    // K01 runs every 15 minutes from 05:00, so each full hour gets the same share.
    expect(k01.estimateByHour[7], closeTo(k01.estimateByHour[12], 0.001));
    expect(r.topTrips, isEmpty);
  });

  test('operators see their own corridors; fleet owners see the routes their vehicles run on', () {
    final metro = build(DemoSeed.pMetro);
    expect(metro.corridors.every((c) => c.route.providerId == DemoSeed.pMetro), isTrue);
    final rail = build(DemoSeed.pRail);
    expect(rail.corridors.map((c) => c.route.code).toSet(), {'MR1', 'MR2'});
    final fleet = build(DemoSeed.pGreenFleet);
    expect(fleet.corridors, isNotEmpty);
    expect(fleet.corridors.every((c) => c.route.providerId == DemoSeed.pMetro), isTrue, reason: 'GreenFleet buses are leased to Abuja Metro');
    expect(build(DemoSeed.pEvents).isEmpty, isTrue, reason: 'an event partner runs no routes');
  });

  test('top trips and today counts come from bookings', () {
    final r = build(null);
    expect(r.topTrips.first.origin, 'Kubwa');
    expect(r.topTrips.first.destination, 'Berger');
    final k01 = r.corridors.firstWhere((c) => c.route.code == 'K01');
    expect(k01.bookedToday, 1, reason: 'one seat on K01 was booked today');
    final rows = r.toCsvRows();
    expect(rows.first.first, 'Corridor');
    expect(rows.length, r.corridors.length + 1);
  });

  test('insights reports carry the demand for their scope', () {
    final report = Analytics.build(providerId: DemoSeed.pMetro, scopeName: 'Metro', routes: routes, vehicles: vehicles, bookings: bookings, now: now);
    expect(report.demand.corridors, isNotEmpty);
    expect(report.toAiJson()['demand_by_corridor'], isNotEmpty);
  });
}
