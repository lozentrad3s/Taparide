import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:latlong2/latlong.dart';

import 'analytics.dart';
import 'api_client.dart';
import 'backend/backend.dart';
import 'dashboards.dart';
import 'format.dart';
import 'insights.dart';
import 'location.dart';
import 'models.dart';
import 'partner_models.dart';
import 'reminders.dart';

enum LoadState { idle, loading, ready, error }

/// When to leave for a booked trip, from real road travel time to the first stop.
class LeavePlan {
  const LeavePlan({required this.leaveAt, required this.travelMinutes, required this.fromLocation});
  final DateTime leaveAt;
  final int travelMinutes;

  /// True when computed from the rider's actual location (otherwise an estimate).
  final bool fromLocation;
}

/// Session, cached data and every user action. Screens read from here and call its
/// methods; the [Backend] behind it decides what each role may see and do.
class AppState extends ChangeNotifier {
  AppState(this.backend, {DateTime Function()? clock, ReminderService? reminders, ApiClient? api})
      : _clock = clock ?? DateTime.now,
        reminders = reminders ?? ReminderService(null),
        api = api ?? ApiClient(backend);

  final Backend backend;
  final DateTime Function() _clock;

  /// Server API: AI assistant, document checks, road routing.
  final ApiClient api;
  final ReminderService reminders;

  List<PartnerApplication> myApplications = const [];
  List<PartnerApplication> partnerApplications = const [];
  final Map<String, LeavePlan> leavePlans = {};

  AppUser? user;
  bool restoring = true;

  LoadState dataState = LoadState.idle;
  String? dataError;

  List<TransportProvider> providers = const [];
  List<TransitRoute> routes = const [];
  List<Vehicle> vehicles = const [];
  List<ChargingStation> stations = const [];
  List<SharedRide> rides = const [];
  List<Booking> myBookings = const [];
  List<Booking> partnerBookings = const [];
  List<AuditEntry> audit = const [];
  List<AppUser> users = const [];
  Wallet? wallet;
  MetricBaselines? baselines;

  /// Popular routes for the public landing page.
  List<TransitRoute> publicRoutes = const [];

  Timer? _pending;
  bool _disposed = false;

  DateTime get now => _clock();
  bool get signedIn => user != null;
  bool get isPartner => user?.role.isPartner ?? false;

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------ session

  Future<void> init() async {
    try {
      user = await backend.restoreSession();
    } catch (_) {
      user = null;
    }
    restoring = false;
    _notify();
    if (user != null) await refresh();
  }

  Future<void> signIn({required String email, required String password, required Portal portal}) async {
    user = await backend.signIn(email: email, password: password, portal: portal);
    _notify();
    await refresh();
  }

  Future<void> register({required String fullName, required String email, required String phone, required String password, String? organisation}) async {
    user = await backend.register(fullName: fullName, email: email, phone: phone, password: password, organisation: organisation);
    _notify();
    await refresh();
  }

  Future<void> loadPublicRoutes() async {
    if (publicRoutes.isNotEmpty) return;
    try {
      publicRoutes = await backend.fetchPublicRoutes();
      _notify();
    } catch (_) {
      // The landing page falls back to its static copy.
    }
  }

  /// Re-reads the account (e.g. after a partner application is approved and the role changes).
  Future<void> reloadUser() async {
    user = await backend.restoreSession();
    _notify();
    await refresh();
  }

  Future<void> sendPasswordReset(String email) => backend.sendPasswordReset(email);

  Future<void> signOut() async {
    _pending?.cancel();
    await backend.signOut();
    user = null;
    dataState = LoadState.idle;
    providers = const [];
    routes = const [];
    vehicles = const [];
    stations = const [];
    rides = const [];
    myBookings = const [];
    partnerBookings = const [];
    audit = const [];
    users = const [];
    myApplications = const [];
    partnerApplications = const [];
    leavePlans.clear();
    wallet = null;
    _notify();
  }

  // ------------------------------------------------------------ data

  Future<void> refresh() async {
    final me = user;
    if (me == null) return;
    dataState = LoadState.loading;
    dataError = null;
    _notify();
    try {
      final results = await Future.wait<Object>([
        backend.fetchProviders(),
        backend.fetchRoutes(),
        backend.fetchVehicles(),
        backend.fetchChargingStations(),
        backend.fetchSharedRides(),
        backend.fetchBaselines(),
      ]);
      providers = results[0] as List<TransportProvider>;
      routes = results[1] as List<TransitRoute>;
      vehicles = results[2] as List<Vehicle>;
      stations = results[3] as List<ChargingStation>;
      rides = results[4] as List<SharedRide>;
      baselines = results[5] as MetricBaselines;

      if (me.role.isPartner) {
        partnerBookings = await backend.fetchPartnerBookings();
        audit = me.role.canVerify ? await backend.fetchAuditLog() : const [];
        users = me.role == UserRole.admin ? await backend.fetchUsers() : const [];
        partnerApplications = me.role.canVerify ? await backend.fetchPartnerApplications() : const [];
      } else {
        final rider = await Future.wait<Object>([backend.fetchWallet(), backend.fetchMyBookings()]);
        wallet = rider[0] as Wallet;
        myBookings = rider[1] as List<Booking>;
      }
      myApplications = await backend.fetchMyApplications();
      dataState = LoadState.ready;
    } on BackendException catch (e) {
      dataError = e.message;
      dataState = LoadState.error;
      if (e.kind == BackendErrorKind.auth) user = null;
    } catch (e) {
      dataError = 'Something went wrong while loading. Pull to refresh or try again.';
      dataState = LoadState.error;
    }
    _notify();
  }

  Future<void> refreshRider() async {
    if (user == null || isPartner) return;
    try {
      final results = await Future.wait<Object>([backend.fetchWallet(), backend.fetchMyBookings(), backend.fetchSharedRides()]);
      wallet = results[0] as Wallet;
      myBookings = results[1] as List<Booking>;
      rides = results[2] as List<SharedRide>;
      _notify();
    } on BackendException {
      // Keep the cached data; the next full refresh reports the problem.
    }
  }

  // ------------------------------------------------------------ lookups

  TransportProvider? providerById(String? id) => id == null ? null : providers.where((p) => p.id == id).firstOrNull;
  TransitRoute? routeById(String? id) => id == null ? null : routes.where((r) => r.id == id).firstOrNull;
  Vehicle? vehicleById(String? id) => id == null ? null : vehicles.where((v) => v.id == id).firstOrNull;
  Booking? bookingById(String? id) => id == null ? null : [...myBookings, ...partnerBookings].where((b) => b.id == id).firstOrNull;

  /// Routes riders can book (active and run by a verified provider).
  List<TransitRoute> get bookableRoutes {
    final verified = {for (final p in providers) if (p.status == Verification.verified) p.id};
    return [for (final r in routes) if (r.active && verified.contains(r.providerId)) r]..sort((a, b) => b.monthlyTrips.compareTo(a.monthlyTrips));
  }

  /// Electric cars and verified private-driver cars riders can book.
  List<Vehicle> get availableEvs {
    final verified = {for (final p in providers) if (p.status == Verification.verified) p.id};
    return [
      for (final v in vehicles)
        if (v.kind.isBookableCar && v.verification == Verification.verified && verified.contains(v.operatorId)) v,
    ]..sort((a, b) => a.status.index.compareTo(b.status.index));
  }

  /// "Book your usual ride" suggestions learned from the rider's history.
  List<RideSuggestion> get suggestions => RideInsights.suggestions(bookings: myBookings, routes: bookableRoutes, now: now);

  List<Booking> get upcomingTrips => [for (final b in myBookings) if (b.isUpcoming) b]..sort((a, b) => a.departureAt.compareTo(b.departureAt));
  List<Booking> get pastTrips => [for (final b in myBookings) if (!b.isUpcoming) b];

  Booking? bookingForRide(String rideId) =>
      myBookings.where((b) => b.rideId == rideId && b.status != BookingStatus.cancelled && b.status != BookingStatus.declined).firstOrNull;

  // ------------------------------------------------------------ rider actions

  Future<Booking> bookTransit(TransitRoute route, DateTime departure, PaymentMethod method) async {
    final booking = await backend.bookTransit(route: route, departure: departure, method: method);
    myBookings = [booking, ...myBookings];
    wallet = await backend.fetchWallet();
    _notify();
    unawaited(scheduleLeaveReminders(booking));
    return booking;
  }

  /// Works out when to leave (road time from the rider to the first stop) and schedules
  /// a heads-up 10 minutes before plus a "leave now" reminder.
  Future<LeavePlan?> scheduleLeaveReminders(Booking booking, {int? minutesBefore}) async {
    final route = routeById(booking.routeId);
    if (route == null || route.stops.isEmpty) return null;
    final stop = route.stops.first;
    final here = await currentLocation();
    final from = (here != null && inFct(here)) ? here : null;
    int minutes = 15; // a typical walk or keke ride to the stop when location is unknown
    if (from != null) {
      final plan = await api.roadRoute(from, LatLng(stop.lat, stop.lng), mode: 'driving');
      if (plan != null) minutes = plan.minutes;
    }
    final leaveAt = booking.departureAt.subtract(Duration(minutes: minutes + 5));
    final leave = LeavePlan(leaveAt: leaveAt, travelMinutes: minutes, fromLocation: from != null);
    leavePlans[booking.id] = leave;

    await reminders.requestPermission();
    final what = '${Fmt.time(booking.departureAt)} ${route.name ?? '${route.origin} – ${route.destination}'}';
    reminders.add(TripReminder(
      id: '${booking.id}-heads-up',
      bookingId: booking.id,
      at: (minutesBefore != null ? booking.departureAt.subtract(Duration(minutes: minutesBefore)) : leaveAt.subtract(const Duration(minutes: 10))),
      title: minutesBefore != null ? 'Your ride is in $minutesBefore min' : 'Leave in 10 minutes',
      body: 'For your $what from ${stop.name}. About $minutes min to the stop.',
    ));
    reminders.add(TripReminder(
      id: '${booking.id}-leave',
      bookingId: booking.id,
      at: leaveAt,
      title: 'Time to leave for ${stop.name}',
      body: 'Your $what departs at ${Fmt.time(booking.departureAt)}. Seat ${booking.seat ?? ''}'.trim(),
    ));
    _notify();
    return leave;
  }

  // ------------------------------------------------------------ partner registration

  Future<AiDocumentCheck> checkDocuments(PartnerApplication draft, List<DocumentFile> documents) => api.verifyDocuments(draft, documents);

  Future<PartnerApplication> submitApplication(PartnerApplication draft, List<DocumentFile> documents) async {
    final app = await backend.submitPartnerApplication(draft, documents);
    myApplications = [app, ...myApplications.where((a) => a.id != app.id)];
    _notify();
    return app;
  }

  Future<void> reviewApplication(PartnerApplication app, ApplicationStatus decision, String note) async {
    final updated = await backend.reviewPartnerApplication(app.id, decision, note);
    partnerApplications = [for (final a in partnerApplications) a.id == updated.id ? updated : a];
    if (decision == ApplicationStatus.approved) {
      final results = await Future.wait<Object>([backend.fetchProviders(), backend.fetchVehicles(), backend.fetchAuditLog()]);
      providers = results[0] as List<TransportProvider>;
      vehicles = results[1] as List<Vehicle>;
      audit = results[2] as List<AuditEntry>;
    } else {
      audit = await backend.fetchAuditLog();
    }
    _notify();
  }

  Future<Booking> bookElectric(Vehicle vehicle, {required String pickup, required String dropoff, required int fare, required PaymentMethod method}) async {
    final booking = await backend.bookElectric(vehicle: vehicle, pickup: pickup, dropoff: dropoff, fare: fare, method: method);
    myBookings = [booking, ...myBookings];
    final results = await Future.wait<Object>([backend.fetchWallet(), backend.fetchVehicles()]);
    wallet = results[0] as Wallet;
    vehicles = results[1] as List<Vehicle>;
    _notify();
    return booking;
  }

  Future<Booking> requestSharedRide(SharedRide ride) async {
    final booking = await backend.requestSharedRide(ride);
    myBookings = [booking, ...myBookings];
    _notify();
    // Hosts answer within seconds in the demo; check back so the status updates on its own.
    _pending?.cancel();
    _pending = Timer(const Duration(seconds: 7), refreshRider);
    return booking;
  }

  Future<SharedRide> offerSharedRide({required String origin, required String destination, required DateTime departAt, required int seats, required int costShare, required String vehicleLabel, String note = ''}) async {
    final ride = await backend.offerSharedRide(origin: origin, destination: destination, departAt: departAt, seats: seats, costShare: costShare, vehicleLabel: vehicleLabel, note: note);
    rides = [...rides, ride]..sort((a, b) => a.departAt.compareTo(b.departAt));
    _notify();
    return ride;
  }

  Future<void> cancelBooking(Booking booking) async {
    final updated = await backend.cancelBooking(booking.id);
    reminders.cancelFor(booking.id);
    leavePlans.remove(booking.id);
    myBookings = [for (final b in myBookings) b.id == updated.id ? updated : b];
    wallet = await backend.fetchWallet();
    if (booking.kind == BookingKind.electric) vehicles = await backend.fetchVehicles();
    _notify();
  }

  Future<void> topUp(int amount) async {
    wallet = await backend.topUp(amount);
    _notify();
  }

  // ------------------------------------------------------------ partner actions

  Future<void> setProviderStatus(TransportProvider provider, Verification status) async {
    final updated = await backend.setProviderStatus(provider.id, status);
    providers = [for (final p in providers) p.id == updated.id ? updated : p];
    audit = user!.role.canVerify ? await backend.fetchAuditLog() : audit;
    _notify();
  }

  Future<void> setVehicleVerification(Vehicle vehicle, Verification status) async {
    final updated = await backend.setVehicleVerification(vehicle.id, status);
    vehicles = [for (final v in vehicles) v.id == updated.id ? updated : v];
    audit = await backend.fetchAuditLog();
    _notify();
  }

  Future<void> setVehicleStatus(Vehicle vehicle, VehicleStatus status) async {
    final updated = await backend.setVehicleStatus(vehicle.id, status);
    vehicles = [for (final v in vehicles) v.id == updated.id ? updated : v];
    if (user!.role.canVerify) audit = await backend.fetchAuditLog();
    _notify();
  }

  Future<void> completeRide(Booking booking) async {
    final updated = await backend.completeRide(booking.id);
    partnerBookings = [for (final b in partnerBookings) b.id == updated.id ? updated : b];
    vehicles = await backend.fetchVehicles();
    _notify();
  }

  Future<void> updateRouteFare(TransitRoute route, int fare) async {
    final updated = await backend.updateRouteFare(route.id, fare);
    routes = [for (final r in routes) r.id == updated.id ? updated : r];
    if (user!.role.canVerify) audit = await backend.fetchAuditLog();
    _notify();
  }

  Future<Vehicle> registerVehicle({required String operatorId, required VehicleKind kind, required String plate, required String model, required int capacity, String? ownerId}) async {
    final vehicle = await backend.registerVehicle(operatorId: operatorId, kind: kind, plate: plate, model: model, capacity: capacity, ownerId: ownerId);
    vehicles = [...vehicles, vehicle];
    if (user!.role.canVerify) audit = await backend.fetchAuditLog();
    _notify();
    return vehicle;
  }

  Future<void> setUserRole(AppUser target, UserRole role, {String? providerId}) async {
    final updated = await backend.setUserRole(target.id, role, providerId: providerId);
    users = [for (final u in users) u.id == updated.id ? updated : u];
    audit = await backend.fetchAuditLog();
    _notify();
  }

  // ------------------------------------------------------------ dashboards

  OperatorDashboard? operatorDashboard(String providerId) {
    final provider = providerById(providerId);
    final base = baselines;
    if (provider == null || base == null) return null;
    return Dashboards.operator(provider: provider, routes: routes, vehicles: vehicles, bookings: partnerBookings, baselines: base, now: now);
  }

  FleetDashboard? fleetDashboard(String providerId) {
    final provider = providerById(providerId);
    final base = baselines;
    if (provider == null || base == null) return null;
    return Dashboards.fleet(provider: provider, vehicles: vehicles, bookings: partnerBookings, baselines: base, now: now);
  }

  /// AI Insights figures for one provider, or the whole platform when [providerId] is null.
  InsightsReport insightsFor(String? providerId) => Analytics.build(
        providerId: providerId,
        scopeName: providerById(providerId)?.name ?? 'All Abuja transport (FCTA view)',
        routes: routes,
        vehicles: vehicles,
        bookings: partnerBookings,
        now: now,
      );

  FctaDashboard? fctaDashboard() {
    final base = baselines;
    if (base == null) return null;
    return Dashboards.fcta(providers: providers, routes: routes, vehicles: vehicles, bookings: partnerBookings, baselines: base, now: now);
  }
}
