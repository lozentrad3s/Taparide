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
    this.providerId,
    this.ticketPrice = 0,
    this.ticketsTotal = 0,
    this.ticketsSold = 0,
    this.sponsored = false,
    this.ticketLink,
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

  /// The event partner organisation that listed it.
  final String? providerId;

  /// Entry price in naira (0 = free entry). Tickets are sold in the app when [ticketsTotal] > 0.
  final int ticketPrice;
  final int ticketsTotal;
  final int ticketsSold;
  final bool sponsored;
  final String? ticketLink;

  LatLng? get point => lat == null || lng == null ? null : LatLng(lat!, lng!);
  bool get sellsTickets => ticketsTotal > 0;
  int get ticketsLeft => (ticketsTotal - ticketsSold).clamp(0, ticketsTotal);

  RideEvent copyWith({int? ticketsSold}) => RideEvent(
        id: id,
        title: title,
        venue: venue,
        area: area,
        startsAt: startsAt,
        endsAt: endsAt,
        category: category,
        description: description,
        organiserId: organiserId,
        organiserName: organiserName,
        lat: lat,
        lng: lng,
        providerId: providerId,
        ticketPrice: ticketPrice,
        ticketsTotal: ticketsTotal,
        ticketsSold: ticketsSold ?? this.ticketsSold,
        sponsored: sponsored,
        ticketLink: ticketLink,
      );

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
        'provider_id': providerId,
        'ticket_price': ticketPrice,
        'tickets_total': ticketsTotal,
        'tickets_sold': ticketsSold,
        'sponsored': sponsored,
        'ticket_link': ticketLink,
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
        providerId: json['provider_id'] as String?,
        ticketPrice: (json['ticket_price'] as num?)?.toInt() ?? 0,
        ticketsTotal: (json['tickets_total'] as num?)?.toInt() ?? 0,
        ticketsSold: (json['tickets_sold'] as num?)?.toInt() ?? 0,
        sponsored: json['sponsored'] == true,
        ticketLink: json['ticket_link'] as String?,
      );
}

enum EventBusStatus { open, confirmed, cancelled }

/// A bus a registered operator runs to an event. Riders book a seat and pick a departure
/// time; the operator then confirms the time most riders chose (matchmaking).
class EventBus {
  const EventBus({
    required this.id,
    required this.eventId,
    required this.providerId,
    required this.providerName,
    required this.origin,
    required this.fare,
    required this.capacity,
    required this.minRiders,
    required this.slots,
    required this.seatsBySlot,
    required this.status,
    this.vehicleId,
    this.vehicleLabel = '',
    this.confirmedAt,
  });

  final String id;
  final String eventId;
  final String providerId;
  final String providerName;
  final String? vehicleId;
  final String vehicleLabel;
  final String origin;
  final int fare;
  final int capacity;

  /// Riders needed before the operator commits to a time.
  final int minRiders;
  final List<DateTime> slots;

  /// Seats booked per departure time (keyed by UTC ISO time).
  final Map<String, int> seatsBySlot;
  final EventBusStatus status;
  final DateTime? confirmedAt;

  static String slotKey(DateTime t) {
    final u = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }

  int seatsAt(DateTime slot) => seatsBySlot[slotKey(slot)] ?? 0;
  int get riders => seatsBySlot.values.fold(0, (a, b) => a + b);

  /// The time most riders picked (the earliest on a tie).
  DateTime? get popularSlot {
    DateTime? best;
    for (final s in slots) {
      if (best == null || seatsAt(s) > seatsAt(best)) best = s;
    }
    return best;
  }

  bool get open => status == EventBusStatus.open;

  EventBus copyWith({Map<String, int>? seatsBySlot, EventBusStatus? status, DateTime? confirmedAt}) => EventBus(
        id: id,
        eventId: eventId,
        providerId: providerId,
        providerName: providerName,
        vehicleId: vehicleId,
        vehicleLabel: vehicleLabel,
        origin: origin,
        fare: fare,
        capacity: capacity,
        minRiders: minRiders,
        slots: slots,
        seatsBySlot: seatsBySlot ?? this.seatsBySlot,
        status: status ?? this.status,
        confirmedAt: confirmedAt ?? this.confirmedAt,
      );

  factory EventBus.fromJson(Map<String, dynamic> json) {
    final raw = json['seats_by_slot'];
    return EventBus(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      providerId: json['provider_id'] as String,
      providerName: (json['provider_name'] as String?) ?? '',
      vehicleId: json['vehicle_id'] as String?,
      vehicleLabel: (json['vehicle_label'] as String?) ?? '',
      origin: (json['origin'] as String?) ?? '',
      fare: (json['fare'] as num?)?.toInt() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      minRiders: (json['min_riders'] as num?)?.toInt() ?? 1,
      slots: [for (final s in (json['slots'] as List? ?? const [])) DateTime.parse(s as String).toLocal()]..sort(),
      seatsBySlot: {
        if (raw is Map)
          for (final e in raw.entries) slotKey(DateTime.parse(e.key as String)): (e.value as num).toInt(),
      },
      status: EventBusStatus.values.where((s) => s.name == json['status']).firstOrNull ?? EventBusStatus.open,
      confirmedAt: json['confirmed_at'] == null ? null : DateTime.parse(json['confirmed_at'] as String).toLocal(),
    );
  }
}

/// A sponsored message in the rider header. Watching it in full earns ride credit.
class PromoAd {
  const PromoAd({
    required this.id,
    required this.sponsor,
    required this.headline,
    required this.body,
    required this.ctaLabel,
    required this.colour,
    required this.icon,
    required this.reward,
    required this.seconds,
    this.ctaLink,
    this.house = false,
    this.banner,
    this.poster,
  });

  final String id;
  final String sponsor;

  /// Wide artwork for the header slot (an app asset path or an image URL).
  final String? banner;

  /// Larger artwork shown while the ad plays (falls back to [banner]).
  final String? poster;
  final String headline;
  final String body;
  final String ctaLabel;
  final String? ctaLink;
  final Color colour;
  final String icon;
  final int reward;
  final int seconds;

  /// Tap A Ride's own promotion, not a paying advertiser.
  final bool house;

  IconData get iconData => switch (icon) {
        'electric_car' => Icons.electric_car_rounded,
        'celebration' => Icons.celebration_rounded,
        'directions_bus' => Icons.directions_bus_rounded,
        'local_offer' => Icons.local_offer_rounded,
        _ => Icons.campaign_rounded,
      };

  factory PromoAd.fromJson(Map<String, dynamic> json) {
    final hex = ((json['colour'] as String?) ?? '#0B5D3B').replaceAll('#', '');
    return PromoAd(
      id: json['id'] as String,
      sponsor: (json['sponsor'] as String?) ?? '',
      headline: (json['headline'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      ctaLabel: (json['cta_label'] as String?) ?? 'Learn more',
      ctaLink: json['cta_link'] as String?,
      colour: Color(int.tryParse('FF$hex', radix: 16) ?? 0xFF0B5D3B),
      icon: (json['icon'] as String?) ?? 'campaign',
      reward: (json['reward'] as num?)?.toInt() ?? 0,
      seconds: (json['seconds'] as num?)?.toInt() ?? 15,
      house: json['house'] == true,
      banner: json['banner_url'] as String?,
      poster: json['poster_url'] as String?,
    );
  }

  PromoAd copyWith({String? banner, String? poster, String? ctaLink, String? ctaLabel}) => PromoAd(
        id: id,
        sponsor: sponsor,
        headline: headline,
        body: body,
        ctaLabel: ctaLabel ?? this.ctaLabel,
        ctaLink: ctaLink ?? this.ctaLink,
        colour: colour,
        icon: icon,
        reward: reward,
        seconds: seconds,
        house: house,
        banner: banner ?? this.banner,
        poster: poster ?? this.poster,
      );
}

/// A started ad view; the server times it.
class AdView {
  const AdView({required this.id, required this.adId});
  final String id;
  final String adId;
}

/// Ride credit earned for watching an ad.
class AdReward {
  const AdReward({required this.reward, required this.balance, required this.left});
  final int reward;
  final int balance;

  /// Rewards still available today.
  final int left;
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

/// Sign in with an outside account.
enum SocialProvider {
  google('Google'),
  apple('Apple');

  const SocialProvider(this.label);
  final String label;
}

/// An event-bus seat someone reserved on the website.
class WaitlistSeat {
  const WaitlistSeat({required this.event, required this.day, required this.pickup, required this.time, this.ticket});
  final String event;

  /// Personal pass ID (e.g. TW24-K7P2QX), checked with the rider's name and photo ID at boarding.
  final String? ticket;
  final DateTime day;
  final String pickup;
  final String time;

  factory WaitlistSeat.fromJson(Map<String, dynamic> j) => WaitlistSeat(
        event: j['event'] as String,
        day: DateTime.parse(j['day'] as String),
        pickup: j['area'] as String,
        time: j['slot'] as String,
        ticket: j['ticket'] as String?,
      );
}

/// Someone who joined on the website: the waitlist, their invite code and any Tech Week seats.
class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.email,
    this.name,
    this.phone,
    this.area,
    required this.role,
    required this.code,
    this.referredBy,
    required this.referrals,
    this.source,
    required this.joinedAt,
    this.creditedAt,
    this.seats = const [],
    this.contactedAt,
    this.note,
    this.dupPhone = false,
    this.dupName = false,
  });

  final int id;
  final String email;
  final String? name;
  final String? phone;
  final String? area;
  final String role;
  final String code;
  final String? referredBy;
  final int referrals;
  final String? source;
  final DateTime joinedAt;
  final DateTime? creditedAt;
  final List<WaitlistSeat> seats;

  /// When an admin marked this person as contacted, and the admin's private note.
  final DateTime? contactedAt;
  final String? note;

  /// Another sign-up has the same WhatsApp number / the same full name.
  final bool dupPhone;
  final bool dupName;

  bool get possibleDuplicate => dupPhone || dupName;

  /// One pass per event: every day of a person's pass carries the same pass ID.
  List<EventPass> get passes {
    final byEvent = <String, List<WaitlistSeat>>{};
    for (final s in seats) {
      byEvent.putIfAbsent(s.event, () => []).add(s);
    }
    return [
      for (final e in byEvent.entries)
        EventPass(
          event: e.key,
          code: e.value.map((s) => s.ticket).whereType<String>().firstOrNull,
          days: [for (final s in e.value) s.day]..sort(),
          pickup: e.value.first.pickup,
          time: e.value.first.time,
        ),
    ];
  }

  factory WaitlistEntry.fromJson(Map<String, dynamic> j) => WaitlistEntry(
        id: (j['id'] as num).toInt(),
        email: j['email'] as String,
        name: j['name'] as String?,
        phone: j['phone'] as String?,
        area: j['area'] as String?,
        role: (j['role'] as String?) ?? 'rider',
        code: j['code'] as String,
        referredBy: j['referred_by'] as String?,
        referrals: (j['referrals'] as num?)?.toInt() ?? 0,
        source: j['source'] as String?,
        joinedAt: DateTime.parse(j['created_at'] as String),
        creditedAt: j['credited_at'] == null ? null : DateTime.parse(j['credited_at'] as String),
        seats: [for (final s in (j['seats'] as List? ?? const [])) WaitlistSeat.fromJson(Map<String, dynamic>.from(s as Map))],
        contactedAt: _date(j['contacted_at']),
        note: j['note'] as String?,
        dupPhone: j['dup_phone'] == true,
        dupName: j['dup_name'] == true,
      );
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');
int _num(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// A person's free event-bus pass: one pass ID, valid on each of [days].
class EventPass {
  const EventPass({required this.event, required this.code, required this.days, required this.pickup, required this.time});
  final String event;
  final String? code;
  final List<DateTime> days;
  final String pickup;
  final String time;
}

/// The sign-up reward for people who joined on taparide.com before launch. Until full launch it
/// carries no money: the rider just sees "Ride reward granted" once their account email matches.
class SignupReward {
  const SignupReward({required this.granted, this.at, this.label = 'Ride reward granted'});

  final bool granted;
  final DateTime? at;
  final String label;

  static const none = SignupReward(granted: false);

  factory SignupReward.fromJson(Map<String, dynamic> j) => SignupReward(
        granted: j['granted'] == true,
        at: DateTime.tryParse('${j['at'] ?? ''}')?.toLocal(),
        label: (j['label'] as String?)?.trim().isNotEmpty == true ? j['label'] as String : 'Ride reward granted',
      );
}

/// One card / bank top-up of the rider's wallet (Bachs).
class TopUpRecord {
  const TopUpRecord({required this.reference, required this.amount, required this.status, required this.createdAt, this.channel, this.paidAt});

  final String reference;
  final int amount;

  /// pending · paid · failed
  final String status;
  final String? channel;
  final DateTime createdAt;
  final DateTime? paidAt;

  factory TopUpRecord.fromJson(Map<String, dynamic> j) => TopUpRecord(
        reference: '${j['reference'] ?? ''}',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        status: '${j['status'] ?? 'pending'}',
        channel: j['channel'] as String?,
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
        paidAt: DateTime.tryParse('${j['paid_at'] ?? ''}')?.toLocal(),
      );
}

/// Money a partner has collected through tap to pay. Fares are held until the trip is over.
class CollectionWallet {
  const CollectionWallet({required this.available, required this.paidOut, required this.held, this.recent = const []});
  final int available;
  final int paidOut;
  final int held;
  final List<CollectionPayment> recent;

  static const empty = CollectionWallet(available: 0, paidOut: 0, held: 0);

  factory CollectionWallet.fromJson(Map<String, dynamic> j) => CollectionWallet(
        available: _num(j['available']),
        paidOut: _num(j['paid_out']),
        held: _num(j['held']),
        recent: [for (final r in (j['recent'] as List? ?? const [])) CollectionPayment.fromJson(Map<String, dynamic>.from(r as Map))],
      );
}

class CollectionPayment {
  const CollectionPayment({required this.bookingId, required this.amount, required this.status, required this.createdAt, this.releaseAt, this.title});
  final String bookingId;
  final int amount;

  /// held, released or refunded.
  final String status;
  final DateTime createdAt;
  final DateTime? releaseAt;
  final String? title;

  factory CollectionPayment.fromJson(Map<String, dynamic> j) => CollectionPayment(
        bookingId: '${j['booking'] ?? ''}',
        amount: _num(j['amount']),
        status: '${j['status'] ?? 'held'}',
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        releaseAt: _date(j['release_at']),
        title: j['title'] as String?,
      );
}

typedef CollectionRow = ({String provider, String kind, int available, int paidOut});
typedef TopUpRow = ({String reference, int amount, String status, String? channel, DateTime createdAt, String? name});

/// Money across the platform, for the master admin.
class MoneyOverview {
  const MoneyOverview({
    required this.walletCount,
    required this.walletBalance,
    required this.rideCredit,
    required this.topupsPaid,
    required this.topupsPaidAmount,
    required this.topupsPending,
    required this.topupsFailed,
    required this.held,
    required this.released,
    required this.refunded,
    this.collection = const [],
    this.recentTopups = const [],
  });
  final int walletCount;
  final int walletBalance;
  final int rideCredit;
  final int topupsPaid;
  final int topupsPaidAmount;
  final int topupsPending;
  final int topupsFailed;
  final int held;
  final int released;
  final int refunded;
  final List<CollectionRow> collection;
  final List<TopUpRow> recentTopups;

  static const empty = MoneyOverview(walletCount: 0, walletBalance: 0, rideCredit: 0, topupsPaid: 0, topupsPaidAmount: 0, topupsPending: 0, topupsFailed: 0, held: 0, released: 0, refunded: 0);

  factory MoneyOverview.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> m(String k) => Map<String, dynamic>.from((j[k] as Map?) ?? const {});
    final w = m('wallets'), t = m('topups'), p = m('payouts');
    return MoneyOverview(
      walletCount: _num(w['count']),
      walletBalance: _num(w['balance']),
      rideCredit: _num(w['ride_credit']),
      topupsPaid: _num(t['paid']),
      topupsPaidAmount: _num(t['paid_amount']),
      topupsPending: _num(t['pending']),
      topupsFailed: _num(t['failed']),
      held: _num(p['held']),
      released: _num(p['released']),
      refunded: _num(p['refunded']),
      collection: [
        for (final c in (j['collection'] as List? ?? const []))
          (provider: '${(c as Map)['provider'] ?? ''}', kind: '${c['kind'] ?? ''}', available: _num(c['available']), paidOut: _num(c['paid_out'])),
      ],
      recentTopups: [
        for (final r in (j['recent_topups'] as List? ?? const []))
          (
            reference: '${(r as Map)['reference'] ?? ''}',
            amount: _num(r['amount']),
            status: '${r['status'] ?? ''}',
            channel: r['channel'] as String?,
            createdAt: _date(r['created_at']) ?? DateTime.now(),
            name: r['name'] as String?,
          ),
      ],
    );
  }
}

typedef SeatCount = ({DateTime day, String area, String slot, int riders});

/// Free-bus bookings for one event an organiser runs: people per day, pick-up point and time.
class EventSeatBookings {
  const EventSeatBookings({
    required this.eventId,
    required this.title,
    required this.venue,
    required this.startsAt,
    this.endsAt,
    required this.people,
    required this.rows,
    this.lastBooking,
    this.days = const [],
    this.areas = const [],
    this.slots = const [],
  });
  final String eventId;
  final String title;
  final String venue;
  final DateTime startsAt;
  final DateTime? endsAt;
  final int people;
  final List<SeatCount> rows;
  final DateTime? lastBooking;
  final List<DateTime> days;
  final List<String> areas;
  final List<String> slots;

  int ridersOn(DateTime day, [String? area]) =>
      rows.where((r) => r.day.year == day.year && r.day.month == day.month && r.day.day == day.day && (area == null || r.area == area)).fold(0, (a, r) => a + r.riders);

  factory EventSeatBookings.fromJson(Map<String, dynamic> j) {
    final config = Map<String, dynamic>.from((j['config'] as Map?) ?? const {});
    return EventSeatBookings(
      eventId: '${j['event_id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      venue: '${j['venue'] ?? ''}',
      startsAt: _date(j['starts_at']) ?? DateTime.now(),
      endsAt: _date(j['ends_at']),
      people: _num(j['people']),
      lastBooking: _date(j['last_booking']),
      rows: [
        for (final r in (j['rows'] as List? ?? const [])) (day: DateTime.parse('${(r as Map)['day']}'), area: '${r['area'] ?? ''}', slot: '${r['slot'] ?? ''}', riders: _num(r['riders'])),
      ],
      days: [for (final d in (config['days'] as List? ?? const [])) DateTime.parse('$d')],
      areas: [for (final a in (config['areas'] as List? ?? const [])) '$a'],
      slots: [for (final s in (config['slots'] as List? ?? const [])) '$s'],
    );
  }
}

/// Two-step sign-in (authenticator app) for platform admins and FCTA staff.
class TwoStepStatus {
  const TwoStepStatus({required this.enforced, required this.verified, this.factorId});

  /// False on the demo backend, which has no authenticator support.
  final bool enforced;

  /// This session has passed the second step.
  final bool verified;

  /// The confirmed authenticator, if one is set up.
  final String? factorId;
}

/// A new authenticator to add: scan [uri] as a QR code or type [secret] into the app.
class TwoStepSetup {
  const TwoStepSetup({required this.factorId, required this.secret, required this.uri});
  final String factorId;
  final String secret;
  final String uri;
}
