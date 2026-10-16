import 'models.dart';

/// Demand at one place (stop / area), from route volumes and live bookings.
class AreaDemand {
  const AreaDemand({required this.name, required this.lat, required this.lng, required this.trips, required this.bookingsToday});
  final String name;
  final double lat;
  final double lng;
  final int trips;
  final int bookingsToday;
}

class RouteIncome {
  const RouteIncome({required this.route, required this.monthlyRevenue, required this.tripsPerDeparture});
  final TransitRoute route;
  final int monthlyRevenue;
  final double tripsPerDeparture;
}

class Opportunity {
  const Opportunity({required this.title, required this.detail});
  final String title;
  final String detail;
}

/// Everything the AI Insights dashboard shows for one scope (a provider, or the whole platform).
class InsightsReport {
  const InsightsReport({
    required this.scopeName,
    required this.routes,
    required this.vehicles,
    required this.monthlyRevenue,
    required this.revenueToday,
    required this.bookingsToday,
    required this.routeIncome,
    required this.areas,
    required this.utilisation,
    required this.idleVehicles,
    required this.idleCostPerMonth,
    required this.topEarners,
    required this.lowEarners,
    required this.bookingsByHour,
    required this.opportunities,
  });

  final String scopeName;
  final List<TransitRoute> routes;
  final List<Vehicle> vehicles;
  final int monthlyRevenue;
  final int revenueToday;
  final int bookingsToday;
  final List<RouteIncome> routeIncome;
  final List<AreaDemand> areas;

  /// Share of the fleet working (available, on a trip or charging).
  final double utilisation;
  final List<Vehicle> idleVehicles;
  final int idleCostPerMonth;
  final List<Vehicle> topEarners;
  final List<Vehicle> lowEarners;

  /// Bookings by departure hour (0–23), from real bookings.
  final List<int> bookingsByHour;
  final List<Opportunity> opportunities;

  int get projectedNextMonth => (monthlyRevenue * 1.0 + revenueToday * 30 * 0.15).round();

  /// Compact numbers for the AI analyst (no personal data).
  Map<String, Object?> toAiJson() => {
        'scope': scopeName,
        'monthly_revenue_naira': monthlyRevenue,
        'revenue_today_naira': revenueToday,
        'bookings_today': bookingsToday,
        'routes': [for (final r in routeIncome.take(8)) {'route': r.route.title, 'fare': r.route.fare, 'trips_30d': r.route.monthlyTrips, 'departures_per_day': r.route.departures.length, 'trips_per_departure': r.tripsPerDeparture.toStringAsFixed(1), 'est_monthly_revenue': r.monthlyRevenue}],
        'vehicles_total': vehicles.length,
        'fleet_utilisation_pct': (utilisation * 100).round(),
        'idle_vehicles': [for (final v in idleVehicles.take(10)) '${v.displayName} (${v.status.label})'],
        'idle_cost_per_month_naira': idleCostPerMonth,
        'top_earners': [for (final v in topEarners) '${v.displayName}: ${v.monthEarnings}'],
        'low_earners': [for (final v in lowEarners) '${v.displayName}: ${v.monthEarnings}'],
        'high_demand_areas': [for (final a in areas.take(8)) '${a.name}: ${a.trips} trips/30d, ${a.bookingsToday} bookings today'],
        'bookings_by_hour': {for (var h = 0; h < 24; h++) if (bookingsByHour[h] > 0) '$h:00': bookingsByHour[h]},
        'opportunities': [for (final o in opportunities) o.title],
      };
}

abstract final class Analytics {
  /// [providerId] null = whole platform (FCTA / admin view).
  static InsightsReport build({
    required String? providerId,
    required String scopeName,
    required List<TransitRoute> routes,
    required List<Vehicle> vehicles,
    required List<Booking> bookings,
    required DateTime now,
  }) {
    final myRoutes = [for (final r in routes) if (providerId == null || r.providerId == providerId) r];
    final myVehicles = [for (final v in vehicles) if (providerId == null || v.operatorId == providerId || v.ownerId == providerId) v];
    final myVehicleIds = {for (final v in myVehicles) v.id};
    final myBookings = [
      for (final b in bookings)
        if (b.status != BookingStatus.cancelled && (providerId == null || b.providerId == providerId || myVehicleIds.contains(b.vehicleId))) b,
    ];
    final today = [for (final b in myBookings) if (b.createdAt.year == now.year && b.createdAt.month == now.month && b.createdAt.day == now.day) b];

    final routeIncome = [
      for (final r in myRoutes)
        RouteIncome(route: r, monthlyRevenue: r.monthlyTrips * r.fare, tripsPerDeparture: r.departures.isEmpty ? 0 : r.monthlyTrips / (r.departures.length * 30)),
    ]..sort((a, b) => b.monthlyRevenue.compareTo(a.monthlyRevenue));

    final vehicleEarnings = myVehicles.fold<int>(0, (s, v) => s + v.monthEarnings);
    final monthlyRevenue = vehicleEarnings > 0 ? vehicleEarnings : routeIncome.fold<int>(0, (s, r) => s + r.monthlyRevenue);

    // Demand per place: each route's trips spread across its stops, plus today's live bookings.
    final areaMap = <String, (double, double, double, int)>{};
    for (final r in (providerId == null ? routes : myRoutes)) {
      if (r.stops.isEmpty) continue;
      final share = r.monthlyTrips / r.stops.length;
      for (final s in r.stops) {
        final cur = areaMap[s.name] ?? (s.lat, s.lng, 0.0, 0);
        areaMap[s.name] = (cur.$1, cur.$2, cur.$3 + share, cur.$4);
      }
    }
    for (final b in today) {
      for (final name in [b.origin, b.destination]) {
        final cur = areaMap[name];
        if (cur != null) areaMap[name] = (cur.$1, cur.$2, cur.$3, cur.$4 + 1);
      }
    }
    final areas = [
      for (final e in areaMap.entries) AreaDemand(name: e.key, lat: e.value.$1, lng: e.value.$2, trips: e.value.$3.round(), bookingsToday: e.value.$4),
    ]..sort((a, b) => (b.trips + b.bookingsToday * 50).compareTo(a.trips + a.bookingsToday * 50));

    final working = myVehicles.where((v) => v.status == VehicleStatus.active || v.status == VehicleStatus.onTrip || v.status == VehicleStatus.charging).length;
    final idle = [for (final v in myVehicles) if (v.status == VehicleStatus.maintenance || v.status == VehicleStatus.inactive) v];
    final earners = [for (final v in myVehicles) if (v.monthEarnings > 0) v]..sort((a, b) => b.monthEarnings.compareTo(a.monthEarnings));
    final avgEarning = earners.isEmpty ? 0 : earners.fold<int>(0, (s, v) => s + v.monthEarnings) ~/ earners.length;

    final byHour = List<int>.filled(24, 0);
    for (final b in myBookings) {
      byHour[b.departureAt.hour]++;
    }

    // Opportunities: busy places this scope doesn't serve, and routes that need more departures.
    final served = {for (final r in myRoutes) for (final s in r.stops) s.name};
    final opportunities = <Opportunity>[];
    if (providerId != null) {
      for (final a in areas.where((a) => !served.contains(a.name)).take(2)) {
        opportunities.add(Opportunity(title: 'High demand at ${a.name}', detail: '${a.trips} trips a month pass through ${a.name}, which none of your routes serve. Consider a feeder route or a pickup point there.'));
      }
    }
    for (final r in routeIncome.where((r) => r.tripsPerDeparture > 40).take(2)) {
      opportunities.add(Opportunity(title: 'Add departures on ${r.route.title}', detail: 'About ${r.tripsPerDeparture.round()} riders per departure. Adding peak-hour departures would cut crowding and lift revenue.'));
    }
    if (idle.isNotEmpty && avgEarning > 0) {
      opportunities.add(Opportunity(title: 'Bring ${idle.length} idle vehicle${idle.length == 1 ? '' : 's'} back', detail: 'Each working vehicle earns about ₦$avgEarning a month; idle vehicles cost about ₦${avgEarning * idle.length} a month in lost income.'));
    }

    return InsightsReport(
      scopeName: scopeName,
      routes: myRoutes,
      vehicles: myVehicles,
      monthlyRevenue: monthlyRevenue,
      revenueToday: today.where((b) => b.paymentMethod != PaymentMethod.splitCost).fold<int>(0, (s, b) => s + b.fare),
      bookingsToday: today.length,
      routeIncome: routeIncome,
      areas: areas,
      utilisation: myVehicles.isEmpty ? 0 : working / myVehicles.length,
      idleVehicles: idle,
      idleCostPerMonth: avgEarning * idle.length,
      topEarners: earners.take(3).toList(),
      lowEarners: earners.reversed.take(3).toList(),
      bookingsByHour: byHour,
      opportunities: opportunities,
    );
  }
}

/// The AI analyst's reading of an [InsightsReport] (from /api/insights).
class AiInsights {
  const AiInsights({required this.headline, required this.findings, required this.actions, required this.model});
  final String headline;
  final List<({String title, String detail, String kind})> findings;
  final List<({String title, String why, String impact})> actions;
  final String model;

  factory AiInsights.fromJson(Map<String, dynamic> j) => AiInsights(
        headline: '${j['headline'] ?? ''}',
        findings: [
          for (final f in (j['findings'] as List? ?? const []))
            (title: '${(f as Map)['title'] ?? ''}', detail: '${f['detail'] ?? ''}', kind: '${f['kind'] ?? 'income'}'),
        ],
        actions: [
          for (final a in (j['actions'] as List? ?? const []))
            (title: '${(a as Map)['title'] ?? ''}', why: '${a['why'] ?? ''}', impact: '${a['impact'] ?? 'medium'}'),
        ],
        model: '${j['model'] ?? ''}',
      );
}

/// Live road time for a route's end-to-end trip versus its timetable.
class TrafficCheck {
  const TrafficCheck({required this.route, required this.scheduledMin, required this.liveMin, required this.distanceKm, required this.label});
  final TransitRoute route;
  final int scheduledMin;
  final int liveMin;
  final double distanceKm;
  final String label;

  int get delayMin => liveMin - scheduledMin;
}
