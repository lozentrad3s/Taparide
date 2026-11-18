import 'package:flutter/material.dart';

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final value in values) {
    if (value.name == raw || _snake(value.name) == raw) return value;
  }
  return fallback;
}

/// camelCase -> snake_case, used for the Supabase column/enum values.
String _snake(String name) => name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

extension EnumWire on Enum {
  String get wire => _snake(name);
}

DateTime _date(Object? raw) => raw is String ? DateTime.parse(raw).toLocal() : DateTime.now();
int _int(Object? raw) => raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
double? _double(Object? raw) => raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');

// ---------------------------------------------------------------- accounts

enum UserRole { passenger, operator, fleetOwner, government, admin, eventPartner, fleetDriver }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.passenger => 'Passenger',
        UserRole.operator => 'Transport operator',
        UserRole.fleetOwner => 'Fleet owner',
        UserRole.government => 'Government / FCTA',
        UserRole.admin => 'Platform admin',
        UserRole.eventPartner => 'Event partner',
        UserRole.fleetDriver => 'Fleet driver',
      };

  IconData get icon => switch (this) {
        UserRole.passenger => Icons.person_outline_rounded,
        UserRole.operator => Icons.directions_bus_outlined,
        UserRole.fleetOwner => Icons.local_shipping_outlined,
        UserRole.government => Icons.account_balance_outlined,
        UserRole.admin => Icons.admin_panel_settings_outlined,
        UserRole.eventPartner => Icons.celebration_outlined,
        UserRole.fleetDriver => Icons.badge_outlined,
      };

  bool get isPartner => this != UserRole.passenger;
  bool get canVerify => this == UserRole.government || this == UserRole.admin;
}

enum Portal { passenger, partner }

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
    this.providerId,
    this.organisation,
    this.verified = true,
    DateTime? createdAt,
  }) : _createdAt = createdAt;

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final UserRole role;
  final String? providerId;

  /// Workplace, shown on Tag Along so colleagues can recognise each other.
  final String? organisation;
  final bool verified;
  final DateTime? _createdAt;

  DateTime get createdAt => _createdAt ?? DateTime(2026, 9, 1);
  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  AppUser copyWith({UserRole? role, String? providerId, bool clearProvider = false, String? organisation}) => AppUser(
        id: id,
        fullName: fullName,
        email: email,
        phone: phone,
        role: role ?? this.role,
        providerId: clearProvider ? null : providerId ?? this.providerId,
        organisation: organisation ?? this.organisation,
        verified: verified,
        createdAt: _createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'role': role.wire,
        'provider_id': providerId,
        'organisation': organisation,
        'verified': verified,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        fullName: (json['full_name'] as String?) ?? 'Rider',
        email: (json['email'] as String?) ?? '',
        phone: json['phone'] as String?,
        role: _enumByName(UserRole.values, json['role'], UserRole.passenger),
        providerId: json['provider_id'] as String?,
        organisation: json['organisation'] as String?,
        verified: (json['verified'] as bool?) ?? true,
        createdAt: _date(json['created_at']),
      );
}

// ---------------------------------------------------------------- providers

enum ProviderKind { busOperator, fleetOwner, rail, electric, shuttle, tricycle, privateDriver, eventOrganiser }

extension ProviderKindX on ProviderKind {
  String get label => switch (this) {
        ProviderKind.busOperator => 'Bus operator',
        ProviderKind.fleetOwner => 'Fleet owner',
        ProviderKind.rail => 'Rail operator',
        ProviderKind.electric => 'Electric vehicles',
        ProviderKind.shuttle => 'Shuttle service',
        ProviderKind.tricycle => 'Tricycle (keke) co-op',
        ProviderKind.privateDriver => 'Private driver',
        ProviderKind.eventOrganiser => 'Event organiser',
      };

  IconData get icon => switch (this) {
        ProviderKind.busOperator => Icons.directions_bus_rounded,
        ProviderKind.fleetOwner => Icons.local_shipping_rounded,
        ProviderKind.rail => Icons.tram_rounded,
        ProviderKind.electric => Icons.electric_car_rounded,
        ProviderKind.shuttle => Icons.airport_shuttle_rounded,
        ProviderKind.tricycle => Icons.electric_rickshaw_rounded,
        ProviderKind.privateDriver => Icons.drive_eta_rounded,
        ProviderKind.eventOrganiser => Icons.celebration_rounded,
      };
}

enum Verification { verified, pending, suspended }

extension VerificationX on Verification {
  String get label => switch (this) {
        Verification.verified => 'Verified',
        Verification.pending => 'Pending review',
        Verification.suspended => 'Suspended',
      };
}

class TransportProvider {
  const TransportProvider({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    required this.area,
    required this.contactName,
    required this.contactEmail,
    required this.joinedAt,
    this.description = '',
  });

  final String id;
  final String name;
  final ProviderKind kind;
  final Verification status;
  final String area;
  final String contactName;
  final String contactEmail;
  final DateTime joinedAt;
  final String description;

  TransportProvider copyWith({Verification? status}) => TransportProvider(
        id: id,
        name: name,
        kind: kind,
        status: status ?? this.status,
        area: area,
        contactName: contactName,
        contactEmail: contactEmail,
        joinedAt: joinedAt,
        description: description,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.wire,
        'status': status.wire,
        'area': area,
        'contact_name': contactName,
        'contact_email': contactEmail,
        'joined_at': joinedAt.toUtc().toIso8601String(),
        'description': description,
      };

  factory TransportProvider.fromJson(Map<String, dynamic> json) => TransportProvider(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: _enumByName(ProviderKind.values, json['kind'], ProviderKind.busOperator),
        status: _enumByName(Verification.values, json['status'], Verification.pending),
        area: (json['area'] as String?) ?? 'FCT',
        contactName: (json['contact_name'] as String?) ?? '',
        contactEmail: (json['contact_email'] as String?) ?? '',
        joinedAt: _date(json['joined_at']),
        description: (json['description'] as String?) ?? '',
      );
}

// ---------------------------------------------------------------- routes

enum TransitMode { bus, rail, shuttle }

extension TransitModeX on TransitMode {
  String get label => switch (this) {
        TransitMode.bus => 'Bus',
        TransitMode.rail => 'Metro rail',
        TransitMode.shuttle => 'E-shuttle',
      };

  IconData get icon => switch (this) {
        TransitMode.bus => Icons.directions_bus_rounded,
        TransitMode.rail => Icons.tram_rounded,
        TransitMode.shuttle => Icons.airport_shuttle_rounded,
      };
}

class RouteStop {
  const RouteStop(this.name, this.lat, this.lng);
  final String name;
  final double lat;
  final double lng;

  Map<String, Object?> toJson() => {'name': name, 'lat': lat, 'lng': lng};
  factory RouteStop.fromJson(Map<String, dynamic> json) =>
      RouteStop(json['name'] as String, _double(json['lat']) ?? 9.06, _double(json['lng']) ?? 7.49);
}

class TransitRoute {
  const TransitRoute({
    required this.id,
    required this.providerId,
    required this.code,
    required this.stops,
    required this.fare,
    required this.durationMin,
    required this.mode,
    required this.departures,
    required this.monthlyTrips,
    this.active = true,
    this.name,
    this.servedBy = const [],
  });

  final String id;
  final String providerId;
  final String code;
  final List<RouteStop> stops;
  final int fare;
  final int durationMin;
  final TransitMode mode;

  /// Daily departure times as `HH:mm`.
  final List<String> departures;

  /// Platform-wide trips in the last 30 days (demo baseline for FCTA ranking).
  final int monthlyTrips;
  final bool active;

  /// Branded line name, e.g. "Abuja Metro Rail".
  final String? name;

  /// Public information on who runs vehicles on this corridor today (not Tap A Ride partners).
  final List<CorridorOperator> servedBy;

  String get origin => stops.first.name;
  String get destination => stops.last.name;
  String get title => name ?? '$origin – $destination';

  /// False for a real corridor no Tap A Ride operator runs yet (seat booking opens when one joins).
  bool get hasOperator => providerId.isNotEmpty;

  TransitRoute copyWith({int? fare, bool? active, List<CorridorOperator>? servedBy}) => TransitRoute(
        id: id,
        providerId: providerId,
        code: code,
        stops: stops,
        fare: fare ?? this.fare,
        durationMin: durationMin,
        mode: mode,
        departures: departures,
        monthlyTrips: monthlyTrips,
        active: active ?? this.active,
        name: name,
        servedBy: servedBy ?? this.servedBy,
      );

  /// Next departures from [now] (wraps to tomorrow when the day is over).
  List<DateTime> upcomingDepartures(DateTime now, {int count = 4}) {
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(DateTime day, String hhmm) {
      final parts = hhmm.split(':');
      return day.add(Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])));
    }

    final result = <DateTime>[
      for (final d in departures) if (at(today, d).isAfter(now)) at(today, d),
    ];
    final tomorrow = today.add(const Duration(days: 1));
    for (final d in departures) {
      if (result.length >= count) break;
      result.add(at(tomorrow, d));
    }
    return result.take(count).toList();
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'provider_id': providerId,
        'code': code,
        'stops': [for (final s in stops) s.toJson()],
        'fare': fare,
        'duration_min': durationMin,
        'mode': mode.wire,
        'departures': departures,
        'monthly_trips': monthlyTrips,
        'active': active,
        'name': name,
        'served_by': [for (final o in servedBy) o.toJson()],
      };

  factory TransitRoute.fromJson(Map<String, dynamic> json) => TransitRoute(
        id: json['id'] as String,
        // Real corridors with no Tap A Ride operator yet have no provider: riders can see them, not book them.
        providerId: (json['provider_id'] as String?) ?? '',
        code: (json['code'] as String?) ?? '',
        stops: [for (final s in (json['stops'] as List? ?? const [])) RouteStop.fromJson(Map<String, dynamic>.from(s as Map))],
        fare: _int(json['fare']),
        durationMin: _int(json['duration_min']),
        mode: _enumByName(TransitMode.values, json['mode'], TransitMode.bus),
        departures: [for (final d in (json['departures'] as List? ?? const [])) '$d'],
        monthlyTrips: _int(json['monthly_trips']),
        active: (json['active'] as bool?) ?? true,
        name: json['name'] as String?,
        servedBy: [for (final o in (json['served_by'] as List? ?? const [])) CorridorOperator.fromJson(Map<String, dynamic>.from(o as Map))],
      );
}

/// A real operator or service reported on a corridor, from public sources. Not a Tap A Ride partner.
class CorridorOperator {
  const CorridorOperator({required this.name, required this.type, required this.source, required this.publisher, required this.asOf, this.note, this.uncertain = false});

  final String name;

  /// Vehicle or service type, e.g. "CNG bus", "Diesel bus", "Light rail".
  final String type;
  final String? note;

  /// Link to the report this entry is based on.
  final String source;
  final String publisher;

  /// Month the source reported it, e.g. "Oct 2026".
  final String asOf;

  /// True when the report is older or does not confirm the service still runs this exact corridor.
  final bool uncertain;

  Map<String, Object?> toJson() => {'name': name, 'type': type, 'note': note, 'source': source, 'publisher': publisher, 'as_of': asOf, if (uncertain) 'uncertain': true};

  factory CorridorOperator.fromJson(Map<String, dynamic> json) => CorridorOperator(
        name: (json['name'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        note: json['note'] as String?,
        source: (json['source'] as String?) ?? '',
        publisher: (json['publisher'] as String?) ?? '',
        asOf: (json['as_of'] as String?) ?? '',
        uncertain: (json['uncertain'] as bool?) ?? false,
      );
}

// ---------------------------------------------------------------- vehicles

enum VehicleKind { bus, minibus, train, evCar, evShuttle, evKeke, car }

extension VehicleKindX on VehicleKind {
  String get label => switch (this) {
        VehicleKind.bus => 'Bus',
        VehicleKind.minibus => 'Minibus',
        VehicleKind.train => 'Metro trainset',
        VehicleKind.evCar => 'Electric car',
        VehicleKind.evShuttle => 'Electric shuttle',
        VehicleKind.evKeke => 'Electric keke',
        VehicleKind.car => 'Car',
      };

  IconData get icon => switch (this) {
        VehicleKind.bus => Icons.directions_bus_rounded,
        VehicleKind.minibus => Icons.airport_shuttle_rounded,
        VehicleKind.train => Icons.tram_rounded,
        VehicleKind.evCar => Icons.electric_car_rounded,
        VehicleKind.evShuttle => Icons.airport_shuttle_rounded,
        VehicleKind.evKeke => Icons.electric_rickshaw_rounded,
        VehicleKind.car => Icons.directions_car_rounded,
      };

  bool get isElectric => this == VehicleKind.evCar || this == VehicleKind.evShuttle || this == VehicleKind.evKeke || this == VehicleKind.train;

  /// Cars riders can book door to door (electric cars and verified private drivers).
  bool get isBookableCar => this == VehicleKind.evCar || this == VehicleKind.car;
}

enum VehicleStatus { active, onTrip, charging, maintenance, inactive }

extension VehicleStatusX on VehicleStatus {
  String get label => switch (this) {
        VehicleStatus.active => 'Available',
        VehicleStatus.onTrip => 'On trip',
        VehicleStatus.charging => 'Charging',
        VehicleStatus.maintenance => 'In maintenance',
        VehicleStatus.inactive => 'Inactive',
      };
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.operatorId,
    required this.plate,
    required this.kind,
    required this.model,
    required this.capacity,
    required this.status,
    required this.verification,
    required this.area,
    required this.monthEarnings,
    this.ownerId,
    this.driverName,
    this.batteryPct,
    this.rangeKm,
    this.baseFare,
    this.perKmFare,
  });

  final String id;

  /// Provider that runs the vehicle day to day.
  final String operatorId;

  /// Fleet owner/investor that owns the vehicle, when different from the operator.
  final String? ownerId;
  final String plate;
  final VehicleKind kind;
  final String model;
  final int capacity;
  final VehicleStatus status;
  final Verification verification;
  final String area;
  final int monthEarnings;
  final String? driverName;
  final int? batteryPct;
  final int? rangeKm;
  final int? baseFare;
  final int? perKmFare;

  bool get electric => kind.isElectric;
  String get displayName => kind == VehicleKind.bus || kind == VehicleKind.minibus ? 'Bus #$plate' : '$model · $plate';

  Vehicle copyWith({VehicleStatus? status, Verification? verification, int? monthEarnings}) => Vehicle(
        id: id,
        operatorId: operatorId,
        ownerId: ownerId,
        plate: plate,
        kind: kind,
        model: model,
        capacity: capacity,
        status: status ?? this.status,
        verification: verification ?? this.verification,
        area: area,
        monthEarnings: monthEarnings ?? this.monthEarnings,
        driverName: driverName,
        batteryPct: batteryPct,
        rangeKm: rangeKm,
        baseFare: baseFare,
        perKmFare: perKmFare,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'operator_id': operatorId,
        'owner_id': ownerId,
        'plate': plate,
        'kind': kind.wire,
        'model': model,
        'capacity': capacity,
        'status': status.wire,
        'verification': verification.wire,
        'area': area,
        'month_earnings': monthEarnings,
        'driver_name': driverName,
        'battery_pct': batteryPct,
        'range_km': rangeKm,
        'base_fare': baseFare,
        'per_km_fare': perKmFare,
      };

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'] as String,
        operatorId: json['operator_id'] as String,
        ownerId: json['owner_id'] as String?,
        plate: (json['plate'] as String?) ?? '',
        kind: _enumByName(VehicleKind.values, json['kind'], VehicleKind.bus),
        model: (json['model'] as String?) ?? '',
        capacity: _int(json['capacity']),
        status: _enumByName(VehicleStatus.values, json['status'], VehicleStatus.active),
        verification: _enumByName(Verification.values, json['verification'], Verification.pending),
        area: (json['area'] as String?) ?? 'FCT',
        monthEarnings: _int(json['month_earnings']),
        driverName: json['driver_name'] as String?,
        batteryPct: json['battery_pct'] == null ? null : _int(json['battery_pct']),
        rangeKm: json['range_km'] == null ? null : _int(json['range_km']),
        baseFare: json['base_fare'] == null ? null : _int(json['base_fare']),
        perKmFare: json['per_km_fare'] == null ? null : _int(json['per_km_fare']),
      );
}

class ChargingStation {
  const ChargingStation({required this.id, required this.name, required this.area, required this.ports, required this.available, required this.operatorId});
  final String id;
  final String name;
  final String area;
  final int ports;
  final int available;
  final String operatorId;

  factory ChargingStation.fromJson(Map<String, dynamic> json) => ChargingStation(
        id: json['id'] as String,
        name: json['name'] as String,
        area: (json['area'] as String?) ?? '',
        ports: _int(json['ports']),
        available: _int(json['available']),
        operatorId: (json['operator_id'] as String?) ?? '',
      );
}

// ---------------------------------------------------------------- bookings

enum BookingKind { transit, electric, tagAlong, eventBus, eventTicket }

extension BookingKindX on BookingKind {
  String get label => switch (this) {
        BookingKind.transit => 'Public transport',
        BookingKind.electric => 'Electric ride',
        BookingKind.tagAlong => 'Tag Along',
        BookingKind.eventBus => 'Event bus',
        BookingKind.eventTicket => 'Event ticket',
      };

  IconData get icon => switch (this) {
        BookingKind.transit => Icons.directions_bus_rounded,
        BookingKind.electric => Icons.electric_car_rounded,
        BookingKind.tagAlong => Icons.groups_rounded,
        BookingKind.eventBus => Icons.directions_bus_filled_rounded,
        BookingKind.eventTicket => Icons.local_activity_rounded,
      };
}

enum BookingStatus { confirmed, requested, accepted, completed, cancelled, declined }

extension BookingStatusX on BookingStatus {
  String get label => switch (this) {
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.requested => 'Request sent',
        BookingStatus.accepted => 'Accepted',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
        BookingStatus.declined => 'Declined',
      };

  bool get isOpen => this == BookingStatus.confirmed || this == BookingStatus.requested || this == BookingStatus.accepted;
}

enum PaymentMethod { tapCard, qr, splitCost }

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.tapCard => 'Tap card',
        PaymentMethod.qr => 'QR code',
        PaymentMethod.splitCost => 'Split with host',
      };
}

class Booking {
  const Booking({
    required this.id,
    required this.userId,
    required this.passengerName,
    required this.kind,
    required this.status,
    required this.origin,
    required this.destination,
    required this.departureAt,
    required this.fare,
    required this.paymentMethod,
    required this.ticketCode,
    required this.createdAt,
    this.title,
    this.seat,
    this.routeId,
    this.vehicleId,
    this.rideId,
    this.providerId,
    this.eventId,
    this.eventBusId,
  });

  final String id;
  final String userId;
  final String passengerName;
  final BookingKind kind;
  final BookingStatus status;
  final String origin;
  final String destination;
  final DateTime departureAt;
  final int fare;
  final PaymentMethod paymentMethod;
  final String ticketCode;
  final DateTime createdAt;
  final String? title;
  final String? seat;
  final String? routeId;
  final String? vehicleId;
  final String? rideId;
  final String? providerId;
  final String? eventId;
  final String? eventBusId;

  /// Status as riders read it (an event-bus seat waits for the operator to fix the time).
  String get statusLabel => kind == BookingKind.eventBus && status == BookingStatus.requested ? 'Seat held' : status.label;

  bool get isUpcoming => status.isOpen && departureAt.isAfter(DateTime.now().subtract(const Duration(minutes: 30)));

  /// Payload encoded in the boarding QR code.
  String get qrPayload => 'TAPARIDE:$ticketCode:${routeId ?? vehicleId ?? rideId ?? '-'}:${departureAt.toUtc().toIso8601String()}';

  Booking copyWith({BookingStatus? status, DateTime? departureAt}) => Booking(
        id: id,
        userId: userId,
        passengerName: passengerName,
        kind: kind,
        status: status ?? this.status,
        origin: origin,
        destination: destination,
        departureAt: departureAt ?? this.departureAt,
        fare: fare,
        paymentMethod: paymentMethod,
        ticketCode: ticketCode,
        createdAt: createdAt,
        title: title,
        seat: seat,
        routeId: routeId,
        vehicleId: vehicleId,
        rideId: rideId,
        providerId: providerId,
        eventId: eventId,
        eventBusId: eventBusId,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'user_id': userId,
        'passenger_name': passengerName,
        'kind': kind.wire,
        'status': status.wire,
        'origin': origin,
        'destination': destination,
        'departure_at': departureAt.toUtc().toIso8601String(),
        'fare': fare,
        'payment_method': paymentMethod.wire,
        'ticket_code': ticketCode,
        'created_at': createdAt.toUtc().toIso8601String(),
        'title': title,
        'seat': seat,
        'route_id': routeId,
        'vehicle_id': vehicleId,
        'ride_id': rideId,
        'provider_id': providerId,
        'event_id': eventId,
        'event_bus_id': eventBusId,
      };

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        passengerName: (json['passenger_name'] as String?) ?? 'Passenger',
        kind: _enumByName(BookingKind.values, json['kind'], BookingKind.transit),
        status: _enumByName(BookingStatus.values, json['status'], BookingStatus.confirmed),
        origin: (json['origin'] as String?) ?? '',
        destination: (json['destination'] as String?) ?? '',
        departureAt: _date(json['departure_at']),
        fare: _int(json['fare']),
        paymentMethod: _enumByName(PaymentMethod.values, json['payment_method'], PaymentMethod.tapCard),
        ticketCode: (json['ticket_code'] as String?) ?? '',
        createdAt: _date(json['created_at']),
        title: json['title'] as String?,
        seat: json['seat'] as String?,
        routeId: json['route_id'] as String?,
        vehicleId: json['vehicle_id'] as String?,
        rideId: json['ride_id'] as String?,
        providerId: json['provider_id'] as String?,
        eventId: json['event_id'] as String?,
        eventBusId: json['event_bus_id'] as String?,
      );
}

class Wallet {
  const Wallet({required this.cardNumber, required this.balance});
  final String cardNumber;
  final int balance;

  String get maskedCard => cardNumber.length <= 4 ? cardNumber : '•••• ${cardNumber.substring(cardNumber.length - 4)}';

  factory Wallet.fromJson(Map<String, dynamic> json) =>
      Wallet(cardNumber: (json['card_number'] as String?) ?? '0000', balance: _int(json['balance']));
}

// ---------------------------------------------------------------- Tag Along

class SharedRide {
  const SharedRide({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.hostOrg,
    required this.hostVerified,
    required this.origin,
    required this.destination,
    required this.departAt,
    required this.seatsTotal,
    required this.seatsTaken,
    required this.costShare,
    required this.vehicleLabel,
    this.note = '',
    this.eventId,
    this.cancelled = false,
  });

  final String id;
  final String hostId;
  final String hostName;
  final String hostOrg;
  final bool hostVerified;
  final String origin;
  final String destination;
  final DateTime departAt;
  final int seatsTotal;
  final int seatsTaken;
  final int costShare;
  final String vehicleLabel;
  final String note;

  /// The event this ride goes to, if it was offered from an event page.
  final String? eventId;

  /// Withdrawn by the host.
  final bool cancelled;

  int get seatsLeft => (seatsTotal - seatsTaken).clamp(0, seatsTotal);

  SharedRide copyWith({int? seatsTaken, bool? cancelled}) => SharedRide(
        id: id,
        hostId: hostId,
        hostName: hostName,
        hostOrg: hostOrg,
        hostVerified: hostVerified,
        origin: origin,
        destination: destination,
        departAt: departAt,
        seatsTotal: seatsTotal,
        seatsTaken: seatsTaken ?? this.seatsTaken,
        costShare: costShare,
        vehicleLabel: vehicleLabel,
        note: note,
        eventId: eventId,
        cancelled: cancelled ?? this.cancelled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'host_id': hostId,
        'host_name': hostName,
        'host_org': hostOrg,
        'host_verified': hostVerified,
        'origin': origin,
        'destination': destination,
        'depart_at': departAt.toUtc().toIso8601String(),
        'seats_total': seatsTotal,
        'seats_taken': seatsTaken,
        'cost_share': costShare,
        'vehicle_label': vehicleLabel,
        'note': note,
        'event_id': eventId,
        'status': cancelled ? 'cancelled' : 'open',
      };

  factory SharedRide.fromJson(Map<String, dynamic> json) => SharedRide(
        id: json['id'] as String,
        hostId: json['host_id'] as String,
        hostName: (json['host_name'] as String?) ?? '',
        hostOrg: (json['host_org'] as String?) ?? '',
        hostVerified: (json['host_verified'] as bool?) ?? false,
        origin: (json['origin'] as String?) ?? '',
        destination: (json['destination'] as String?) ?? '',
        departAt: _date(json['depart_at']),
        seatsTotal: _int(json['seats_total']),
        seatsTaken: _int(json['seats_taken']),
        costShare: _int(json['cost_share']),
        vehicleLabel: (json['vehicle_label'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
        eventId: json['event_id'] as String?,
        cancelled: json['status'] == 'cancelled',
      );
}

// ---------------------------------------------------------------- audit + metrics

class AuditEntry {
  const AuditEntry({required this.id, required this.at, required this.actorName, required this.actorRole, required this.action, required this.target});
  final String id;
  final DateTime at;
  final String actorName;
  final UserRole actorRole;
  final String action;
  final String target;

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'actor_name': actorName,
        'actor_role': actorRole.wire,
        'action': action,
        'target': target,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: '${json['id']}',
        at: _date(json['at']),
        actorName: (json['actor_name'] as String?) ?? 'System',
        actorRole: _enumByName(UserRole.values, json['actor_role'], UserRole.admin),
        action: (json['action'] as String?) ?? '',
        target: (json['target'] as String?) ?? '',
      );
}

/// Figures that pre-date the live data in this build (illustrative demo baselines).
class MetricBaselines {
  const MetricBaselines({
    required this.operatorProviderId,
    required this.fleetProviderId,
    required this.operatorTrips,
    required this.operatorTripsDelta,
    required this.operatorRevenue,
    required this.operatorRevenueDelta,
    required this.operatorActiveDrivers,
    required this.fleetRevenue,
    required this.fleetRevenueDelta,
    required this.fleetEarnings,
    required this.ridershipByDay,
    required this.ridershipDelta,
    required this.verifiedOffPlatform,
    required this.verifiedDelta,
    required this.routesOffPlatform,
    required this.activeRoutesDelta,
  });

  /// The operator and fleet owner these baseline figures belong to.
  final String operatorProviderId;
  final String fleetProviderId;

  final int operatorTrips;
  final int operatorTripsDelta;
  final int operatorRevenue;
  final int operatorRevenueDelta;
  final int operatorActiveDrivers;
  final int fleetRevenue;
  final int fleetRevenueDelta;
  final List<VehicleEarning> fleetEarnings;

  /// Last seven days, Monday first.
  final List<int> ridershipByDay;
  final int ridershipDelta;

  /// FCT-registered vehicles and routes that are not (yet) on the platform. The FCTA
  /// totals add the live platform counts to these.
  final int verifiedOffPlatform;
  final int verifiedDelta;
  final int routesOffPlatform;
  final int activeRoutesDelta;

  int get totalRidership => ridershipByDay.fold(0, (a, b) => a + b);

  /// Live platform with no off-platform figures: dashboards show only what happens on Tap A Ride.
  static const none = MetricBaselines(
    operatorProviderId: '',
    fleetProviderId: '',
    operatorTrips: 0,
    operatorTripsDelta: 0,
    operatorRevenue: 0,
    operatorRevenueDelta: 0,
    operatorActiveDrivers: 0,
    fleetRevenue: 0,
    fleetRevenueDelta: 0,
    fleetEarnings: [],
    ridershipByDay: [0, 0, 0, 0, 0, 0, 0],
    ridershipDelta: 0,
    verifiedOffPlatform: 0,
    verifiedDelta: 0,
    routesOffPlatform: 0,
    activeRoutesDelta: 0,
  );

  bool get isNone => identical(this, none);
}

class VehicleEarning {
  const VehicleEarning({required this.plate, required this.amount, required this.date});
  final String plate;
  final int amount;
  final DateTime date;
}
