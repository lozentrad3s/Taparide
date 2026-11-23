import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:latlong2/latlong.dart';

import '../account_models.dart';
import '../fleet_drivers.dart';
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

  static const _storageKey = 'taparide_demo_state_v7';

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
  List<FleetDriver> _drivers = [];

  /// Refund requests: (owner user id, request). Kept with the rest of the demo state.
  List<({String userId, RefundRequest request})> _refunds = [];

  /// Uploaded document bytes stay in memory in demo mode (too large for local storage).
  final Map<String, DocumentFile> _documents = {};
  String? _sessionUserId;

  // Events, trip links and vehicle positions live in memory in demo mode.
  late final List<RideEvent> _events = _seedEvents();
  late final List<EventBus> _eventBuses = [for (final b in _seedEventBuses()) DemoSeed.withSeedVehicle(b)];
  final Map<String, ({String adId, String userId, DateTime startedAt, bool rewarded})> _adViews = {};
  final Map<String, List<DateTime>> _adRewards = {}; // user id -> reward times
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
      List<T> list<T>(String key, T Function(Map<String, dynamic>) from) => [for (final item in (json[key] as List)) from(Map<String, dynamic>.from(item as Map))];
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
      _refunds = [
        if (json['refunds'] is List)
          for (final r in json['refunds'] as List) (userId: '${(r as Map)['user_id']}', request: RefundRequest.fromJson(Map<String, dynamic>.from(r))),
      ];
      if (json['fleet_drivers'] is List) {
        _drivers = list('fleet_drivers', FleetDriver.fromJson);
      } else {
        _seedFleetDrivers();
      }
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
    _bookings = [...DemoSeed.bookings(now), ...DemoSeed.fleetDriverBookings(now)];
    _audit = DemoSeed.audit(now);
    _wallets = {DemoSeed.uAisha: const Wallet(cardNumber: '5061004219872500', balance: 5000)};
    _applications = DemoSeed.applications(now);
    _drivers = DemoSeed.fleetDrivers();
    _seedVerificationsAndRefunds(now);
    _sessionUserId = null;
    _save();
  }

  /// Sample review queues so the admin demo shows verifications and a refund waiting.
  void _seedVerificationsAndRefunds(DateTime now) {
    AppUser? edit(String id, AppUser Function(AppUser) change) {
      final i = _accounts.indexWhere((a) => a.user.id == id);
      if (i < 0) return null;
      _accounts[i] = _accounts[i].withUser(change(_accounts[i].user));
      return _accounts[i].user;
    }

    edit(DemoSeed.uAisha, (u) => u.copyWith(nin: '12345678901', dateOfBirth: DateTime(1993, 4, 18), homeArea: 'Wuse 2', verificationStatus: VerificationStatus.verified, verified: true));
    edit('u_emeka', (u) => u.copyWith(phone: '+234 803 555 0303', nin: '22345678902', dateOfBirth: DateTime(1996, 11, 2), homeArea: 'Lugbe', verificationStatus: VerificationStatus.pending, verified: false, verificationSubmittedAt: now.subtract(const Duration(hours: 5))));
    edit('u_zainab', (u) => u.copyWith(verificationStatus: VerificationStatus.unverified, verified: false));
    edit('u_musa', (u) => u.copyWith(nin: '32345678903', dateOfBirth: DateTime(2001, 2, 9), verificationStatus: VerificationStatus.pending, verified: false, verificationSubmittedAt: now.subtract(const Duration(days: 1))));
    _refunds = [];
    final paid = _bookings.where((b) => b.userId == DemoSeed.uAisha && b.paidFromWallet && b.status != BookingStatus.cancelled).toList()..sort((a, b) => b.departureAt.compareTo(a.departureAt));
    final past = paid.where((b) => b.departureAt.isBefore(now)).firstOrNull;
    if (past != null) {
      _refunds.add((
        userId: DemoSeed.uAisha,
        request: RefundRequest(id: 1, bookingId: past.id, amount: past.fare, reason: 'The bus left before the time on my ticket, so I took another ride.', status: RefundStatus.pending, createdAt: now.subtract(const Duration(hours: 3))),
      ));
    }
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
        'wallets': {
          for (final e in _wallets.entries) e.key: {'card_number': e.value.cardNumber, 'balance': e.value.balance}
        },
        'session': _sessionUserId,
        'applications': [for (final a in _applications) a.toJson()],
        'fleet_drivers': [for (final d in _drivers) d.toJson()],
        'refunds': [
          for (final r in _refunds)
            {
              'user_id': r.userId,
              'id': r.request.id,
              'booking_id': r.request.bookingId,
              'amount': r.request.amount,
              'reason': r.request.reason,
              'status': r.request.status.wire,
              'admin_note': r.request.adminNote,
              'created_at': r.request.createdAt.toUtc().toIso8601String(),
              'reviewed_at': r.request.reviewedAt?.toUtc().toIso8601String(),
            }
        ],
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

  bool _manages(AppUser user, String providerId) => user.role == UserRole.admin || ((user.role == UserRole.operator || user.role == UserRole.fleetOwner) && user.providerId == providerId);

  Set<String> get _verifiedProviderIds => {
        for (final p in _providers)
          if (p.status == Verification.verified) p.id
      };

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
    // Ride credit is spent first, as on the live server.
    _wallets[userId] = Wallet(cardNumber: wallet.cardNumber, balance: wallet.balance - amount, rideCredit: wallet.rideCredit > amount ? wallet.rideCredit - amount : 0);
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
  bool get passwordRecovery => false;

  @override
  String? takeAuthRedirectError() => null;

  @override
  Future<void> setNewPassword(String password) async => _wait();

  @override
  Future<void> signOut() async {
    _sessionUserId = null;
    _save();
  }

  @override
  Future<void> signInWithProvider(SocialProvider provider, {String? redirectTo}) async {
    await _wait();
    throw BackendException(BackendErrorKind.validation, 'Continue with ${provider.label} works on the live app. In this demo, sign in with email.');
  }

  /// The demo has no authenticator support; two-step sign-in applies on the live app only.
  @override
  Future<TwoStepStatus> twoStepStatus() async => const TwoStepStatus(enforced: false, verified: false);

  @override
  Future<TwoStepSetup> twoStepSetup() async => throw const BackendException(BackendErrorKind.validation, 'Two-step sign-in works on the live dashboard.');

  @override
  Future<void> twoStepVerify({required String factorId, required String code}) async => throw const BackendException(BackendErrorKind.validation, 'Two-step sign-in works on the live dashboard.');

  /// The real list lives in the live database (filled from the website). The demo shows a few
  /// clearly-labelled sample sign-ups so the admin page can be tried; changes last for the session.
  List<WaitlistEntry>? _signups;

  List<WaitlistEntry> _sampleSignups() {
    final now = _clock();
    WaitlistEntry e(int id, String name, String email, String phone, String area, int refs, int daysAgo, List<(int, String)> seats) => WaitlistEntry(
          id: id,
          email: email,
          name: '$name (sample)',
          phone: phone,
          area: area,
          role: 'rider',
          code: 'SMPL${id.toString().padLeft(2, '0')}',
          referrals: refs,
          source: seats.isEmpty ? 'website' : 'tech-week',
          joinedAt: now.subtract(Duration(days: daysAgo, hours: id)),
          seats: [for (final s in seats) WaitlistSeat(event: 'abuja-tech-week-2026', day: DateTime(2026, 11, s.$1), pickup: s.$2, time: '07:00', ticket: 'TW-SMPL0$id')],
        );
    const gwagwalada = 'University of Abuja, Gwagwalada';
    const lugbe = 'Police Signboard, Lugbe';
    const nyanya = 'Checkpoint, Maraba–Nyanya';
    return [
      e(1, 'Ngozi Eze', 'ngozi.sample@example.com', '08031112222', 'Gwagwalada', 3, 0, [(24, gwagwalada), (25, gwagwalada), (26, gwagwalada)]),
      e(2, 'Ibrahim Bello', 'ibrahim.sample@example.com', '08062223333', 'Lugbe', 1, 0, [(24, lugbe), (25, lugbe), (26, lugbe)]),
      e(3, 'Chioma Okafor', 'chioma.sample@example.com', '09013334444', 'Garki', 0, 1, [(26, 'Old Parade Ground (corps members)')]),
      e(4, 'Musa Danladi', 'musa.sample@example.com', '07024445555', 'Nyanya', 2, 1, [(24, nyanya), (25, nyanya)]),
      e(5, 'Aisha Lawal', 'aisha.sample@example.com', '08105556666', 'Jabi', 0, 2, const []),
    ];
  }

  List<WaitlistEntry> get _waitlist => _signups ??= _sampleSignups();

  int _signupIndex(int id) {
    final i = _waitlist.indexWhere((e) => e.id == id);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'That sign-up no longer exists.');
    return i;
  }

  WaitlistEntry _copySignup(WaitlistEntry e, {String? name, String? phone, List<WaitlistSeat>? seats, DateTime? contactedAt, bool clearContacted = false, String? note}) => WaitlistEntry(
        id: e.id,
        email: e.email,
        name: name ?? e.name,
        phone: phone ?? e.phone,
        area: e.area,
        role: e.role,
        code: e.code,
        referredBy: e.referredBy,
        referrals: e.referrals,
        source: e.source,
        joinedAt: e.joinedAt,
        creditedAt: e.creditedAt,
        seats: seats ?? e.seats,
        contactedAt: clearContacted ? null : (contactedAt ?? e.contactedAt),
        note: note ?? e.note,
        dupPhone: e.dupPhone,
        dupName: e.dupName,
      );

  @override
  Future<List<WaitlistEntry>> fetchWaitlist() async {
    await _wait();
    _require(_me.role == UserRole.admin, 'see the waitlist');
    return List.of(_waitlist);
  }

  @override
  Future<void> setSignupContacted(int id, {required bool contacted, String? note}) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'update sign-ups');
    final i = _signupIndex(id);
    final n = note?.trim();
    _waitlist[i] = _copySignup(_waitlist[i], contactedAt: contacted ? (_waitlist[i].contactedAt ?? _clock()) : null, clearContacted: !contacted, note: n == null || n.isEmpty ? null : n);
  }

  @override
  Future<void> updateEventPass({required int id, required String event, required String pickup, required List<DateTime> days, String? name, String? phone}) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'change bus passes');
    if (days.isEmpty) throw const BackendException(BackendErrorKind.validation, 'Pick at least one day.');
    final i = _signupIndex(id);
    final e = _waitlist[i];
    final code = e.seats.where((s) => s.event == event).map((s) => s.ticket).whereType<String>().firstOrNull ?? 'TW-SMPL0$id';
    final kept = [
      for (final s in e.seats)
        if (s.event != event) s
    ];
    final n = name?.trim(), p = phone?.trim();
    _waitlist[i] = _copySignup(
      e,
      name: n == null || n.isEmpty ? null : n,
      phone: p == null || p.isEmpty ? null : p,
      seats: [...kept, for (final d in days) WaitlistSeat(event: event, day: d, pickup: pickup, time: '07:00', ticket: code)],
    );
    _log('Changed bus pass', code);
  }

  @override
  Future<void> cancelEventPass(int id, String event) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'cancel bus passes');
    final i = _signupIndex(id);
    final e = _waitlist[i];
    final seat = e.seats.where((s) => s.event == event).firstOrNull;
    if (seat == null) throw const BackendException(BackendErrorKind.notFound, 'That person has no pass for this event.');
    _waitlist[i] = _copySignup(e, seats: [
      for (final s in e.seats)
        if (s.event != event) s
    ]);
    _log('Cancelled bus pass', seat.ticket ?? e.code);
  }

  @override
  Future<void> removeSignup(int id) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'remove sign-ups');
    final i = _signupIndex(id);
    if (_waitlist[i].creditedAt != null) {
      throw const BackendException(BackendErrorKind.validation, "This sign-up's ride reward was already granted to an account; it can't be removed.");
    }
    _waitlist.removeAt(i);
    _log('Removed duplicate sign-up', 'waitlist #$id');
  }

  /// Tap-to-pay holds, worked out from the demo bookings like the live server does: a paid fare is
  /// held until 45 minutes after departure (or the trip is completed), refunded if cancelled first.
  List<({Booking booking, String status})> _payouts({String? providerId}) {
    final now = DateTime.now();
    return [
      for (final b in _bookings)
        if (b.providerId != null && b.fare > 0 && b.kind != BookingKind.tagAlong && b.paymentMethod != PaymentMethod.splitCost && (providerId == null || b.providerId == providerId))
          (
            booking: b,
            status: switch (b.status) {
              BookingStatus.cancelled || BookingStatus.declined => 'refunded',
              BookingStatus.completed => 'released',
              _ => b.departureAt.add(const Duration(minutes: 45)).isBefore(now) ? 'released' : 'held',
            },
          ),
    ];
  }

  int _sum(Iterable<({Booking booking, String status})> rows, String status) => rows.where((r) => r.status == status).fold(0, (a, r) => a + r.booking.fare);

  @override
  Future<MoneyOverview> fetchMoney() async {
    await _wait();
    _require(_me.role == UserRole.admin, 'see money');
    final wallets = _wallets.values;
    final payouts = _payouts();
    final topUps = [for (final list in _topUps.values) ...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final byProvider = <String, int>{};
    for (final r in payouts.where((r) => r.status == 'released')) {
      byProvider.update(r.booking.providerId!, (v) => v + r.booking.fare, ifAbsent: () => r.booking.fare);
    }
    return MoneyOverview(
      walletCount: wallets.length,
      walletBalance: wallets.fold(0, (a, w) => a + w.balance),
      rideCredit: wallets.fold(0, (a, w) => a + w.rideCredit),
      topupsPaid: topUps.length,
      topupsPaidAmount: topUps.fold(0, (a, t) => a + t.amount),
      topupsPending: 0,
      topupsFailed: 0,
      held: _sum(payouts, 'held'),
      released: _sum(payouts, 'released'),
      refunded: _sum(payouts, 'refunded'),
      collection: [
        for (final e in (byProvider.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
          (provider: _providers.where((p) => p.id == e.key).firstOrNull?.name ?? e.key, kind: _providers.where((p) => p.id == e.key).firstOrNull?.kind.label ?? '', available: e.value, paidOut: 0),
      ],
      recentTopups: [
        for (final t in topUps.take(25))
          (
            reference: t.reference,
            amount: t.amount,
            status: t.status,
            channel: t.channel,
            createdAt: t.createdAt,
            name: _accounts.where((a) => _topUps[a.user.id]?.contains(t) ?? false).firstOrNull?.user.fullName
          ),
      ],
    );
  }

  @override
  Future<CollectionWallet> fetchCollectionWallet() async {
    await _wait();
    _require(_me.providerId != null, 'see a collection wallet');
    final rows = _payouts(providerId: _me.providerId)..sort((a, b) => b.booking.createdAt.compareTo(a.booking.createdAt));
    return CollectionWallet(
      available: _sum(rows, 'released'),
      paidOut: 0,
      held: _sum(rows, 'held'),
      recent: [
        for (final r in rows.take(20))
          CollectionPayment(
            bookingId: r.booking.id,
            amount: r.booking.fare,
            status: r.status,
            createdAt: r.booking.createdAt,
            releaseAt: r.booking.departureAt.add(const Duration(minutes: 45)),
            title: r.booking.title ?? '${r.booking.origin} → ${r.booking.destination}',
          ),
      ],
    );
  }

  final _topUps = <String, List<TopUpRecord>>{};

  @override
  Future<List<TopUpRecord>> fetchMyTopUps() async {
    await _wait();
    return List.unmodifiable(_topUps[_me.id] ?? const <TopUpRecord>[]);
  }

  @override
  Future<SignupReward> fetchSignupReward() async {
    await _wait();
    // The sample rider joined on the website before launch; other demo riders did not.
    return _me.id == DemoSeed.uAisha ? SignupReward(granted: true, at: DateTime.now().subtract(const Duration(days: 3))) : SignupReward.none;
  }

  @override
  Future<List<EventSeatBookings>> fetchOrganiserSeatBookings() async {
    await _wait();
    _require(const {UserRole.admin, UserRole.eventPartner, UserRole.government}.contains(_me.role), 'see event bookings');
    final counts = <(DateTime, String, String), int>{};
    final people = <int>{};
    for (final e in _waitlist) {
      for (final s in e.seats.where((s) => s.event == 'abuja-tech-week-2026')) {
        people.add(e.id);
        final k = (s.day, s.pickup, s.time);
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    return [
      EventSeatBookings(
        eventId: 'ev_techweek',
        title: 'Abuja Tech Week 2026 (sample bookings)',
        venue: 'Velodrome, National Stadium',
        startsAt: DateTime(2026, 11, 24, 9),
        endsAt: DateTime(2026, 11, 26, 17),
        people: people.length,
        rows: [for (final c in counts.entries) (day: c.key.$1, area: c.key.$2, slot: c.key.$3, riders: c.value)],
        lastBooking: _clock(),
        days: [DateTime(2026, 11, 24), DateTime(2026, 11, 25), DateTime(2026, 11, 26)],
        areas: const [
          'University of Abuja, Gwagwalada',
          'Nnamdi Azikiwe Airport',
          'Old Parade Ground (corps members)',
          'Nile University',
          'Police Signboard, Lugbe',
          'Checkpoint, Maraba–Nyanya',
        ],
        slots: const ['07:00'],
      ),
    ];
  }

  // ------------------------------------------------------------ catalogue

  @override
  Future<List<TransitRoute>> fetchPublicRoutes() async {
    await _wait();
    final verified = _verifiedProviderIds;
    return [
      for (final r in _routes)
        if (r.active && verified.contains(r.providerId)) r
    ]..sort((a, b) => b.monthlyTrips.compareTo(a.monthlyTrips));
  }

  @override
  Future<List<TransportProvider>> fetchProviders() async {
    await _wait();
    final me = _me;
    if (me.role == UserRole.government || me.role == UserRole.admin) return List.of(_providers);
    return [
      for (final p in _providers)
        if (p.status == Verification.verified || p.id == me.providerId) p
    ];
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
        if ((v.verification == Verification.verified && verified.contains(v.operatorId)) || v.operatorId == me.providerId || v.ownerId == me.providerId || v.id == _driverVehicle(me)) v,
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
    final rides = [
      for (final r in _rides)
        if (!r.cancelled && r.departAt.isAfter(now.subtract(const Duration(minutes: 30)))) r
    ]..sort((a, b) => a.departAt.compareTo(b.departAt));
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
    return [
      for (final b in _bookings)
        if (b.userId == me.id) b
    ]..sort((a, b) => b.departureAt.compareTo(a.departureAt));
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
  Future<SharedRide> offerSharedRide(
      {required String origin,
      required String destination,
      required DateTime departAt,
      required int seats,
      required int costShare,
      required String vehicleLabel,
      String note = '',
      String? eventId}) async {
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
      _wallets[me.id] = Wallet(cardNumber: wallet.cardNumber, balance: wallet.balance + booking.fare, rideCredit: wallet.rideCredit);
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
    if (booking.kind == BookingKind.eventBus) {
      final k = _eventBuses.indexWhere((x) => x.id == booking.eventBusId);
      if (k >= 0) {
        final key = EventBus.slotKey(booking.departureAt);
        _eventBuses[k] = _eventBuses[k].copyWith(seatsBySlot: {..._eventBuses[k].seatsBySlot, key: max(0, _eventBuses[k].seatsAt(booking.departureAt) - 1)});
      }
    }
    if (booking.kind == BookingKind.eventTicket) {
      final k = _events.indexWhere((x) => x.id == booking.eventId);
      if (k >= 0) _events[k] = _events[k].copyWith(ticketsSold: max(0, _events[k].ticketsSold - 1));
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
    final updated = Wallet(cardNumber: wallet.cardNumber, balance: wallet.balance + amount, rideCredit: wallet.rideCredit);
    final now = DateTime.now();
    (_topUps[_me.id] ??= []).insert(0, TopUpRecord(reference: 'TAR-DEMO${now.millisecondsSinceEpoch % 1000000}', amount: amount, status: 'paid', channel: 'demo', createdAt: now, paidAt: now));
    _wallets[me.id] = updated;
    _save();
    return updated;
  }

  void _credit(String userId, int amount) {
    final w = _walletFor(userId);
    _wallets[userId] = Wallet(cardNumber: w.cardNumber, balance: w.balance + amount, rideCredit: w.rideCredit);
  }

  // ------------------------------------------------------------ Tag Along hosting

  @override
  Future<List<Booking>> fetchRideRequests() async {
    await _wait();
    final me = _me;
    final mine = {
      for (final r in _rides)
        if (r.hostId == me.id) r.id
    };
    return [
      for (final b in _bookings)
        if (b.rideId != null && mine.contains(b.rideId)) b
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
    const org = 'Capital Events Hub (sample)';
    return [
      // Real event: Tap A Ride is the official ride partner (free buses, booked on taparide.com).
      RideEvent(
          id: 'ev_techweek',
          title: 'Abuja Tech Week 2026',
          venue: 'Velodrome, National Stadium',
          area: 'Kukwaba',
          startsAt: DateTime(2026, 11, 24, 9),
          endsAt: DateTime(2026, 11, 26, 17),
          category: EventCategory.conference,
          organiserName: 'Abuja Tech & Digital Economy Week',
          sponsored: true,
          description:
              'Abuja Tech & Digital Economy Week at the Velodrome, National Stadium. Tap A Ride is the official ride partner: free buses leave at 7:00 AM sharp from University of Abuja (Gwagwalada), Nnamdi Azikiwe Airport, Old Parade Ground (corps members), Nile University, Police Signboard (Lugbe) and the checkpoint between Maraba and Nyanya. Powered by Pi-CNG & EV.',
          lat: 9.0392,
          lng: 7.4556),
      RideEvent(
          id: 'ev_showcase',
          title: 'Smart Mobility Showcase',
          venue: 'International Conference Centre',
          area: 'Central Area',
          startsAt: at(3, 10),
          endsAt: at(3, 16),
          category: EventCategory.conference,
          organiserId: 'u_events',
          organiserName: org,
          providerId: DemoSeed.pEvents,
          description: 'Sample event: demos and talks on how Abuja moves.',
          lat: 9.0412,
          lng: 7.4893,
          ticketPrice: 2000,
          ticketsTotal: 400,
          ticketsSold: 118),
      RideEvent(
          id: 'ev_music',
          title: 'Abuja Live Music Night',
          venue: 'Millennium Park',
          area: 'Maitama',
          startsAt: at(5, 18),
          endsAt: at(5, 22),
          category: EventCategory.concert,
          organiserId: 'u_events',
          organiserName: org,
          providerId: DemoSeed.pEvents,
          description: 'Sample event: an evening of live music in the park.',
          lat: 9.0718,
          lng: 7.5003,
          ticketPrice: 5000,
          ticketsTotal: 1200,
          ticketsSold: 640),
      RideEvent(
          id: 'ev_cup',
          title: 'Community Cup Final',
          venue: 'Moshood Abiola National Stadium',
          area: 'Kukwaba',
          startsAt: at(6, 20),
          endsAt: at(6, 22),
          category: EventCategory.sport,
          organiserId: 'u_events',
          organiserName: org,
          providerId: DemoSeed.pEvents,
          sponsored: true,
          description: 'Sample event: the weekend football final. Event buses run from Kubwa and Nyanya.',
          lat: 9.0379,
          lng: 7.4531),
    ];
  }

  List<EventBus> _seedEventBuses() {
    final now = _clock();
    DateTime at(int days, int hour) => DateTime(now.year, now.month, now.day + days, hour);
    Map<String, int> seats(List<(DateTime, int)> v) => {for (final e in v) EventBus.slotKey(e.$1): e.$2};
    return [
      EventBus(
          id: 'eb_kubwa',
          eventId: 'ev_cup',
          providerId: DemoSeed.pMetro,
          providerName: 'Abuja Metro Bus Co. (sample)',
          vehicleLabel: 'City bus',
          origin: 'Kubwa',
          fare: 1200,
          capacity: 40,
          minRiders: 20,
          slots: [at(6, 17), at(6, 18), at(6, 19)],
          seatsBySlot: seats([(at(6, 17), 4), (at(6, 18), 11), (at(6, 19), 7)]),
          status: EventBusStatus.open),
      EventBus(
          id: 'eb_nyanya',
          eventId: 'ev_cup',
          providerId: DemoSeed.pMetro,
          providerName: 'Abuja Metro Bus Co. (sample)',
          vehicleLabel: 'Toyota Coaster',
          origin: 'Nyanya',
          fare: 1000,
          capacity: 30,
          minRiders: 15,
          slots: [at(6, 18), at(6, 19)],
          seatsBySlot: seats([(at(6, 18), 9), (at(6, 19), 3)]),
          status: EventBusStatus.open),
      EventBus(
          id: 'eb_jabi',
          eventId: 'ev_music',
          providerId: DemoSeed.pAirport,
          providerName: 'FCT Airport E-Shuttle (sample)',
          vehicleLabel: 'Electric shuttle',
          origin: 'Jabi',
          fare: 800,
          capacity: 14,
          minRiders: 8,
          slots: [at(5, 16), at(5, 17)],
          seatsBySlot: seats([(at(5, 17), 8)]),
          status: EventBusStatus.confirmed,
          confirmedAt: at(5, 17)),
    ];
  }

  @override
  Future<List<RideEvent>> fetchEvents() async {
    await _wait();
    _me;
    final now = _clock();
    return [
      for (final e in _events)
        if ((e.endsAt ?? e.startsAt).isAfter(now.subtract(const Duration(hours: 6)))) e
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  @override
  Future<RideEvent> createEvent(
      {required String title,
      required String venue,
      required String area,
      required DateTime startsAt,
      DateTime? endsAt,
      required EventCategory category,
      String description = '',
      double? lat,
      double? lng,
      int ticketPrice = 0,
      int ticketsTotal = 0,
      String? ticketLink}) async {
    await _wait();
    final me = _me;
    if (me.role != UserRole.eventPartner && me.role != UserRole.admin) {
      throw const BackendException(BackendErrorKind.permission, 'Only event partners can list events. Apply as an event partner to post yours.');
    }
    final org = _providers.where((p) => p.id == me.providerId).firstOrNull;
    if (me.role == UserRole.eventPartner && org?.status != Verification.verified) {
      throw const BackendException(BackendErrorKind.permission, 'Your organisation is not verified yet.');
    }
    if (startsAt.isBefore(_clock())) throw const BackendException(BackendErrorKind.validation, 'Choose a start time later than now.');
    if (ticketPrice > 0 && ticketsTotal < 1) throw const BackendException(BackendErrorKind.validation, 'Set how many tickets are for sale.');
    final event = RideEvent(
      id: _id('ev'),
      title: title.trim(),
      venue: venue.trim(),
      area: area.trim().isEmpty ? 'Abuja' : area.trim(),
      startsAt: startsAt,
      endsAt: endsAt,
      category: category,
      description: description.trim(),
      organiserId: me.id,
      organiserName: org?.name ?? me.organisation ?? me.fullName,
      providerId: me.providerId,
      lat: lat,
      lng: lng,
      ticketPrice: max(0, ticketPrice),
      ticketsTotal: max(0, ticketsTotal),
      sponsored: me.role == UserRole.admin,
      ticketLink: ticketLink,
    );
    _events.add(event);
    _log('Listed event', event.title);
    _save();
    return event;
  }

  @override
  Future<void> removeEvent(String eventId) async {
    await _wait();
    final me = _me;
    final event = _events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) throw const BackendException(BackendErrorKind.notFound, 'Event not found.');
    _require(me.role.canVerify || (me.role == UserRole.eventPartner && event.providerId == me.providerId), 'remove this event');
    _events.remove(event);
    for (var i = 0; i < _bookings.length; i++) {
      final b = _bookings[i];
      if (b.eventId == eventId && b.status.isOpen) {
        _credit(b.userId, b.fare);
        _bookings[i] = b.copyWith(status: BookingStatus.cancelled);
      }
    }
    _eventBuses.removeWhere((b) => b.eventId == eventId);
    _log('Removed event', event.title);
    _save();
  }

  @override
  Future<Booking> buyEventTicket(String eventId, PaymentMethod method) async {
    await _wait();
    final me = _me;
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'Event not found.');
    final e = _events[i];
    if (e.startsAt.isBefore(_clock())) throw const BackendException(BackendErrorKind.validation, 'This event has started.');
    if (!e.sellsTickets) throw const BackendException(BackendErrorKind.validation, 'Tickets for this event are not sold on Tap A Ride.');
    if (e.ticketsLeft <= 0) throw const BackendException(BackendErrorKind.validation, 'Sold out.');
    if (_bookings.where((b) => b.userId == me.id && b.eventId == e.id && b.kind == BookingKind.eventTicket && b.status.isOpen).length >= 4) {
      throw const BackendException(BackendErrorKind.validation, 'You can hold up to 4 tickets for one event.');
    }
    if (e.ticketPrice > 0) _charge(me.id, e.ticketPrice);
    _events[i] = e.copyWith(ticketsSold: e.ticketsSold + 1);
    final booking = Booking(
        id: _id('bk'),
        userId: me.id,
        passengerName: me.fullName,
        kind: BookingKind.eventTicket,
        status: BookingStatus.confirmed,
        origin: e.venue,
        destination: e.venue,
        departureAt: e.startsAt,
        fare: e.ticketPrice,
        paymentMethod: method,
        ticketCode: _ticket('ET'),
        createdAt: _clock(),
        title: e.title,
        seat: 'Entry',
        providerId: e.providerId,
        eventId: e.id);
    _bookings.add(booking);
    _save();
    return booking;
  }

  // ------------------------------------------------------------ event buses

  @override
  Future<List<EventBus>> fetchEventBuses() async {
    await _wait();
    _me;
    return [
      for (final b in _eventBuses)
        if (b.status != EventBusStatus.cancelled) b
    ];
  }

  @override
  Future<EventBus> offerEventBus(
      {required String eventId, required String origin, required int fare, required int capacity, required int minRiders, required List<DateTime> slots, String? vehicleId}) async {
    await _wait();
    final me = _me;
    if (me.role != UserRole.operator && me.role != UserRole.admin) {
      throw const BackendException(BackendErrorKind.permission, 'Only registered bus operators can run event buses.');
    }
    final org = _providers.where((p) => p.id == (me.providerId ?? DemoSeed.pMetro)).firstOrNull;
    if (org == null || org.status != Verification.verified) throw const BackendException(BackendErrorKind.permission, 'Your company is not verified yet.');
    if (!{ProviderKind.busOperator, ProviderKind.shuttle, ProviderKind.electric}.contains(org.kind)) {
      throw const BackendException(BackendErrorKind.permission, 'Event buses need a bus, shuttle or electric fleet operator.');
    }
    final event = _events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) throw const BackendException(BackendErrorKind.notFound, 'Event not found.');
    if (slots.isEmpty) throw const BackendException(BackendErrorKind.validation, 'Add at least one departure time.');
    if (slots.length > 4) throw const BackendException(BackendErrorKind.validation, 'Offer up to 4 departure times.');
    if (slots.any((t) => t.isBefore(_clock()) || t.isAfter(event.startsAt))) {
      throw const BackendException(BackendErrorKind.validation, 'Departure times must be before the event starts.');
    }
    if (fare < 100 || fare > 20000) throw const BackendException(BackendErrorKind.validation, 'Set a fare between ₦100 and ₦20,000.');
    Vehicle? v;
    if (vehicleId != null) {
      v = _vehicles.where((x) => x.id == vehicleId && x.operatorId == org.id && x.verification == Verification.verified).firstOrNull;
      if (v == null) throw const BackendException(BackendErrorKind.validation, 'Pick one of your verified vehicles.');
    }
    final cap = v?.capacity ?? capacity;
    final bus = EventBus(
      id: _id('eb'),
      eventId: eventId,
      providerId: org.id,
      providerName: org.name,
      vehicleId: v?.id,
      vehicleLabel: v == null ? '' : '${v.model} · ${v.plate}',
      origin: origin.trim(),
      fare: fare,
      capacity: cap,
      minRiders: minRiders.clamp(1, cap),
      slots: [...slots]..sort(),
      seatsBySlot: const {},
      status: EventBusStatus.open,
    );
    _eventBuses.add(bus);
    _log('Offered event bus', '${event.title} from ${bus.origin}');
    _save();
    return bus;
  }

  @override
  Future<Booking> bookEventBus(String busId, DateTime slot, PaymentMethod method) async {
    await _wait();
    final me = _me;
    final i = _eventBuses.indexWhere((b) => b.id == busId);
    if (i < 0 || _eventBuses[i].status == EventBusStatus.cancelled) throw const BackendException(BackendErrorKind.notFound, 'This bus is no longer running.');
    final bus = _eventBuses[i];
    final event = _events.where((e) => e.id == bus.eventId).firstOrNull;
    if (event == null) throw const BackendException(BackendErrorKind.notFound, 'This event has been removed.');
    final when = bus.status == EventBusStatus.confirmed ? bus.confirmedAt! : slot;
    if (!bus.slots.any((s) => s.isAtSameMomentAs(when))) throw const BackendException(BackendErrorKind.validation, 'Pick one of the departure times offered.');
    if (when.isBefore(_clock())) throw const BackendException(BackendErrorKind.validation, 'That departure has already left.');
    if (_bookings.any((b) => b.userId == me.id && b.eventBusId == bus.id && b.status.isOpen)) {
      throw const BackendException(BackendErrorKind.validation, 'You already have a seat on this bus.');
    }
    final taken = bus.seatsAt(when);
    if (taken >= bus.capacity) throw const BackendException(BackendErrorKind.validation, 'That departure is full. Pick another time.');
    _charge(me.id, bus.fare);
    _eventBuses[i] = bus.copyWith(seatsBySlot: {...bus.seatsBySlot, EventBus.slotKey(when): taken + 1});
    final booking = Booking(
      id: _id('bk'),
      userId: me.id,
      passengerName: me.fullName,
      kind: BookingKind.eventBus,
      status: bus.status == EventBusStatus.confirmed ? BookingStatus.confirmed : BookingStatus.requested,
      origin: bus.origin,
      destination: event.venue,
      departureAt: when,
      fare: bus.fare,
      paymentMethod: method,
      ticketCode: _ticket('EB'),
      createdAt: _clock(),
      title: event.title,
      seat: 'S${(taken + 1).toString().padLeft(2, '0')}',
      vehicleId: bus.vehicleId,
      providerId: bus.providerId,
      eventId: event.id,
      eventBusId: bus.id,
    );
    _bookings.add(booking);
    _save();
    return booking;
  }

  @override
  Future<EventBus> confirmEventBus(String busId, DateTime slot) async {
    await _wait();
    final me = _me;
    final i = _eventBuses.indexWhere((b) => b.id == busId);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'Bus not found.');
    final bus = _eventBuses[i];
    _require(_manages(me, bus.providerId), 'confirm this bus');
    if (!bus.slots.any((s) => s.isAtSameMomentAs(slot))) throw const BackendException(BackendErrorKind.validation, 'Pick one of the offered times.');
    // Seeded seat counts stand for riders without accounts on this device.
    final total = bus.riders;
    if (total > bus.capacity) throw const BackendException(BackendErrorKind.validation, 'More riders than seats: add a second bus first.');
    for (var k = 0; k < _bookings.length; k++) {
      final b = _bookings[k];
      if (b.eventBusId == bus.id && b.status.isOpen) _bookings[k] = b.copyWith(status: BookingStatus.confirmed, departureAt: slot);
    }
    _eventBuses[i] = bus.copyWith(status: EventBusStatus.confirmed, confirmedAt: slot, seatsBySlot: {EventBus.slotKey(slot): total});
    _log('Confirmed event bus', bus.origin);
    _save();
    return _eventBuses[i];
  }

  @override
  Future<EventBus> cancelEventBus(String busId) async {
    await _wait();
    final me = _me;
    final i = _eventBuses.indexWhere((b) => b.id == busId);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'Bus not found.');
    _require(_manages(me, _eventBuses[i].providerId), 'cancel this bus');
    for (var k = 0; k < _bookings.length; k++) {
      final b = _bookings[k];
      if (b.eventBusId == busId && b.status.isOpen) {
        _credit(b.userId, b.fare);
        _bookings[k] = b.copyWith(status: BookingStatus.cancelled);
      }
    }
    _eventBuses[i] = _eventBuses[i].copyWith(status: EventBusStatus.cancelled, seatsBySlot: const {});
    _log('Cancelled event bus', _eventBuses[i].origin);
    _save();
    return _eventBuses[i];
  }

  // ------------------------------------------------------------ header ads

  static const _ads = [
    PromoAd(
        id: 'ad_advertise',
        sponsor: 'Tap A Ride',
        headline: 'Your brand here, in front of Abuja commuters',
        body: 'Reach riders on every trip without interrupting them. Ask about header slots and sponsored rides.',
        ctaLabel: 'Advertise with us',
        ctaLink: 'mailto:hello@taparide.app',
        colour: Color(0xFF0B5D3B),
        icon: 'campaign',
        reward: 50,
        seconds: 15,
        house: true),
    PromoAd(
        id: 'ad_ev',
        sponsor: 'Tap A Ride Electric',
        headline: 'Go electric this week',
        body: 'Verified electric cars across Maitama, Wuse and Jabi. Quiet, clean and fixed fares.',
        ctaLabel: 'Book an EV',
        ctaLink: '/ev',
        colour: Color(0xFF0E7C66),
        icon: 'electric_car',
        reward: 50,
        seconds: 15,
        house: true),
    PromoAd(
        id: 'ad_events',
        sponsor: 'Tap A Ride Events',
        headline: 'Event buses: skip the parking',
        body: 'Book a seat on a bus to the stadium or the conference centre and ride back together.',
        ctaLabel: 'See event rides',
        ctaLink: '/events',
        colour: Color(0xFF1F3A8A),
        icon: 'celebration',
        reward: 50,
        seconds: 15,
        house: true),
  ];

  int _rewardsLeft(String userId) {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    return max(0, 3 - (_adRewards[userId] ?? const []).where((t) => !t.isBefore(today)).length);
  }

  @override
  Future<List<PromoAd>> fetchAds() async {
    await _wait();
    _me;
    return _ads;
  }

  @override
  Future<void> countAdImpressions(List<String> adIds) async {}

  @override
  Future<AdView> startAdView(String adId) async {
    await _wait();
    final me = _me;
    if (!_ads.any((a) => a.id == adId)) throw const BackendException(BackendErrorKind.notFound, 'This ad has ended.');
    final id = _id('av');
    _adViews[id] = (adId: adId, userId: me.id, startedAt: _clock(), rewarded: false);
    return AdView(id: id, adId: adId);
  }

  @override
  Future<AdReward> claimAdReward(String viewId) async {
    await _wait();
    final me = _me;
    final v = _adViews[viewId];
    if (v == null || v.userId != me.id) throw const BackendException(BackendErrorKind.notFound, 'Ad view not found.');
    if (v.rewarded) throw const BackendException(BackendErrorKind.validation, 'You already earned this reward.');
    final ad = _ads.firstWhere((a) => a.id == v.adId);
    if (_clock().difference(v.startedAt).inSeconds < ad.seconds - 1) throw const BackendException(BackendErrorKind.validation, 'Watch the whole ad to earn the reward.');
    final credit = _rewardsLeft(me.id) > 0 ? ad.reward : 0;
    _adViews[viewId] = (adId: v.adId, userId: v.userId, startedAt: v.startedAt, rewarded: true);
    if (credit > 0) {
      _adRewards.putIfAbsent(me.id, () => []).add(_clock());
      _credit(me.id, credit);
      _save();
    }
    return AdReward(reward: credit, balance: _walletFor(me.id).balance, left: _rewardsLeft(me.id));
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
    return [
      for (final p in _positions.values)
        if (now.difference(p.updatedAt).inMinutes < 5) p
    ];
  }

  @override
  Future<void> reportVehiclePosition(String vehicleId, double lat, double lng, {double? heading, double? speedKmh}) async {
    final me = _me;
    final v = _vehicles.where((x) => x.id == vehicleId).firstOrNull;
    if (v == null) throw const BackendException(BackendErrorKind.notFound, 'Vehicle not found.');
    _require(_manages(me, v.operatorId) || (v.ownerId != null && _manages(me, v.ownerId!)) || _driverVehicle(me) == v.id, 'track this vehicle');
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
    } else if (me.role == UserRole.eventPartner) {
      final mine = {
        for (final e in _events)
          if (e.providerId == me.providerId) e.id
      };
      scoped = [
        for (final b in _bookings)
          if (mine.contains(b.eventId)) b
      ];
    } else if (me.role == UserRole.fleetDriver) {
      scoped = _driverBookings(me);
    } else if (me.role == UserRole.fleetOwner) {
      final owned = {
        for (final v in _vehicles)
          if (v.ownerId == me.providerId) v.id
      };
      scoped = [
        for (final b in _bookings)
          if (owned.contains(b.vehicleId)) b
      ];
    } else {
      scoped = [
        for (final b in _bookings)
          if (b.providerId == me.providerId) b
      ];
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
    _log(
        status == Verification.verified
            ? 'Verified vehicle'
            : status == Verification.suspended
                ? 'Rejected vehicle'
                : 'Flagged vehicle for review',
        updated.displayName);
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

  // ------------------------------------------------------------ fleet drivers

  /// Saved demo states from before fleet drivers: add the sample driver, their login and riders.
  void _seedFleetDrivers() {
    _drivers = DemoSeed.fleetDrivers();
    final login = DemoSeed.users().firstWhere((u) => u.id == DemoSeed.uFleetDriver);
    if (!_accounts.any((a) => a.user.id == login.id || a.user.email == login.email)) _accounts.add(_Account.create(login, DemoSeed.password));
    if (!_bookings.any((b) => b.id.startsWith('bk_fd_'))) _bookings.addAll(DemoSeed.fleetDriverBookings(_clock()));
  }

  /// The signed-in fleet driver's own record (null for everyone else).
  FleetDriver? _driverRecord(AppUser me) => me.role == UserRole.fleetDriver ? _drivers.where((d) => d.userId == me.id).firstOrNull : null;

  /// The vehicle the signed-in driver may work on right now (none while suspended).
  String? _driverVehicle(AppUser me) {
    final d = _driverRecord(me);
    return d != null && d.active ? d.vehicleId : null;
  }

  /// Bookings on the driver's vehicle, including seats on event buses it runs.
  List<Booking> _driverBookings(AppUser me) {
    final vehicle = _driverVehicle(me);
    if (vehicle == null) return [];
    final buses = {
      for (final b in _eventBuses)
        if (b.vehicleId == vehicle) b.id
    };
    return [
      for (final b in _bookings)
        if (b.vehicleId == vehicle || buses.contains(b.eventBusId)) b
    ];
  }

  /// Drivers go only on the company's own vehicles, and on routes those vehicles run.
  void _checkAssignment(String providerId, String? vehicleId, String? routeId) {
    if (vehicleId == null) {
      if (routeId != null) throw const BackendException(BackendErrorKind.validation, 'Pick a vehicle before choosing a route.');
      return;
    }
    final v = _vehicles.where((x) => x.id == vehicleId).firstOrNull;
    if (v == null) throw const BackendException(BackendErrorKind.notFound, 'Vehicle not found.');
    if (v.operatorId != providerId && v.ownerId != providerId) throw const BackendException(BackendErrorKind.permission, 'You can only assign drivers to your own vehicles.');
    if (v.verification == Verification.suspended) throw const BackendException(BackendErrorKind.validation, 'This vehicle is suspended from the register.');
    if (routeId == null) return;
    final r = _routes.where((x) => x.id == routeId).firstOrNull;
    if (r == null) throw const BackendException(BackendErrorKind.notFound, 'Route not found.');
    if (r.providerId != v.operatorId && r.providerId != providerId) throw const BackendException(BackendErrorKind.validation, 'Pick a route this vehicle runs on.');
  }

  /// The register shows who drives each vehicle.
  void _setVehicleDriver(String? vehicleId, String name) {
    final k = _vehicles.indexWhere((v) => v.id == vehicleId);
    if (k >= 0) _vehicles[k] = Vehicle.fromJson({..._vehicles[k].toJson(), 'driver_name': name});
  }

  @override
  Future<List<FleetDriver>> fetchFleetDrivers() async {
    await _wait();
    final me = _me;
    if (me.role == UserRole.admin) return List.of(_drivers);
    if (me.role == UserRole.operator || me.role == UserRole.fleetOwner)
      return [
        for (final d in _drivers)
          if (d.providerId == me.providerId) d
      ];
    return [
      for (final d in _drivers)
        if (d.userId == me.id) d
    ];
  }

  @override
  Future<FleetDriver> addFleetDriver(
      {required String fullName, required String phone, required String email, required String licenceNumber, String? providerId, String? vehicleId, String? routeId}) async {
    await _wait();
    final me = _me;
    final companyId = providerId ?? me.providerId;
    _require(companyId != null && _manages(me, companyId), 'add drivers for this company');
    final company = _providers.where((p) => p.id == companyId).firstOrNull;
    if (company == null) throw const BackendException(BackendErrorKind.notFound, 'Company not found.');
    _require(company.kind != ProviderKind.privateDriver && company.kind != ProviderKind.eventOrganiser, 'add drivers (only fleet owners and bus or EV operators can)');
    final problem = FleetDriverRules.name(fullName) ?? FleetDriverRules.email(email) ?? FleetDriverRules.phone(phone) ?? FleetDriverRules.licence(licenceNumber);
    if (problem != null) throw BackendException(BackendErrorKind.validation, problem);
    final normalised = email.trim().toLowerCase();
    if (_drivers.any((d) => d.email.toLowerCase() == normalised)) throw const BackendException(BackendErrorKind.validation, 'A driver with this email is already registered.');
    _checkAssignment(company.id, vehicleId, routeId);
    // Their login: an existing passenger account with this email, or a new one (demo password).
    final i = _accounts.indexWhere((a) => a.user.email.toLowerCase() == normalised);
    if (i >= 0 && _accounts[i].user.role != UserRole.passenger) {
      throw const BackendException(BackendErrorKind.validation, "This email belongs to another partner account. Use the driver's personal email.");
    }
    final AppUser login;
    if (i >= 0) {
      login = _accounts[i].user.copyWith(role: UserRole.fleetDriver, clearProvider: true, organisation: company.name);
      _accounts[i] = _accounts[i].withUser(login);
    } else {
      login = AppUser(id: _id('u'), fullName: fullName.trim(), email: normalised, phone: phone.trim(), role: UserRole.fleetDriver, organisation: company.name, createdAt: _clock());
      _accounts.add(_Account.create(login, DemoSeed.password));
    }
    final driver = FleetDriver(
      id: _id('fd'),
      providerId: company.id,
      userId: login.id,
      fullName: fullName.trim(),
      phone: phone.trim(),
      email: normalised,
      licenceNumber: licenceNumber.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
      vehicleId: vehicleId,
      routeId: vehicleId == null ? null : routeId,
      status: FleetDriverStatus.active,
      createdAt: _clock(),
    );
    _drivers.add(driver);
    if (vehicleId != null) _setVehicleDriver(vehicleId, driver.fullName);
    _log('Added driver', '${driver.fullName} · ${company.name}');
    _save();
    return driver;
  }

  @override
  Future<FleetDriver> assignFleetDriver(String driverId, {String? vehicleId, String? routeId}) async {
    await _wait();
    final me = _me;
    final i = _drivers.indexWhere((d) => d.id == driverId);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'Driver not found.');
    _require(_manages(me, _drivers[i].providerId), 'manage this driver');
    _checkAssignment(_drivers[i].providerId, vehicleId, routeId);
    _drivers[i] = _drivers[i].copyWith(vehicleId: vehicleId, routeId: routeId, clearAssignment: vehicleId == null, clearRoute: routeId == null);
    final v = _vehicles.where((x) => x.id == vehicleId).firstOrNull;
    if (v != null) _setVehicleDriver(v.id, _drivers[i].fullName);
    _log(v == null ? 'Unassigned driver' : 'Assigned driver', v == null ? _drivers[i].fullName : '${_drivers[i].fullName} → ${v.displayName}');
    _save();
    return _drivers[i];
  }

  @override
  Future<FleetDriver> setFleetDriverStatus(String driverId, FleetDriverStatus status) async {
    await _wait();
    final me = _me;
    final i = _drivers.indexWhere((d) => d.id == driverId);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'Driver not found.');
    _require(_manages(me, _drivers[i].providerId), 'suspend or reactivate this driver');
    _drivers[i] = _drivers[i].copyWith(status: status);
    // A suspended driver's vehicle drops off the live map.
    if (status == FleetDriverStatus.suspended && _drivers[i].vehicleId != null) _positions.remove(_drivers[i].vehicleId);
    _log(status == FleetDriverStatus.suspended ? 'Suspended driver' : 'Reactivated driver', _drivers[i].fullName);
    _save();
    return _drivers[i];
  }

  @override
  Future<Booking> driverBookingAction(String bookingId, DriverBookingAction action) async {
    await _wait();
    final me = _me;
    _require(me.role == UserRole.fleetDriver, 'update rides from the driver dashboard');
    if (_driverVehicle(me) == null) throw const BackendException(BackendErrorKind.permission, 'You are not assigned to a vehicle right now. Ask your fleet manager.');
    final i = _bookings.indexWhere((b) => b.id == bookingId);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'Booking not found.');
    final b = _bookings[i];
    _require(_driverBookings(me).any((x) => x.id == b.id), 'update this booking (it is not on your vehicle)');
    switch (action) {
      case DriverBookingAction.accept:
        if (b.kind == BookingKind.eventBus && b.status == BookingStatus.requested) {
          throw const BackendException(BackendErrorKind.validation, 'This seat is confirmed once the operator fixes the departure time.');
        }
        if (b.status != BookingStatus.confirmed) throw const BackendException(BackendErrorKind.validation, 'This booking is not waiting for you.');
        _bookings[i] = b.copyWith(status: BookingStatus.accepted);
      case DriverBookingAction.complete:
        if (b.status != BookingStatus.confirmed && b.status != BookingStatus.accepted) throw const BackendException(BackendErrorKind.validation, 'This booking is not in progress.');
        _bookings[i] = b.copyWith(status: BookingStatus.completed);
        if (b.kind == BookingKind.electric) {
          final v = _vehicles.indexWhere((x) => x.id == b.vehicleId);
          if (v >= 0) _vehicles[v] = _vehicles[v].copyWith(status: VehicleStatus.active, monthEarnings: _vehicles[v].monthEarnings + b.fare);
        }
        _log('Completed ride', '${b.passengerName} · ${b.origin} → ${b.destination}');
    }
    _save();
    return _bookings[i];
  }

  @override
  Future<Vehicle> driverSetTrip({required bool start}) async {
    await _wait();
    final me = _me;
    _require(me.role == UserRole.fleetDriver, 'start or end trips');
    final vehicle = _driverVehicle(me);
    if (vehicle == null) throw const BackendException(BackendErrorKind.permission, 'You are not assigned to a vehicle right now. Ask your fleet manager.');
    final k = _vehicles.indexWhere((v) => v.id == vehicle);
    if (k < 0) throw const BackendException(BackendErrorKind.notFound, 'Vehicle not found.');
    final v = _vehicles[k];
    if (start) {
      if (v.status == VehicleStatus.maintenance || v.status == VehicleStatus.inactive) {
        throw BackendException(BackendErrorKind.validation, 'Your vehicle is marked ${v.status.label.toLowerCase()}. Ask your fleet manager before starting a trip.');
      }
      _vehicles[k] = v.copyWith(status: VehicleStatus.onTrip);
    } else {
      _vehicles[k] = v.copyWith(status: VehicleStatus.active);
      // Riders who boarded for a departure that has left are dropped off.
      final now = _clock().add(const Duration(minutes: 1));
      for (var i = 0; i < _bookings.length; i++) {
        final b = _bookings[i];
        if (b.vehicleId == vehicle && b.status == BookingStatus.accepted && b.departureAt.isBefore(now)) _bookings[i] = b.copyWith(status: BookingStatus.completed);
      }
    }
    _log(start ? 'Started trip' : 'Ended trip', v.displayName);
    _save();
    return _vehicles[k];
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
        (_applications
                .any((a) => a.status != ApplicationStatus.rejected && a.userId != me.id && (PartnerRules.normalise(a.chassisNumber) == chassis || PartnerRules.normalise(a.plateNumber) == plate)) ||
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
    return [
      for (final a in _applications)
        if (a.userId == me.id) a
    ];
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
      if (vehicleId != null)
        _vehicles.add(Vehicle(
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

  // ------------------------------------------------------------ profile, verification, refunds

  void _replaceUser(AppUser updated) {
    final i = _accounts.indexWhere((a) => a.user.id == updated.id);
    if (i >= 0) _accounts[i] = _accounts[i].withUser(updated);
  }

  static String _digits(String? v) => (v ?? '').replaceAll(RegExp(r'\D'), '');

  @override
  Future<AppUser> updateMyProfile({required String fullName, String? phone, String? homeArea, String? emergencyName, String? emergencyPhone}) async {
    await _wait();
    final me = _me;
    final name = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.split(' ').length < 2) throw const BackendException(BackendErrorKind.validation, 'Enter your first and last name.');
    if ((phone ?? '').trim().isNotEmpty && _digits(phone).length < 10) throw const BackendException(BackendErrorKind.validation, 'Enter a valid phone number, e.g. 0803 123 4567.');
    if ((emergencyPhone ?? '').trim().isNotEmpty && _digits(emergencyPhone).length < 10) throw const BackendException(BackendErrorKind.validation, 'Enter a valid emergency contact number.');
    final renamed = me.isVerified && me.role == UserRole.passenger && me.fullName.toLowerCase() != name.toLowerCase();
    final updated = me.copyWith(
      fullName: name,
      phone: (phone ?? '').trim(),
      homeArea: (homeArea ?? '').trim(),
      emergencyName: (emergencyName ?? '').trim(),
      emergencyPhone: (emergencyPhone ?? '').trim(),
      verificationStatus: renamed ? VerificationStatus.pending : null,
      verified: renamed ? false : null,
    );
    _replaceUser(updated);
    _save();
    return updated;
  }

  @override
  Future<AppUser> submitVerification({required String nin, required DateTime dateOfBirth, required String phone}) async {
    await _wait();
    final me = _me;
    final n = _digits(nin);
    if (me.verificationStatus == VerificationStatus.pending) throw const BackendException(BackendErrorKind.validation, 'Your verification is already being reviewed.');
    if (me.verificationStatus == VerificationStatus.verified) throw const BackendException(BackendErrorKind.validation, 'Your verification is already complete.');
    if (n.length != 11) throw const BackendException(BackendErrorKind.validation, 'Your NIN has 11 digits.');
    if (me.nin != null && me.nin != n) throw const BackendException(BackendErrorKind.validation, 'Your NIN is already on file; contact support to change it.');
    if (_accounts.any((a) => a.user.id != me.id && a.user.nin == n)) throw const BackendException(BackendErrorKind.validation, 'This NIN is already used by another account.');
    final now = _clock();
    final sixteen = DateTime(now.year - 16, now.month, now.day);
    if (dateOfBirth.isAfter(sixteen) || dateOfBirth.isBefore(DateTime(1920))) throw const BackendException(BackendErrorKind.validation, 'Enter your date of birth (you must be 16 or older).');
    if (_digits(phone).length < 10) throw const BackendException(BackendErrorKind.validation, 'Enter your phone number.');
    final updated = me.copyWith(nin: n, dateOfBirth: me.dateOfBirth ?? dateOfBirth, phone: phone.trim(), verificationStatus: VerificationStatus.pending, clearVerificationNote: true, verificationSubmittedAt: now);
    _replaceUser(updated);
    _save();
    return updated;
  }

  @override
  Future<List<RiderVerification>> fetchRiderVerifications(String status) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'see rider verifications');
    String key(String? p) {
      final d = _digits(p);
      return d.length >= 10 ? d.substring(d.length - 10) : d;
    }

    final riders = _accounts.map((a) => a.user).where((u) => u.role == UserRole.passenger && (status == 'all' || u.verificationStatus.wire == status)).toList()
      ..sort((a, b) => (b.verificationSubmittedAt ?? b.createdAt).compareTo(a.verificationSubmittedAt ?? a.createdAt));
    return [
      for (final u in riders)
        RiderVerification(
          id: u.id,
          name: u.fullName,
          email: u.email,
          status: u.verificationStatus.wire,
          phone: u.phone,
          nin: u.nin,
          dateOfBirth: u.dateOfBirth,
          homeArea: u.homeArea,
          emergencyName: u.emergencyName,
          emergencyPhone: u.emergencyPhone,
          note: u.verificationNote,
          submittedAt: u.verificationSubmittedAt,
          createdAt: u.createdAt,
          phoneShared: key(u.phone).isNotEmpty && _accounts.any((o) => o.user.id != u.id && key(o.user.phone) == key(u.phone)),
        ),
    ];
  }

  @override
  Future<void> reviewVerification(String userId, {required bool approve, String? note}) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'review rider verifications');
    final account = _accounts.where((a) => a.user.id == userId).firstOrNull;
    if (account == null || account.user.role != UserRole.passenger) throw const BackendException(BackendErrorKind.notFound, 'That rider has no verification to review.');
    final n = (note ?? '').trim();
    _replaceUser(account.user.copyWith(
      verificationStatus: approve ? VerificationStatus.verified : VerificationStatus.rejected,
      verified: approve,
      verificationNote: n.isEmpty ? null : n,
      clearVerificationNote: n.isEmpty,
    ));
    _log(approve ? 'Verified rider' : 'Declined rider verification', account.user.fullName);
    _save();
  }

  @override
  Future<RefundRequest> requestRefund(String bookingId, String reason) async {
    await _wait();
    final me = _me;
    final b = _bookings.where((x) => x.id == bookingId && x.userId == me.id).firstOrNull;
    if (b == null) throw const BackendException(BackendErrorKind.notFound, "That booking isn't on your account.");
    final why = reason.trim();
    if (why.length < 5) throw const BackendException(BackendErrorKind.validation, 'Tell us briefly what went wrong.');
    if (b.refundedAt != null || b.status == BookingStatus.cancelled || b.status == BookingStatus.declined) throw const BackendException(BackendErrorKind.validation, 'This booking has already been refunded.');
    if (!b.paidFromWallet) throw const BackendException(BackendErrorKind.validation, 'This booking was free; there is nothing to refund.');
    if (b.createdAt.isBefore(_clock().subtract(const Duration(days: 14)))) throw const BackendException(BackendErrorKind.validation, 'Refunds can be requested up to 14 days after booking.');
    if (_refunds.any((r) => r.request.bookingId == b.id && r.request.status == RefundStatus.pending)) {
      throw const BackendException(BackendErrorKind.validation, "You already asked for a refund on this booking; we'll get back to you.");
    }
    final id = _refunds.fold<int>(0, (m, r) => max(m, r.request.id)) + 1;
    final request = RefundRequest(id: id, bookingId: b.id, amount: b.fare, reason: why.length > 500 ? why.substring(0, 500) : why, status: RefundStatus.pending, createdAt: _clock());
    _refunds.add((userId: me.id, request: request));
    _save();
    return request;
  }

  @override
  Future<List<RefundRequest>> fetchMyRefunds() async {
    await _wait();
    final me = _me;
    return [for (final r in _refunds.reversed) if (r.userId == me.id) r.request];
  }

  @override
  Future<List<AdminRefund>> fetchRefundRequests(String status) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'see refund requests');
    final out = <AdminRefund>[];
    for (final r in _refunds.reversed) {
      if (status != 'all' && r.request.status.wire != status) continue;
      final b = _bookings.where((x) => x.id == r.request.bookingId).firstOrNull;
      final rider = _accounts.where((a) => a.user.id == r.userId).firstOrNull?.user;
      out.add(AdminRefund(
        id: r.request.id,
        bookingId: r.request.bookingId,
        amount: r.request.amount,
        reason: r.request.reason,
        status: r.request.status,
        note: r.request.adminNote,
        createdAt: r.request.createdAt,
        reviewedAt: r.request.reviewedAt,
        rider: rider?.fullName,
        email: rider?.email,
        phone: rider?.phone,
        title: b?.title ?? (b == null ? null : '${b.origin} → ${b.destination}'),
        kind: b?.kind.name,
        departureAt: b?.departureAt,
        bookingStatus: b?.status.name,
        ticket: b?.ticketCode,
        operator: b?.providerId == null ? null : _providers.where((p) => p.id == b!.providerId).firstOrNull?.name,
      ));
    }
    return out;
  }

  /// Money back for one booking (wallet credited, booking cancelled and marked refunded).
  int _refundBooking(String bookingId) {
    final i = _bookings.indexWhere((b) => b.id == bookingId);
    if (i < 0) throw const BackendException(BackendErrorKind.notFound, 'That booking no longer exists.');
    final b = _bookings[i];
    if (b.refundedAt != null) throw const BackendException(BackendErrorKind.validation, 'This booking was already refunded.');
    if (!b.paidFromWallet) throw const BackendException(BackendErrorKind.validation, 'This booking was free or paid outside the wallet; there is nothing to refund here.');
    if (b.status == BookingStatus.cancelled || b.status == BookingStatus.declined) throw const BackendException(BackendErrorKind.validation, 'This booking was cancelled and its fare already returned.');
    _credit(b.userId, b.fare);
    _bookings[i] = b.copyWith(status: BookingStatus.cancelled, refundedAt: _clock());
    return b.fare;
  }

  @override
  Future<int> reviewRefund(int requestId, {required bool approve, String? note}) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'review refunds');
    final i = _refunds.indexWhere((r) => r.request.id == requestId);
    if (i < 0 || _refunds[i].request.status != RefundStatus.pending) throw const BackendException(BackendErrorKind.validation, 'That refund request was already handled.');
    final r = _refunds[i];
    final amount = approve ? _refundBooking(r.request.bookingId) : 0;
    final n = (note ?? '').trim();
    _refunds[i] = (
      userId: r.userId,
      request: RefundRequest(
        id: r.request.id,
        bookingId: r.request.bookingId,
        amount: r.request.amount,
        reason: r.request.reason,
        status: approve ? RefundStatus.approved : RefundStatus.declined,
        adminNote: n.isEmpty ? null : n,
        createdAt: r.request.createdAt,
        reviewedAt: _clock(),
      ),
    );
    _log(approve ? 'Approved refund' : 'Declined refund', r.request.bookingId);
    _save();
    return amount;
  }

  @override
  Future<int> refundBooking(String bookingId, String reason) async {
    await _wait();
    _require(_me.role == UserRole.admin, 'refund bookings');
    if (reason.trim().isEmpty) throw const BackendException(BackendErrorKind.validation, 'Give a reason for the refund.');
    final amount = _refundBooking(bookingId);
    for (var i = 0; i < _refunds.length; i++) {
      final r = _refunds[i];
      if (r.request.bookingId == bookingId && r.request.status == RefundStatus.pending) {
        _refunds[i] = (
          userId: r.userId,
          request: RefundRequest(id: r.request.id, bookingId: bookingId, amount: r.request.amount, reason: r.request.reason, status: RefundStatus.approved, adminNote: reason.trim(), createdAt: r.request.createdAt, reviewedAt: _clock()),
        );
      }
    }
    _log('Refunded booking', bookingId);
    _save();
    return amount;
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
  factory _Account.fromJson(Map<String, dynamic> json) => _Account(AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)), json['salt'] as String, json['hash'] as String);
}
