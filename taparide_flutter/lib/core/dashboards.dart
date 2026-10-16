import 'models.dart';

enum TripStatus { onTime, delayed, boarding, scheduled }

extension TripStatusX on TripStatus {
  String get label => switch (this) {
        TripStatus.onTime => 'On time',
        TripStatus.delayed => 'Delayed',
        TripStatus.boarding => 'Boarding',
        TripStatus.scheduled => 'Scheduled',
      };
}

class TripRecord {
  const TripRecord({required this.route, required this.at, required this.vehicle, required this.status, this.delayMin = 0});
  final TransitRoute route;
  final DateTime at;
  final Vehicle? vehicle;
  final TripStatus status;
  final int delayMin;
}

class OperatorDashboard {
  const OperatorDashboard({
    required this.provider,
    required this.totalTrips,
    required this.tripsDelta,
    required this.revenue,
    required this.revenueDelta,
    required this.routes,
    required this.vehicles,
    required this.activeDrivers,
    required this.recentTrips,
    required this.bookingsToday,
    required this.revenueToday,
    required this.latestBookings,
  });

  final TransportProvider provider;
  final int totalTrips;
  final int? tripsDelta;
  final int revenue;
  final int? revenueDelta;
  final List<TransitRoute> routes;
  final List<Vehicle> vehicles;
  final int activeDrivers;
  final List<TripRecord> recentTrips;
  final int bookingsToday;
  final int revenueToday;
  final List<Booking> latestBookings;
}

class FleetDashboard {
  const FleetDashboard({
    required this.provider,
    required this.vehicles,
    required this.revenue,
    required this.revenueDelta,
    required this.earnings,
    required this.bookingsToday,
  });

  final TransportProvider provider;
  final List<Vehicle> vehicles;
  final int revenue;
  final int? revenueDelta;
  final List<VehicleEarning> earnings;
  final int bookingsToday;

  int count(Set<VehicleStatus> statuses) => vehicles.where((v) => statuses.contains(v.status)).length;
  int get active => count({VehicleStatus.active, VehicleStatus.onTrip, VehicleStatus.charging});
  int get maintenance => count({VehicleStatus.maintenance});
  int get inactive => count({VehicleStatus.inactive});
}

class RouteVolume {
  const RouteVolume(this.route, this.trips);
  final TransitRoute route;
  final int trips;
}

class FctaDashboard {
  const FctaDashboard({
    required this.ridershipByDay,
    required this.todayIndex,
    required this.ridershipDelta,
    required this.verifiedVehicles,
    required this.verifiedDelta,
    required this.activeRoutes,
    required this.routesDelta,
    required this.topRoutes,
    required this.providers,
    required this.pendingVehicles,
    required this.electricVehicles,
    required this.bookingsToday,
  });

  final List<int> ridershipByDay;
  final int todayIndex;
  final int ridershipDelta;
  final int verifiedVehicles;
  final int verifiedDelta;
  final int activeRoutes;
  final int routesDelta;
  final List<RouteVolume> topRoutes;
  final List<TransportProvider> providers;
  final List<Vehicle> pendingVehicles;
  final List<Vehicle> electricVehicles;
  final int bookingsToday;

  int get totalRidership => ridershipByDay.fold(0, (a, b) => a + b);
  int providersWith(Verification status) => providers.where((p) => p.status == status).length;
}

/// Pure functions that turn the catalogue + bookings into the dashboard figures.
abstract final class Dashboards {
  static bool _isToday(DateTime d, DateTime now) => d.year == now.year && d.month == now.month && d.day == now.day;

  static Iterable<Booking> _liveToday(Iterable<Booking> bookings, DateTime now) =>
      bookings.where((b) => b.status != BookingStatus.cancelled && b.status != BookingStatus.declined && _isToday(b.createdAt, now));

  static OperatorDashboard operator({
    required TransportProvider provider,
    required List<TransitRoute> routes,
    required List<Vehicle> vehicles,
    required List<Booking> bookings,
    required MetricBaselines baselines,
    required DateTime now,
  }) {
    final ownRoutes = [for (final r in routes) if (r.providerId == provider.id) r];
    final ownVehicles = [for (final v in vehicles) if (v.operatorId == provider.id) v];
    final ownBookings = [for (final b in bookings) if (b.providerId == provider.id) b];
    final live = _liveToday(ownBookings, now).toList();
    final liveRevenue = live.fold<int>(0, (sum, b) => sum + b.fare);
    final hasBaseline = provider.id == baselines.operatorProviderId;

    return OperatorDashboard(
      provider: provider,
      totalTrips: hasBaseline ? baselines.operatorTrips : ownBookings.where((b) => b.status != BookingStatus.cancelled).length,
      tripsDelta: hasBaseline ? baselines.operatorTripsDelta : null,
      revenue: (hasBaseline ? baselines.operatorRevenue : ownVehicles.fold<int>(0, (s, v) => s + v.monthEarnings)) + liveRevenue,
      revenueDelta: hasBaseline ? baselines.operatorRevenueDelta : null,
      routes: ownRoutes,
      vehicles: ownVehicles,
      activeDrivers: hasBaseline ? baselines.operatorActiveDrivers : ownVehicles.where((v) => v.driverName != null).length,
      recentTrips: recentTrips(ownRoutes, ownVehicles, now),
      bookingsToday: live.length,
      revenueToday: liveRevenue,
      latestBookings: ownBookings.take(8).toList(),
    );
  }

  /// Departures that left in the last few hours, plus the next one boarding.
  static List<TripRecord> recentTrips(List<TransitRoute> routes, List<Vehicle> vehicles, DateTime now, {int limit = 6}) {
    final fleet = [for (final v in vehicles) if (v.status != VehicleStatus.inactive && v.status != VehicleStatus.maintenance) v];
    final ranked = [...routes]..sort((a, b) => b.monthlyTrips.compareTo(a.monthlyTrips));
    final records = <TripRecord>[];
    final today = DateTime(now.year, now.month, now.day);
    for (final route in ranked.take(4)) {
      for (final hhmm in route.departures) {
        final parts = hhmm.split(':');
        final at = today.add(Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])));
        final age = now.difference(at).inMinutes;
        if (age < -15 || age > 180) continue;
        final seed = (route.id.hashCode ^ at.hour * 61 ^ at.minute).abs();
        final vehicle = fleet.isEmpty ? null : fleet[seed % fleet.length];
        final status = age < 0 ? TripStatus.boarding : (seed % 7 == 0 ? TripStatus.delayed : TripStatus.onTime);
        records.add(TripRecord(route: route, at: at, vehicle: vehicle, status: status, delayMin: status == TripStatus.delayed ? 4 + seed % 9 : 0));
      }
    }
    if (records.isEmpty) {
      for (final route in ranked.take(3)) {
        final next = route.upcomingDepartures(now, count: 1);
        if (next.isEmpty) continue;
        final seed = route.id.hashCode.abs();
        records.add(TripRecord(route: route, at: next.first, vehicle: fleet.isEmpty ? null : fleet[seed % fleet.length], status: TripStatus.scheduled));
      }
    }
    records.sort((a, b) => b.at.compareTo(a.at));
    return records.take(limit).toList();
  }

  static FleetDashboard fleet({
    required TransportProvider provider,
    required List<Vehicle> vehicles,
    required List<Booking> bookings,
    required MetricBaselines baselines,
    required DateTime now,
  }) {
    final owned = [for (final v in vehicles) if (v.ownerId == provider.id || (v.ownerId == null && v.operatorId == provider.id)) v];
    final ownedIds = {for (final v in owned) v.id};
    final live = _liveToday(bookings.where((b) => ownedIds.contains(b.vehicleId)), now).toList();
    final liveRevenue = live.fold<int>(0, (s, b) => s + b.fare);
    final hasBaseline = provider.id == baselines.fleetProviderId;
    final derivedEarnings = ([...owned]..sort((a, b) => b.monthEarnings.compareTo(a.monthEarnings)))
        .take(5)
        .map((v) => VehicleEarning(plate: v.plate, amount: v.monthEarnings, date: DateTime(now.year, now.month, 1)))
        .toList();
    return FleetDashboard(
      provider: provider,
      vehicles: owned,
      revenue: (hasBaseline ? baselines.fleetRevenue : owned.fold<int>(0, (s, v) => s + v.monthEarnings)) + liveRevenue,
      revenueDelta: hasBaseline ? baselines.fleetRevenueDelta : null,
      earnings: hasBaseline ? baselines.fleetEarnings : derivedEarnings,
      bookingsToday: live.length,
    );
  }

  static FctaDashboard fcta({
    required List<TransportProvider> providers,
    required List<TransitRoute> routes,
    required List<Vehicle> vehicles,
    required List<Booking> bookings,
    required MetricBaselines baselines,
    required DateTime now,
  }) {
    final verifiedProviders = {for (final p in providers) if (p.status == Verification.verified) p.id};
    final live = _liveToday(bookings, now).toList();
    final todayIndex = now.weekday - 1;
    final byDay = [...baselines.ridershipByDay];
    byDay[todayIndex] += live.length;

    final liveByRoute = <String, int>{};
    for (final b in live) {
      if (b.routeId != null) liveByRoute[b.routeId!] = (liveByRoute[b.routeId!] ?? 0) + 1;
    }
    final volumes = [
      for (final r in routes)
        if (r.monthlyTrips > 0 || liveByRoute.containsKey(r.id)) RouteVolume(r, r.monthlyTrips + (liveByRoute[r.id] ?? 0)),
    ]..sort((a, b) => b.trips.compareTo(a.trips));

    final platformVerified = vehicles.where((v) => v.verification == Verification.verified).length;
    final platformRoutes = routes.where((r) => r.active && verifiedProviders.contains(r.providerId)).length;

    return FctaDashboard(
      ridershipByDay: byDay,
      todayIndex: todayIndex,
      ridershipDelta: baselines.ridershipDelta,
      verifiedVehicles: baselines.verifiedOffPlatform + platformVerified,
      verifiedDelta: baselines.verifiedDelta,
      activeRoutes: baselines.routesOffPlatform + platformRoutes,
      routesDelta: baselines.activeRoutesDelta,
      topRoutes: volumes,
      providers: providers,
      pendingVehicles: [for (final v in vehicles) if (v.verification == Verification.pending) v],
      electricVehicles: [for (final v in vehicles) if (v.electric && v.kind != VehicleKind.train) v],
      bookingsToday: live.length,
    );
  }
}
