import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/partner_models.dart';
import 'assistant_tools.dart';

/// Answers common requests on the device when the AI service can't be reached
/// (no key configured, or no network). Uses the same tools as the AI, so bookings,
/// reminders and cards behave identically; only the wording is simpler.
class OfflineAssistant {
  OfflineAssistant(this.state, this.tools);
  final AppState state;
  final AssistantTools tools;

  Future<Map<String, dynamic>> _run(String name, [Map<String, dynamic> args = const {}]) async {
    final result = await tools.run(ToolCall(id: 'local', name: name, args: args));
    return result is Map<String, dynamic> ? result : Map<String, dynamic>.from(result as Map? ?? const {});
  }

  static final _fromTo = RegExp(r'from\s+(.+?)\s+to\s+(.+?)(?=\s+(?:at|by|tomorrow|today|now|tonight)\b|[?.!,]|$)', caseSensitive: false);
  static final _toOnly = RegExp(r'\bto\s+(?:the\s+)?([a-z0-9][a-z0-9 ]*?)(?=\s+(?:at|by|tomorrow|today|now|tonight)\b|[?.!,]|$)', caseSensitive: false);

  Future<String> answer(String message, {required bool partner}) async {
    final m = message.toLowerCase();
    return partner ? _partner(m) : _rider(message, m);
  }

  Future<String> _rider(String raw, String m) async {
    final next = state.upcomingTrips.where((b) => b.kind == BookingKind.transit).firstOrNull;

    if (RegExp(r'\b(sos|emergency|nearby|traffic|hospital|police|pharmacy|atm|map)\b').hasMatch(m)) {
      await _run('open_findme_map', {if (m.contains('hospital')) 'category': 'hospital', if (m.contains('police')) 'category': 'police'});
      return 'Opening the FindMe AI map for live traffic, places near you and SOS.';
    }
    if (m.contains('remind') || m.contains('when should i leave') || m.contains('leave for')) {
      if (next == null) return 'You have no upcoming bus or train trips. Book one and I will remind you when to leave.';
      final minutes = int.tryParse(RegExp(r'(\d{1,3})\s*(?:min|minute)').firstMatch(m)?.group(1) ?? '');
      final r = await _run('set_reminder', {'booking_id': next.id, if (minutes != null) 'minutes_before': minutes});
      final leave = r['leave_by'];
      return [
        'Your next trip is ${next.origin} → ${next.destination}, ${Fmt.dayTime(next.departureAt)}.',
        if (leave != null) 'Leave by $leave (about ${r['travel_minutes_to_stop']} min to the stop).',
        minutes != null ? 'I will remind you $minutes minutes before it departs.' : 'I set two reminders: 10 minutes before you need to leave, and when it is time to go.',
      ].join(' ');
    }
    if (m.contains('balance') || m.contains('wallet') || m.contains('tap card')) {
      final r = await _run('wallet_balance');
      return 'Your Tap Card ${r['card'] ?? ''} has ${Fmt.naira((r['balance_naira'] as num?)?.toInt() ?? 0)}.';
    }
    if (m.contains('my trips') || m.contains('my bookings') || m.contains('next trip')) {
      if (next == null) return 'You have no upcoming trips. Ask me to find a route and I can book it.';
      return 'Next: ${next.origin} → ${next.destination}, ${Fmt.dayTime(next.departureAt)}, seat ${next.seat ?? '-'}. Open My Trips for your ticket.';
    }
    final fromTo = _fromTo.firstMatch(raw);
    final to = fromTo?.group(2) ?? _toOnly.firstMatch(raw)?.group(1);
    if (RegExp(r'\b(shared|tag along|tag-along|lift|carpool)\b').hasMatch(m)) {
      final r = await _run('list_tag_along_rides', {if (to != null) 'destination': to.trim()});
      final rides = (r['rides'] as List? ?? const []).cast<Map>();
      if (rides.isEmpty) return 'No shared rides${to == null ? '' : ' to ${to.trim()}'} right now. Open Tag Along to offer one.';
      return 'Shared rides: ${rides.take(3).map((x) => '${x['host']} (${x['workplace']}) ${x['from']} → ${x['to']} at ${x['leaves']}, ${x['seats_left']} seats, ${Fmt.naira((x['cost_share'] as num).toInt())}').join('; ')}. Open Tag Along to join.';
    }
    if (RegExp(r'\b(electric|ev|car|taxi|cab)\b').hasMatch(m)) {
      if (fromTo != null) {
        final r = await _run('book_electric_ride', {'pickup': fromTo.group(1)!.trim(), 'dropoff': fromTo.group(2)!.trim()});
        if (r['booked'] == true) return 'Booked. Your driver ${r['driver'] ?? ''} arrives in about ${r['eta_min']} min. Your ticket is in My Trips.';
        if (r['declined'] == true) return 'No problem, nothing was booked.';
        return '${r['error'] ?? 'I could not book that car.'}';
      }
      final r = await _run('list_electric_cars');
      final cars = (r['cars'] as List? ?? const []).cast<Map>();
      if (cars.isEmpty) return 'No cars are free right now. Try again in a few minutes.';
      return '${cars.length} cars are free: ${cars.take(3).map((c) => '${c['model']} in ${c['area']}').join(', ')}. Say "book an electric car from Wuse 2 to Jabi" and I will book it.';
    }
    final r = await _run('search_routes', {if (fromTo != null) 'from': fromTo.group(1)!.trim(), if (to != null) 'to': to.trim(), if (fromTo == null && to == null) 'query': raw});
    final routes = (r['routes'] as List? ?? const []).cast<Map>();
    if (routes.isEmpty) return 'I could not find a route for that. Try a place like Wuse, Maitama, Gwarinpa, Kubwa or Nyanya.';
    final first = routes.first;
    return 'Best match: ${first['name'] ?? first['code']}, ${Fmt.naira((first['fare_naira'] as num?)?.toInt() ?? 0)}, about ${first['duration_min'] ?? '-'} min. Tap a route above to pick a departure and book.';
  }

  Future<String> _partner(String m) async {
    final user = state.user!;
    final scope = user.role.canVerify ? null : user.providerId;
    final report = state.insightsFor(scope);
    if (m.contains('review') || m.contains('waiting') || m.contains('application') || m.contains('verif')) {
      final open = state.partnerApplications.where((a) => a.status.isOpen).toList();
      final pendingVehicles = state.vehicles.where((v) => v.verification == Verification.pending).length;
      return '${open.length} partner application${open.length == 1 ? '' : 's'} waiting${open.isEmpty ? '' : ' (${open.map((a) => a.displayName).join(', ')})'} and $pendingVehicles vehicle${pendingVehicles == 1 ? '' : 's'} pending verification. Open Partner applications to review.';
    }
    if (m.contains('attention') || m.contains('vehicle') || m.contains('fleet') || m.contains('idle')) {
      if (report.idleVehicles.isEmpty) return 'All ${report.vehicles.length} vehicles are on the road. Fleet utilisation is ${(report.utilisation * 100).round()}%.';
      return '${report.idleVehicles.length} vehicles are off the road: ${report.idleVehicles.take(4).map((v) => '${v.displayName} (${v.status.label})').join(', ')}. That costs about ${Fmt.naira(report.idleCostPerMonth)} a month in lost income.';
    }
    if (m.contains('demand') || m.contains('route') || m.contains('busiest') || m.contains('area')) {
      final top = report.areas.take(3).map((a) => '${a.name} (${Fmt.count(a.trips)} trips)').join(', ');
      final best = report.routeIncome.firstOrNull;
      return 'Highest demand: $top.${best == null ? '' : ' Top route: ${best.route.title}, ${Fmt.naira(best.monthlyRevenue)} a month, ~${best.tripsPerDeparture.round()} riders per departure.'} Open AI insights for the map and live traffic.';
    }
    return '${report.scopeName}: ${Fmt.naira(report.monthlyRevenue)} this month, ${Fmt.naira(report.revenueToday)} and ${report.bookingsToday} bookings today. ${report.vehicles.length} vehicles, ${(report.utilisation * 100).round()}% working.${report.opportunities.isEmpty ? '' : ' Top opportunity: ${report.opportunities.first.title}.'}';
  }
}
