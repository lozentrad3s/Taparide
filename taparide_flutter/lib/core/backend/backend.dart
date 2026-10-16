import '../models.dart';

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
  Future<SharedRide> offerSharedRide({required String origin, required String destination, required DateTime departAt, required int seats, required int costShare, required String vehicleLabel, String note});
  Future<Booking> cancelBooking(String bookingId);
  Future<Wallet> topUp(int amount);

  // ---- partners (scoped server-side by role and provider)
  Future<List<Booking>> fetchPartnerBookings();
  Future<List<AuditEntry>> fetchAuditLog();
  Future<List<AppUser>> fetchUsers();
  Future<TransportProvider> setProviderStatus(String providerId, Verification status);
  Future<Vehicle> setVehicleVerification(String vehicleId, Verification status);
  Future<Vehicle> setVehicleStatus(String vehicleId, VehicleStatus status);
  Future<TransitRoute> updateRouteFare(String routeId, int fare);
  Future<Vehicle> registerVehicle({required String operatorId, required VehicleKind kind, required String plate, required String model, required int capacity, String? ownerId});
  Future<AppUser> setUserRole(String userId, UserRole role, {String? providerId});
}
