import 'package:supabase_flutter/supabase_flutter.dart';

import '../live_models.dart';
import '../models.dart';
import '../partner_models.dart';
import 'backend.dart';

/// Supabase implementation. Reads go through tables guarded by row-level security;
/// every write goes through a `security definer` SQL function that re-checks the
/// caller's role (see `supabase/migrations`).
class SupabaseBackend implements Backend {
  SupabaseBackend(this._client);

  static Future<SupabaseBackend> create({required String url, required String anonKey}) async {
    await Supabase.initialize(url: url, publishableKey: anonKey);
    return SupabaseBackend(Supabase.instance.client);
  }

  final SupabaseClient _client;

  @override
  String get modeLabel => 'Live · Supabase';

  @override
  bool get isDemo => false;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const BackendException(BackendErrorKind.auth, 'Your session has ended. Please sign in again.');
    return id;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on BackendException {
      rethrow;
    } on AuthException catch (e) {
      final message = e.message.toLowerCase().contains('invalid login')
          ? 'That email and password do not match an account.'
          : e.message;
      throw BackendException(BackendErrorKind.auth, message);
    } on PostgrestException catch (e) {
      // Our SQL functions raise readable messages with these SQLSTATE codes.
      final kind = switch (e.code) {
        '42501' => BackendErrorKind.permission,
        'P0002' => BackendErrorKind.insufficientFunds,
        'P0003' => BackendErrorKind.notFound,
        'P0001' || '23505' || '23514' => BackendErrorKind.validation,
        _ => BackendErrorKind.unknown,
      };
      final message = kind == BackendErrorKind.unknown ? 'Something went wrong on the server (${e.code ?? 'error'}). Please try again.' : e.message;
      throw BackendException(kind, message);
    } catch (_) {
      throw const BackendException(BackendErrorKind.network, 'Could not reach Tap A Ride. Check your connection and try again.');
    }
  }

  Map<String, dynamic> _row(dynamic result) {
    if (result is List && result.isNotEmpty) return Map<String, dynamic>.from(result.first as Map);
    if (result is Map) return Map<String, dynamic>.from(result);
    throw const BackendException(BackendErrorKind.unknown, 'The server returned an empty response.');
  }

  List<Map<String, dynamic>> _rows(dynamic result) => [for (final r in (result as List)) Map<String, dynamic>.from(r as Map)];

  Future<AppUser> _profile(String id) async => AppUser.fromJson(_row(await _client.from('profiles').select().eq('id', id).limit(1)));

  // ------------------------------------------------------------ accounts

  @override
  Future<AppUser?> restoreSession() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      return await _profile(user.id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AppUser> signIn({required String email, required String password, required Portal portal}) => _guard(() async {
        final response = await _client.auth.signInWithPassword(email: email.trim(), password: password);
        final profile = await _profile(response.user!.id);
        final wrongPortal = (portal == Portal.passenger && profile.role.isPartner) || (portal == Portal.partner && !profile.role.isPartner);
        if (wrongPortal) {
          await _client.auth.signOut();
          throw BackendException(
            BackendErrorKind.permission,
            profile.role.isPartner ? 'This is a partner account. Use the partner portal to sign in.' : 'This is a passenger account. Use passenger sign-in instead.',
          );
        }
        return profile;
      });

  @override
  Future<AppUser> register({required String fullName, required String email, required String phone, required String password, String? organisation}) => _guard(() async {
        final response = await _client.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'full_name': fullName.trim(), 'phone': phone.trim(), 'organisation': organisation?.trim()},
        );
        // Supabase answers a repeat sign-up with a user that has no identities instead of an error.
        if (response.user == null || (response.user!.identities?.isEmpty ?? false)) {
          throw const BackendException(BackendErrorKind.validation, 'An account with this email already exists. Sign in instead.');
        }
        if (response.session == null) {
          throw const BackendException(BackendErrorKind.validation, 'Check your email to confirm your account, then sign in.');
        }
        return _profile(response.user!.id);
      });

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _client.auth.resetPasswordForEmail(email.trim()));

  @override
  Future<void> signOut() => _guard(() => _client.auth.signOut());

  // ------------------------------------------------------------ catalogue

  @override
  Future<List<TransitRoute>> fetchPublicRoutes() => _guard(() async => [
        for (final r in _rows(await _client.from('routes').select().eq('active', true).order('monthly_trips', ascending: false))) TransitRoute.fromJson(r),
      ]);

  @override
  Future<List<TransportProvider>> fetchProviders() =>
      _guard(() async => [for (final r in _rows(await _client.from('providers').select().order('name'))) TransportProvider.fromJson(r)]);

  @override
  Future<List<TransitRoute>> fetchRoutes() =>
      _guard(() async => [for (final r in _rows(await _client.from('routes').select().order('code'))) TransitRoute.fromJson(r)]);

  @override
  Future<List<Vehicle>> fetchVehicles() =>
      _guard(() async => [for (final r in _rows(await _client.from('vehicles').select().order('plate'))) Vehicle.fromJson(r)]);

  @override
  Future<List<ChargingStation>> fetchChargingStations() =>
      _guard(() async => [for (final r in _rows(await _client.from('charging_stations').select().order('name'))) ChargingStation.fromJson(r)]);

  @override
  Future<List<SharedRide>> fetchSharedRides() => _guard(() async {
        final since = DateTime.now().subtract(const Duration(minutes: 30)).toUtc().toIso8601String();
        return [for (final r in _rows(await _client.from('shared_rides').select().eq('status', 'open').gte('depart_at', since).order('depart_at'))) SharedRide.fromJson(r)];
      });

  @override
  Future<MetricBaselines> fetchBaselines() => _guard(() async {
        final row = _row(await _client.from('metric_baselines').select('data').eq('id', 1).limit(1));
        final d = Map<String, dynamic>.from(row['data'] as Map);
        int n(String k) => (d[k] as num).toInt();
        return MetricBaselines(
          operatorProviderId: d['operator_provider_id'] as String,
          fleetProviderId: d['fleet_provider_id'] as String,
          operatorTrips: n('operator_trips'),
          operatorTripsDelta: n('operator_trips_delta'),
          operatorRevenue: n('operator_revenue'),
          operatorRevenueDelta: n('operator_revenue_delta'),
          operatorActiveDrivers: n('operator_active_drivers'),
          fleetRevenue: n('fleet_revenue'),
          fleetRevenueDelta: n('fleet_revenue_delta'),
          fleetEarnings: [
            for (final e in (d['fleet_earnings'] as List))
              VehicleEarning(plate: e['plate'] as String, amount: (e['amount'] as num).toInt(), date: DateTime.parse(e['date'] as String)),
          ],
          ridershipByDay: [for (final v in (d['ridership_by_day'] as List)) (v as num).toInt()],
          ridershipDelta: n('ridership_delta'),
          verifiedOffPlatform: n('verified_off_platform'),
          verifiedDelta: n('verified_delta'),
          routesOffPlatform: n('routes_off_platform'),
          activeRoutesDelta: n('active_routes_delta'),
        );
      });

  // ------------------------------------------------------------ rider

  @override
  Future<Wallet> fetchWallet() => _guard(() async => Wallet.fromJson(_row(await _client.from('wallets').select().eq('user_id', _uid).limit(1))));

  @override
  Future<List<Booking>> fetchMyBookings() => _guard(() async {
        await _client.rpc('settle_tag_along_requests');
        final rows = _rows(await _client.from('bookings').select().eq('user_id', _uid).order('departure_at', ascending: false));
        return [for (final r in rows) Booking.fromJson(r)];
      });

  @override
  Future<Booking> bookTransit({required TransitRoute route, required DateTime departure, required PaymentMethod method}) => _guard(() async => Booking.fromJson(_row(
      await _client.rpc('book_transit', params: {'p_route_id': route.id, 'p_departure': departure.toUtc().toIso8601String(), 'p_method': method.wire}))));

  @override
  Future<Booking> bookElectric({required Vehicle vehicle, required String pickup, required String dropoff, required int fare, required PaymentMethod method}) =>
      _guard(() async => Booking.fromJson(_row(await _client.rpc('book_electric',
          params: {'p_vehicle_id': vehicle.id, 'p_pickup': pickup, 'p_dropoff': dropoff, 'p_fare': fare, 'p_method': method.wire}))));

  @override
  Future<Booking> requestSharedRide(SharedRide ride) =>
      _guard(() async => Booking.fromJson(_row(await _client.rpc('request_shared_ride', params: {'p_ride_id': ride.id}))));

  @override
  Future<SharedRide> offerSharedRide({required String origin, required String destination, required DateTime departAt, required int seats, required int costShare, required String vehicleLabel, String note = '', String? eventId}) =>
      _guard(() async => SharedRide.fromJson(_row(await _client.rpc('offer_shared_ride', params: {
            'p_origin': origin,
            'p_destination': destination,
            'p_depart_at': departAt.toUtc().toIso8601String(),
            'p_seats': seats,
            'p_cost_share': costShare,
            'p_vehicle_label': vehicleLabel,
            'p_note': note,
            'p_event_id': eventId,
          }))));

  @override
  Future<Booking> cancelBooking(String bookingId) =>
      _guard(() async => Booking.fromJson(_row(await _client.rpc('cancel_booking', params: {'p_booking_id': bookingId}))));

  @override
  Future<Wallet> topUp(int amount) => _guard(() async => Wallet.fromJson(_row(await _client.rpc('top_up', params: {'p_amount': amount}))));

  // ------------------------------------------------------------ Tag Along hosting

  @override
  Future<List<Booking>> fetchRideRequests() => _guard(() async {
        await _client.rpc('settle_tag_along_requests');
        return [for (final r in _rows(await _client.rpc('my_ride_requests'))) Booking.fromJson(r)];
      });

  @override
  Future<Booking> respondToRideRequest(String bookingId, {required bool accept}) =>
      _guard(() async => Booking.fromJson(_row(await _client.rpc('respond_ride_request', params: {'p_booking_id': bookingId, 'p_accept': accept}))));

  @override
  Future<SharedRide> cancelSharedRide(String rideId) =>
      _guard(() async => SharedRide.fromJson(_row(await _client.rpc('cancel_shared_ride', params: {'p_ride_id': rideId}))));

  // ------------------------------------------------------------ events

  @override
  Future<List<RideEvent>> fetchEvents() => _guard(() async {
        final since = DateTime.now().subtract(const Duration(hours: 6)).toUtc().toIso8601String();
        final rows = _rows(await _client.from('events').select().eq('status', 'listed').gte('starts_at', since).order('starts_at').limit(100));
        return [for (final r in rows) RideEvent.fromJson(r)];
      });

  @override
  Future<RideEvent> createEvent({required String title, required String venue, required String area, required DateTime startsAt, DateTime? endsAt, required EventCategory category, String description = '', double? lat, double? lng}) =>
      _guard(() async => RideEvent.fromJson(_row(await _client.rpc('create_event', params: {
            'p_title': title,
            'p_venue': venue,
            'p_area': area,
            'p_starts_at': startsAt.toUtc().toIso8601String(),
            'p_ends_at': endsAt?.toUtc().toIso8601String(),
            'p_category': category.name,
            'p_description': description,
            'p_lat': lat,
            'p_lng': lng,
          }))));

  @override
  Future<void> removeEvent(String eventId) => _guard(() => _client.rpc('remove_event', params: {'p_event_id': eventId}));

  // ------------------------------------------------------------ share my ride

  @override
  Future<TripShare> shareTrip(String bookingId) =>
      _guard(() async => TripShare.fromJson(_row(await _client.rpc('share_trip', params: {'p_booking_id': bookingId}))));

  @override
  Future<void> stopSharingTrip(String bookingId) => _guard(() => _client.rpc('stop_trip_share', params: {'p_booking_id': bookingId}));

  @override
  Future<void> updateTripLocation(String bookingId, double lat, double lng) =>
      _guard(() => _client.rpc('update_trip_location', params: {'p_booking_id': bookingId, 'p_lat': lat, 'p_lng': lng}));

  @override
  Future<SharedTrip?> fetchSharedTrip(String token) => _guard(() async {
        final result = await _client.rpc('get_shared_trip', params: {'p_token': token});
        return result is Map ? SharedTrip.fromJson(Map<String, dynamic>.from(result)) : null;
      });

  // ------------------------------------------------------------ live vehicle positions

  @override
  Future<List<VehiclePosition>> fetchVehiclePositions() => _guard(() async {
        final since = DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String();
        return [for (final r in _rows(await _client.from('vehicle_positions').select().gte('updated_at', since))) VehiclePosition.fromJson(r)];
      });

  @override
  Future<void> reportVehiclePosition(String vehicleId, double lat, double lng, {double? heading, double? speedKmh}) => _guard(() =>
      _client.rpc('report_vehicle_position', params: {'p_vehicle_id': vehicleId, 'p_lat': lat, 'p_lng': lng, 'p_heading': heading, 'p_speed_kmh': speedKmh}));

  @override
  Future<void> stopVehicleTracking(String vehicleId) => _guard(() => _client.rpc('stop_vehicle_tracking', params: {'p_vehicle_id': vehicleId}));

  // ------------------------------------------------------------ partners

  @override
  Future<List<Booking>> fetchPartnerBookings() => _guard(() async {
        // Row-level security scopes this to the caller's provider (or everything for FCTA/admin).
        final rows = _rows(await _client.from('bookings').select().order('created_at', ascending: false).limit(500));
        return [for (final r in rows) Booking.fromJson(r)];
      });

  @override
  Future<List<AuditEntry>> fetchAuditLog() =>
      _guard(() async => [for (final r in _rows(await _client.from('audit_log').select().order('at', ascending: false).limit(200))) AuditEntry.fromJson(r)]);

  @override
  Future<List<AppUser>> fetchUsers() =>
      _guard(() async => [for (final r in _rows(await _client.from('profiles').select().order('full_name'))) AppUser.fromJson(r)]);

  @override
  Future<TransportProvider> setProviderStatus(String providerId, Verification status) => _guard(() async =>
      TransportProvider.fromJson(_row(await _client.rpc('set_provider_status', params: {'p_provider_id': providerId, 'p_status': status.wire}))));

  @override
  Future<Vehicle> setVehicleVerification(String vehicleId, Verification status) => _guard(() async =>
      Vehicle.fromJson(_row(await _client.rpc('set_vehicle_verification', params: {'p_vehicle_id': vehicleId, 'p_status': status.wire}))));

  @override
  Future<Vehicle> setVehicleStatus(String vehicleId, VehicleStatus status) => _guard(() async =>
      Vehicle.fromJson(_row(await _client.rpc('set_vehicle_status', params: {'p_vehicle_id': vehicleId, 'p_status': status.wire}))));

  @override
  Future<Booking> completeRide(String bookingId) =>
      _guard(() async => Booking.fromJson(_row(await _client.rpc('complete_ride', params: {'p_booking_id': bookingId}))));

  @override
  Future<TransitRoute> updateRouteFare(String routeId, int fare) =>
      _guard(() async => TransitRoute.fromJson(_row(await _client.rpc('update_route_fare', params: {'p_route_id': routeId, 'p_fare': fare}))));

  @override
  Future<Vehicle> registerVehicle({required String operatorId, required VehicleKind kind, required String plate, required String model, required int capacity, String? ownerId}) =>
      _guard(() async => Vehicle.fromJson(_row(await _client.rpc('register_vehicle', params: {
            'p_operator_id': operatorId,
            'p_kind': kind.wire,
            'p_plate': plate,
            'p_model': model,
            'p_capacity': capacity,
            'p_owner_id': ownerId,
          }))));

  @override
  Future<AppUser> setUserRole(String userId, UserRole role, {String? providerId}) => _guard(() async =>
      AppUser.fromJson(_row(await _client.rpc('set_user_role', params: {'p_user_id': userId, 'p_role': role.wire, 'p_provider_id': providerId}))));

  // ------------------------------------------------------------ partner registration

  static const _bucket = 'partner-docs';

  @override
  Future<String?> accessToken() async => _client.auth.currentSession?.accessToken;

  @override
  Future<PartnerApplication> submitPartnerApplication(PartnerApplication draft, List<DocumentFile> documents) => _guard(() async {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final uploaded = <DocumentFile>[];
        for (final d in documents) {
          final bytes = d.bytes;
          if (bytes == null) continue;
          final ext = d.mimeType == 'application/pdf' ? 'pdf' : (d.mimeType == 'image/png' ? 'png' : 'jpg');
          // Private bucket; the first folder is the owner's id so storage policies can check it.
          final path = '$_uid/$stamp/${d.slot.wire}.$ext';
          await _client.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: d.mimeType, upsert: true));
          uploaded.add(d.copyWith(path: path));
        }
        final payload = draft.copyWith(documents: uploaded).toJson()
          ..remove('id')
          ..remove('user_id')
          ..remove('status');
        return PartnerApplication.fromJson(_row(await _client.rpc('submit_partner_application', params: {'p_application': payload})));
      });

  @override
  Future<List<PartnerApplication>> fetchMyApplications() => _guard(() async => [
        for (final r in _rows(await _client.from('partner_applications').select().eq('user_id', _uid).order('created_at', ascending: false))) PartnerApplication.fromJson(r),
      ]);

  @override
  Future<List<PartnerApplication>> fetchPartnerApplications() => _guard(() async => [
        for (final r in _rows(await _client.from('partner_applications').select().order('created_at', ascending: false).limit(200))) PartnerApplication.fromJson(r),
      ]);

  @override
  Future<PartnerApplication> reviewPartnerApplication(String applicationId, ApplicationStatus decision, String note) => _guard(() async =>
      PartnerApplication.fromJson(_row(await _client.rpc('review_partner_application', params: {'p_id': applicationId, 'p_decision': decision.wire, 'p_note': note}))));

  @override
  Future<DocumentFile> openDocument(DocumentFile document) => _guard(() async {
        final path = document.path;
        if (path == null) return document;
        final url = await _client.storage.from(_bucket).createSignedUrl(path, 600);
        return document.copyWith(url: url);
      });
}
