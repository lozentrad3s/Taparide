import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../shared/brand.dart';
import '../../shared/ui.dart';
import '../assistant/assistant_sheet.dart';
import 'portal_chrome.dart';

/// One area of the partner portal and the roles allowed into it.
/// The backend enforces the same rules; this only decides what to show.
class PortalSection {
  const PortalSection(this.path, this.label, this.icon, this.roles, {String? short}) : _short = short;
  final String path;
  final String label;
  final String? _short;

  /// Label for the phone navigation bar.
  String get shortLabel => _short ?? label;
  final IconData icon;
  final Set<UserRole> roles;

  static const _partners = {UserRole.operator, UserRole.fleetOwner, UserRole.government, UserRole.admin};

  static const overview = PortalSection('/portal/overview', 'Control centre', Icons.space_dashboard_rounded, {UserRole.admin}, short: 'Admin');
  static const fcta = PortalSection('/portal/fcta', 'FCTA dashboard', Icons.account_balance_rounded, {UserRole.government, UserRole.admin}, short: 'FCTA');
  static const operator = PortalSection('/portal/operator', 'Operator dashboard', Icons.directions_bus_rounded, {UserRole.operator, UserRole.government, UserRole.admin}, short: 'Dashboard');
  static const fleet = PortalSection('/portal/fleet', 'Fleet owner dashboard', Icons.local_shipping_rounded, {UserRole.fleetOwner, UserRole.admin}, short: 'Fleet');
  static const providers = PortalSection('/portal/providers', 'Transport providers', Icons.apartment_rounded, {UserRole.government, UserRole.admin}, short: 'Providers');
  static const evs = PortalSection('/portal/evs', 'Electric vehicles', Icons.electric_car_rounded, {UserRole.operator, UserRole.government, UserRole.admin}, short: 'EVs');
  static const routes = PortalSection('/portal/routes', 'Routes & fares', Icons.alt_route_rounded, {UserRole.operator, UserRole.government, UserRole.admin}, short: 'Routes');
  static const vehicles = PortalSection('/portal/vehicles', 'Vehicles', Icons.directions_car_filled_rounded, _partners);
  static const bookings = PortalSection('/portal/bookings', 'Bookings & trips', Icons.confirmation_number_rounded, _partners, short: 'Bookings');
  static const verification = PortalSection('/portal/verification', 'Verification', Icons.verified_user_rounded, {UserRole.government, UserRole.admin});
  static const users = PortalSection('/portal/users', 'Users & roles', Icons.manage_accounts_rounded, {UserRole.admin}, short: 'Users');
  static const audit = PortalSection('/portal/audit', 'Audit log', Icons.history_rounded, {UserRole.government, UserRole.admin});

  static const insights = PortalSection('/portal/insights', 'AI insights', Icons.insights_rounded, _partners, short: 'Insights');
  static const applications = PortalSection('/portal/applications', 'Partner applications', Icons.how_to_reg_rounded, {UserRole.government, UserRole.admin}, short: 'Applications');

  static const waitlist = PortalSection('/portal/waitlist', 'Website sign-ups', Icons.how_to_reg_outlined, {UserRole.admin}, short: 'Sign-ups');

  /// Master admin: wallets, top-ups, held fares and partner collection wallets.
  static const money = PortalSection('/portal/money', 'Money', Icons.payments_rounded, {UserRole.admin});

  static const events = PortalSection('/portal/events', 'Events & event buses', Icons.celebration_rounded, {UserRole.eventPartner, UserRole.operator, UserRole.government, UserRole.admin}, short: 'Events');

  /// Drivers employed by a fleet owner or operator: their dashboard, and the page their managers use.
  static const driverShift = PortalSection('/portal/driver', 'Driver dashboard', Icons.badge_rounded, {UserRole.fleetDriver, UserRole.admin}, short: 'Dashboard');
  static const drivers = PortalSection('/portal/drivers', 'Drivers', Icons.groups_2_rounded, {UserRole.operator, UserRole.fleetOwner, UserRole.admin});

  static const all = [overview, waitlist, money, insights, fcta, operator, fleet, events, applications, providers, evs, routes, vehicles, drivers, driverShift, bookings, verification, users, audit];

  /// The operator dashboard as private drivers see it (same page, driver wording).
  static const driver = PortalSection('/portal/operator', 'Driver dashboard', Icons.directions_car_rounded, {UserRole.operator, UserRole.government, UserRole.admin}, short: 'Driver');

  static PortalSection? byPath(String path) => all.where((s) => s.path == path).firstOrNull;

  // Sections are identified by their path (the driver view is the operator page).
  @override
  bool operator ==(Object other) => other is PortalSection && other.path == path;

  @override
  int get hashCode => path.hashCode;

  /// Sections in the order each role uses them most.
  static List<PortalSection> forRole(UserRole role, {bool privateDriver = false}) => privateDriver
      ? const [driver, insights, bookings, vehicles]
      : switch (role) {
        UserRole.admin => all,
        UserRole.government => [fcta, insights, applications, providers, verification, vehicles, routes, evs, operator, bookings, audit],
        UserRole.operator => [operator, insights, routes, vehicles, drivers, events, bookings, evs],
        UserRole.fleetOwner => [fleet, insights, vehicles, drivers, bookings],
        UserRole.eventPartner => [events, bookings],
        UserRole.fleetDriver => const [driverShift],
        UserRole.passenger => const [],
      };
}

class PortalShell extends StatelessWidget {
  const PortalShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user;
    if (user == null) return const SizedBox.shrink();
    // Until the partner's own company has loaded we can't tell a driver from an operator,
    // so hold the shell rather than flash the wrong menu.
    if (user.providerId != null && state.providerById(user.providerId) == null && state.dataState != LoadState.ready && state.dataState != LoadState.error) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final privateDriver = user.role == UserRole.operator && state.providerById(user.providerId)?.kind == ProviderKind.privateDriver;
    final sections = PortalSection.forRole(user.role, privateDriver: privateDriver);
    final current = PortalSection.byPath(location);
    final wide = isWide(context, 1024);

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.ground,
        body: Row(children: [
          PortalSidebar(user: user, sections: sections, current: current),
          Expanded(
            child: Column(children: [
              PortalTopBar(user: user, current: current),
              Expanded(child: child),
            ]),
          ),
        ]),
        floatingActionButton: const AssistantButton(),
      );
    }

    // Phone: the first three sections in the bottom bar, the rest under "More".
    final primary = sections.take(3).toList();
    final index = primary.indexWhere((s) => s.path == current?.path);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.forestDeep,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: const BrandLockup(height: 26, onDark: true),
        actions: [
          const DemoBadge(onDark: true),
          IconButton(tooltip: 'Refresh', onPressed: state.refresh, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: const AssistantButton(),
      drawer: Drawer(
        backgroundColor: AppColors.forestDeep,
        width: 288,
        child: Builder(builder: (drawer) => PortalSidebar(user: user, sections: sections, current: current, width: 288, onNavigate: () => Navigator.of(drawer).pop())),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? primary.length : index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i < primary.length) {
            context.go(primary[i].path);
          } else {
            showPortalMenu(context, user: user, sections: sections, current: current);
          }
        },
        destinations: [
          for (final s in primary) NavigationDestination(icon: Icon(s.icon), label: s.shortLabel),
          const NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'More'),
        ],
      ),
    );
  }
}
