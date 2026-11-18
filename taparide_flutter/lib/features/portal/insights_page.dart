import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/mascot/mascot.dart';
import '../../shared/route_map.dart';
import '../../shared/ui.dart';
import 'demand_widgets.dart';
import 'portal_widgets.dart';

/// AI Insights: income, fleet health, demand hot-spots, live traffic and an AI analyst, per organisation.
/// Admins and the FCTA can open any organisation's view (or the whole platform) to test it.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key, this.providerId});
  final String? providerId;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

/// AI readings survive switching scopes and pages for this session (each costs an AI call).
final _aiCache = <String, AiInsights>{};
final _trafficCache = <String, List<TrafficCheck>>{};

class _InsightsPageState extends State<InsightsPage> {
  static const _all = '';
  String? _picked;
  bool _thinking = false;
  String? _aiError;
  bool _loadingTraffic = false;

  String? _scopeId(AppState state) {
    final user = state.user!;
    if (user.role == UserRole.admin || user.role == UserRole.government) {
      final pick = _picked ?? widget.providerId ?? _all;
      return pick == _all ? null : pick;
    }
    return user.providerId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTraffic());
  }

  Future<void> _runAi(InsightsReport report, String key) async {
    setState(() {
      _thinking = true;
      _aiError = null;
    });
    try {
      final result = await context.read<AppState>().api.insights(report.toAiJson());
      _aiCache[key] = result;
    } on BackendException catch (e) {
      _aiError = e.message;
    } catch (_) {
      _aiError = 'The AI analyst is unavailable right now. The figures below are still live.';
    }
    if (mounted) setState(() => _thinking = false);
  }

  Future<void> _loadTraffic() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.user == null) return;
    final key = _scopeId(state) ?? _all;
    if (_trafficCache.containsKey(key)) return;
    final report = state.insightsFor(_scopeId(state));
    final routes = [for (final r in report.routeIncome.take(5)) r.route];
    if (routes.isEmpty) return;
    setState(() => _loadingTraffic = true);
    final checks = <TrafficCheck>[];
    await Future.wait([
      for (final r in routes)
        if (r.stops.length >= 2)
          state.api.roadRoute(LatLng(r.stops.first.lat, r.stops.first.lng), LatLng(r.stops.last.lat, r.stops.last.lng)).then((plan) {
            if (plan == null) return;
            checks.add(TrafficCheck(
              route: r,
              scheduledMin: r.durationMin,
              liveMin: ((plan.trafficDurationS ?? plan.durationS) / 60).round(),
              distanceKm: plan.distanceM / 1000,
              label: plan.label,
            ));
          }),
    ]);
    checks.sort((a, b) => b.delayMin.compareTo(a.delayMin));
    _trafficCache[key] = checks;
    if (mounted) setState(() => _loadingTraffic = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final text = Theme.of(context).textTheme;
    final canPick = user.role == UserRole.admin || user.role == UserRole.government;
    final scope = _scopeId(state);
    if (!canPick && scope == null) {
      return const PortalScaffold(title: 'AI insights', children: [EmptyState(icon: Icons.insights_rounded, title: 'No organisation linked', message: 'Ask a platform admin to link your account to your company.')]);
    }
    final key = scope ?? _all;
    final report = state.insightsFor(scope);
    final ai = _aiCache[key];
    final traffic = _trafficCache[key];
    final orgs = [
      for (final p in state.providers)
        if (state.routes.any((r) => r.providerId == p.id) || state.vehicles.any((v) => v.operatorId == p.id || v.ownerId == p.id)) p,
    ];

    return PortalScaffold(
      title: 'AI insights',
      subtitle: '${report.scopeName} · live from Tap A Ride data',
      icon: Icons.insights_rounded,
      actions: [
        if (canPick)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: DropdownButtonFormField<String>(
              initialValue: key,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'View as', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              items: [
                const DropdownMenuItem(value: _all, child: Text('Whole platform (FCTA)')),
                for (final p in orgs) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                setState(() {
                  _picked = v;
                  _aiError = null;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) => _loadTraffic());
              },
            ),
          ),
      ],
      children: [
        _AnalystPanel(ai: ai, thinking: _thinking, error: _aiError, onRun: () => _runAi(report, key)),
        const SizedBox(height: PortalSpace.gap),
        Cols(min: 200, max: 5, children: [
          FigureCard(label: 'Revenue this month', value: Fmt.naira(report.monthlyRevenue), icon: Icons.payments_rounded, caption: 'Projected next month ${Fmt.nairaShort(report.projectedNextMonth)}'),
          FigureCard(label: 'Revenue today', value: Fmt.naira(report.revenueToday), icon: Icons.today_rounded, caption: '${report.bookingsToday} bookings so far'),
          FigureCard(label: 'Fleet working', value: '${(report.utilisation * 100).round()}%', icon: Icons.directions_bus_rounded, caption: '${report.vehicles.length} vehicles'),
          FigureCard(label: 'Idle cost / month', value: Fmt.naira(report.idleCostPerMonth), icon: Icons.build_circle_rounded, caption: '${report.idleVehicles.length} off the road'),
          FigureCard(label: 'Routes', value: '${report.routes.length}', icon: Icons.alt_route_rounded, caption: '${report.routes.fold<int>(0, (s, r) => s + r.departures.length)} departures a day'),
        ]),
        DemandSection(report: report.demand, title: 'Demand by corridor and hour'),
        const SectionLabel('Income and fleet'),
        TwoUp(
          leftFlex: 1,
          rightFlex: 1,
          left: _IncomePanel(report: report),
          right: _FleetPanel(report: report),
        ),
        const SectionLabel('Places, traffic and opportunities'),
        TwoUp(
          leftFlex: 1,
          rightFlex: 1,
          left: DemandPanel(report: report),
          right: _TrafficPanel(checks: traffic, loading: _loadingTraffic, onRetry: () {
            _trafficCache.remove(key);
            _loadTraffic();
          }),
        ),
        const SizedBox(height: PortalSpace.gap),
        DashPanel(
          title: 'Opportunities',
          subtitle: 'Worked out from your routes, fleet and demand',
          children: [
            if (report.opportunities.isEmpty) Text('No gaps found. Your routes cover the busiest areas and your fleet is on the road.', style: text.bodyMedium),
            for (final o in report.opportunities)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const IconBadge(Icons.lightbulb_rounded, size: 34, radius: 10, color: AppColors.amberSoft, iconColor: AppColors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.title, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Text(o.detail, style: text.bodySmall),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      ],
    );
  }
}

class _AnalystPanel extends StatelessWidget {
  const _AnalystPanel({required this.ai, required this.thinking, required this.error, required this.onRun});
  final AiInsights? ai;
  final bool thinking;
  final String? error;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mood = thinking ? MascotMood.think : (ai != null ? MascotMood.celebrate : MascotMood.wave);
    final onDark = text.bodyMedium?.copyWith(color: AppColors.onForestMuted);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0E6B45), AppColors.forestDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 760;
        final intro = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AI ANALYST', style: text.labelMedium?.copyWith(color: AppLime.lime, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            ai?.headline ?? (thinking ? 'Reading your routes, fleet, demand and traffic…' : 'Get a plain-English reading of these numbers and what to do next.'),
            style: text.headlineSmall?.copyWith(color: Colors.white),
          ),
          if (error != null) ...[const SizedBox(height: 8), Text(error!, style: onDark?.copyWith(color: const Color(0xFFFFD7A8)))],
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppLime.lime, foregroundColor: AppLime.onLime),
            onPressed: thinking ? null : onRun,
            icon: thinking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(ai == null ? Icons.auto_awesome_rounded : Icons.refresh_rounded, size: 18),
            label: Text(thinking ? 'Analysing…' : (ai == null ? 'Analyse with AI' : 'Analyse again')),
          ),
          if (ai != null && ai!.model.isNotEmpty) ...[const SizedBox(height: 8), Text('Model: ${ai!.model} · the AI only interprets live figures', style: text.labelSmall?.copyWith(color: AppColors.onForestMuted))],
        ]);
        final results = ai == null
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final f in ai!.findings)
                    _GlassCard(width: wide ? (c.maxWidth - 20) / 3 - 1 : c.maxWidth, icon: _kindIcon(f.kind), title: f.title, body: f.detail),
                ]),
                const SizedBox(height: 16),
                Text('Do next', style: text.titleMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                for (final (i, a) in ai!.actions.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppLime.lime, shape: BoxShape.circle),
                        child: Text('${i + 1}', style: text.labelLarge?.copyWith(color: AppLime.onLime)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(a.title, style: text.titleSmall?.copyWith(color: Colors.white))),
                            const SizedBox(width: 8),
                            _ImpactTag(a.impact),
                          ]),
                          Text(a.why, style: onDark),
                        ]),
                      ),
                    ]),
                  ),
              ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          wide
              ? Row(children: [Expanded(child: intro), const SizedBox(width: 12), Mascot(mood: mood, size: 150)])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: intro), Mascot(mood: mood, size: 90)]),
          if (results != null) results,
        ]);
      }),
    );
  }

  static IconData _kindIcon(String kind) => switch (kind) {
        'fleet' => Icons.directions_bus_rounded,
        'demand' => Icons.groups_rounded,
        'traffic' => Icons.traffic_rounded,
        'routing' => Icons.alt_route_rounded,
        'safety' => Icons.health_and_safety_rounded,
        _ => Icons.payments_rounded,
      };
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.width, required this.icon, required this.title, required this.body});
  final double width;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppLime.lime, size: 20),
        const SizedBox(height: 6),
        Text(title, style: text.titleSmall?.copyWith(color: Colors.white)),
        const SizedBox(height: 2),
        Text(body, style: text.bodySmall?.copyWith(color: AppColors.onForestMuted)),
      ]),
    );
  }
}

class _ImpactTag extends StatelessWidget {
  const _ImpactTag(this.impact);
  final String impact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (impact) {
      'high' => (AppLime.lime, AppLime.onLime),
      'low' => (Colors.white24, Colors.white),
      _ => (Colors.white, AppColors.forest),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('$impact impact', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _IncomePanel extends StatelessWidget {
  const _IncomePanel({required this.report});
  final InsightsReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = report.routeIncome.take(6).toList();
    final top = rows.isEmpty ? 1 : math.max(1, rows.first.monthlyRevenue);
    return Panel(
      radius: AppRadius.md,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const PanelTitle('Income by route', subtitle: 'Trips in the last 30 days × fare'),
        if (rows.isEmpty) Text('No routes yet. Fleet income shows on the right.', style: text.bodyMedium),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(r.route.title, style: text.titleSmall, overflow: TextOverflow.ellipsis)),
                Text(Fmt.naira(r.monthlyRevenue), style: text.titleSmall),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: r.monthlyRevenue / top, minHeight: 8, backgroundColor: AppColors.mint, color: AppColors.forest),
              ),
              const SizedBox(height: 3),
              Text('${Fmt.count(r.route.monthlyTrips)} trips · ${Fmt.naira(r.route.fare)} fare · ~${r.tripsPerDeparture.round()} riders per departure', style: text.bodySmall),
            ]),
          ),
      ]),
    );
  }
}

class _FleetPanel extends StatelessWidget {
  const _FleetPanel({required this.report});
  final InsightsReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    int count(VehicleStatus s) => report.vehicles.where((v) => v.status == s).length;
    final parts = [
      (VehicleStatus.active, AppColors.forest),
      (VehicleStatus.onTrip, AppColors.leaf),
      (VehicleStatus.charging, AppColors.blue),
      (VehicleStatus.maintenance, const Color(0xFFE0A030)),
      (VehicleStatus.inactive, AppColors.red),
    ];
    return Panel(
      radius: AppRadius.md,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle('Vehicle status', subtitle: '${report.vehicles.length} vehicles · ${(report.utilisation * 100).round()}% working'),
        ShareBar(parts: [for (final p in parts) (count(p.$1), p.$2)], height: 12),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final p in parts)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: p.$2, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('${p.$1.label} ${count(p.$1)}', style: text.bodySmall),
            ]),
        ]),
        const SizedBox(height: 16),
        Text('Top earners this month', style: text.titleSmall),
        const SizedBox(height: 4),
        if (report.topEarners.isEmpty) Text('Earnings appear once vehicles complete trips.', style: text.bodySmall),
        for (final v in report.topEarners) _EarnerRow(vehicle: v, good: true),
        if (report.idleVehicles.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Off the road', style: text.titleSmall),
          const SizedBox(height: 4),
          for (final v in report.idleVehicles.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(v.displayName, style: text.bodyMedium, overflow: TextOverflow.ellipsis)),
                StatusPill(v.status.label, tone: vehicleTone(v.status)),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _EarnerRow extends StatelessWidget {
  const _EarnerRow({required this.vehicle, required this.good});
  final Vehicle vehicle;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(vehicle.electric ? Icons.electric_car_rounded : Icons.directions_bus_rounded, size: 18, color: AppColors.forest),
        const SizedBox(width: 8),
        Expanded(child: Text(vehicle.displayName, style: text.bodyMedium, overflow: TextOverflow.ellipsis)),
        Text(Fmt.naira(vehicle.monthEarnings), style: text.titleSmall?.copyWith(color: good ? AppColors.leafText : AppColors.ink)),
      ]),
    );
  }
}

class DemandPanel extends StatelessWidget {
  const DemandPanel({super.key, required this.report});
  final InsightsReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final areas = report.areas.take(12).toList();
    final peak = areas.isEmpty ? 1 : math.max(1, areas.map((a) => a.trips).reduce(math.max));
    final points = [for (final a in areas) LatLng(a.lat, a.lng)];
    return Panel(
      radius: AppRadius.md,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const PanelTitle('High-demand areas', subtitle: 'Where trips start and end · bigger circle, more riders'),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 280,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(36), maxZoom: 13.5) : null,
                initialCenter: points.isEmpty ? const LatLng(9.0579, 7.4951) : points.first,
                initialZoom: 11.5,
                backgroundColor: const Color(0xFFEAF1EC),
                // The page scrolls with the mouse wheel; the map zooms with pinch or double-click.
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.scrollWheelZoom),
              ),
              children: [
                if (MapTiles.enabled)
                  TileLayer(urlTemplate: MapTiles.urlTemplate, subdomains: MapTiles.subdomains, retinaMode: RetinaMode.isHighDensity(context), userAgentPackageName: 'com.taparide.app'),
                CircleLayer(circles: [
                  for (final a in areas)
                    CircleMarker(
                      point: LatLng(a.lat, a.lng),
                      radius: 8 + 26 * math.sqrt(a.trips / peak),
                      color: (a.bookingsToday > 0 ? AppColors.leaf : AppColors.forest).withValues(alpha: 0.35),
                      borderColor: a.bookingsToday > 0 ? AppColors.leaf : AppColors.forest,
                      borderStrokeWidth: 2,
                    ),
                ]),
                const MapCredit(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final (i, a) in areas.take(5).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${i + 1}', style: text.titleSmall?.copyWith(color: AppColors.faint))),
              Expanded(child: Text(a.name, style: text.bodyMedium)),
              if (a.bookingsToday > 0) ...[StatusPill('${a.bookingsToday} today', tone: Tone.success), const SizedBox(width: 8)],
              Text('${Fmt.count(a.trips)} trips', style: text.titleSmall),
            ]),
          ),
      ]),
    );
  }
}

class _TrafficPanel extends StatelessWidget {
  const _TrafficPanel({required this.checks, required this.loading, required this.onRetry});
  final List<TrafficCheck>? checks;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final list = checks ?? const [];
    final late = list.where((c) => c.delayMin >= 5).toList();
    return Panel(
      radius: AppRadius.md,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle(
          'Traffic & smart routing',
          subtitle: 'Live road time (FindMe AI) vs your timetable',
          trailing: IconButton(tooltip: 'Check traffic again', onPressed: loading ? null : onRetry, icon: const Icon(Icons.refresh_rounded)),
        ),
        if (loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
        else if (list.isEmpty)
          Text('Live traffic is unavailable right now. Tap refresh to try again.', style: text.bodyMedium)
        else ...[
          for (final c in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(
                  c.delayMin >= 10 ? Icons.traffic_rounded : (c.delayMin >= 5 ? Icons.schedule_rounded : Icons.check_circle_rounded),
                  color: c.delayMin >= 10 ? AppColors.red : (c.delayMin >= 5 ? AppColors.amber : AppColors.leafText),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.route.title, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                    Text('${c.distanceKm.toStringAsFixed(1)} km${c.label.isEmpty ? '' : ' via ${c.label}'} · timetable ${c.scheduledMin} min', style: text.bodySmall, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${c.liveMin} min', style: text.titleSmall),
                  Text(c.delayMin > 0 ? '+${c.delayMin} min' : 'on time', style: text.bodySmall?.copyWith(color: c.delayMin >= 5 ? AppColors.red : AppColors.leafText)),
                ]),
              ]),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: late.isEmpty ? AppColors.mint : AppColors.amberSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Text(
              late.isEmpty
                  ? 'Roads match your timetables right now. No changes needed.'
                  : 'Smart routing: ${late.first.route.title} is running ${late.first.delayMin} min over its timetable. Add buffer to departures or reroute around the slow stretch, and riders get leave-early reminders automatically.',
              style: text.bodyMedium?.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ]),
    );
  }
}
