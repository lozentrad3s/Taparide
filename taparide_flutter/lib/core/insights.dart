import 'format.dart';
import 'models.dart';

/// A proactive suggestion on the rider's home screen.
class RideSuggestion {
  const RideSuggestion({required this.route, required this.departure, required this.title, required this.reason});
  final TransitRoute route;
  final DateTime departure;
  final String title;
  final String reason;
}

/// Learns the rider's regular trips from their history and suggests booking the next one early.
/// Pure and deterministic, so it is testable and needs no network.
abstract final class RideInsights {
  static bool _isPeak(DateTime d) => (d.hour >= 6 && d.hour < 9) || (d.hour >= 16 && d.hour < 19);

  static List<RideSuggestion> suggestions({required List<Booking> bookings, required List<TransitRoute> routes, required DateTime now, int limit = 2}) {
    final byRoute = {for (final r in routes) r.id: r};
    final recent = [
      for (final b in bookings)
        if (b.kind == BookingKind.transit && b.routeId != null && b.status != BookingStatus.cancelled && now.difference(b.departureAt).inDays < 45) b,
    ];

    // Group by route + time of day; a "habit" is the same trip on at least two different days.
    final habits = <String, List<Booking>>{};
    for (final b in recent) {
      final key = '${b.routeId}@${b.departureAt.hour}:${b.departureAt.minute ~/ 30}';
      habits.putIfAbsent(key, () => []).add(b);
    }

    final result = <RideSuggestion>[];
    final ranked = habits.values.where((list) => {for (final b in list) '${b.departureAt.year}-${b.departureAt.month}-${b.departureAt.day}'}.length >= 2).toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final list in ranked) {
      final route = byRoute[list.first.routeId];
      if (route == null || !route.active) continue;
      final usual = list.first.departureAt;
      final usualHhmm = '${usual.hour.toString().padLeft(2, '0')}:${usual.minute.toString().padLeft(2, '0')}';
      final next = _nextOccurrence(route, usualHhmm, now);
      if (next == null) continue;
      final alreadyBooked = bookings.any((b) => b.routeId == route.id && b.status.isOpen && b.departureAt == next);
      if (alreadyBooked) continue;
      final weekdays = list.map((b) => Fmt.weekday(b.departureAt)).toSet().join(', ');
      result.add(RideSuggestion(
        route: route,
        departure: next,
        title: 'Your usual ${Fmt.time(next)} ${route.name ?? '${route.origin} – ${route.destination}'}',
        reason: _isPeak(next)
            ? 'You took it ${list.length} times recently ($weekdays). Peak-hour seats go first, so book now.'
            : 'You took it ${list.length} times recently ($weekdays).',
      ));
      if (result.length >= limit) break;
    }
    return result;
  }

  /// The next weekday departure at [hhmm] (today if still ahead, else the next working day).
  static DateTime? _nextOccurrence(TransitRoute route, String hhmm, DateTime now) {
    if (!route.departures.contains(hhmm)) return null;
    final parts = hhmm.split(':');
    for (var add = 0; add < 7; add++) {
      final day = DateTime(now.year, now.month, now.day + add, int.parse(parts[0]), int.parse(parts[1]));
      if (day.weekday >= DateTime.saturday) continue;
      if (day.isAfter(now.add(const Duration(minutes: 20)))) return day;
    }
    return null;
  }
}
