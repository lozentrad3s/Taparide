import 'dart:math';

import 'models.dart';

/// Whether a fleet driver may work: suspended drivers keep their login but lose their vehicle.
enum FleetDriverStatus { active, suspended }

extension FleetDriverStatusX on FleetDriverStatus {
  String get label => switch (this) {
        FleetDriverStatus.active => 'Active',
        FleetDriverStatus.suspended => 'Suspended',
      };
}

/// What a driver can do to a booking on their vehicle.
/// [accept] takes a car ride or boards a bus rider; [complete] ends it.
enum DriverBookingAction { accept, complete }

/// A driver employed by a fleet owner or a bus/EV operator, and what they drive today.
class FleetDriver {
  const FleetDriver({
    required this.id,
    required this.providerId,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.licenceNumber,
    required this.status,
    required this.createdAt,
    this.userId,
    this.vehicleId,
    this.routeId,
  });

  final String id;

  /// The company that employs the driver (fleet owner or operator).
  final String providerId;

  /// The driver's own Tap A Ride login, once they have one.
  final String? userId;
  final String fullName;
  final String phone;
  final String email;
  final String licenceNumber;
  final String? vehicleId;
  final String? routeId;
  final FleetDriverStatus status;
  final DateTime createdAt;

  bool get active => status == FleetDriverStatus.active;
  bool get hasLogin => userId != null;
  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  FleetDriver copyWith({String? userId, String? vehicleId, String? routeId, bool clearAssignment = false, bool clearRoute = false, FleetDriverStatus? status}) => FleetDriver(
        id: id,
        providerId: providerId,
        userId: userId ?? this.userId,
        fullName: fullName,
        phone: phone,
        email: email,
        licenceNumber: licenceNumber,
        vehicleId: clearAssignment ? null : vehicleId ?? this.vehicleId,
        routeId: clearAssignment || clearRoute ? null : routeId ?? this.routeId,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'provider_id': providerId,
        'user_id': userId,
        'full_name': fullName,
        'phone': phone,
        'email': email,
        'licence_number': licenceNumber,
        'vehicle_id': vehicleId,
        'route_id': routeId,
        'status': status.wire,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory FleetDriver.fromJson(Map<String, dynamic> json) => FleetDriver(
        id: json['id'] as String,
        providerId: json['provider_id'] as String,
        userId: json['user_id'] as String?,
        fullName: (json['full_name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        licenceNumber: (json['licence_number'] as String?) ?? '',
        vehicleId: json['vehicle_id'] as String?,
        routeId: json['route_id'] as String?,
        status: json['status'] == 'suspended' ? FleetDriverStatus.suspended : FleetDriverStatus.active,
        createdAt: json['created_at'] is String ? DateTime.parse(json['created_at'] as String).toLocal() : DateTime.now(),
      );
}

/// Form checks shared by the dashboard form and the demo backend (the server repeats them).
abstract final class FleetDriverRules {
  static String? name(String v) => v.trim().length < 2 ? "Enter the driver's full name." : null;
  static String? email(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Enter a valid email address.';
  static String? phone(String v) => v.replaceAll(RegExp(r'\D'), '').length < 10 ? 'Enter a valid phone number.' : null;
  static String? licence(String v) => v.replaceAll(RegExp(r'\s'), '').length < 6 ? "Enter the driver's licence number." : null;
}

/// Riders waiting at one stop in one hour.
class DemandCell {
  const DemandCell({required this.stop, required this.hour, required this.riders, required this.booked});
  final RouteStop stop;
  final int hour;

  /// Estimated riders boarding (route ridership spread over stops and hours, plus real bookings).
  final int riders;

  /// Of which booked on Tap A Ride for this vehicle.
  final int booked;
}

/// Where and when riders board along a driver's route: a stop × hour grid.
class RouteDemand {
  const RouteDemand({required this.route, required this.hours, required this.cells, required this.peak});
  final TransitRoute route;
  final List<int> hours;
  final List<DemandCell> cells;
  final int peak;

  static const firstHour = 5;
  static const lastHour = 21;

  DemandCell cell(int stopIndex, int hour) => cells[stopIndex * hours.length + (hour - firstHour)];
  int atStop(int stopIndex, int hour) => cell(stopIndex, hour).riders;

  /// Total riders across the route in [hour].
  int inHour(int hour) => [for (var s = 0; s < route.stops.length; s++) atStop(s, hour)].fold(0, (a, b) => a + b);

  /// The busiest hour of the day on this route.
  int get busiestHour => hours.reduce((a, b) => inHour(b) > inHour(a) ? b : a);

  /// Builds the grid from the route's 30-day ridership and a typical Abuja weekday
  /// (morning peak into town, evening peak back out), plus the real bookings riders made.
  static RouteDemand build({required TransitRoute route, required List<Booking> bookings}) {
    final hours = [for (var h = firstHour; h <= lastHour; h++) h];
    final perDay = max(route.monthlyTrips, 3000) / 30;
    final stops = route.stops;
    final n = stops.length;
    final cells = <DemandCell>[];
    var peak = 1;
    final shares = [for (final h in hours) _hourShare(h)];
    final shareTotal = shares.fold<double>(0, (a, b) => a + b);
    for (var s = 0; s < n; s++) {
      // Outer stops (suburbs) fill the morning buses; inner stops the evening ones.
      final outer = n == 1 ? 1.0 : 1 - s / (n - 1);
      for (var i = 0; i < hours.length; i++) {
        final h = hours[i];
        final morning = h < 13;
        final stopWeight = (morning ? 0.4 + outer : 0.4 + (1 - outer)) / (0.9 * n);
        final booked = bookings.where((b) => b.status != BookingStatus.cancelled && b.departureAt.hour == h && (b.origin == stops[s].name || (s == 0 && !stops.any((x) => x.name == b.origin)))).length;
        final riders = (perDay * shares[i] / shareTotal * stopWeight / 6).round() + booked;
        peak = max(peak, riders);
        cells.add(DemandCell(stop: stops[s], hour: h, riders: riders, booked: booked));
      }
    }
    return RouteDemand(route: route, hours: hours, cells: cells, peak: peak);
  }

  // Share of a weekday's riders by hour (Abuja commuter pattern: 6–9 am and 4–7 pm peaks).
  static double _hourShare(int h) => switch (h) {
        5 => 2.5,
        6 => 7,
        7 => 10,
        8 => 8.5,
        9 => 5,
        10 || 11 || 12 || 13 || 14 => 3.5,
        15 => 4.5,
        16 => 7.5,
        17 => 10,
        18 => 8,
        19 => 5,
        20 => 3,
        _ => 1.5,
      };
}
