import 'analytics.dart';
import 'models.dart';
import 'partner_models.dart';

/// Revenue for one operating partner (who runs the vehicles or routes).
class ProviderRevenue {
  const ProviderRevenue({required this.provider, required this.monthlyRevenue, required this.vehicles, required this.routes, required this.bookingsToday});
  final TransportProvider provider;
  final int monthlyRevenue;
  final int vehicles;
  final int routes;
  final int bookingsToday;
}

/// Platform-wide figures for the admin control centre. Pure and deterministic.
class AdminAnalytics {
  const AdminAnalytics({
    required this.platform,
    required this.faresThisMonth,
    required this.ridesThisMonth,
    required this.bookingsToday,
    required this.faresToday,
    required this.revenueByMode,
    required this.byOperator,
    required this.payments,
    required this.vehiclesByStatus,
    required this.verifiedVehicles,
    required this.pendingVehicles,
    required this.electricVehicles,
    required this.lowBatteryEvs,
    required this.providersByStatus,
    required this.applicationsByStatus,
    required this.usersByRole,
    required this.activeRoutes,
    required this.departuresPerDay,
  });

  /// The whole-platform insights report (demand areas, hours, utilisation).
  final InsightsReport platform;
  final int faresThisMonth;
  final int ridesThisMonth;
  final int bookingsToday;
  final int faresToday;

  /// Fixed category order: Bus, Rail, Shuttle, Cars & EVs.
  final List<(String, int)> revenueByMode;
  final List<ProviderRevenue> byOperator;
  final Map<PaymentMethod, int> payments;
  final Map<VehicleStatus, int> vehiclesByStatus;
  final int verifiedVehicles;
  final int pendingVehicles;
  final int electricVehicles;
  final int lowBatteryEvs;
  final Map<Verification, int> providersByStatus;
  final Map<ApplicationStatus, int> applicationsByStatus;
  final Map<UserRole, int> usersByRole;
  final int activeRoutes;
  final int departuresPerDay;

  int get totalUsers => usersByRole.values.fold(0, (a, b) => a + b);
  int get vehicles => vehiclesByStatus.values.fold(0, (a, b) => a + b);
  int get openApplications => (applicationsByStatus[ApplicationStatus.submitted] ?? 0) + (applicationsByStatus[ApplicationStatus.underReview] ?? 0);
  double get electricShare => vehicles == 0 ? 0 : electricVehicles / vehicles;

  static AdminAnalytics build({
    required List<TransportProvider> providers,
    required List<TransitRoute> routes,
    required List<Vehicle> vehicles,
    required List<Booking> bookings,
    required List<PartnerApplication> applications,
    required List<AppUser> users,
    required DateTime now,
  }) {
    final platform = Analytics.build(providerId: null, scopeName: 'Whole platform', routes: routes, vehicles: vehicles, bookings: bookings, now: now);
    bool today(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
    final live = [for (final b in bookings) if (b.status != BookingStatus.cancelled && b.status != BookingStatus.declined) b];
    final liveToday = [for (final b in live) if (today(b.createdAt)) b];

    // Same rule as each partner's own AI insights: what the vehicles earned this month,
    // or trips × fare for an operator whose vehicles report no earnings yet.
    int operatorRevenue(String providerId) {
      final earned = vehicles.where((v) => v.operatorId == providerId).fold<int>(0, (s, v) => s + v.monthEarnings);
      return earned > 0 ? earned : routes.where((r) => r.providerId == providerId && r.active).fold<int>(0, (s, r) => s + r.monthlyTrips * r.fare);
    }

    // Revenue by mode from vehicle earnings, so it adds up to the operator totals.
    int earnedBy(bool Function(VehicleKind k) test) => vehicles.where((v) => test(v.kind)).fold(0, (s, v) => s + v.monthEarnings);
    final byMode = <(String, int)>[
      ('Bus', earnedBy((k) => k == VehicleKind.bus || k == VehicleKind.minibus)),
      ('Rail', earnedBy((k) => k == VehicleKind.train)),
      ('Shuttle & keke', earnedBy((k) => k == VehicleKind.evShuttle || k == VehicleKind.evKeke)),
      ('Cars & EVs', earnedBy((k) => k.isBookableCar)),
    ];

    // Operators only (fleet owners lease to operators, so counting both would double count).
    final operators = [for (final p in providers) if (p.kind != ProviderKind.fleetOwner) p];
    final byOperator = [
      for (final p in operators)
        () {
          final own = vehicles.where((v) => v.operatorId == p.id).toList();
          final ownRoutes = routes.where((r) => r.providerId == p.id).toList();
          return ProviderRevenue(
            provider: p,
            monthlyRevenue: operatorRevenue(p.id),
            vehicles: own.length,
            routes: ownRoutes.length,
            bookingsToday: liveToday.where((b) => b.providerId == p.id).length,
          );
        }(),
    ]..sort((a, b) => b.monthlyRevenue.compareTo(a.monthlyRevenue));

    final carRides = vehicles.where((v) => v.kind.isBookableCar && v.baseFare != null && v.baseFare! > 0).fold<int>(0, (s, v) => s + v.monthEarnings ~/ (v.baseFare! * 2));

    return AdminAnalytics(
      platform: platform,
      faresThisMonth: byOperator.fold(0, (s, r) => s + r.monthlyRevenue),
      ridesThisMonth: routes.where((r) => r.active).fold<int>(0, (s, r) => s + r.monthlyTrips) + carRides,
      bookingsToday: liveToday.length,
      faresToday: liveToday.where((b) => b.paymentMethod != PaymentMethod.splitCost).fold(0, (s, b) => s + b.fare),
      revenueByMode: byMode,
      byOperator: [for (final r in byOperator) if (r.monthlyRevenue > 0 || r.vehicles > 0) r],
      payments: {for (final m in PaymentMethod.values) m: live.where((b) => b.paymentMethod == m).length},
      vehiclesByStatus: {for (final s in VehicleStatus.values) s: vehicles.where((v) => v.status == s).length},
      verifiedVehicles: vehicles.where((v) => v.verification == Verification.verified).length,
      pendingVehicles: vehicles.where((v) => v.verification == Verification.pending).length,
      electricVehicles: vehicles.where((v) => v.electric && v.kind != VehicleKind.train).length,
      lowBatteryEvs: vehicles.where((v) => (v.batteryPct ?? 100) < 30).length,
      providersByStatus: {for (final s in Verification.values) s: providers.where((p) => p.status == s).length},
      applicationsByStatus: {for (final s in ApplicationStatus.values) s: applications.where((a) => a.status == s).length},
      usersByRole: {for (final r in UserRole.values) r: users.where((u) => u.role == r).length},
      activeRoutes: routes.where((r) => r.active).length,
      departuresPerDay: routes.where((r) => r.active).fold(0, (s, r) => s + r.departures.length),
    );
  }

  /// Rows for the platform CSV report.
  List<List<Object?>> toCsvRows(DateTime now) => [
        ['Tap A Ride platform report', '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'],
        [],
        ['Fares this month (NGN)', faresThisMonth],
        ['Rides this month', ridesThisMonth],
        ['Bookings today', bookingsToday],
        ['Fares today (NGN)', faresToday],
        ['Users', totalUsers],
        ['Vehicles', vehicles],
        ['Verified vehicles', verifiedVehicles],
        ['Electric vehicles', electricVehicles],
        ['Active routes', activeRoutes],
        [],
        ['Mode', 'Revenue this month (NGN)'],
        for (final m in revenueByMode) [m.$1, m.$2],
        [],
        ['Operator', 'Type', 'FCTA status', 'Routes', 'Vehicles', 'Revenue this month (NGN)', 'Bookings today'],
        for (final r in byOperator) [r.provider.name, r.provider.kind.label, r.provider.status.label, r.routes, r.vehicles, r.monthlyRevenue, r.bookingsToday],
      ];
}
