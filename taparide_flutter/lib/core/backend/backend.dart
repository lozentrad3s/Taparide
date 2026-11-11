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
  Future<void> signOut();

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
  Future<RideEvent> createEvent({required String title, required String venue, required String area, required DateTime startsAt, DateTime? endsAt, required EventCategory category, String description, double? lat, double? lng});
  Future<void> removeEvent(String eventId);

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
