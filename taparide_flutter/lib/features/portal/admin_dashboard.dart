import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/demo_backend.dart';
import '../../core/backend/demo_seed.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/partner_models.dart';
import '../../shared/download/download.dart';
import '../../shared/ui.dart';
import 'dashboard_pages.dart' show AuditTile;
import 'insights_page.dart' show DemandPanel, HourBars;
import 'partner_widgets.dart';
import 'portal_widgets.dart';

/// Categorical chart colours, always used in this order (validated for colour-blind separation).
const chartColors = [Color(0xFF1F8A55), Color(0xFF2D6CC4), Color(0xFFC9822B), Color(0xFF8E5BB5), Color(0xFF5FB83A)];

/// The platform admin's control centre: every figure across the platform, system health,
/// and one tap into any partner's own dashboard.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final a = state.adminAnalytics();
    final fcta = state.fctaDashboard();

    return PortalScaffold(
      title: 'Master control centre',
      subtitle: 'Signed in as ${state.user?.fullName ?? ''} · the whole of Tap A Ride · ${Fmt.date(state.now)}',
      leading: const IconBadge(Icons.admin_panel_settings_rounded, size: 52, color: AppColors.forest, iconColor: Colors.white, radius: 26),
      actions: [
        if (state.backend is DemoBackend)
          TextButton.icon(
            onPressed: () => _resetDemo(context),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reset demo data'),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await downloadCsv('taparide-platform-report.csv', a.toCsvRows(state.now));
            if (context.mounted) showMessage(context, ok ? 'Platform report downloaded' : 'Download is available in the web app.', error: !ok);
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Platform report'),
        ),
      ],
      children: [
        _SystemStrip(services: state.services, demo: state.backend.isDemo),
        const SizedBox(height: 16),
        Cols(min: 200, max: 4, children: [
          FigureCard(label: 'Fares this month', value: Fmt.naira(a.faresThisMonth), icon: Icons.payments_rounded, caption: '${Fmt.naira(a.faresToday)} paid today'),
          FigureCard(label: 'Rides this month', value: Fmt.count(a.ridesThisMonth), icon: Icons.route_rounded, caption: '${a.bookingsToday} bookings today', onTap: () => context.go('/portal/bookings')),
          FigureCard(label: 'Users', value: Fmt.count(a.totalUsers), icon: Icons.people_alt_rounded, caption: '${a.usersByRole[UserRole.passenger] ?? 0} riders · ${a.totalUsers - (a.usersByRole[UserRole.passenger] ?? 0)} partner staff', onTap: () => context.go('/portal/users')),
          FigureCard(label: 'Verified vehicles', value: Fmt.count(fcta?.verifiedVehicles ?? a.verifiedVehicles), delta: fcta?.verifiedDelta, icon: Icons.verified_rounded, caption: '${a.pendingVehicles} awaiting checks', onTap: () => context.go('/portal/vehicles')),
        ]),
        const SizedBox(height: 18),
        _Two(
          left: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Ridership', subtitle: 'Trips per day, last 7 days, all operators', trailing: fcta == null ? null : StatusPill('${fcta.ridershipDelta >= 0 ? '+' : ''}${fcta.ridershipDelta}% vs last week', tone: Tone.success)),
            if (fcta != null) WeekBars(values: fcta.ridershipByDay, labels: fcta.dayLabels, highlightIndex: fcta.todayIndex),
          ])),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PanelTitle('Fares by mode', subtitle: 'This month'),
            _DonutWithLegend(items: a.revenueByMode, centerLabel: 'this month', money: true),
          ])),
        ),
        const SizedBox(height: 18),
        _Two(
          left: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Revenue by operator', subtitle: 'Fares this month · tap to open their dashboard', trailing: TextButton(onPressed: () => context.go('/portal/providers'), child: const Text('Providers'))),
            _HBars(
              rows: [
                for (final r in a.byOperator.take(8))
                  _BarRow(label: r.provider.name, value: r.monthlyRevenue, valueText: Fmt.nairaShort(r.monthlyRevenue), detail: '${r.routes} routes · ${r.vehicles} vehicles · ${r.bookingsToday} bookings today', onTap: () => context.go(_dashboardFor(r.provider))),
              ],
            ),
          ])),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PanelTitle('When people ride', subtitle: 'Bookings by departure hour'),
            HourBars(values: a.platform.bookingsByHour),
            const SizedBox(height: 18),
            Text('How riders pay', style: text.titleSmall),
            const SizedBox(height: 8),
            _ShareWithLegend(items: [
              ('Tap card', a.payments[PaymentMethod.tapCard] ?? 0),
              ('QR code', a.payments[PaymentMethod.qr] ?? 0),
              ('Tag Along cost share', a.payments[PaymentMethod.splitCost] ?? 0),
            ], unit: 'bookings'),
          ])),
        ),
        const SizedBox(height: 18),
        _Two(
          left: LiveFleetMap(vehicles: state.vehicles, routes: state.routes, height: 360),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Fleet health', subtitle: '${a.vehicles} vehicles · ${(a.platform.utilisation * 100).round()}% working'),
            ShareBar(parts: [for (final s in VehicleStatus.values) (a.vehiclesByStatus[s] ?? 0, statusColor(s))], height: 12),
            const SizedBox(height: 10),
            for (final s in VehicleStatus.values)
              if ((a.vehiclesByStatus[s] ?? 0) > 0) LegendRow(color: statusColor(s), label: s.label, value: '${a.vehiclesByStatus[s]}'),
            const Divider(height: 28),
            _Metric(icon: Icons.electric_car_rounded, label: 'Electric share of the fleet', value: '${(a.electricShare * 100).round()}% · ${a.electricVehicles} EVs'),
            _Metric(icon: Icons.battery_alert_rounded, label: 'Below 30% battery', value: '${a.lowBatteryEvs}', onTap: () => context.go('/portal/evs')),
            _Metric(icon: Icons.alt_route_rounded, label: 'Active routes', value: '${a.activeRoutes} · ${Fmt.count(a.departuresPerDay)} departures a day', onTap: () => context.go('/portal/routes')),
            _Metric(icon: Icons.build_circle_rounded, label: 'Idle-vehicle cost', value: '${Fmt.naira(a.platform.idleCostPerMonth)} a month'),
          ])),
        ),
        const SizedBox(height: 18),
        _Two(
          left: DemandPanel(report: a.platform),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Partner pipeline', subtitle: '${a.openApplications} waiting for review', trailing: TextButton(onPressed: () => context.go('/portal/applications'), child: const Text('Review'))),
            _HBars(rows: [
              for (final s in [ApplicationStatus.submitted, ApplicationStatus.underReview, ApplicationStatus.needsChanges, ApplicationStatus.approved, ApplicationStatus.rejected])
                _BarRow(label: s.label, value: a.applicationsByStatus[s] ?? 0, valueText: '${a.applicationsByStatus[s] ?? 0}', onTap: () => context.go('/portal/applications')),
            ]),
            const Divider(height: 28),
            Text('Providers on the FCTA register', style: text.titleSmall),
            const SizedBox(height: 8),
            _ShareWithLegend(items: [
              ('Verified', a.providersByStatus[Verification.verified] ?? 0),
              ('Pending', a.providersByStatus[Verification.pending] ?? 0),
              ('Suspended', a.providersByStatus[Verification.suspended] ?? 0),
            ], unit: 'providers'),
          ])),
        ),
        const SizedBox(height: 18),
        _Two(
          left: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Users by role', subtitle: '${a.totalUsers} accounts', trailing: TextButton(onPressed: () => context.go('/portal/users'), child: const Text('Manage'))),
            _HBars(rows: [
              for (final r in UserRole.values) _BarRow(label: r.label, value: a.usersByRole[r] ?? 0, valueText: '${a.usersByRole[r] ?? 0}', onTap: () => context.go('/portal/users')),
            ]),
          ])),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Recent activity', trailing: TextButton(onPressed: () => context.go('/portal/audit'), child: const Text('Audit log'))),
            for (final e in state.audit.take(6)) AuditTile(entry: e),
            if (state.audit.isEmpty) Text('No changes recorded yet.', style: text.bodyMedium),
          ])),
        ),
        const SizedBox(height: 18),
        _SecurityPanel(users: state.users, demo: state.backend.isDemo),
        const SizedBox(height: 22),
        Text('Open any dashboard', style: text.titleLarge),
        const SizedBox(height: 4),
        Text('See exactly what each partner and the FCTA see.', style: text.bodyMedium),
        const SizedBox(height: 12),
        Cols(min: 300, max: 3, children: [
          _DashCard(icon: Icons.account_balance_rounded, title: 'FCTA dashboard', subtitle: 'Ridership, register, safety', onOpen: () => context.go('/portal/fcta'), onInsights: () => context.go('/portal/insights')),
          for (final p in state.providers)
            _DashCard(
              icon: p.kind.icon,
              title: p.name,
              subtitle: '${p.kind.label} · ${p.status.label}',
              onOpen: () => context.go(_dashboardFor(p)),
              onInsights: () => context.go('/portal/insights?provider=${p.id}'),
            ),
        ]),
      ],
    );
  }

  static Future<void> _resetDemo(BuildContext context) async {
    final state = context.read<AppState>();
    final backend = state.backend;
    if (backend is! DemoBackend) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text('Every booking, approval and change made in this browser is cleared and the original demo data comes back. Do this before a demo so testers start fresh. You will be signed out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await backend.reset();
    await state.signOut();
    if (context.mounted) context.go('/');
  }

  static String _dashboardFor(TransportProvider p) => p.kind == ProviderKind.fleetOwner ? '/portal/fleet?provider=${p.id}' : '/portal/operator?provider=${p.id}';
}

class _Two extends StatelessWidget {
  const _Two({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 980
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: left), const SizedBox(width: 18), Expanded(flex: 2, child: right)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 18), right]),
      );
}

/// Backend, AI, maps and place search: what is live right now.
class _SystemStrip extends StatelessWidget {
  const _SystemStrip({required this.services, required this.demo});
  final Map<String, dynamic> services;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final ai = services['ai'] as String?;
    final tiles = services['tiles'] as String?;
    final items = [
      (Icons.storage_rounded, 'Data', demo ? 'Demo data on this device' : 'Live Supabase', demo ? Tone.warning : Tone.success),
      (Icons.auto_awesome_rounded, 'AI', ai == null ? (services.isEmpty ? 'Checking…' : 'Offline answers (add GEMINI_API_KEY)') : 'Live · ${ai[0].toUpperCase()}${ai.substring(1)}', ai == null ? Tone.warning : Tone.success),
      (Icons.map_rounded, 'Maps', tiles == null ? 'Checking…' : (tiles == 'carto' ? 'CARTO basemaps' : 'OpenStreetMap (add CARTO_API_KEY)'), tiles == 'carto' ? Tone.success : Tone.info),
      (Icons.alt_route_rounded, 'Routing', 'FindMe AI road routes', Tone.success),
    ];
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(spacing: 22, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('System', style: text.titleSmall),
        for (final (icon, label, status, tone) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 6),
            Text('$label ', style: text.labelLarge),
            StatusPill(status, tone: tone),
          ]),
      ]),
    );
  }
}

/// Who can see what: every staff account and its role, with where the data lives.
class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({required this.users, required this.demo});
  final List<AppUser> users;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final staff = [for (final u in users) if (u.role != UserRole.passenger) u]..sort((a, b) => b.role.index.compareTo(a.role.index));
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle('Security & access', subtitle: '${staff.length} staff accounts · only admins see this page', trailing: TextButton(onPressed: () => context.go('/portal/users'), child: const Text('Change roles'))),
        for (final u in staff)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Avatar(initials: u.fullName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join(), size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text('${u.fullName} · ${u.email}', style: text.bodyMedium, overflow: TextOverflow.ellipsis)),
              StatusPill(u.role == UserRole.admin ? (u.email == DemoSeed.demoAdminEmail ? 'Demo admin' : 'Master admin') : u.role.label, tone: u.role == UserRole.admin ? Tone.danger : (u.role == UserRole.government ? Tone.info : Tone.neutral)),
            ]),
          ),
        const Divider(height: 24),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(demo ? Icons.info_outline_rounded : Icons.lock_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              demo
                  ? 'Demo mode: data lives in each visitor\'s browser. The master admin sign-in is private (only a hash ships in the app) and is not listed on the login page. Connect Supabase for shared, server-enforced data.'
                  : 'Live mode: roles are enforced by the database (row-level security). Only accounts promoted to admin can open this page.',
              style: text.bodySmall,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.forest),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(value, style: text.titleSmall),
        ]),
      ),
    );
  }
}

class _BarRow {
  const _BarRow({required this.label, required this.value, required this.valueText, this.detail, this.onTap});
  final String label;
  final int value;
  final String valueText;
  final String? detail;
  final VoidCallback? onTap;
}

/// Single-series horizontal bars: label above, value at the end, details in a tooltip.
class _HBars extends StatelessWidget {
  const _HBars({required this.rows});
  final List<_BarRow> rows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final top = rows.isEmpty ? 1 : math.max(1, rows.map((r) => r.value).reduce(math.max));
    if (rows.isEmpty) return Text('Nothing to show yet.', style: text.bodyMedium);
    return Column(children: [
      for (final r in rows)
        Tooltip(
          message: r.detail == null ? '${r.label}: ${r.valueText}' : '${r.label}: ${r.valueText}\n${r.detail}',
          child: InkWell(
            onTap: r.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 170, child: Text(r.label, style: text.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 10),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final w = c.maxWidth * (r.value / top);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: math.max(r.value > 0 ? 4 : 0, w),
                        height: 14,
                        decoration: const BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.horizontal(right: Radius.circular(4))),
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 74, child: Text(r.valueText, style: text.titleSmall, textAlign: TextAlign.right)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Part-of-whole bar with a legend that names each part, its count and share.
class _ShareWithLegend extends StatelessWidget {
  const _ShareWithLegend({required this.items, required this.unit});
  final List<(String, int)> items;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (s, i) => s + i.$2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ShareBar(parts: [for (final (i, it) in items.indexed) (it.$2, chartColors[i])], height: 12),
      const SizedBox(height: 8),
      for (final (i, it) in items.indexed)
        LegendRow(color: chartColors[i], label: it.$1, value: '${it.$2} ${total == 0 ? '' : '· ${(it.$2 * 100 / total).round()}%'}'),
      if (total == 0) Text('No $unit yet.', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

/// Donut for a few categories (fixed colour order) with a labelled legend; the total sits in the middle.
class _DonutWithLegend extends StatelessWidget {
  const _DonutWithLegend({required this.items, required this.centerLabel, this.money = false});
  final List<(String, int)> items;
  final String centerLabel;
  final bool money;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = items.fold<int>(0, (s, i) => s + i.$2);
    final legend = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, it) in items.indexed)
        Tooltip(
          message: '${it.$1}: ${money ? Fmt.naira(it.$2) : it.$2}',
          child: LegendRow(color: chartColors[i], label: it.$1, value: '${money ? Fmt.nairaShort(it.$2) : it.$2} · ${total == 0 ? 0 : (it.$2 * 100 / total).round()}%'),
        ),
    ]);
    final donut = SizedBox(
      width: 180,
      height: 180,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: const Size(180, 180), painter: _DonutPainter([for (final it in items) it.$2], chartColors)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(money ? Fmt.nairaShort(total) : '$total', style: text.headlineSmall),
          Text(centerLabel, style: text.bodySmall),
        ]),
      ]),
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 420
          ? Row(children: [donut, const SizedBox(width: 22), Expanded(child: legend)])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: donut), const SizedBox(height: 14), legend]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.colors);
  final List<int> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (a, b) => a + b);
    final rect = Offset.zero & size;
    const stroke = 26.0;
    final arcRect = rect.deflate(stroke / 2);
    if (total == 0) {
      canvas.drawArc(arcRect, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = AppColors.mint);
      return;
    }
    // 2px surface gap between segments.
    final gap = 2 / (arcRect.width / 2);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep <= 0) continue;
      canvas.drawArc(arcRect, start + gap / 2, math.max(0.001, sweep - gap), false, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = colors[i % colors.length]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values != values;
}

class _DashCard extends StatelessWidget {
  const _DashCard({required this.icon, required this.title, required this.subtitle, required this.onOpen, required this.onInsights});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onOpen;
  final VoidCallback onInsights;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        IconBadge(icon, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(subtitle, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(tooltip: 'AI insights', onPressed: onInsights, icon: const Icon(Icons.insights_rounded, color: AppColors.forest)),
        FilledButton(onPressed: onOpen, style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)), child: const Text('Open')),
      ]),
    );
  }
}
