import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:latlong2/latlong.dart';

import 'admin_analytics.dart';
import 'analytics.dart';
import 'api_client.dart';
import 'backend/backend.dart';
import 'dashboards.dart';
import 'format.dart';
import 'insights.dart';
import 'live_models.dart';
import 'location.dart';
import 'models.dart';
import 'partner_models.dart';
import 'places.dart';
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
  List<RideEvent> events = const [];
  List<EventBus> eventBuses = const [];

  /// Header ads for riders (house promotions until advertisers sign).
  List<PromoAd> ads = const [];

  /// Ad rewards left today, once the rider has claimed one (null = not known yet).
  int? adRewardsLeft;

  /// The rider's position (from the device), and the nearest named place.
  LatLng? here;
  String? hereName;
  bool locating = false;

  /// Requests on the Tag Along rides this user hosts.
  List<Booking> rideRequests = const [];

  /// Fresh GPS fixes from vehicles in service, by vehicle id.
  Map<String, VehiclePosition> positions = const {};

  /// Trip links this rider has switched on, by booking id.
  final Map<String, TripShare> tripShares = {};
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

  Timer? _shareTicker;
  Timer? _trackTicker;

  /// The vehicle this device is reporting GPS for (driver or conductor), if any.
  String? trackingVehicleId;
  String? trackingError;

  DateTime get now => _clock();

  /// True once card and bank top-ups are switched on; until then wallet money is test money.
  bool get paymentsLive => services['payments'] == 'paystack';
  bool get signedIn => user != null;
  bool get isPartner => user?.role.isPartner ?? false;

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _shareTicker?.cancel();
    _trackTicker?.cancel();
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

  /// Continue with Google or Apple. On the web the page leaves and comes back signed in.
  Future<void> signInWithProvider(SocialProvider provider, {String? redirectTo}) => backend.signInWithProvider(provider, redirectTo: redirectTo);

  /// Website sign-ups (waitlist and Tech Week seats), for the admin dashboard.
  Future<List<WaitlistEntry>> fetchWaitlist() => backend.fetchWaitlist();

  Future<void> signOut() async {
    _pending?.cancel();
    _shareTicker?.cancel();
    await stopTracking();
    tripShares.clear();
    events = const [];
    rideRequests = const [];
    positions = const {};
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
        backend.fetchVehiclePositions(),
        backend.fetchEvents(),
        backend.fetchEventBuses(),
      ]);
      events = results[7] as List<RideEvent>;
      eventBuses = results[8] as List<EventBus>;
      positions = {for (final p in results[6] as List<VehiclePosition>) p.vehicleId: p};
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
        final rider = await Future.wait<Object>([backend.fetchWallet(), backend.fetchMyBookings(), backend.fetchRideRequests(), backend.fetchAds()]);
        wallet = rider[0] as Wallet;
        myBookings = rider[1] as List<Booking>;
        rideRequests = rider[2] as List<Booking>;
        ads = rider[3] as List<PromoAd>;
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
      final results = await Future.wait<Object>([backend.fetchMyBookings(), backend.fetchSharedRides(), backend.fetchEvents(), backend.fetchRideRequests(), backend.fetchEventBuses()]);
      myBookings = results[0] as List<Booking>;
      rides = results[1] as List<SharedRide>;
      events = results[2] as List<RideEvent>;
      rideRequests = results[3] as List<Booking>;
      eventBuses = results[4] as List<EventBus>;
      // After the bookings: settling a ride that has left can change the balance.
      wallet = await backend.fetchWallet();
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
    // Check back shortly so the status updates on its own when the host answers.
    _pending?.cancel();
    _pending = Timer(const Duration(seconds: 7), refreshRider);
    return booking;
  }

  // ------------------------------------------------------------ Tag Along hosting

  SharedRide? rideById(String? id) => id == null ? null : rides.where((r) => r.id == id).firstOrNull;

  /// Requests still waiting for this host's answer.
  List<Booking> get pendingRideRequests => [for (final b in rideRequests) if (b.status == BookingStatus.requested) b];

  Future<void> respondToRideRequest(Booking request, {required bool accept}) async {
    final updated = await backend.respondToRideRequest(request.id, accept: accept);
    rideRequests = [for (final b in rideRequests) b.id == updated.id ? updated : b];
    rides = await backend.fetchSharedRides();
    _notify();
  }

  Future<void> cancelSharedRide(SharedRide ride) async {
    await backend.cancelSharedRide(ride.id);
    final results = await Future.wait<Object>([backend.fetchSharedRides(), backend.fetchRideRequests()]);
    rides = results[0] as List<SharedRide>;
    rideRequests = results[1] as List<Booking>;
    _notify();
  }

  // ------------------------------------------------------------ events

  RideEvent? eventById(String? id) => id == null ? null : events.where((e) => e.id == id).firstOrNull;
  List<SharedRide> ridesForEvent(String eventId) => [for (final r in rides) if (r.eventId == eventId) r];

  Future<RideEvent> createEvent({required String title, required String venue, required String area, required DateTime startsAt, DateTime? endsAt, required EventCategory category, String description = '', double? lat, double? lng, int ticketPrice = 0, int ticketsTotal = 0, String? ticketLink}) async {
    final event = await backend.createEvent(title: title, venue: venue, area: area, startsAt: startsAt, endsAt: endsAt, category: category, description: description, lat: lat, lng: lng, ticketPrice: ticketPrice, ticketsTotal: ticketsTotal, ticketLink: ticketLink);
    events = [...events, event]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    _notify();
    return event;
  }

  Future<void> removeEvent(RideEvent event) async {
    await backend.removeEvent(event.id);
    events = [for (final e in events) if (e.id != event.id) e];
    eventBuses = [for (final b in eventBuses) if (b.eventId != event.id) b];
    _notify();
  }

  Future<Booking> buyEventTicket(RideEvent event, PaymentMethod method) async {
    final booking = await backend.buyEventTicket(event.id, method);
    myBookings = [booking, ...myBookings];
    events = [for (final e in events) e.id == event.id ? e.copyWith(ticketsSold: e.ticketsSold + 1) : e];
    wallet = await backend.fetchWallet();
    _notify();
    return booking;
  }

  // ------------------------------------------------------------ event buses

  List<EventBus> busesForEvent(String eventId) => [for (final b in eventBuses) if (b.eventId == eventId && b.status != EventBusStatus.cancelled) b];
  EventBus? eventBusById(String? id) => id == null ? null : eventBuses.where((b) => b.id == id).firstOrNull;
  Booking? myEventBusSeat(String busId) => myBookings.where((b) => b.eventBusId == busId && b.status.isOpen).firstOrNull;

  Future<EventBus> offerEventBus({required RideEvent event, required String origin, required int fare, required int capacity, required int minRiders, required List<DateTime> slots, String? vehicleId}) async {
    final bus = await backend.offerEventBus(eventId: event.id, origin: origin, fare: fare, capacity: capacity, minRiders: minRiders, slots: slots, vehicleId: vehicleId);
    eventBuses = [...eventBuses, bus];
    _notify();
    return bus;
  }

  Future<Booking> bookEventBus(EventBus bus, DateTime slot, PaymentMethod method) async {
    final booking = await backend.bookEventBus(bus.id, slot, method);
    myBookings = [booking, ...myBookings];
    final results = await Future.wait<Object>([backend.fetchEventBuses(), backend.fetchWallet()]);
    eventBuses = results[0] as List<EventBus>;
    wallet = results[1] as Wallet;
    _notify();
    return booking;
  }

  Future<void> confirmEventBus(EventBus bus, DateTime slot) async {
    final updated = await backend.confirmEventBus(bus.id, slot);
    eventBuses = [for (final b in eventBuses) b.id == bus.id ? updated : b];
    _notify();
    unawaited(refresh());
  }

  Future<void> cancelEventBus(EventBus bus) async {
    await backend.cancelEventBus(bus.id);
    eventBuses = [for (final b in eventBuses) if (b.id != bus.id) b];
    _notify();
    unawaited(refresh());
  }

  // ------------------------------------------------------------ header ads

  Future<AdView> startAdView(PromoAd ad) => backend.startAdView(ad.id);

  Future<AdReward> claimAdReward(AdView view) async {
    final reward = await backend.claimAdReward(view.id);
    adRewardsLeft = reward.left;
    final w = wallet;
    if (w != null) wallet = Wallet(cardNumber: w.cardNumber, balance: reward.balance);
    _notify();
    return reward;
  }

  void countAdImpressions(List<PromoAd> shown) => unawaited(backend.countAdImpressions([for (final a in shown) a.id]));

  // ------------------------------------------------------------ rider location

  /// Finds the rider's position once (precise GPS on phones) and names the nearest known place.
  Future<LatLng?> locate({bool force = false}) async {
    if (locating || (here != null && !force)) return here;
    locating = true;
    _notify();
    try {
      final p = await currentLocation(precise: true);
      if (p != null) {
        here = p;
        hereName = nearestPlaceName(p, routes: routes);
      }
    } finally {
      locating = false;
      _notify();
    }
    return here;
  }

  // ------------------------------------------------------------ share my ride

  /// Switches on the private link for a trip and starts sending this device's location to it.
  Future<TripShare> shareTrip(Booking booking) async {
    final share = await backend.shareTrip(booking.id);
    tripShares[booking.id] = share;
    _notify();
    unawaited(_sendShareLocations());
    _shareTicker ??= Timer.periodic(const Duration(seconds: 25), (_) => _sendShareLocations());
    return share;
  }

  Future<void> stopSharingTrip(Booking booking) async {
    await backend.stopSharingTrip(booking.id);
    tripShares.remove(booking.id);
    if (tripShares.isEmpty) {
      _shareTicker?.cancel();
      _shareTicker = null;
    }
    _notify();
  }

  Future<void> _sendShareLocations() async {
    tripShares.removeWhere((_, s) => s.expiresAt.isBefore(now));
    if (tripShares.isEmpty) return;
    final here = await currentLocation();
    if (here == null) return;
    for (final id in tripShares.keys.toList()) {
      try {
        await backend.updateTripLocation(id, here.latitude, here.longitude);
      } on BackendException {
        // The contact still sees the trip and vehicle; the next tick tries again.
      }
    }
  }

  // ------------------------------------------------------------ live vehicle positions

  Future<void> refreshPositions() async {
    try {
      positions = {for (final p in await backend.fetchVehiclePositions()) p.vehicleId: p};
      _notify();
    } on BackendException {
      // Keep the last known positions.
    }
  }

  /// A vehicle's GPS fix if its driver is reporting right now.
  VehiclePosition? livePosition(String? vehicleId) {
    final p = vehicleId == null ? null : positions[vehicleId];
    return p != null && p.isFresh(now) ? p : null;
  }

  /// Starts reporting this device's GPS as [vehicle]'s position (driver or conductor phone).
  Future<bool> startTracking(Vehicle vehicle) async {
    await stopTracking();
    trackingVehicleId = vehicle.id;
    trackingError = null;
    final ok = await _reportPosition();
    if (!ok) {
      trackingVehicleId = null;
      _notify();
      return false;
    }
    _trackTicker = Timer.periodic(const Duration(seconds: 15), (_) => _reportPosition());
    _notify();
    return true;
  }

  Future<void> stopTracking() async {
    _trackTicker?.cancel();
    _trackTicker = null;
    final id = trackingVehicleId;
    trackingVehicleId = null;
    if (id == null) return;
    try {
      await backend.stopVehicleTracking(id);
    } on BackendException {
      // The fix simply goes stale after a few minutes.
    }
    positions = {...positions}..remove(id);
    _notify();
  }

  Future<bool> _reportPosition() async {
    final id = trackingVehicleId;
    if (id == null) return false;
    final here = await currentLocation();
    if (here == null) {
      trackingError = 'Allow location access on this device to share the vehicle\'s position.';
      _notify();
      return false;
    }
    try {
      await backend.reportVehiclePosition(id, here.latitude, here.longitude);
      positions = {...positions, id: VehiclePosition(vehicleId: id, point: here, updatedAt: now)};
      trackingError = null;
      _notify();
      return true;
    } on BackendException catch (e) {
      trackingError = e.message;
      _notify();
      return false;
    }
  }

  Future<SharedRide> offerSharedRide({required String origin, required String destination, required DateTime departAt, required int seats, required int costShare, required String vehicleLabel, String note = '', String? eventId}) async {
    final ride = await backend.offerSharedRide(origin: origin, destination: destination, departAt: departAt, seats: seats, costShare: costShare, vehicleLabel: vehicleLabel, note: note, eventId: eventId);
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

  /// Test-money top-up (demo mode, or a live server before payments are switched on).
  Future<void> topUp(int amount) async {
    wallet = await backend.topUp(amount);
    _notify();
  }

  /// Confirms a card or bank payment after the rider returns, and refreshes the balance.
  Future<TopUpResult> confirmTopUp(String reference) async {
    final result = await api.verifyTopUp(reference);
    wallet = await backend.fetchWallet();
    _notify();
    return result;
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

  /// Which server services are live (from /api/config): tiles, geocoder, ai, backend. Never keys.
  Map<String, dynamic> services = const {};

  void setServices(Map<String, dynamic> value) {
    services = value;
    _notify();
  }

  /// Platform-wide analytics for the admin control centre.
  AdminAnalytics adminAnalytics() => AdminAnalytics.build(
        providers: providers,
        routes: routes,
        vehicles: vehicles,
        bookings: partnerBookings,
        applications: partnerApplications,
        users: users,
        now: now,
      );

  FctaDashboard? fctaDashboard() {
    final base = baselines;
    if (base == null) return null;
    return Dashboards.fcta(providers: providers, routes: routes, vehicles: vehicles, bookings: partnerBookings, baselines: base, now: now);
  }
}
