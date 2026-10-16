import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/partner_models.dart';
import '../../core/places.dart';

/// Something the assistant did that the chat should show as a card.
sealed class AssistantCard {
  const AssistantCard();
}

class RoutesCard extends AssistantCard {
  const RoutesCard(this.routes);
  final List<TransitRoute> routes;
}

class BookingCard extends AssistantCard {
  const BookingCard(this.booking);
  final Booking booking;
}

class TripPlanCard extends AssistantCard {
  const TripPlanCard({required this.from, required this.to, required this.plan});
  final String from;
  final String to;
  final RoadPlan plan;
}

/// Runs the assistant's tool calls inside the app, with the signed-in user's own permissions.
/// Anything that spends money or cancels asks the user first.
class AssistantTools {
  AssistantTools(this.state, this.context, {required this.onCard});

  final AppState state;
  final BuildContext context;
  final void Function(AssistantCard card) onCard;

  static String label(String tool) => switch (tool) {
        'search_routes' => 'Finding routes',
        'get_departures' => 'Checking departures',
        'plan_road_trip' => 'Checking live road time',
        'book_seat' => 'Booking your seat',
        'list_my_trips' => 'Looking at your trips',
        'cancel_trip' => 'Cancelling',
        'wallet_balance' => 'Checking your Tap Card',
        'set_reminder' => 'Setting a reminder',
        'list_electric_cars' => 'Finding cars nearby',
        'book_electric_ride' => 'Booking your car',
        'list_tag_along_rides' => 'Looking for shared rides',
        'open_findme_map' => 'Opening the map',
        'dashboard_summary' => 'Reading your dashboard',
        'list_vehicles' => 'Checking vehicles',
        'route_performance' => 'Analysing routes',
        'recent_bookings' => 'Reading bookings',
        'verification_queue' => 'Checking the review queue',
        _ => 'Working',
      };

  Future<Object?> run(ToolCall call) async {
    final a = call.args;
    switch (call.name) {
      case 'search_routes':
        final found = _searchRoutes(a['from'] as String?, a['to'] as String?, a['query'] as String?);
        if (found.isNotEmpty) onCard(RoutesCard(found.take(3).toList()));
        return {'routes': [for (final r in found.take(6)) _route(r)]};
      case 'get_departures':
        final route = state.routeById('${a['route_id']}');
        if (route == null) return {'error': 'Unknown route id'};
        final after = DateTime.tryParse('${a['after'] ?? ''}') ?? state.now;
        final count = ((a['count'] as num?)?.toInt() ?? 5).clamp(1, 10);
        return {'route_id': route.id, 'departures': [for (final d in route.upcomingDepartures(after, count: count)) _time(d)]};
      case 'plan_road_trip':
        return _planTrip('${a['from'] ?? 'my location'}', '${a['to'] ?? ''}', (a['mode'] as String?) ?? 'driving');
      case 'book_seat':
        return _bookSeat('${a['route_id']}', '${a['departure']}', a['payment'] == 'qr' ? PaymentMethod.qr : PaymentMethod.tapCard);
      case 'list_my_trips':
        final upcomingOnly = a['upcoming_only'] == true;
        final trips = upcomingOnly ? state.upcomingTrips : state.myBookings.take(12).toList();
        return {'trips': [for (final b in trips) _booking(b)]};
      case 'cancel_trip':
        return _cancel('${a['booking_id']}');
      case 'wallet_balance':
        return {'balance_naira': state.wallet?.balance, 'card': state.wallet?.maskedCard};
      case 'set_reminder':
        final booking = state.bookingById('${a['booking_id']}');
        if (booking == null) return {'error': 'Unknown booking id'};
        final minutes = (a['minutes_before'] as num?)?.toInt();
        final plan = await state.scheduleLeaveReminders(booking, minutesBefore: minutes?.clamp(5, 120));
        return {'reminder_set': true, if (plan != null) 'leave_by': Fmt.time(plan.leaveAt), if (plan != null) 'travel_minutes_to_stop': plan.travelMinutes};
      case 'list_electric_cars':
        return {
          'cars': [
            for (final v in state.availableEvs.where((v) => v.status == VehicleStatus.active))
              {'vehicle_id': v.id, 'model': v.model, 'plate': v.plate, 'electric': v.electric, 'battery_pct': v.batteryPct, 'area': v.area, 'base_fare': v.baseFare, 'seats': v.capacity},
          ],
        };
      case 'book_electric_ride':
        return _bookCar(a['vehicle_id'] as String?, '${a['pickup']}', '${a['dropoff']}');
      case 'list_tag_along_rides':
        final dest = (a['destination'] as String?)?.toLowerCase();
        return {
          'rides': [
            for (final r in state.rides)
              if (dest == null || r.destination.toLowerCase().contains(dest))
                {'host': r.hostName, 'workplace': r.hostOrg, 'from': r.origin, 'to': r.destination, 'leaves': _time(r.departAt), 'seats_left': r.seatsLeft, 'cost_share': r.costShare},
          ],
        };
      case 'open_findme_map':
        if (context.mounted) context.push(Uri(path: '/nearby', queryParameters: {if (a['category'] != null) 'c': '${a['category']}'}).toString());
        return {'opened': true};
      // ---- partner tools
      case 'dashboard_summary':
        return _dashboard();
      case 'list_vehicles':
        return {
          'vehicles': [
            for (final v in _myVehicles())
              if ((a['status'] == null || v.status.wire == a['status']) && (a['verification'] == null || v.verification.wire == a['verification']))
                {'plate': v.plate, 'kind': v.kind.label, 'model': v.model, 'status': v.status.label, 'register': v.verification.label, 'month_earnings': v.monthEarnings, 'driver': v.driverName, 'battery_pct': v.batteryPct},
          ].take(40).toList(),
        };
      case 'route_performance':
        return {'routes': [for (final r in _myRoutes()) {..._route(r), 'trips_30d': r.monthlyTrips, 'bookings_today': _bookingsToday(r.id)}]};
      case 'recent_bookings':
        final limit = ((a['limit'] as num?)?.toInt() ?? 10).clamp(1, 30);
        return {'bookings': [for (final b in state.partnerBookings.take(limit)) _booking(b)]};
      case 'verification_queue':
        return {
          'providers_pending': [for (final p in state.providers.where((p) => p.status == Verification.pending)) p.name],
          'vehicles_pending': [for (final v in state.vehicles.where((v) => v.verification == Verification.pending)) v.displayName],
          'applications_open': [for (final x in state.partnerApplications.where((x) => x.status.isOpen)) '${x.displayName} (${x.type.label}, AI check: ${x.aiCheck?.overall ?? 'not run'})'],
        };
    }
    return {'error': 'Unknown tool ${call.name}'};
  }

  // ---------------------------------------------------------------- rider helpers

  List<TransitRoute> _searchRoutes(String? from, String? to, String? query) {
    bool stopMatches(RouteStop s, String q) => s.name.toLowerCase().contains(q) || q.contains(s.name.toLowerCase());
    final f = from?.trim().toLowerCase(), t = to?.trim().toLowerCase(), q = query?.trim().toLowerCase();
    final routes = state.bookableRoutes;
    final scored = <(TransitRoute, int)>[];
    for (final r in routes) {
      var score = 0;
      final fi = f == null || f.isEmpty ? -1 : r.stops.indexWhere((s) => stopMatches(s, f));
      final ti = t == null || t.isEmpty ? -1 : r.stops.lastIndexWhere((s) => stopMatches(s, t));
      if (fi >= 0) score += 2;
      if (ti >= 0) score += 2;
      if (fi >= 0 && ti >= 0 && fi < ti) score += 3;
      if (q != null && q.isNotEmpty) {
        final hay = '${r.name ?? ''} ${r.code} ${r.stops.map((s) => s.name).join(' ')}'.toLowerCase();
        if (q.split(RegExp(r'\s+')).any((w) => w.length > 2 && hay.contains(w))) score += 1;
      }
      if (score > 0) scored.add((r, score));
    }
    scored.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : b.$1.monthlyTrips.compareTo(a.$1.monthlyTrips));
    return [for (final s in scored) s.$1];
  }

  Map<String, Object?> _route(TransitRoute r) => {
        'route_id': r.id,
        'code': r.code,
        'name': r.name ?? '${r.origin} – ${r.destination}',
        'stops': [for (final s in r.stops) s.name],
        'fare_naira': r.fare,
        'duration_min': r.durationMin,
        'mode': r.mode.label,
        'next_departures': [for (final d in r.upcomingDepartures(state.now, count: 4)) _time(d)],
      };

  Map<String, Object?> _booking(Booking b) => {
        'booking_id': b.id,
        'what': b.kind.label,
        'from': b.origin,
        'to': b.destination,
        'when': _time(b.departureAt),
        'fare_naira': b.fare,
        'status': b.status.label,
        if (b.seat != null) 'seat': b.seat,
        'ticket': b.ticketCode,
        if (b.passengerName.isNotEmpty) 'passenger': b.passengerName,
      };

  Map<String, String> _time(DateTime d) => {'iso': d.toIso8601String(), 'local': Fmt.dayTime(d)};

  Future<Map<String, Object?>> _planTrip(String from, String to, String mode) async {
    LatLng? a;
    String fromName = from;
    if (from.toLowerCase().contains('my location') || from.toLowerCase() == 'here') {
      a = await currentLocation();
      if (a != null && !inFct(a)) a = null;
      fromName = 'your location';
      if (a == null) return {'error': 'Location is off or outside Abuja. Ask the rider where they are starting from.'};
    } else {
      final p = resolvePlace(from, routes: state.routes);
      if (p == null) return {'error': 'Unknown place "$from". Ask for a nearby area or landmark.'};
      a = p.point;
      fromName = p.name;
    }
    final q = resolvePlace(to, routes: state.routes);
    if (q == null) return {'error': 'Unknown place "$to". Ask for a nearby area or landmark.'};
    final plan = await state.api.roadRoute(a, q.point, mode: mode == 'walking' ? 'walking' : 'driving');
    if (plan == null) {
      final km = straightKm(a, q.point) * 1.3;
      return {'from': fromName, 'to': q.name, 'estimated_km': km.toStringAsFixed(1), 'estimated_minutes': (km * 2.4).round(), 'note': 'Live routing unavailable; estimate only.'};
    }
    onCard(TripPlanCard(from: fromName, to: q.name, plan: plan));
    return {
      'from': fromName,
      'to': q.name,
      'distance': plan.distanceText,
      'minutes': plan.minutes,
      'with_traffic': plan.trafficDurationS != null,
      'via': plan.label,
      'directions': plan.steps.take(6).toList(),
      'transit_options': [for (final r in _searchRoutes(fromName, q.name, null).take(3)) _route(r)],
    };
  }

  Future<bool> _confirm({required String title, required String body, required String action}) async {
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<Map<String, Object?>> _bookSeat(String routeId, String departureIso, PaymentMethod method) async {
    final route = state.routeById(routeId);
    if (route == null) return {'error': 'Unknown route id'};
    var departure = DateTime.tryParse(departureIso);
    if (departure == null) return {'error': 'Departure must be an ISO date-time'};
    if (departure.isUtc) departure = departure.toLocal();
    // Snap to a real departure (the model may round times).
    final options = route.upcomingDepartures(departure.subtract(const Duration(minutes: 1)), count: 1);
    if (options.isEmpty) return {'error': 'No departure at that time'};
    departure = options.first;
    final ok = await _confirm(
      title: 'Book this seat?',
      body: '${route.name ?? '${route.origin} → ${route.destination}'}\n${Fmt.dayTime(departure)}\n${Fmt.naira(route.fare)} from your Tap Card (balance ${Fmt.naira(state.wallet?.balance ?? 0)}).',
      action: 'Pay ${Fmt.naira(route.fare)}',
    );
    if (!ok) return {'declined': true, 'message': 'The rider chose not to book.'};
    try {
      final booking = await state.bookTransit(route, departure, method);
      onCard(BookingCard(booking));
      return {'booked': true, ..._booking(booking), 'balance_after': state.wallet?.balance};
    } catch (e) {
      return {'error': '$e'};
    }
  }

  Future<Map<String, Object?>> _cancel(String bookingId) async {
    final booking = state.bookingById(bookingId);
    if (booking == null || booking.userId != state.user?.id) return {'error': 'Unknown booking id'};
    final ok = await _confirm(title: 'Cancel this trip?', body: '${booking.origin} → ${booking.destination}, ${Fmt.dayTime(booking.departureAt)}.', action: 'Cancel trip');
    if (!ok) return {'declined': true};
    try {
      await state.cancelBooking(booking);
      return {'cancelled': true, 'balance_after': state.wallet?.balance};
    } catch (e) {
      return {'error': '$e'};
    }
  }

  Future<Map<String, Object?>> _bookCar(String? vehicleId, String pickup, String dropoff) async {
    final from = resolvePlace(pickup, routes: state.routes), to = resolvePlace(dropoff, routes: state.routes);
    if (from == null || to == null) return {'error': 'Pickup and drop-off must be Abuja areas such as ${evPlaceNames.take(5).join(', ')}.'};
    final free = state.availableEvs.where((v) => v.status == VehicleStatus.active).toList();
    if (free.isEmpty) return {'error': 'No cars are free right now.'};
    final car = free.where((v) => v.id == vehicleId).firstOrNull ?? (free..sort((a, b) => carEta(a, from.name).compareTo(carEta(b, from.name)))).first;
    final km = straightKm(from.point, to.point) * 1.3;
    final fare = carFare(car, km);
    final ok = await _confirm(
      title: 'Book ${car.model}?',
      body: '${from.name} → ${to.name} · about ${km.toStringAsFixed(1)} km\nPickup in about ${carEta(car, from.name)} min · ${car.plate}\n${Fmt.naira(fare)} from your Tap Card.',
      action: 'Pay ${Fmt.naira(fare)}',
    );
    if (!ok) return {'declined': true};
    try {
      final booking = await state.bookElectric(car, pickup: from.name, dropoff: to.name, fare: fare, method: PaymentMethod.tapCard);
      onCard(BookingCard(booking));
      return {'booked': true, ..._booking(booking), 'driver': car.driverName, 'eta_min': carEta(car, from.name)};
    } catch (e) {
      return {'error': '$e'};
    }
  }

  // ---------------------------------------------------------------- partner helpers

  Iterable<Vehicle> _myVehicles() {
    final me = state.user;
    if (me == null) return const [];
    if (me.role.canVerify) return state.vehicles;
    return state.vehicles.where((v) => v.operatorId == me.providerId || v.ownerId == me.providerId);
  }

  Iterable<TransitRoute> _myRoutes() {
    final me = state.user;
    if (me == null) return const [];
    final list = me.role.canVerify ? state.routes : state.routes.where((r) => r.providerId == me.providerId);
    return list.toList()..sort((a, b) => b.monthlyTrips.compareTo(a.monthlyTrips));
  }

  int _bookingsToday(String routeId) {
    final now = state.now;
    return state.partnerBookings.where((b) => b.routeId == routeId && b.createdAt.day == now.day && b.createdAt.month == now.month).length;
  }

  Map<String, Object?> _dashboard() {
    final me = state.user!;
    if (me.role == UserRole.fleetOwner && me.providerId != null) {
      final d = state.fleetDashboard(me.providerId!);
      if (d == null) return {};
      return {'fleet': d.provider.name, 'vehicles': d.vehicles.length, 'active': d.active, 'maintenance': d.maintenance, 'inactive': d.inactive, 'revenue_month': d.revenue, 'bookings_today': d.bookingsToday};
    }
    if (me.role == UserRole.operator && me.providerId != null) {
      final d = state.operatorDashboard(me.providerId!);
      if (d == null) return {};
      return {'operator': d.provider.name, 'trips': d.totalTrips, 'revenue': d.revenue, 'routes': d.routes.length, 'vehicles': d.vehicles.length, 'bookings_today': d.bookingsToday, 'revenue_today': d.revenueToday};
    }
    final f = state.fctaDashboard();
    if (f == null) return {};
    return {
      'ridership_7d': f.totalRidership,
      'ridership_by_day': {for (var i = 0; i < f.dayLabels.length; i++) f.dayLabels[i]: f.ridershipByDay[i]},
      'verified_vehicles': f.verifiedVehicles,
      'active_routes': f.activeRoutes,
      'bookings_today': f.bookingsToday,
      'providers_pending': f.providersWith(Verification.pending),
      'applications_open': state.partnerApplications.where((a) => a.status.isOpen).length,
    };
  }
}
