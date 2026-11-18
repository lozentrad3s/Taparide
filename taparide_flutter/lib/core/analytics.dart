import 'format.dart';
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
    required this.demand,
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

  /// Demand by corridor and hour for the routes in this scope.
  final DemandReport demand;

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
        'demand_by_corridor': [
          for (final c in demand.corridors.take(8)) {'corridor': c.route.title, 'riders_per_day': c.dailyTrips.round(), 'busiest_hour': hourLabel(c.peakHour), 'riders_in_busiest_hour_est': c.peakRiders.round(), 'app_bookings_30d': c.booked},
        ],
        'busiest_hour_overall': demand.isEmpty ? null : hourLabel(demand.peakHour),
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

    final demand = Demand.build(scopeName: scopeName, routes: Demand.routesFor(providerId, routes, vehicles), bookings: bookings, now: now);

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
    final busiest = demand.corridors.where((c) => c.crowdedAtPeak).firstOrNull;
    if (busiest != null) {
      opportunities.add(Opportunity(title: 'Peak crowding on ${busiest.route.code} at ${hourLabel(busiest.peakHour)}', detail: 'About ${busiest.peakLoad.round()} riders per departure between ${hourLabel(busiest.peakHour)} and ${hourLabel(busiest.peakHour + 1)} on ${busiest.route.title} (estimated from trips and app bookings). An extra departure in that hour would ease it.'));
    }
    if (idle.isNotEmpty && avgEarning > 0) {
      opportunities.add(Opportunity(title: 'Bring ${idle.length} idle vehicle${idle.length == 1 ? '' : 's'} back', detail: 'Each working vehicle earns about ${Fmt.naira(avgEarning)} a month; idle vehicles cost about ${Fmt.naira(avgEarning * idle.length)} a month in lost income.'));
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
      demand: demand,
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

/// Demand on one corridor (a published route), hour by hour on an average day.
class CorridorDemand {
  const CorridorDemand({required this.route, required this.dailyTrips, required this.departuresByHour, required this.estimateByHour, required this.bookedByHour, required this.bookedToday, required this.revenueToday});
  final TransitRoute route;

  /// Average riders a day over the last 30 days (route data).
  final double dailyTrips;
  final List<int> departuresByHour;

  /// Estimated riders per hour: [dailyTrips] spread over the timetable, weighted by when riders book.
  final List<double> estimateByHour;

  /// Seats booked in the app per departure hour (last 30 days and upcoming).
  final List<int> bookedByHour;
  final int bookedToday;
  final int revenueToday;

  int get booked => bookedByHour.fold(0, (a, b) => a + b);
  int get peakHour => _argMax(estimateByHour);
  double get peakRiders => estimateByHour[peakHour];

  /// Riders per departure in the busiest hour.
  double get peakLoad => departuresByHour[peakHour] == 0 ? 0 : peakRiders / departuresByHour[peakHour];

  /// More riders per departure than a city bus seats (42–48); trains carry hundreds, so rail never counts.
  bool get crowdedAtPeak => route.mode != TransitMode.rail && peakLoad > 45;
}

/// One origin → destination pair riders booked.
class TripPair {
  const TripPair({required this.origin, required this.destination, required this.bookings, required this.fares});
  final String origin;
  final String destination;
  final int bookings;
  final int fares;
}

/// Where and when riders travel: demand by corridor and by hour for one scope.
class DemandReport {
  const DemandReport({required this.scopeName, required this.corridors, required this.estimateByHour, required this.bookedByHour, required this.topTrips, required this.bookingsUsed, required this.windowDays});
  final String scopeName;

  /// Busiest first.
  final List<CorridorDemand> corridors;
  final List<double> estimateByHour;
  final List<int> bookedByHour;
  final List<TripPair> topTrips;

  /// App bookings (city-wide) that shaped the hourly profile.
  final int bookingsUsed;
  final int windowDays;

  bool get isEmpty => corridors.isEmpty;
  double get dailyTrips => corridors.fold(0.0, (s, c) => s + c.dailyTrips);
  int get booked => bookedByHour.fold(0, (a, b) => a + b);
  int get peakHour => _argMax(estimateByHour.every((v) => v == 0) ? [for (final v in bookedByHour) v.toDouble()] : estimateByHour);

  /// Share of the day's riders travelling in the morning (6–9) and evening (16–19) peaks.
  double get peakShare {
    final total = estimateByHour.fold(0.0, (a, b) => a + b);
    if (total == 0) return 0;
    var peak = 0.0;
    for (final h in [6, 7, 8, 16, 17, 18]) {
      peak += estimateByHour[h];
    }
    return peak / total;
  }

  String get peakWindow => '${hourLabel(peakHour)}–${hourLabel(peakHour + 1)}';

  /// Rows for a CSV export.
  List<List<Object?>> toCsvRows() => [
        ['Corridor', 'Code', 'Riders per day (30-day average)', 'Busiest hour', 'Riders in busiest hour (est.)', 'App bookings ($windowDays days)', for (var h = 5; h <= 22; h++) '${hourLabel(h)} (est.)'],
        for (final c in corridors) [c.route.title, c.route.code, c.dailyTrips.round(), hourLabel(c.peakHour), c.peakRiders.round(), c.booked, for (var h = 5; h <= 22; h++) c.estimateByHour[h].round()],
      ];
}

/// "07:00" for hour 7.
String hourLabel(int h) => '${(h % 24).toString().padLeft(2, '0')}:00';

int _argMax(List<double> values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[best]) best = i;
  }
  return best;
}

/// Builds [DemandReport]s from route volumes, timetables and app bookings. Pure and deterministic.
abstract final class Demand {
  static const windowDays = 30;

  static bool _counts(Booking b, DateTime now) =>
      b.status != BookingStatus.cancelled && b.status != BookingStatus.declined && b.departureAt.isAfter(now.subtract(const Duration(days: windowDays))) && b.departureAt.isBefore(now.add(const Duration(days: 8)));

  /// Routes a scope is responsible for: its own, or (for a fleet owner) the routes its leased vehicles run on.
  static List<TransitRoute> routesFor(String? providerId, List<TransitRoute> routes, List<Vehicle> vehicles) {
    if (providerId == null) return routes;
    final own = [for (final r in routes) if (r.providerId == providerId) r];
    if (own.isNotEmpty) return own;
    final operators = {for (final v in vehicles) if (v.ownerId == providerId && v.operatorId != providerId) v.operatorId};
    return [for (final r in routes) if (operators.contains(r.providerId)) r];
  }

  static DemandReport build({required String scopeName, required List<TransitRoute> routes, required List<Booking> bookings, required DateTime now}) {
    final live = [for (final r in routes) if (r.active) r];
    final ids = {for (final r in live) r.id};
    final transit = [for (final b in bookings) if (b.kind == BookingKind.transit && b.routeId != null && _counts(b, now)) b];
    final scoped = [for (final b in transit) if (ids.contains(b.routeId)) b];

    // When riders book, city-wide (more data than one operator has), smoothed over neighbouring hours.
    final raw = List<double>.filled(24, 0);
    for (final b in transit) {
      raw[b.departureAt.hour] += 1;
    }
    final profile = List<double>.generate(24, (h) => 0.5 * raw[h] + 0.25 * (h > 0 ? raw[h - 1] : 0) + 0.25 * (h < 23 ? raw[h + 1] : 0));
    final profileTotal = profile.fold(0.0, (a, b) => a + b);
    // Trust in the booking profile grows with the number of bookings behind it.
    final confidence = transit.length / (transit.length + 10);

    bool isToday(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
    final corridors = <CorridorDemand>[];
    for (final r in live) {
      final deps = List<int>.filled(24, 0);
      for (final hhmm in r.departures) {
        final h = int.tryParse(hhmm.split(':').first) ?? -1;
        if (h >= 0 && h < 24) deps[h]++;
      }
      final own = [for (final b in scoped) if (b.routeId == r.id) b];
      final daily = r.monthlyTrips / 30;
      if (daily == 0 && own.isEmpty) continue;
      final booked = List<int>.filled(24, 0);
      for (final b in own) {
        booked[b.departureAt.hour]++;
      }
      final totalDeps = deps.fold(0, (a, b) => a + b);
      final weights = List<double>.generate(24, (h) {
        if (deps[h] == 0) return 0;
        final share = profileTotal == 0 ? 0.0 : profile[h] / profileTotal;
        return deps[h] / totalDeps * (1 + confidence * 24 * share);
      });
      final weightTotal = weights.fold(0.0, (a, b) => a + b);
      final todays = [for (final b in own) if (isToday(b.createdAt)) b];
      corridors.add(CorridorDemand(
        route: r,
        dailyTrips: daily,
        departuresByHour: deps,
        estimateByHour: [for (final w in weights) weightTotal == 0 ? 0.0 : daily * w / weightTotal],
        bookedByHour: booked,
        bookedToday: todays.length,
        revenueToday: todays.fold(0, (s, b) => s + b.fare),
      ));
    }
    corridors.sort((a, b) => (b.dailyTrips + b.booked).compareTo(a.dailyTrips + a.booked));

    final pairs = <String, (String, String, int, int)>{};
    for (final b in scoped) {
      final key = '${b.origin}→${b.destination}';
      final cur = pairs[key] ?? (b.origin, b.destination, 0, 0);
      pairs[key] = (cur.$1, cur.$2, cur.$3 + 1, cur.$4 + b.fare);
    }
    final top = [for (final p in pairs.values) TripPair(origin: p.$1, destination: p.$2, bookings: p.$3, fares: p.$4)]..sort((a, b) => b.bookings.compareTo(a.bookings));

    return DemandReport(
      scopeName: scopeName,
      corridors: corridors,
      estimateByHour: [for (var h = 0; h < 24; h++) corridors.fold(0.0, (s, c) => s + c.estimateByHour[h])],
      bookedByHour: [for (var h = 0; h < 24; h++) corridors.fold(0, (s, c) => s + c.bookedByHour[h])],
      topTrips: top.take(6).toList(),
      bookingsUsed: transit.length,
      windowDays: windowDays,
    );
  }
}
