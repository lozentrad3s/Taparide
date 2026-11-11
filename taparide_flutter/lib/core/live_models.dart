import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';

/// Kinds of public events riders travel to together.
enum EventCategory { conference, concert, sport, worship, wedding, community, other }

extension EventCategoryX on EventCategory {
  String get label => switch (this) {
        EventCategory.conference => 'Conference',
        EventCategory.concert => 'Concert',
        EventCategory.sport => 'Sport',
        EventCategory.worship => 'Worship',
        EventCategory.wedding => 'Wedding',
        EventCategory.community => 'Community',
        EventCategory.other => 'Other',
      };

  IconData get icon => switch (this) {
        EventCategory.conference => Icons.co_present_rounded,
        EventCategory.concert => Icons.music_note_rounded,
        EventCategory.sport => Icons.sports_soccer_rounded,
        EventCategory.worship => Icons.volunteer_activism_rounded,
        EventCategory.wedding => Icons.celebration_rounded,
        EventCategory.community => Icons.diversity_3_rounded,
        EventCategory.other => Icons.event_rounded,
      };
}

/// An event in Abuja that riders can share rides to.
class RideEvent {
  const RideEvent({
    required this.id,
    required this.title,
    required this.venue,
    required this.area,
    required this.startsAt,
    required this.category,
    required this.organiserName,
    this.endsAt,
    this.description = '',
    this.organiserId,
    this.lat,
    this.lng,
  });

  final String id;
  final String title;
  final String venue;
  final String area;
  final DateTime startsAt;
  final DateTime? endsAt;
  final EventCategory category;
  final String description;
  final String? organiserId;
  final String organiserName;
  final double? lat;
  final double? lng;

  LatLng? get point => lat == null || lng == null ? null : LatLng(lat!, lng!);

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'venue': venue,
        'area': area,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'category': category.name,
        'description': description,
        'organiser_id': organiserId,
        'organiser_name': organiserName,
        'lat': lat,
        'lng': lng,
      };

  factory RideEvent.fromJson(Map<String, dynamic> json) => RideEvent(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        venue: (json['venue'] as String?) ?? '',
        area: (json['area'] as String?) ?? 'Abuja',
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: json['ends_at'] == null ? null : DateTime.parse(json['ends_at'] as String).toLocal(),
        category: EventCategory.values.where((c) => c.name == json['category']).firstOrNull ?? EventCategory.other,
        description: (json['description'] as String?) ?? '',
        organiserId: json['organiser_id'] as String?,
        organiserName: (json['organiser_name'] as String?) ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );
}

/// A private link to one trip, for a trusted contact.
class TripShare {
  const TripShare({required this.token, required this.bookingId, required this.expiresAt});
  final String token;
  final String bookingId;
  final DateTime expiresAt;

  factory TripShare.fromJson(Map<String, dynamic> json) => TripShare(
        token: json['token'] as String,
        bookingId: json['booking_id'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      );
}

/// What the trusted contact sees when they open a shared trip link.
class SharedTrip {
  const SharedTrip({
    required this.passenger,
    required this.kind,
    required this.status,
    required this.origin,
    required this.destination,
    required this.departureAt,
    required this.ticketCode,
    required this.expiresAt,
    this.operatorName,
    this.operatorVerified = false,
    this.vehicle,
    this.vehicleVerified = false,
    this.driver,
    this.stops = const [],
    this.rider,
    this.riderLocatedAt,
    this.vehiclePoint,
    this.vehicleLocatedAt,
  });

  final String passenger;
  final BookingKind kind;
  final BookingStatus status;
  final String origin;
  final String destination;
  final DateTime departureAt;
  final String ticketCode;
  final DateTime expiresAt;
  final String? operatorName;
  final bool operatorVerified;
  final String? vehicle;
  final bool vehicleVerified;
  final String? driver;
  final List<RouteStop> stops;
  final LatLng? rider;
  final DateTime? riderLocatedAt;
  final LatLng? vehiclePoint;
  final DateTime? vehicleLocatedAt;

  static LatLng? _point(dynamic lat, dynamic lng) => lat is num && lng is num ? LatLng(lat.toDouble(), lng.toDouble()) : null;
  static DateTime? _time(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory SharedTrip.fromJson(Map<String, dynamic> json) => SharedTrip(
        passenger: (json['passenger'] as String?) ?? 'Your contact',
        kind: BookingKind.values.where((k) => k.wire == json['kind']).firstOrNull ?? BookingKind.transit,
        status: BookingStatus.values.where((s) => s.wire == json['status']).firstOrNull ?? BookingStatus.confirmed,
        origin: (json['origin'] as String?) ?? '',
        destination: (json['destination'] as String?) ?? '',
        departureAt: _time(json['departure_at']) ?? DateTime.now(),
        ticketCode: (json['ticket_code'] as String?) ?? '',
        expiresAt: _time(json['expires_at']) ?? DateTime.now(),
        operatorName: json['operator'] as String?,
        operatorVerified: (json['operator_verified'] as bool?) ?? false,
        vehicle: (json['vehicle'] as String?)?.trim().isEmpty ?? true ? null : (json['vehicle'] as String).trim(),
        vehicleVerified: (json['vehicle_verified'] as bool?) ?? false,
        driver: json['driver'] as String?,
        stops: [for (final s in (json['stops'] as List? ?? const [])) RouteStop.fromJson(Map<String, dynamic>.from(s as Map))],
        rider: _point(json['rider_lat'], json['rider_lng']),
        riderLocatedAt: _time(json['rider_located_at']),
        vehiclePoint: _point(json['vehicle_lat'], json['vehicle_lng']),
        vehicleLocatedAt: _time(json['vehicle_located_at']),
      );
}

/// A vehicle's last GPS fix, sent by its driver's or conductor's device.
class VehiclePosition {
  const VehiclePosition({required this.vehicleId, required this.point, required this.updatedAt, this.speedKmh});
  final String vehicleId;
  final LatLng point;
  final DateTime updatedAt;
  final double? speedKmh;

  /// Older fixes are treated as "not reporting" and the timetable estimate is used instead.
  bool isFresh(DateTime now) => now.difference(updatedAt).inMinutes < 3;

  factory VehiclePosition.fromJson(Map<String, dynamic> json) => VehiclePosition(
        vehicleId: json['vehicle_id'] as String,
        point: LatLng((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
      );
}

/// A card or bank payment the rider has been sent to complete.
class TopUpStart {
  const TopUpStart({required this.url, required this.reference});
  final String url;
  final String reference;
}

enum TopUpStatus { paid, pending, failed }

class TopUpResult {
  const TopUpResult({required this.status, required this.amount});
  final TopUpStatus status;
  final int amount;
}
