import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/brand.dart';
import '../../shared/ui.dart';

/// Rider navigation: bottom bar on phones, a side rail on wide screens.
class RiderShell extends StatelessWidget {
  const RiderShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.alt_route_outlined, Icons.alt_route_rounded, 'Routes'),
    (Icons.confirmation_number_outlined, Icons.confirmation_number_rounded, 'My Trips'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    if (isWide(context, 900)) {
      return Scaffold(
        body: Row(children: [
          Container(
            width: 232,
            decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.line))),
            child: SafeArea(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 16, 28),
                  child: InkWell(onTap: () => context.go('/'), child: const Align(alignment: Alignment.centerLeft, child: BrandLockup(height: 30))),
                ),
                for (var i = 0; i < _destinations.length; i++)
                  _RailItem(
                    icon: shell.currentIndex == i ? _destinations[i].$2 : _destinations[i].$1,
                    label: _destinations[i].$3,
                    selected: shell.currentIndex == i,
                    onTap: () => _go(i),
                  ),
                const Spacer(),
                const Padding(padding: EdgeInsets.all(20), child: Align(alignment: Alignment.centerLeft, child: DemoBadge())),
              ]),
            ),
          ),
          Expanded(child: shell),
        ]),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? AppColors.mint : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Icon(icon, color: selected ? AppColors.forest : AppColors.muted),
              const SizedBox(width: 14),
              Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? AppColors.forest : AppColors.inkSoft, fontSize: 15)),
            ]),
          ),
        ),
      ),
    );
  }
}
