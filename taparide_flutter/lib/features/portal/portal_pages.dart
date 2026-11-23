import 'package:flutter/material.dart';

import 'admin_dashboard.dart';
import 'applications_page.dart';
import 'dashboard_pages.dart';
import 'events_portal_page.dart';
import 'fleet_driver_dashboard.dart';
import 'fleet_drivers_page.dart';
import 'insights_page.dart';
import 'manage_pages.dart';
import 'money_page.dart';
import 'portal_shell.dart';
import 'refunds_pages.dart';
import 'waitlist_page.dart';

export 'portal_shell.dart' show PortalSection;

/// Maps a portal section to its page. `?provider=` opens a specific provider's dashboard.
Widget portalPageFor(PortalSection section, Map<String, String> query) => switch (section.path) {
      '/portal/overview' => const AdminDashboard(),
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
      '/portal/insights' => InsightsPage(providerId: query['provider']),
      '/portal/applications' => const ApplicationsPage(),
      '/portal/events' => const EventsPortalPage(),
      '/portal/waitlist' => const WaitlistPage(),
      '/portal/money' => const MoneyPage(),
      '/portal/refunds' => const RefundsPage(),
      '/portal/rider-verification' => const RiderChecksPage(),
      '/portal/drivers' => FleetDriversPage(providerId: query['provider']),
      '/portal/driver' => FleetDriverDashboard(driverId: query['driver']),
      _ => const OverviewPage(),
    };
