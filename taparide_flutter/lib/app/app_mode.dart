/// Which part of Tap A Ride this build serves.
///
/// - `rider`: the rider app at taparide.com/app (onboarding, sign-in, booking).
/// - `dashboard`: the partner, FCTA and admin dashboards at taparide.com/dashboard.
/// - `all`: both in one build (local development and tests).
///
/// Set with `--dart-define=APP_MODE=rider|dashboard` (see deploy/scripts/build-web.mjs).
enum AppMode {
  all,
  rider,
  dashboard;

  static final AppMode current = switch (const String.fromEnvironment('APP_MODE')) {
    'rider' => AppMode.rider,
    'dashboard' => AppMode.dashboard,
    _ => AppMode.all,
  };

  bool get hasRiderApp => this != AppMode.dashboard;
  bool get hasDashboards => this != AppMode.rider;

  /// Where the other half lives when this build only serves one of them (same site).
  static const riderAppUrl = String.fromEnvironment('RIDER_APP_URL', defaultValue: '/app/');
  static const dashboardUrl = String.fromEnvironment('DASHBOARD_URL', defaultValue: '/dashboard/');
}
