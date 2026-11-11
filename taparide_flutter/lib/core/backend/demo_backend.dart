import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:latlong2/latlong.dart';

import '../live_models.dart';
import '../models.dart';
import '../partner_models.dart';
import 'backend.dart';
import 'demo_seed.dart';

/// On-device backend used when no Supabase project is configured.
///
/// It applies the same role rules as the Supabase row-level-security policies so the
/// app behaves the same way in both modes. State persists in shared preferences.
class DemoBackend implements Backend {
  DemoBackend._(this._prefs, this._latency, this._clock);

  static const _storageKey = 'taparide_demo_state_v5';

  static Future<DemoBackend> create({Duration latency = const Duration(milliseconds: 260), DateTime Function()? clock}) async {
    final prefs = await SharedPreferences.getInstance();
    final backend = DemoBackend._(prefs, latency, clock ?? DateTime.now);
    backend._load();
    return backend;
  }

  final SharedPreferences _prefs;
  final Duration _latency;
  final DateTime Function() _clock;
  final _random = Random();

  late List<_Account> _accounts;
  late List<TransportProvider> _providers;
  late List<TransitRoute> _routes;
  late List<Vehicle> _vehicles;
  late List<SharedRide> _rides;
  late List<Booking> _bookings;
  late Map<String, Wallet> _wallets;
  late List<AuditEntry> _audit;
  List<PartnerApplication> _applications = [];

  /// Uploaded document bytes stay in memory in demo mode (too large for local storage).
  final Map<String, DocumentFile> _documents = {};
  String? _sessionUserId;

  // Events, trip links and vehicle positions live in memory in demo mode.
  late final List<RideEvent> _events = _seedEvents();
  final Map<String, String> _shares = {}; // token -> booking id
  final Map<String, LatLng> _shareLocations = {};
  final Map<String, VehiclePosition> _positions = {};

  @override
  String get modeLabel => 'Demo data';

  @override
  bool get isDemo => true;

  // ------------------------------------------------------------ persistence

  void _load() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null) {
      _seed();
      return;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      List<T> list<T>(String key, T Function(Map<String, dynamic>) from) =>
          [for (final item in (json[key] as List)) from(Map<String, dynamic>.from(item as Map))];
      _accounts = list('accounts', _Account.fromJson);
      _providers = list('providers', TransportProvider.fromJson);
      _routes = list('routes', TransitRoute.fromJson);
      _vehicles = list('vehicles', Vehicle.fromJson);
      _rides = list('rides', SharedRide.fromJson);
      _bookings = list('bookings', Booking.fromJson);
      _audit = list('audit', AuditEntry.fromJson);
      _wallets = {
        for (final e in (json['wallets'] as Map).entries) e.key as String: Wallet.fromJson(Map<String, dynamic>.from(e.value as Map)),
      };
      _sessionUserId = json['session'] as String?;
      _applications = json['applications'] is List ? list('applications', PartnerApplication.fromJson) : [];
      _refreshSeedRides();
    } catch (_) {
      _seed();
    }
  }

  void _seed() {
    final now = _clock();
    _accounts = [
      for (final u in DemoSeed.users())
        // The master admin signs in with a private password whose hash is injected at build time.
        if (u.id == 'u_admin' && DemoSeed.masterHash.isNotEmpty) _Account(u, DemoSeed.masterSalt, DemoSeed.masterHash) else _Account.create(u, DemoSeed.password),
    ];
    _providers = DemoSeed.providers();
    _routes = DemoSeed.routes();
    _vehicles = DemoSeed.vehicles();
    _rides = DemoSeed.sharedRides(now);
    _bookings = DemoSeed.bookings(now);
    _audit = DemoSeed.audit(now);
    _wallets = {DemoSeed.uAisha: const Wallet(cardNumber: '5061004219872500', balance: 2500)};
    _applications = DemoSeed.applications(now);
    _sessionUserId = null;
    _save();
  }

  /// Seeded Tag Along rides keep rolling forward so the demo always has rides to join.
  void _refreshSeedRides() {
    final now = _clock();
    final fresh = {for (final r in DemoSeed.sharedRides(now)) r.id: r};
    _rides = [
      for (final r in _rides)
        if (fresh.containsKey(r.id) && r.departAt.isBefore(now)) fresh[r.id]!.copyWith(seatsTaken: min(r.seatsTaken, fresh[r.id]!.seatsTotal - 1)) else r,
    ];
  }

  void _save() {
    _prefs.setString(
      _storageKey,
      jsonEncode({
        'accounts': [for (final a in _accounts) a.toJson()],
        'providers': [for (final p in _providers) p.toJson()],
        'routes': [for (final r in _routes) r.toJson()],
        'vehicles': [for (final v in _vehicles) v.toJson()],
        'rides': [for (final r in _rides) r.toJson()],
        'bookings': [for (final b in _bookings) b.toJson()],
        'audit': [for (final a in _audit) a.toJson()],
        'wallets': {for (final e in _wallets.entries) e.key: {'card_number': e.value.cardNumber, 'balance': e.value.balance}},
        'session': _sessionUserId,
        'applications': [for (final a in _applications) a.toJson()],
      }),
    );
  }

  /// Wipes every change and restores the original demo data.
  Future<void> reset() async {
    await _prefs.remove(_storageKey);
    _seed();
  }

  Future<void> _wait() => _latency == Duration.zero ? Future.value() : Future.delayed(_latency);

  String _id(String prefix) => '${prefix}_${_clock().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 20).toRadixString(36)}';

  String _ticket(String prefix) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return '$prefix-${List.generate(6, (_) => alphabet[_random.nextInt(alphabet.length)]).join()}';
  }

  // ------------------------------------------------------------ permission helpers

  AppUser get _me {
    final id = _sessionUserId;
    final account = id == null ? null : _accounts.where((a) => a.user.id == id).firstOrNull;
    if (account == null) throw const BackendException(BackendErrorKind.auth, 'Your session has ended. Please sign in again.');
    return account.user;
  }

  void _require(bool allowed, String what) {
    if (!allowed) throw BackendException(BackendErrorKind.permission, 'Your account is not allowed to $what.');
  }

  bool _manages(AppUser user, String providerId) =>
      user.role == UserRole.admin || ((user.role == UserRole.operator || user.role == UserRole.fleetOwner) && user.providerId == providerId);

  Set<String> get _verifiedProviderIds => {for (final p in _providers) if (p.status == Verification.verified) p.id};

  void _log(String action, String target) {
    final me = _me;
    _audit.insert(0, AuditEntry(id: _id('a'), at: _clock(), actorName: me.fullName, actorRole: me.role, action: action, target: target));
  }

  Wallet _walletFor(String userId) => _wallets.putIfAbsent(
        userId,
        () => Wallet(cardNumber: '50610042${(1000 + _random.nextInt(8999))}${(1000 + _random.nextInt(8999))}', balance: 2500),
      );

  void _charge(String userId, int amount) {
    final wallet = _walletFor(userId);
    if (wallet.balance < amount) {
      throw BackendException(BackendErrorKind.insufficientFunds, 'Your tap card balance is too low for this fare. Top up and try again.');
    }
    _wallets[userId] = Wallet(cardNumber: wallet.cardNumber, balance: wallet.balance - amount);
  }

  // ------------------------------------------------------------ accounts

  @override
  Future<AppUser?> restoreSession() async {
    final id = _sessionUserId;
    if (id == null) return null;
    return _accounts.where((a) => a.user.id == id).firstOrNull?.user;
  }

  @override
  Future<AppUser> signIn({required String email, required String password, required Portal portal}) async {
    await _wait();
    final account = _accounts.where((a) => a.user.email.toLowerCase() == email.trim().toLowerCase()).firstOrNull;
    if (account == null || !account.matches(password)) {
      throw const BackendException(BackendErrorKind.auth, 'That email and password do not match an account.');
    }
    if (portal == Portal.passenger && account.user.role.isPartner) {
      throw const BackendException(BackendErrorKind.permission, 'This is a partner account. Use the partner portal to sign in.');
    }
    if (portal == Portal.partner && !account.user.role.isPartner) {
      throw const BackendException(BackendErrorKind.permission, 'This is a passenger account. Use passenger sign-in instead.');
    }
    _sessionUserId = account.user.id;
    _save();
    return account.user;
  }

  @override
  Future<AppUser> register({required String fullName, required String email, required String phone, required String password, String? organisation}) async {
    await _wait();
    final normalised = email.trim().toLowerCase();
    if (_accounts.any((a) => a.user.email.toLowerCase() == normalised)) {
      throw const BackendException(BackendErrorKind.validation, 'An account with this email already exists. Sign in instead.');
    }
    final user = AppUser(
      id: _id('u'),
      fullName: fullName.trim(),
      email: normalised,
      phone: phone.trim(),
      role: UserRole.passenger,
      organisation: (organisation ?? '').trim().isEmpty ? null : organisation!.trim(),
      verified: false,
      createdAt: _clock(),
    );
    _accounts.add(_Account.create(user, password));
    _walletFor(user.id);
    _sessionUserId = user.id;
    _save();
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _wait();
    // The demo has no mail server; a real backend emails a reset link.
  }

  @override
  Future<void> signOut() async {
    _sessionUserId = null;
    _save();
  }

  // ------------------------------------------------------------ catalogue

  @override
  Future<List<TransitRoute>> fetchPublicRoutes() async {
    await _wait();
    final verified = _verifiedProviderIds;
    return [for (final r in _routes) if (r.active && verified.contains(r.providerId)) r]..sort((a, b) => b.monthlyTrips.compareTo(a.monthlyTrips));
  }

  @override
  Future<List<TransportProvider>> fetchProviders() async {
    await _wait();
    final me = _me;
    if (me.role == UserRole.government || me.role == UserRole.admin) return List.of(_providers);
    return [for (final p in _providers) if (p.status == Verification.verified || p.id == me.providerId) p];
  }

  @override
  Future<List<TransitRoute>> fetchRoutes() async {
    await _wait();
    final me = _me;
    final verified = _verifiedProviderIds;
    if (me.role == UserRole.government || me.role == UserRole.admin) return List.of(_routes);
    return [
      for (final r in _routes)
        if ((r.active && verified.contains(r.providerId)) || r.providerId == me.providerId) r,
    ];
  }

  @override
  Future<List<Vehicle>> fetchVehicles() async {
    await _wait();
    final me = _me;
    if (me.role == UserRole.government || me.role == UserRole.admin) return List.of(_vehicles);
    final verified = _verifiedProviderIds;
    return [
      for (final v in _vehicles)
        if ((v.verification == Verification.verified && verified.contains(v.operatorId)) || v.operatorId == me.providerId || v.ownerId == me.providerId) v,
    ];
  }

  @override
  Future<List<ChargingStation>> fetchChargingStations() async {
    await _wait();
    _me;
    return DemoSeed.chargingStations;
  }

  @override
  Future<List<SharedRide>> fetchSharedRides() async {
    await _wait();
    _me;
    _refreshSeedRides();
    final now = _clock();
    final rides = [for (final r in _rides) if (!r.cancelled && r.departAt.isAfter(now.subtract(const Duration(minutes: 30)))) r]
      ..sort((a, b) => a.departAt.compareTo(b.departAt));
    return rides;
  }

  @override
  Future<MetricBaselines> fetchBaselines() async {
    await _wait();
    return DemoSeed.baselines;
  }

  // ------------------------------------------------------------ rider

  @override
  Future<Wallet> fetchWallet() async {
    await _wait();
    return _walletFor(_me.id);
  }

  @override
  Future<List<Booking>> fetchMyBookings() async {
    await _wait();
    final me = _me;
    _settleTagAlongRequests();
    _completePastTrips();
    return [for (final b in _bookings) if (b.userId == me.id) b]..sort((a, b) => b.departureAt.compareTo(a.departureAt));
  }

  bool _hostIsAccount(String hostId) => _accounts.any((a) => a.user.id == hostId);

  /// Sample hosts (not real accounts) accept a few seconds after a request; real hosts answer themselves.
  void _settleTagAlongRequests() {
    final now = _clock();
    var changed = false;
    for (var i = 0; i < _bookings.length; i++) {
      final b = _bookings[i];
      if (b.kind == BookingKind.tagAlong && b.status == BookingStatus.requested && now.difference(b.createdAt).inSeconds >= 6) {
        final rideIndex = _rides.indexWhere((r) => r.id == b.rideId);
        if (rideIndex >= 0 && _hostIsAccount(_rides[rideIndex].hostId)) continue;
        if (rideIndex >= 0 && _rides[rideIndex].seatsLeft > 0) {
          _rides[rideIndex] = _rides[rideIndex].copyWith(seatsTaken: _rides[rideIndex].seatsTaken + 1);
          _bookings[i] = b.copyWith(status: BookingStatus.accepted);
        } else {
          _bookings[i] = b.copyWith(status: BookingStatus.declined);
        }
        changed = true;
      }
    }
    if (changed) _save();
  }

  void _completePastTrips() {
    final now = _clock();
    var changed = false;
    for (var i = 0; i < _bookings.length; i++) {
      final b = _bookings[i];
      if ((b.status == BookingStatus.confirmed || b.status == BookingStatus.accepted) && b.departureAt.add(const Duration(hours: 3)).isBefore(now)) {
        _bookings[i] = b.copyWith(status: BookingStatus.completed);
        changed = true;
      }
    }
    if (changed) _save();
  }

  @override
  Future<Booking> bookTransit({required TransitRoute route, required DateTime departure, required PaymentMethod method}) async {
    await _wait();
    final me = _me;
    final current = _routes.where((r) => r.id == route.id).firstOrNull;
    if (current == null || !current.active || !_verifiedProviderIds.contains(current.providerId)) {
      throw const BackendException(BackendErrorKind.validation, 'This route is not taking bookings right now.');
    }
    if (departure.isBefore(_clock())) {
      throw const BackendException(BackendErrorKind.validation, 'That departure has already left. Pick a later time.');
    }
    final duplicate = _bookings.any((b) => b.userId == me.id && b.routeId == current.id && b.departureAt == departure && b.status.isOpen);
    if (duplicate) throw const BackendException(BackendErrorKind.validation, 'You already have a seat on this departure.');

    _charge(me.id, current.fare);
    final buses = [
      for (final v in _vehicles)
        if (v.operatorId == current.providerId && v.verification == Verification.verified && (v.status == VehicleStatus.active || v.status == VehicleStatus.onTrip)) v,
    ];
    final vehicle = buses.isEmpty ? null : buses[(current.id.hashCode ^ departure.hashCode).abs() % buses.length];
    final booking = Booking(
      id: _id('bk'),
      userId: me.id,
      passengerName: me.fullName,
      kind: BookingKind.transit,
      status: BookingStatus.confirmed,
      origin: current.origin,
      destination: current.destination,
      departureAt: departure,
      fare: current.fare,
      paymentMethod: method,
      ticketCode: _ticket('TR'),
      createdAt: _clock(),
      title: current.name,
      seat: 'S${(1 + _random.nextInt(vehicle?.capacity ?? 40)).toString().padLeft(2, '0')}',
      routeId: current.id,
      vehicleId: vehicle?.id,
      providerId: current.providerId,
    );
    _bookings.add(booking);
    _save();
    return booking;
  }

  @override
  Future<Booking> bookElectric({required Vehicle vehicle, required String pickup, required String dropoff, required int fare, required PaymentMethod method}) async {
    await _wait();
    final me = _me;
    final index = _vehicles.indexWhere((v) => v.id == vehicle.id);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'That vehicle is no longer listed.');
    final current = _vehicles[index];
    if (!current.kind.isBookableCar || current.verification != Verification.verified || !_verifiedProviderIds.contains(current.operatorId)) {
      throw const BackendException(BackendErrorKind.validation, 'Only verified cars can be booked.');
    }
    if (current.status != VehicleStatus.active) {
      throw const BackendException(BackendErrorKind.validation, 'This vehicle was just taken. Choose another one.');
    }
    if (fare < (current.baseFare ?? 0)) throw const BackendException(BackendErrorKind.validation, 'The fare estimate is out of date. Refresh and try again.');
    _charge(me.id, fare);
    _vehicles[index] = current.copyWith(status: VehicleStatus.onTrip);
    final booking = Booking(
      id: _id('bk'),
      userId: me.id,
      passengerName: me.fullName,
      kind: BookingKind.electric,
      status: BookingStatus.confirmed,
      origin: pickup,
      destination: dropoff,
      departureAt: _clock().add(const Duration(minutes: 6)),
      fare: fare,
      paymentMethod: method,
      ticketCode: _ticket('EV'),
      createdAt: _clock(),
      title: '${current.model} · ${current.plate}',
      vehicleId: current.id,
      providerId: current.operatorId,
    );
    _bookings.add(booking);
    _save();
    return booking;
  }

  @override
  Future<Booking> requestSharedRide(SharedRide ride) async {
    await _wait();
    final me = _me;
    final current = _rides.where((r) => r.id == ride.id).firstOrNull;
    if (current == null || current.cancelled) throw const BackendException(BackendErrorKind.notFound, 'This ride has been withdrawn by the host.');
    if (current.hostId == me.id) throw const BackendException(BackendErrorKind.validation, 'You are hosting this ride.');
    if (current.seatsLeft <= 0) throw const BackendException(BackendErrorKind.validation, 'This ride is full.');
    if (_bookings.any((b) => b.userId == me.id && b.rideId == current.id && b.status.isOpen)) {
      throw const BackendException(BackendErrorKind.validation, 'You have already asked to join this ride.');
    }
    final booking = Booking(
      id: _id('bk'),
      userId: me.id,
      passengerName: me.fullName,
      kind: BookingKind.tagAlong,
      status: BookingStatus.requested,
      origin: current.origin,
      destination: current.destination,
      departureAt: current.departAt,
      fare: current.costShare,
      paymentMethod: PaymentMethod.splitCost,
      ticketCode: _ticket('TA'),
      createdAt: _clock(),
      title: 'With ${current.hostName}',
      rideId: current.id,
    );
    _bookings.add(booking);
    _save();
    return booking;
  }

  @override
  Future<SharedRide> offerSharedRide({required String origin, required String destination, required DateTime departAt, required int seats, required int costShare, required String vehicleLabel, String note = '', String? eventId}) async {
    await _wait();
    final me = _me;
    if (departAt.isBefore(_clock())) throw const BackendException(BackendErrorKind.validation, 'Choose a departure time later than now.');
    final ride = SharedRide(
      id: _id('ride'),
      hostId: me.id,
      hostName: me.fullName,
      hostOrg: me.organisation ?? 'Tap A Ride member',
      hostVerified: me.verified,
      origin: origin.trim(),
      destination: destination.trim(),
      departAt: departAt,
      seatsTotal: seats,
      seatsTaken: 0,
      costShare: costShare,
      vehicleLabel: vehicleLabel.trim(),
      note: note.trim(),
      eventId: eventId,
    );
    _rides.add(ride);
    _save();
    return ride;
  }

  @override
  Future<Booking> cancelBooking(String bookingId) async {
    await _wait();
    final me = _me;
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'Booking not found.');
    final booking = _bookings[index];
    _require(booking.userId == me.id, 'cancel this booking');
    if (!booking.status.isOpen) throw const BackendException(BackendErrorKind.validation, 'This booking can no longer be cancelled.');
    if (booking.paymentMethod != PaymentMethod.splitCost && booking.departureAt.isAfter(_clock())) {
      final wallet = _walletFor(me.id);
      _wallets[me.id] = Wallet(cardNumber: wallet.cardNumber, balance: wallet.balance + booking.fare);
    }
    if (booking.kind == BookingKind.electric && booking.vehicleId != null) {
      final v = _vehicles.indexWhere((x) => x.id == booking.vehicleId);
      if (v >= 0) _vehicles[v] = _vehicles[v].copyWith(status: VehicleStatus.active);
    }
    if (booking.kind == BookingKind.tagAlong && booking.status == BookingStatus.accepted) {
      final r = _rides.indexWhere((x) => x.id == booking.rideId);
      if (r >= 0) {
        _rides[r] = _rides[r].copyWith(seatsTaken: max(0, _rides[r].seatsTaken - 1));
        // A real host took the share when accepting; it goes back if the ride has not left.
        if (_hostIsAccount(_rides[r].hostId) && booking.departureAt.isAfter(_clock())) _credit(me.id, booking.fare);
      }
    }
    _shares.removeWhere((_, id) => id == booking.id);
    final updated = booking.copyWith(status: BookingStatus.cancelled);
    _bookings[index] = updated;
    _save();
    return updated;
  }

  @override
  Future<Wallet> topUp(int amount) async {
    await _wait();
    final me = _me;
    if (amount < 100 || amount > 50000) throw const BackendException(BackendErrorKind.validation, 'Top up between ₦100 and ₦50,000.');
    final wallet = _walletFor(me.id);
    final updated = Wallet(cardNumber: wallet.cardNumber, balance: wallet.balance + amount);
    _wallets[me.id] = updated;
    _save();
    return updated;
  }

  void _credit(String userId, int amount) {
    final w = _walletFor(userId);
    _wallets[userId] = Wallet(cardNumber: w.cardNumber, balance: w.balance + amount);
  }

  // ------------------------------------------------------------ Tag Along hosting

  @override
  Future<List<Booking>> fetchRideRequests() async {
    await _wait();
    final me = _me;
    final mine = {for (final r in _rides) if (r.hostId == me.id) r.id};
    return [for (final b in _bookings) if (b.rideId != null && mine.contains(b.rideId)) b]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Booking> respondToRideRequest(String bookingId, {required bool accept}) async {
    await _wait();
    final me = _me;
    final i = _bookings.indexWhere((b) => b.id == bookingId && b.kind == BookingKind.tagAlong);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'Request not found.');
    final b = _bookings[i];
    final r = _rides.indexWhere((x) => x.id == b.rideId);
    if (r < 0 || _rides[r].hostId != me.id) throw const BackendException(BackendErrorKind.permission, 'Only the host can answer this request.');
    if (b.status != BookingStatus.requested) throw const BackendException(BackendErrorKind.validation, 'This request has already been answered.');
    if (accept) {
      if (_rides[r].seatsLeft <= 0) throw const BackendException(BackendErrorKind.validation, 'Your ride is full.');
      if (_walletFor(b.userId).balance < b.fare) {
        throw BackendException(BackendErrorKind.insufficientFunds, '${b.passengerName} no longer has enough balance for their share.');
      }
      _credit(b.userId, -b.fare);
      _rides[r] = _rides[r].copyWith(seatsTaken: _rides[r].seatsTaken + 1);
    }
    _bookings[i] = b.copyWith(status: accept ? BookingStatus.accepted : BookingStatus.declined);
    _save();
    return _bookings[i];
  }

  @override
  Future<SharedRide> cancelSharedRide(String rideId) async {
    await _wait();
    final me = _me;
    final r = _rides.indexWhere((x) => x.id == rideId);
    if (r < 0) throw const BackendException(BackendErrorKind.notFound, 'Ride not found.');
    if (_rides[r].hostId != me.id) throw const BackendException(BackendErrorKind.permission, 'Only the host can withdraw this ride.');
    for (var i = 0; i < _bookings.length; i++) {
      final b = _bookings[i];
      if (b.rideId != rideId || !b.status.isOpen) continue;
      if (b.status == BookingStatus.accepted) _credit(b.userId, b.fare);
      _bookings[i] = b.copyWith(status: b.status == BookingStatus.accepted ? BookingStatus.cancelled : BookingStatus.declined);
    }
    _rides[r] = _rides[r].copyWith(seatsTaken: 0, cancelled: true);
    _save();
    return _rides[r];
  }

  // ------------------------------------------------------------ events

  List<RideEvent> _seedEvents() {
    final now = _clock();
    DateTime at(int days, int hour) => DateTime(now.year, now.month, now.day + days, hour);
    return [
      RideEvent(id: 'ev_showcase', title: 'Smart Mobility Showcase', venue: 'International Conference Centre', area: 'Central Area', startsAt: at(3, 10), endsAt: at(3, 16), category: EventCategory.conference, organiserName: 'Tap A Ride (sample event)', description: 'Sample event: demos and talks on how Abuja moves.', lat: 9.0412, lng: 7.4893),
      RideEvent(id: 'ev_music', title: 'Abuja Live Music Night', venue: 'Millennium Park', area: 'Maitama', startsAt: at(5, 18), endsAt: at(5, 22), category: EventCategory.concert, organiserName: 'Tap A Ride (sample event)', description: 'Sample event: an evening of live music in the park.', lat: 9.0718, lng: 7.5003),
      RideEvent(id: 'ev_cup', title: 'Community Cup Final', venue: 'Moshood Abiola National Stadium', area: 'Kukwaba', startsAt: at(6, 16), endsAt: at(6, 19), category: EventCategory.sport, organiserName: 'Tap A Ride (sample event)', description: 'Sample event: the weekend football final.', lat: 9.0379, lng: 7.4531),
    ];
  }

  @override
  Future<List<RideEvent>> fetchEvents() async {
    await _wait();
    _me;
    final now = _clock();
    return [for (final e in _events) if (e.startsAt.isAfter(now.subtract(const Duration(hours: 6)))) e]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  @override
  Future<RideEvent> createEvent({required String title, required String venue, required String area, required DateTime startsAt, DateTime? endsAt, required EventCategory category, String description = '', double? lat, double? lng}) async {
    await _wait();
    final me = _me;
    if (startsAt.isBefore(_clock())) throw const BackendException(BackendErrorKind.validation, 'Choose a start time later than now.');
    final event = RideEvent(id: _id('ev'), title: title.trim(), venue: venue.trim(), area: area.trim().isEmpty ? 'Abuja' : area.trim(), startsAt: startsAt, endsAt: endsAt, category: category, description: description.trim(), organiserId: me.id, organiserName: me.organisation ?? me.fullName, lat: lat, lng: lng);
    _events.add(event);
    return event;
  }

  @override
  Future<void> removeEvent(String eventId) async {
    await _wait();
    final me = _me;
    final event = _events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) throw const BackendException(BackendErrorKind.notFound, 'Event not found.');
    _require(event.organiserId == me.id || me.role.canVerify, 'remove this event');
    _events.remove(event);
  }

  // ------------------------------------------------------------ share my ride

  @override
  Future<TripShare> shareTrip(String bookingId) async {
    await _wait();
    final me = _me;
    final b = _bookings.where((x) => x.id == bookingId && x.userId == me.id).firstOrNull;
    if (b == null) throw const BackendException(BackendErrorKind.notFound, 'Booking not found.');
    if (!b.status.isOpen) throw const BackendException(BackendErrorKind.validation, 'Only upcoming trips can be shared.');
    final token = _shares.entries.where((e) => e.value == b.id).firstOrNull?.key ?? '${_id('t')}${_random.nextInt(1 << 30).toRadixString(36)}';
    _shares[token] = b.id;
    return TripShare(token: token, bookingId: b.id, expiresAt: b.departureAt.add(const Duration(hours: 6)));
  }

  @override
  Future<void> stopSharingTrip(String bookingId) async {
    await _wait();
    _shares.removeWhere((_, id) => id == bookingId);
  }

  @override
  Future<void> updateTripLocation(String bookingId, double lat, double lng) async {
    if (_shares.containsValue(bookingId)) _shareLocations[bookingId] = LatLng(lat, lng);
  }

  @override
  Future<SharedTrip?> fetchSharedTrip(String token) async {
    await _wait();
    final b = _bookings.where((x) => x.id == _shares[token]).firstOrNull;
    if (b == null) return null;
    final vehicle = _vehicles.where((v) => v.id == b.vehicleId).firstOrNull;
    final route = _routes.where((r) => r.id == b.routeId).firstOrNull;
    final provider = _providers.where((p) => p.id == (b.providerId ?? vehicle?.operatorId)).firstOrNull;
    final ride = _rides.where((r) => r.id == b.rideId).firstOrNull;
    final live = _positions[b.vehicleId];
    return SharedTrip(
      passenger: b.passengerName.split(' ').first,
      kind: b.kind,
      status: b.status,
      origin: b.origin,
      destination: b.destination,
      departureAt: b.departureAt,
      ticketCode: b.ticketCode,
      expiresAt: b.departureAt.add(const Duration(hours: 6)),
      operatorName: provider?.name,
      operatorVerified: provider?.status == Verification.verified,
      vehicle: vehicle?.displayName ?? ride?.vehicleLabel,
      vehicleVerified: vehicle?.verification == Verification.verified,
      driver: vehicle?.driverName ?? ride?.hostName,
      stops: route?.stops ?? const [],
      rider: _shareLocations[b.id],
      riderLocatedAt: _shareLocations[b.id] == null ? null : _clock(),
      vehiclePoint: live?.point,
      vehicleLocatedAt: live?.updatedAt,
    );
  }

  // ------------------------------------------------------------ live vehicle positions

  @override
  Future<List<VehiclePosition>> fetchVehiclePositions() async {
    final now = _clock();
    return [for (final p in _positions.values) if (now.difference(p.updatedAt).inMinutes < 5) p];
  }

  @override
  Future<void> reportVehiclePosition(String vehicleId, double lat, double lng, {double? heading, double? speedKmh}) async {
    final me = _me;
    final v = _vehicles.where((x) => x.id == vehicleId).firstOrNull;
    if (v == null) throw const BackendException(BackendErrorKind.notFound, 'Vehicle not found.');
    _require(_manages(me, v.operatorId) || (v.ownerId != null && _manages(me, v.ownerId!)), 'track this vehicle');
    _positions[vehicleId] = VehiclePosition(vehicleId: vehicleId, point: LatLng(lat, lng), updatedAt: _clock(), speedKmh: speedKmh);
  }

  @override
  Future<void> stopVehicleTracking(String vehicleId) async {
    _positions.remove(vehicleId);
  }

  // ------------------------------------------------------------ partners

  @override
  Future<List<Booking>> fetchPartnerBookings() async {
    await _wait();
    final me = _me;
    _require(me.role.isPartner, 'view provider bookings');
    _completePastTrips();
    final List<Booking> scoped;
    if (me.role == UserRole.government || me.role == UserRole.admin) {
      scoped = List.of(_bookings);
    } else if (me.role == UserRole.fleetOwner) {
      final owned = {for (final v in _vehicles) if (v.ownerId == me.providerId) v.id};
      scoped = [for (final b in _bookings) if (owned.contains(b.vehicleId)) b];
    } else {
      scoped = [for (final b in _bookings) if (b.providerId == me.providerId) b];
    }
    return scoped..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<AuditEntry>> fetchAuditLog() async {
    await _wait();
    final me = _me;
    _require(me.role == UserRole.admin || me.role == UserRole.government, 'view the audit log');
    return List.of(_audit);
  }

  @override
  Future<List<AppUser>> fetchUsers() async {
    await _wait();
    _require(_me.role == UserRole.admin, 'manage user accounts');
    return [for (final a in _accounts) a.user];
  }

  @override
  Future<TransportProvider> setProviderStatus(String providerId, Verification status) async {
    await _wait();
    final me = _me;
    _require(me.role.canVerify, 'approve or suspend providers');
    _require(me.role == UserRole.admin || status != Verification.suspended, 'suspend providers (platform admins only)');
    final index = _providers.indexWhere((p) => p.id == providerId);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'Provider not found.');
    final updated = _providers[index].copyWith(status: status);
    _providers[index] = updated;
    _log(switch (status) { Verification.verified => 'Approved provider', Verification.pending => 'Returned provider to review', Verification.suspended => 'Suspended provider' }, updated.name);
    _save();
    return updated;
  }

  @override
  Future<Vehicle> setVehicleVerification(String vehicleId, Verification status) async {
    await _wait();
    _require(_me.role.canVerify, 'verify vehicles');
    final index = _vehicles.indexWhere((v) => v.id == vehicleId);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'Vehicle not found.');
    final updated = _vehicles[index].copyWith(verification: status);
    _vehicles[index] = updated;
    _log(status == Verification.verified ? 'Verified vehicle' : status == Verification.suspended ? 'Rejected vehicle' : 'Flagged vehicle for review', updated.displayName);
    _save();
    return updated;
  }

  @override
  Future<Vehicle> setVehicleStatus(String vehicleId, VehicleStatus status) async {
    await _wait();
    final me = _me;
    final index = _vehicles.indexWhere((v) => v.id == vehicleId);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'Vehicle not found.');
    final vehicle = _vehicles[index];
    _require(_manages(me, vehicle.operatorId) || (vehicle.ownerId != null && _manages(me, vehicle.ownerId!)), 'change this vehicle');
    final updated = vehicle.copyWith(status: status);
    _vehicles[index] = updated;
    _log('Set vehicle status to ${status.label.toLowerCase()}', updated.displayName);
    _save();
    return updated;
  }

  @override
  Future<Booking> completeRide(String bookingId) async {
    await _wait();
    final me = _me;
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'Booking not found.');
    final booking = _bookings[index];
    if (booking.kind != BookingKind.electric || booking.providerId == null) throw const BackendException(BackendErrorKind.validation, 'Only car rides are completed by the driver.');
    _require(_manages(me, booking.providerId!), 'complete this ride');
    if (booking.status != BookingStatus.confirmed) throw const BackendException(BackendErrorKind.validation, 'This ride is not in progress.');
    final v = _vehicles.indexWhere((x) => x.id == booking.vehicleId);
    if (v >= 0) _vehicles[v] = _vehicles[v].copyWith(status: VehicleStatus.active, monthEarnings: _vehicles[v].monthEarnings + booking.fare);
    final updated = booking.copyWith(status: BookingStatus.completed);
    _bookings[index] = updated;
    _log('Completed ride', '${booking.origin} → ${booking.destination}');
    _save();
    return updated;
  }

  @override
  Future<TransitRoute> updateRouteFare(String routeId, int fare) async {
    await _wait();
    final me = _me;
    final index = _routes.indexWhere((r) => r.id == routeId);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'Route not found.');
    _require(_manages(me, _routes[index].providerId) && me.role != UserRole.fleetOwner, 'change fares on this route');
    if (fare < 100 || fare > 20000) throw const BackendException(BackendErrorKind.validation, 'Fares must be between ₦100 and ₦20,000.');
    final updated = _routes[index].copyWith(fare: fare);
    _routes[index] = updated;
    _log('Updated fare', '${updated.code} ${updated.title} → ₦$fare');
    _save();
    return updated;
  }

  @override
  Future<Vehicle> registerVehicle({required String operatorId, required VehicleKind kind, required String plate, required String model, required int capacity, String? ownerId}) async {
    await _wait();
    final me = _me;
    _require(_manages(me, operatorId) || (ownerId != null && _manages(me, ownerId)), 'register vehicles for this provider');
    final normalised = plate.trim().toUpperCase();
    if (_vehicles.any((v) => v.plate.toUpperCase() == normalised)) {
      throw const BackendException(BackendErrorKind.validation, 'A vehicle with this plate is already registered.');
    }
    final vehicle = Vehicle(
      id: _id('v'),
      operatorId: operatorId,
      ownerId: ownerId,
      plate: normalised,
      kind: kind,
      model: model.trim(),
      capacity: capacity,
      status: VehicleStatus.inactive,
      verification: Verification.pending,
      area: 'FCT',
      monthEarnings: 0,
      batteryPct: kind.isElectric && kind != VehicleKind.train ? 100 : null,
      rangeKm: kind.isElectric && kind != VehicleKind.train ? 300 : null,
      baseFare: kind == VehicleKind.evCar ? 1200 : null,
      perKmFare: kind == VehicleKind.evCar ? 180 : null,
    );
    _vehicles.add(vehicle);
    _log('Registered vehicle', vehicle.displayName);
    _save();
    return vehicle;
  }

  @override
  Future<AppUser> setUserRole(String userId, UserRole role, {String? providerId}) async {
    await _wait();
    final me = _me;
    _require(me.role == UserRole.admin, 'change account roles');
    _require(userId != me.id, 'change your own role');
    final index = _accounts.indexWhere((a) => a.user.id == userId);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'Account not found.');
    // Admin accounts are managed by the platform owner, never from the app.
    _require(role != UserRole.admin && _accounts[index].user.role != UserRole.admin, 'change admin accounts');
    final needsProvider = role == UserRole.operator || role == UserRole.fleetOwner;
    if (needsProvider && providerId == null) throw const BackendException(BackendErrorKind.validation, 'Choose the provider this account belongs to.');
    final updated = _accounts[index].user.copyWith(role: role, providerId: providerId, clearProvider: !needsProvider);
    _accounts[index] = _accounts[index].withUser(updated);
    _log('Changed role to ${role.label}', updated.fullName);
    _save();
    return updated;
  }

  // ------------------------------------------------------------ partner registration

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<PartnerApplication> submitPartnerApplication(PartnerApplication draft, List<DocumentFile> documents) async {
    await _wait();
    final me = _me;
    final org = draft.type.isOrganisation;
    final problem = org
        ? (OrgRules.rcNumber(draft.rcNumber) ?? OrgRules.tin(draft.tin) ?? ((draft.fleetSize ?? 0) < 1 ? 'Enter how many vehicles you run.' : null))
        : (PartnerRules.chassis(draft.chassisNumber) ?? PartnerRules.plate(draft.plateNumber) ?? PartnerRules.licence(draft.licenceNumber));
    if (problem != null) throw BackendException(BackendErrorKind.validation, problem);
    if (!org && !draft.licenceExpiry.isAfter(_clock())) throw const BackendException(BackendErrorKind.validation, "Your driver's licence has expired. Renew it before applying.");
    for (final slot in draft.type.requiredDocs) {
      if (!documents.any((d) => d.slot == slot)) throw BackendException(BackendErrorKind.validation, 'Upload your ${slot.label.toLowerCase()}.');
    }
    final chassis = PartnerRules.normalise(draft.chassisNumber);
    final plate = PartnerRules.normalise(draft.plateNumber);
    final taken = !org &&
        (_applications.any((a) => a.status != ApplicationStatus.rejected && a.userId != me.id && (PartnerRules.normalise(a.chassisNumber) == chassis || PartnerRules.normalise(a.plateNumber) == plate)) ||
            _vehicles.any((v) => PartnerRules.normalise(v.plate) == plate));
    if (taken) throw const BackendException(BackendErrorKind.validation, 'This plate or chassis number is already registered on Tap A Ride.');
    if (_applications.any((a) => a.userId == me.id && a.status.isOpen)) {
      throw const BackendException(BackendErrorKind.validation, 'You already have an application under review.');
    }

    final id = _id('app');
    final stored = <DocumentFile>[];
    for (final d in documents) {
      final path = '$id/${d.slot.wire}';
      _documents[path] = d.copyWith(path: path);
      stored.add(d.copyWith(path: path));
    }
    final application = PartnerApplication.fromJson({
      ...draft.toJson(),
      'id': id,
      'user_id': me.id,
      'status': ApplicationStatus.submitted.wire,
      'chassis_number': org ? draft.chassisNumber : chassis,
      'plate_number': draft.plateNumber.trim().toUpperCase(),
      'rc_number': draft.rcNumber?.replaceAll(RegExp(r'\s'), '').toUpperCase(),
      'created_at': _clock().toUtc().toIso8601String(),
    }).copyWith(documents: stored, aiCheck: draft.aiCheck);
    _applications.insert(0, application);
    _save();
    return application;
  }

  @override
  Future<List<PartnerApplication>> fetchMyApplications() async {
    await _wait();
    final me = _me;
    return [for (final a in _applications) if (a.userId == me.id) a];
  }

  @override
  Future<List<PartnerApplication>> fetchPartnerApplications() async {
    await _wait();
    _require(_me.role.canVerify, 'review partner applications');
    return List.of(_applications);
  }

  @override
  Future<PartnerApplication> reviewPartnerApplication(String applicationId, ApplicationStatus decision, String note) async {
    await _wait();
    final me = _me;
    _require(me.role.canVerify, 'review partner applications');
    final index = _applications.indexWhere((a) => a.id == applicationId);
    if (index < 0) throw const BackendException(BackendErrorKind.notFound, 'Application not found.');
    final app = _applications[index];
    if (app.status == ApplicationStatus.approved) throw const BackendException(BackendErrorKind.validation, 'This application is already approved.');
    if (decision != ApplicationStatus.approved && note.trim().isEmpty) {
      throw const BackendException(BackendErrorKind.validation, 'Tell the applicant what to fix or why it was not approved.');
    }

    String? providerId;
    String? vehicleId;
    if (decision == ApplicationStatus.approved) {
      providerId = _id('p');
      _providers.add(TransportProvider(
        id: providerId,
        name: app.companyName?.trim().isNotEmpty == true ? app.companyName!.trim() : app.fullName,
        kind: app.type.providerKind,
        status: Verification.verified,
        area: app.area,
        contactName: app.fullName,
        contactEmail: app.email,
        joinedAt: _clock(),
        description: '${app.type.label} approved through partner registration.',
      ));
      // Private drivers bring one vehicle; organisations register their fleet from the portal afterwards.
      if (!app.type.isOrganisation) vehicleId = _id('v');
      if (vehicleId != null) _vehicles.add(Vehicle(
        id: vehicleId,
        operatorId: providerId,
        plate: app.plateNumber,
        kind: _vehicleKindFor(app),
        model: '${app.vehicleMake} ${app.vehicleModel}',
        capacity: app.seats,
        status: VehicleStatus.active,
        verification: Verification.verified,
        area: app.area,
        monthEarnings: 0,
        driverName: app.fullName,
        baseFare: 1000,
        perKmFare: 150,
        batteryPct: app.type == PartnerType.evOperator ? 100 : null,
        rangeKm: app.type == PartnerType.evOperator ? 300 : null,
      ));
      final accountIndex = _accounts.indexWhere((a) => a.user.id == app.userId);
      if (accountIndex >= 0) {
        final role = app.type == PartnerType.fleetOwner ? UserRole.fleetOwner : UserRole.operator;
        _accounts[accountIndex] = _accounts[accountIndex].withUser(_accounts[accountIndex].user.copyWith(role: role, providerId: providerId));
      }
    }
    final updated = app.copyWith(status: decision, reviewerNote: note.trim(), reviewedBy: me.fullName, reviewedAt: _clock(), providerId: providerId, vehicleId: vehicleId);
    _applications[index] = updated;
    _log(
      switch (decision) {
        ApplicationStatus.approved => 'Approved partner application',
        ApplicationStatus.rejected => 'Rejected partner application',
        ApplicationStatus.needsChanges => 'Requested changes to partner application',
        _ => 'Updated partner application',
      },
      app.type.isOrganisation ? '${app.displayName} · ${app.rcNumber ?? ''}' : '${app.fullName} · ${app.plateNumber}',
    );
    _save();
    return updated;
  }

  static VehicleKind _vehicleKindFor(PartnerApplication app) => switch (app.type) {
        PartnerType.evOperator => VehicleKind.evCar,
        PartnerType.privateDriver => app.seats > 8 ? VehicleKind.minibus : VehicleKind.car,
        _ => app.seats > 18 ? VehicleKind.bus : (app.seats > 8 ? VehicleKind.minibus : VehicleKind.car),
      };

  @override
  Future<DocumentFile> openDocument(DocumentFile document) async {
    final me = _me;
    final app = _applications.where((a) => a.documents.any((d) => d.path == document.path)).firstOrNull;
    _require(app != null && (app.userId == me.id || me.role.canVerify), 'view this document');
    return _documents[document.path] ?? document;
  }
}

class _Account {
  const _Account(this.user, this.salt, this.hash);

  factory _Account.create(AppUser user, String password) {
    final salt = base64Url.encode(List<int>.generate(12, (_) => Random.secure().nextInt(256)));
    return _Account(user, salt, _hash(salt, password));
  }

  final AppUser user;
  final String salt;
  final String hash;

  static String _hash(String salt, String password) => sha256.convert(utf8.encode('$salt:$password')).toString();

  bool matches(String password) => _hash(salt, password) == hash;
  _Account withUser(AppUser updated) => _Account(updated, salt, hash);

  Map<String, Object?> toJson() => {'user': user.toJson(), 'salt': salt, 'hash': hash};
  factory _Account.fromJson(Map<String, dynamic> json) =>
      _Account(AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)), json['salt'] as String, json['hash'] as String);
}
