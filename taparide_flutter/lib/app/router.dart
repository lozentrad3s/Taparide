import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import 'app_mode.dart';
import '../features/auth/login_page.dart';
import '../features/auth/two_step_page.dart';
import '../features/common/credits_page.dart';
import '../features/ev/ev_page.dart';
import '../features/common/redirect_pages.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/live/live_map_page.dart';
import '../features/nearby/nearby_page.dart';
import '../features/partner/partner_apply_page.dart';
import '../features/partner/partner_status_page.dart';
import '../features/passenger/home_page.dart';
import '../features/passenger/payment_page.dart';
import '../features/passenger/profile_page.dart';
import '../features/passenger/rider_shell.dart';
import '../features/passenger/route_details_page.dart';
import '../features/passenger/routes_page.dart';
import '../features/passenger/ticket_page.dart';
import '../features/passenger/trips_page.dart';
import '../features/portal/portal_pages.dart';
import '../features/portal/portal_shell.dart';
import '../features/events/events_page.dart';
import '../features/share/shared_trip_page.dart';
import '../features/tag_along/tag_along_page.dart';

String homeFor(AppUser user) => switch (user.role) {
      UserRole.passenger => '/app',
      UserRole.operator => '/portal/operator',
      UserRole.fleetOwner => '/portal/fleet',
      UserRole.government => '/portal/fcta',
      UserRole.admin => '/portal/overview',
      UserRole.eventPartner => '/portal/events',
      UserRole.fleetDriver => '/portal/driver',
    };

/// Dashboard-only pages (they live at taparide.com/dashboard in production).
bool _dashboardPath(String path) => path.startsWith('/portal') || path.startsWith('/partner');

/// Where a signed-out visitor starts.
String _startFor(AppMode mode) => mode == AppMode.dashboard ? '/login?portal=partner' : '/';

String _moved(bool toDashboard, Uri uri) => Uri(path: '/moved', queryParameters: {'to': toDashboard ? 'dashboard' : 'app', 'path': uri.toString()}).toString();

bool _riderPath(String path) =>
    path.startsWith('/app') || path.startsWith('/ride') || path.startsWith('/ticket') || path == '/ev' || path == '/tag-along' || path == '/live' || path.startsWith('/events');

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter buildRouter(AppState state, {AppMode? mode}) {
  final appMode = mode ?? AppMode.current;
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: state.user == null ? _startFor(appMode) : homeFor(state.user!),
    refreshListenable: state,
    redirect: (context, s) {
      final user = state.user;
      final path = s.uri.path;
      final portal = path.startsWith('/portal');
      if (path == '/moved') return null;
      // Admins and FCTA staff pass the authenticator step before anything else opens.
      if (user != null && state.twoStepPending) return path == '/two-step' ? null : '/two-step';
      if (path == '/two-step') return user == null ? '/login?portal=partner' : homeFor(user);
      // Each production build serves one side; links to the other side are sent across.
      if (!appMode.hasDashboards && _dashboardPath(path)) return _moved(true, s.uri);
      if (!appMode.hasRiderApp && (_riderPath(path) || path == '/register')) return _moved(false, s.uri);
      if (!appMode.hasRiderApp && path == '/') return '/login?portal=partner';
      if (user != null && !appMode.hasDashboards && user.role.isPartner && !_dashboardPath(path)) return _moved(true, Uri(path: homeFor(user)));
      if (user != null && !appMode.hasRiderApp && !user.role.isPartner) return _moved(false, Uri(path: '/app'));
      // Arriving to create an account while another account is signed in on this browser.
      final email = s.uri.queryParameters['email'];
      if (user != null && path == '/register' && email != null && email.trim().toLowerCase() != user.email.toLowerCase()) {
        return Uri(path: '/switch-account', queryParameters: s.uri.queryParameters).toString();
      }
      if (path == '/switch-account') return null;
      // Signed-in people never see the onboarding again.
      if (user != null && path == '/') return homeFor(user);
      if (user == null) {
        if (_riderPath(path)) return Uri(path: '/login', queryParameters: {'from': s.uri.toString()}).toString();
        if (portal) return Uri(path: '/login', queryParameters: {'portal': 'partner', 'from': s.uri.toString()}).toString();
        return null;
      }
      if (path == '/login' || path == '/register') {
        final from = s.uri.queryParameters['from'];
        if (from != null && from.startsWith('/') && (_riderPath(Uri.parse(from).path) != user.role.isPartner)) return from;
        return homeFor(user);
      }
      if (_riderPath(path) && user.role.isPartner) return homeFor(user);
      if (portal && !user.role.isPartner) return '/app';
      if (path == '/portal' || path == '/portal/') return homeFor(user);
      if (portal) {
        final section = PortalSection.byPath(path);
        if (section != null && !section.roles.contains(user.role)) return homeFor(user);
      }
      return null;
    },
    errorBuilder: (context, s) => appMode.hasRiderApp ? const OnboardingPage() : const LoginPage(portal: Portal.partner),
    routes: [
      GoRoute(path: '/', builder: (context, s) => OnboardingPage(query: s.uri.queryParameters)),
      GoRoute(
        path: '/login',
        builder: (context, s) => LoginPage(
          portal: !appMode.hasRiderApp || s.uri.queryParameters['portal'] == 'partner' ? Portal.partner : Portal.passenger,
          from: s.uri.queryParameters['from'],
          email: s.uri.queryParameters['email'],
          mode: appMode,
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (context, s) => LoginPage(portal: Portal.passenger, startInRegister: true, from: s.uri.queryParameters['from'], email: s.uri.queryParameters['email'], mode: appMode),
      ),
      GoRoute(path: '/two-step', builder: (context, s) => const TwoStepPage()),
      GoRoute(path: '/switch-account', builder: (context, s) => SwitchAccountPage(query: s.uri.queryParameters)),
      GoRoute(
        path: '/moved',
        builder: (context, s) => ElsewherePage(toDashboard: s.uri.queryParameters['to'] == 'dashboard', fragment: s.uri.queryParameters['path']),
      ),
      GoRoute(path: '/credits', builder: (context, s) => const CreditsPage()),
      // Partner onboarding is open to everyone (the apply flow creates an account if needed).
      GoRoute(path: '/partner/apply', parentNavigatorKey: _rootKey, builder: (context, s) => PartnerApplyPage(initialType: s.uri.queryParameters['type'])),
      GoRoute(path: '/partner/status', parentNavigatorKey: _rootKey, builder: (context, s) => const PartnerStatusPage()),
      GoRoute(path: '/nearby', parentNavigatorKey: _rootKey, builder: (context, s) => NearbyPage(category: s.uri.queryParameters['c'])),

      // Rider app: four tabs, with full-screen flows pushed above them.
      StatefulShellRoute.indexedStack(
        builder: (context, s, shell) => RiderShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/app', builder: (context, s) => const HomePage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/app/routes', builder: (context, s) => RoutesPage(initialQuery: s.uri.queryParameters['q']))]),
          StatefulShellBranch(routes: [GoRoute(path: '/app/trips', builder: (context, s) => const TripsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/app/profile', builder: (context, s) => ProfilePage(topUpReference: s.uri.queryParameters['topup']))]),
        ],
      ),
      GoRoute(
        path: '/ride/:routeId',
        parentNavigatorKey: _rootKey,
        builder: (context, s) => RouteDetailsPage(routeId: s.pathParameters['routeId']!),
        routes: [
          GoRoute(
            path: 'pay',
            parentNavigatorKey: _rootKey,
            builder: (context, s) => PaymentPage(
              routeId: s.pathParameters['routeId']!,
              departure: DateTime.tryParse(s.uri.queryParameters['at'] ?? '')?.toLocal(),
            ),
          ),
        ],
      ),
      GoRoute(path: '/ticket/:bookingId', parentNavigatorKey: _rootKey, builder: (context, s) => TicketPage(bookingId: s.pathParameters['bookingId']!)),
      GoRoute(path: '/ev', parentNavigatorKey: _rootKey, builder: (context, s) => const EvPage()),
      GoRoute(path: '/live', parentNavigatorKey: _rootKey, builder: (context, s) => const LiveMapPage()),
      GoRoute(path: '/tag-along', parentNavigatorKey: _rootKey, builder: (context, s) => const TagAlongPage()),
      GoRoute(
        path: '/events',
        parentNavigatorKey: _rootKey,
        builder: (context, s) => const EventsPage(),
        routes: [GoRoute(path: ':eventId', parentNavigatorKey: _rootKey, builder: (context, s) => EventDetailPage(eventId: s.pathParameters['eventId']!))],
      ),
      // Opened from a link by a trusted contact: no sign-in.
      GoRoute(path: '/trip/:token', parentNavigatorKey: _rootKey, builder: (context, s) => SharedTripPage(token: s.pathParameters['token']!)),

      // Partner portal: operators, fleet owners, FCTA and platform admins.
      ShellRoute(
        builder: (context, s, child) => PortalShell(location: s.uri.path, child: child),
        routes: [
          for (final section in PortalSection.all)
            GoRoute(
              path: section.path,
              pageBuilder: (context, s) => NoTransitionPage(
                key: ValueKey(s.uri.toString()),
                child: portalPageFor(section, s.uri.queryParameters),
              ),
            ),
        ],
      ),
    ],
  );
}
