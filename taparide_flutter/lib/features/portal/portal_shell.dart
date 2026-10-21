import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../shared/brand.dart';
import '../../shared/ui.dart';
import '../assistant/assistant_sheet.dart';

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

  static const all = [overview, insights, fcta, operator, fleet, applications, providers, evs, routes, vehicles, bookings, verification, users, audit];

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
        UserRole.operator => [operator, insights, routes, vehicles, bookings, evs],
        UserRole.fleetOwner => [fleet, insights, vehicles, bookings],
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
        body: Row(children: [
          _Sidebar(user: user, sections: sections, current: current),
          Expanded(child: child),
        ]),
        floatingActionButton: const AssistantButton(),
      );
    }

    final primary = sections.take(3).toList();
    final index = primary.indexWhere((s) => s.path == current?.path);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.forestDeep,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: const BrandLockup(height: 26, onDark: true),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: state.refresh, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: const AssistantButton(),
      drawer: Drawer(
        backgroundColor: AppColors.forestDeep,
        child: _SidebarContent(user: user, sections: sections, current: current, onNavigate: () => Navigator.of(context).pop()),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? primary.length : index,
        onDestinationSelected: (i) {
          if (i < primary.length) {
            context.go(primary[i].path);
          } else {
            Scaffold.maybeOf(context)?.openDrawer();
            _openMore(context, user, sections, current);
          }
        },
        destinations: [
          for (final s in primary) NavigationDestination(icon: Icon(s.icon), label: s.shortLabel),
          const NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
        ],
      ),
    );
  }

  void _openMore(BuildContext context, AppUser user, List<PortalSection> sections, PortalSection? current) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final s in sections.skip(3))
              ListTile(
                leading: Icon(s.icon, color: s == current ? AppColors.forest : AppColors.muted),
                title: Text(s.label),
                selected: s == current,
                onTap: () {
                  Navigator.pop(sheet);
                  context.go(s.path);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              onTap: () async {
                Navigator.pop(sheet);
                await context.read<AppState>().signOut();
                if (context.mounted) context.go('/');
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.user, required this.sections, required this.current});
  final AppUser user;
  final List<PortalSection> sections;
  final PortalSection? current;

  @override
  Widget build(BuildContext context) => Container(
        width: 260,
        color: AppColors.forestDeep,
        child: _SidebarContent(user: user, sections: sections, current: current),
      );
}

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({required this.user, required this.sections, required this.current, this.onNavigate});
  final AppUser user;
  final List<PortalSection> sections;
  final PortalSection? current;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final provider = state.providerById(user.providerId);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 16, 18),
          child: InkWell(onTap: () => context.go('/'), child: const Align(alignment: Alignment.centerLeft, child: BrandLockup(height: 30, onDark: true))),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(children: [
            Avatar(initials: user.initials, size: 38, color: AppColors.leaf, textColor: AppColors.forestDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.fullName, style: text.titleSmall?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(provider?.name ?? user.organisation ?? user.role.label, style: text.bodySmall?.copyWith(color: AppColors.onForestMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final s in sections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: s == current ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () {
                        onNavigate?.call();
                        context.go(s.path);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        child: Row(children: [
                          Icon(s.icon, size: 20, color: s == current ? AppColors.leaf : AppColors.onForestMuted),
                          const SizedBox(width: 12),
                          Expanded(child: Text(s.label, style: TextStyle(color: s == current ? Colors.white : const Color(0xFFD5E6DC), fontWeight: s == current ? FontWeight.w700 : FontWeight.w500, fontSize: 15))),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
          child: Row(children: [
            const DemoBadge(onDark: true),
            const Spacer(),
            IconButton(
              tooltip: 'Sign out',
              color: Colors.white,
              onPressed: () async {
                await context.read<AppState>().signOut();
                if (context.mounted) context.go('/');
              },
              icon: const Icon(Icons.logout_rounded),
            ),
          ]),
        ),
      ]),
    );
  }
}
