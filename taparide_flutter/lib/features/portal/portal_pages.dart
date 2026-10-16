import 'package:flutter/material.dart';

import 'dashboard_pages.dart';
import 'manage_pages.dart';
import 'portal_shell.dart';

export 'portal_shell.dart' show PortalSection;

/// Maps a portal section to its page. `?provider=` opens a specific provider's dashboard.
Widget portalPageFor(PortalSection section, Map<String, String> query) => switch (section.path) {
      '/portal/overview' => const OverviewPage(),
      '/portal/fcta' => const FctaPage(),
      '/portal/operator' => OperatorPage(providerId: query['provider']),
      '/portal/fleet' => FleetPage(providerId: query['provider']),
      '/portal/providers' => const ProvidersPage(),
      '/portal/evs' => const EvFleetPage(),
      '/portal/routes' => const PortalRoutesPage(),
      '/portal/vehicles' => const PortalVehiclesPage(),
      '/portal/bookings' => const PortalBookingsPage(),
      '/portal/verification' => const VerificationPage(),
      '/portal/users' => const UsersPage(),
      '/portal/audit' => const AuditPage(),
      _ => const OverviewPage(),
    };
