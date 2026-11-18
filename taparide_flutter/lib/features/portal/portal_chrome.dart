import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../shared/brand.dart';
import '../../shared/ui.dart';
import 'portal_shell.dart';

/// Sidebar groups. Sections not listed here (new ones) fall under "More".
const _groups = <(String, Set<String>)>[
  ('Overview', {'/portal/overview', '/portal/fcta', '/portal/operator', '/portal/fleet', '/portal/insights'}),
  ('Operations', {'/portal/routes', '/portal/vehicles', '/portal/bookings', '/portal/evs', '/portal/events'}),
  ('Oversight', {'/portal/providers', '/portal/verification', '/portal/applications', '/portal/audit'}),
  ('Admin', {'/portal/users', '/portal/waitlist'}),
];

/// The group a section sits in (for the sidebar and the breadcrumb).
String portalGroupOf(PortalSection s) => _groups.where((g) => g.$2.contains(s.path)).firstOrNull?.$1 ?? 'More';

/// Sections grouped in sidebar order, keeping each role's own order inside a group.
List<(String, List<PortalSection>)> groupSections(List<PortalSection> sections) {
  final names = [for (final g in _groups) g.$1, 'More'];
  return [
    for (final name in names)
      if (sections.any((s) => portalGroupOf(s) == name)) (name, [for (final s in sections) if (portalGroupOf(s) == name) s]),
  ];
}

Future<void> _signOut(BuildContext context) async {
  await context.read<AppState>().signOut();
  if (context.mounted) context.go('/');
}

String _orgLine(AppState state, AppUser user) => state.providerById(user.providerId)?.name ?? user.organisation ?? user.role.label;

// ------------------------------------------------------------------ desktop sidebar

class PortalSidebar extends StatelessWidget {
  const PortalSidebar({super.key, required this.user, required this.sections, required this.current, this.onNavigate, this.width = 252});
  final AppUser user;
  final List<PortalSection> sections;
  final PortalSection? current;
  final VoidCallback? onNavigate;
  final double width;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Container(
      width: width,
      color: AppColors.forestDeep,
      child: SafeArea(
        right: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(onTap: () => context.go('/'), borderRadius: BorderRadius.circular(8), child: const BrandLockup(height: 28, onDark: true)),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
            child: Row(children: [
              Avatar(initials: user.initials, size: 34, color: AppLime.lime, textColor: AppColors.forestDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_orgLine(state, user), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(user.role.label, style: const TextStyle(color: AppColors.onForestMuted, fontSize: 12.5, height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              children: [
                for (final (name, items) in groupSections(sections)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                    child: Text(name.toUpperCase(), style: TextStyle(color: AppColors.onForestMuted.withValues(alpha: 0.75), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.9)),
                  ),
                  for (final s in items) _NavItem(section: s, selected: s == current, onNavigate: onNavigate),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
            child: Row(children: [
              const DemoBadge(onDark: true),
              const Spacer(),
              IconButton(tooltip: 'Sign out', color: AppColors.onForestMuted, onPressed: () => _signOut(context), icon: const Icon(Icons.logout_rounded, size: 20)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, this.onNavigate});
  final PortalSection section;
  final bool selected;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            hoverColor: Colors.white.withValues(alpha: 0.05),
            onTap: () {
              onNavigate?.call();
              context.go(section.path);
            },
            child: SizedBox(
              height: 40,
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: 3,
                  height: selected ? 20 : 0,
                  decoration: BoxDecoration(color: AppLime.lime, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 9),
                Icon(section.icon, size: 19, color: selected ? AppLime.lime : AppColors.onForestMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: selected ? Colors.white : const Color(0xFFD5E6DC), fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 14.5),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ desktop top bar

class PortalTopBar extends StatelessWidget {
  const PortalTopBar({super.key, required this.user, required this.current});
  final AppUser user;
  final PortalSection? current;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final loading = state.dataState == LoadState.loading;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(children: [
        if (current != null) ...[
          Text(portalGroupOf(current!), style: text.bodyMedium?.copyWith(color: AppColors.muted)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint)),
          Flexible(child: Text(current!.label, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ] else
          const Spacer(),
        const Spacer(),
        const DemoBadge(),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Refresh data',
          onPressed: loading ? null : state.refresh,
          icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, size: 20),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Account',
          position: PopupMenuPosition.under,
          onSelected: (v) {
            if (v == 'out') _signOut(context);
            if (v == 'home') context.go('/');
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              enabled: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.fullName, style: text.titleSmall),
                Text(user.email, style: text.bodySmall),
              ]),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'home', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.home_outlined), title: Text('Tap A Ride home'))),
            const PopupMenuItem(value: 'out', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout_rounded), title: Text('Sign out'))),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Avatar(initials: user.initials, size: 32),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(user.fullName, style: text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.muted),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ phone navigation

/// Everything that does not fit in the bottom bar, grouped like the desktop sidebar.
Future<void> showPortalMenu(BuildContext context, {required AppUser user, required List<PortalSection> sections, required PortalSection? current}) {
  final state = context.read<AppState>();
  final text = Theme.of(context).textTheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.86),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(children: [
                Avatar(initials: user.initials, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.fullName, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${_orgLine(state, user)} · ${user.role.label}', style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const DemoBadge(),
              ]),
            ),
            for (final (name, items) in groupSections(sections)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                child: Text(name.toUpperCase(), style: text.labelSmall?.copyWith(letterSpacing: 0.9)),
              ),
              for (final s in items)
                ListTile(
                  leading: Icon(s.icon, color: s == current ? AppColors.forest : AppColors.muted),
                  title: Text(s.label, style: text.titleSmall?.copyWith(color: s == current ? AppColors.forest : AppColors.ink, fontWeight: s == current ? FontWeight.w700 : FontWeight.w600)),
                  selected: s == current,
                  selectedTileColor: AppColors.mint,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  trailing: s == current ? const Icon(Icons.check_rounded, color: AppColors.forest, size: 20) : null,
                  onTap: () {
                    Navigator.pop(sheet);
                    context.go(s.path);
                  },
                ),
            ],
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              onTap: () {
                Navigator.pop(sheet);
                _signOut(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}
