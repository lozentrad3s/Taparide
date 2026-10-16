import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../features/auth/login_page.dart';
import '../features/common/credits_page.dart';
import '../features/ev/ev_page.dart';
import '../features/landing/landing_page.dart';
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
import '../features/tag_along/tag_along_page.dart';

String homeFor(AppUser user) => switch (user.role) {
      UserRole.passenger => '/app',
      UserRole.operator => '/portal/operator',
      UserRole.fleetOwner => '/portal/fleet',
      UserRole.government => '/portal/fcta',
      UserRole.admin => '/portal/overview',
    };

bool _riderPath(String path) =>
    path.startsWith('/app') || path.startsWith('/ride') || path.startsWith('/ticket') || path == '/ev' || path == '/tag-along';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter buildRouter(AppState state) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: state.user == null ? '/' : homeFor(state.user!),
    refreshListenable: state,
    redirect: (context, s) {
      final user = state.user;
      final path = s.uri.path;
      final portal = path.startsWith('/portal');
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
    errorBuilder: (context, s) => const LandingPage(),
    routes: [
      GoRoute(path: '/', builder: (context, s) => const LandingPage()),
      GoRoute(
        path: '/login',
        builder: (context, s) => LoginPage(
          portal: s.uri.queryParameters['portal'] == 'partner' ? Portal.partner : Portal.passenger,
          from: s.uri.queryParameters['from'],
        ),
      ),
      GoRoute(path: '/register', builder: (context, s) => LoginPage(portal: Portal.passenger, startInRegister: true, from: s.uri.queryParameters['from'])),
      GoRoute(path: '/credits', builder: (context, s) => const CreditsPage()),

      // Rider app: four tabs, with full-screen flows pushed above them.
      StatefulShellRoute.indexedStack(
        builder: (context, s, shell) => RiderShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/app', builder: (context, s) => const HomePage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/app/routes', builder: (context, s) => RoutesPage(initialQuery: s.uri.queryParameters['q']))]),
          StatefulShellBranch(routes: [GoRoute(path: '/app/trips', builder: (context, s) => const TripsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/app/profile', builder: (context, s) => const ProfilePage())]),
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
      GoRoute(path: '/tag-along', parentNavigatorKey: _rootKey, builder: (context, s) => const TagAlongPage()),

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
