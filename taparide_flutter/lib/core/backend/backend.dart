import '../fleet_drivers.dart';
import '../live_models.dart';
import '../models.dart';
import '../partner_models.dart';

enum BackendErrorKind { auth, permission, validation, insufficientFunds, notFound, network, unknown }

/// A failure the UI can explain to the person using it.
class BackendException implements Exception {
  const BackendException(this.kind, this.message);
  final BackendErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Everything the app needs from a server. [DemoBackend] keeps data on the device;
/// [SupabaseBackend] talks to Supabase Auth + Postgres (with row-level security).
///
/// Permission checks live behind this interface, never only in the UI.
abstract class Backend {
  /// Short label shown in the UI so demo data is never mistaken for live data.
  String get modeLabel;
  bool get isDemo;

  // ---- accounts
  Future<AppUser?> restoreSession();
  Future<AppUser> signIn({required String email, required String password, required Portal portal});
  Future<AppUser> register({required String fullName, required String email, required String phone, required String password, String? organisation});
  Future<void> sendPasswordReset(String email);

  /// True after the visitor arrived from a password-reset email: they must choose a new password.
  bool get passwordRecovery;

  /// A sign-in error the auth server sent back in the address (e.g. Google sign-in was cancelled
  /// or an email link expired), in plain words. Read once, then cleared.
  String? takeAuthRedirectError();

  /// Sets a new password for the signed-in account (after a reset email).
  Future<void> setNewPassword(String password);
  Future<void> signOut();

  /// Continue with Google or Apple. On the web this leaves the page and comes back signed in
  /// to [redirectTo]; new accounts are created as passengers.
  Future<void> signInWithProvider(SocialProvider provider, {String? redirectTo});

  /// Two-step sign-in (authenticator app) for admins and FCTA staff.
  Future<TwoStepStatus> twoStepStatus();
  Future<TwoStepSetup> twoStepSetup();
  Future<void> twoStepVerify({required String factorId, required String code});

  /// Everyone who joined on the website (waitlist, Tech Week seats). Admins only.
  Future<List<WaitlistEntry>> fetchWaitlist();

  /// Admins: mark a website sign-up as contacted (or not), with an optional private note.
  Future<void> setSignupContacted(int id, {required bool contacted, String? note});

  /// Admins: change a person's free event-bus pass (pick-up point, days, name, phone). Keeps the pass ID.
  Future<void> updateEventPass({required int id, required String event, required String pickup, required List<DateTime> days, String? name, String? phone});

  /// Admins: cancel a person's pass for one event.
  Future<void> cancelEventPass(int id, String event);

  /// Admins: remove a duplicate sign-up (refused once its free ride was paid into an account).
  Future<void> removeSignup(int id);

  /// Admins: wallets, top-ups, held fares and collection wallets across the platform.
  Future<MoneyOverview> fetchMoney();

  /// Partners: the signed-in company's collection wallet (tap-to-pay fares, held until each trip ends).
  Future<CollectionWallet> fetchCollectionWallet();

  /// Riders: whether this account earned the website sign-up reward (no money until full launch).
  Future<SignupReward> fetchSignupReward();

  /// Riders: their latest card / bank top-ups, newest first.
  Future<List<TopUpRecord>> fetchMyTopUps();

  /// Event organisers (and admins/FCTA): free-bus bookings for their events, counts only.
  Future<List<EventSeatBookings>> fetchOrganiserSeatBookings();

  /// Active routes of verified providers, readable before sign-in (landing page).
  Future<List<TransitRoute>> fetchPublicRoutes();

  // ---- catalogue (readable by every signed-in user)
  Future<List<TransportProvider>> fetchProviders();
  Future<List<TransitRoute>> fetchRoutes();
  Future<List<Vehicle>> fetchVehicles();
  Future<List<ChargingStation>> fetchChargingStations();
  Future<List<SharedRide>> fetchSharedRides();
  Future<MetricBaselines> fetchBaselines();

  // ---- rider
  Future<Wallet> fetchWallet();
  Future<List<Booking>> fetchMyBookings();
  Future<Booking> bookTransit({required TransitRoute route, required DateTime departure, required PaymentMethod method});
  Future<Booking> bookElectric({required Vehicle vehicle, required String pickup, required String dropoff, required int fare, required PaymentMethod method});
  Future<Booking> requestSharedRide(SharedRide ride);
  Future<SharedRide> offerSharedRide({required String origin, required String destination, required DateTime departAt, required int seats, required int costShare, required String vehicleLabel, String note, String? eventId});
  Future<Booking> cancelBooking(String bookingId);
  /// Test-money top-up. Refused by the live server once card and bank payments are on.
  Future<Wallet> topUp(int amount);

  // ---- Tag Along hosting
  /// Requests on the rides the signed-in user hosts.
  Future<List<Booking>> fetchRideRequests();

  /// Accepting takes the rider's share and holds it until the ride leaves; then it is paid to the host.
  Future<Booking> respondToRideRequest(String bookingId, {required bool accept});
  Future<SharedRide> cancelSharedRide(String rideId);

  // ---- events
  Future<List<RideEvent>> fetchEvents();
  /// Event partners (and admins) only. Tickets are sold in the app when [ticketsTotal] > 0.
  Future<RideEvent> createEvent({required String title, required String venue, required String area, required DateTime startsAt, DateTime? endsAt, required EventCategory category, String description, double? lat, double? lng, int ticketPrice, int ticketsTotal, String? ticketLink});
  Future<void> removeEvent(String eventId);
  Future<Booking> buyEventTicket(String eventId, PaymentMethod method);

  // ---- event buses (registered operators run them; riders pick a departure time)
  Future<List<EventBus>> fetchEventBuses();
  Future<EventBus> offerEventBus({required String eventId, required String origin, required int fare, required int capacity, required int minRiders, required List<DateTime> slots, String? vehicleId});

  /// The fare is held; the seat is confirmed when the operator fixes the departure time.
  Future<Booking> bookEventBus(String busId, DateTime slot, PaymentMethod method);
  Future<EventBus> confirmEventBus(String busId, DateTime slot);
  Future<EventBus> cancelEventBus(String busId);

  // ---- header ads
  Future<List<PromoAd>> fetchAds();
  Future<void> countAdImpressions(List<String> adIds);

  /// Starts the server clock for a full ad view.
  Future<AdView> startAdView(String adId);

  /// Pays the ride credit once the ad has played in full (server-checked, daily cap).
  Future<AdReward> claimAdReward(String viewId);

  // ---- share my ride
  /// A private link token for one upcoming trip (the same one while it is still valid).
  Future<TripShare> shareTrip(String bookingId);
  Future<void> stopSharingTrip(String bookingId);
  Future<void> updateTripLocation(String bookingId, double lat, double lng);

  /// Readable without signing in: the token is the key. Null when the link has ended.
  Future<SharedTrip?> fetchSharedTrip(String token);

  // ---- live vehicle positions
  Future<List<VehiclePosition>> fetchVehiclePositions();
  Future<void> reportVehiclePosition(String vehicleId, double lat, double lng, {double? heading, double? speedKmh});
  Future<void> stopVehicleTracking(String vehicleId);

  // ---- partners (scoped server-side by role and provider)
  Future<List<Booking>> fetchPartnerBookings();
  Future<List<AuditEntry>> fetchAuditLog();
  Future<List<AppUser>> fetchUsers();
  Future<TransportProvider> setProviderStatus(String providerId, Verification status);
  Future<Vehicle> setVehicleVerification(String vehicleId, Verification status);
  Future<Vehicle> setVehicleStatus(String vehicleId, VehicleStatus status);

  /// Driver finishes a car ride: the booking completes, the car is free again and the fare counts towards its earnings.
  Future<Booking> completeRide(String bookingId);
  Future<TransitRoute> updateRouteFare(String routeId, int fare);
  Future<Vehicle> registerVehicle({required String operatorId, required VehicleKind kind, required String plate, required String model, required int capacity, String? ownerId});
  Future<AppUser> setUserRole(String userId, UserRole role, {String? providerId});

  // ---- fleet drivers (people who drive a fleet owner's or operator's vehicles)
  /// Admins see every driver, fleet owners and operators their own, a driver only themself.
  Future<List<FleetDriver>> fetchFleetDrivers();

  /// Fleet owners and operators add drivers to their own company ([providerId] is for admins).
  Future<FleetDriver> addFleetDriver({required String fullName, required String phone, required String email, required String licenceNumber, String? providerId, String? vehicleId, String? routeId});

  /// Puts the driver on one of the company's own vehicles (and optionally a route); null vehicle unassigns.
  Future<FleetDriver> assignFleetDriver(String driverId, {String? vehicleId, String? routeId});
  Future<FleetDriver> setFleetDriverStatus(String driverId, FleetDriverStatus status);

  /// A fleet driver accepts/boards or completes a booking on their assigned vehicle.
  Future<Booking> driverBookingAction(String bookingId, DriverBookingAction action);

  /// A fleet driver starts or ends a trip on their assigned vehicle (ending completes boarded riders).
  Future<Vehicle> driverSetTrip({required bool start});

  // ---- partner registration
  /// Session token for calls to the Tap A Ride API (AI assistant, document checks). Null in demo mode.
  Future<String?> accessToken();
  Future<PartnerApplication> submitPartnerApplication(PartnerApplication draft, List<DocumentFile> documents);
  Future<List<PartnerApplication>> fetchMyApplications();

  /// Review queue (FCTA and platform admins).
  Future<List<PartnerApplication>> fetchPartnerApplications();
  Future<PartnerApplication> reviewPartnerApplication(String applicationId, ApplicationStatus decision, String note);

  /// Bytes or a short-lived URL to show an uploaded document to its owner or a reviewer.
  Future<DocumentFile> openDocument(DocumentFile document);
}
