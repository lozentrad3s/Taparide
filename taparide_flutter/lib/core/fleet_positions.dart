import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'places.dart';

/// Where a vehicle is estimated to be right now, and on which route.
class FleetPosition {
  const FleetPosition({required this.vehicle, required this.point, this.route});
  final Vehicle vehicle;
  final LatLng point;
  final TransitRoute? route;
}

/// Estimates vehicle positions from timetables and status, until vehicles report GPS.
/// Buses on a trip move along their operator's routes; cars and parked vehicles sit
/// in their home area. Deterministic for a given [now], so it is testable.
abstract final class FleetPositions {
  static List<FleetPosition> estimate({required List<Vehicle> vehicles, required List<TransitRoute> routes, required DateTime now}) {
    final byProvider = <String, List<TransitRoute>>{};
    for (final r in routes) {
      if (r.stops.length >= 2) byProvider.putIfAbsent(r.providerId, () => []).add(r);
    }
    final positions = <FleetPosition>[];
    final counters = <String, int>{};
    for (final v in vehicles) {
      final seed = v.id.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff);
      final own = byProvider[v.operatorId] ?? const [];
      final moving = (v.status == VehicleStatus.onTrip || v.status == VehicleStatus.active) && !v.kind.isBookableCar && own.isNotEmpty;
      if (moving) {
        final i = counters[v.operatorId] = (counters[v.operatorId] ?? -1) + 1;
        final route = own[i % own.length];
        final period = max(route.durationMin, 10) * 60;
        final t = (now.hour * 3600 + now.minute * 60 + now.second + seed % (period * 2)) % (period * 2);
        final f = t < period ? t / period : 2 - t / period; // out and back
        positions.add(FleetPosition(vehicle: v, point: along(route.stops, f), route: route));
      } else {
        final home = resolvePlace(v.area, routes: routes)?.point ?? const LatLng(9.0579, 7.4951);
        // Spread vehicles in the same area so they don't overlap (≈ up to 600 m).
        final angle = (seed % 360) * pi / 180;
        final r = 0.0015 + (seed % 40) / 10000;
        positions.add(FleetPosition(vehicle: v, point: LatLng(home.latitude + r * sin(angle), home.longitude + r * cos(angle))));
      }
    }
    return positions;
  }

  /// The point a fraction [f] (0–1) of the way along the stops, by distance.
  static LatLng along(List<RouteStop> stops, double f) {
    final pts = [for (final s in stops) LatLng(s.lat, s.lng)];
    final legs = [for (var i = 0; i < pts.length - 1; i++) straightKm(pts[i], pts[i + 1])];
    final total = legs.fold<double>(0, (a, b) => a + b);
    if (total == 0) return pts.first;
    var target = f.clamp(0.0, 1.0) * total;
    for (var i = 0; i < legs.length; i++) {
      if (target <= legs[i] || i == legs.length - 1) {
        final k = legs[i] == 0 ? 0.0 : (target / legs[i]).clamp(0.0, 1.0);
        return LatLng(pts[i].latitude + (pts[i + 1].latitude - pts[i].latitude) * k, pts[i].longitude + (pts[i + 1].longitude - pts[i].longitude) * k);
      }
      target -= legs[i];
    }
    return pts.last;
  }
}
