import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../core/app_state.dart';
import '../../core/fleet_positions.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/download/download.dart';
import '../../shared/route_map.dart';
import '../../shared/ui.dart';
import 'portal_widgets.dart';

Color statusColor(VehicleStatus s) => switch (s) {
      VehicleStatus.active => AppColors.forest,
      VehicleStatus.onTrip => AppColors.leaf,
      VehicleStatus.charging => AppColors.blue,
      VehicleStatus.maintenance => const Color(0xFFE0A030),
      VehicleStatus.inactive => AppColors.red,
    };

/// Lets a driver or conductor report a vehicle's GPS from this device, so riders and
/// dashboards see where it really is.
class LiveTrackerPanel extends StatefulWidget {
  const LiveTrackerPanel({super.key, required this.vehicles});
  final List<Vehicle> vehicles;

  @override
  State<LiveTrackerPanel> createState() => _LiveTrackerPanelState();
}

class _LiveTrackerPanelState extends State<LiveTrackerPanel> {
  String? _picked;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final vehicles = widget.vehicles;
    if (vehicles.isEmpty) return const SizedBox.shrink();
    final tracking = vehicles.where((v) => v.id == state.trackingVehicleId).firstOrNull;
    final selected = tracking ?? vehicles.where((v) => v.id == _picked).firstOrNull ?? vehicles.first;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconBadge(tracking == null ? Icons.location_searching_rounded : Icons.my_location_rounded, size: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Live location', style: text.titleMedium),
              Text(
                tracking == null
                    ? 'Share this device\'s GPS as the vehicle\'s position. Riders see it on their ticket.'
                    : 'Sharing ${tracking.displayName} from this device. Keep this page open while driving.',
                style: text.bodySmall,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
          else
            Switch(
              value: tracking != null,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.leaf,
              onChanged: (on) async {
                setState(() => _busy = true);
                if (on) {
                  final ok = await state.startTracking(selected);
                  if (context.mounted) showMessage(context, ok ? 'Sharing live location for ${selected.displayName}' : (state.trackingError ?? 'Could not start sharing.'), error: !ok);
                } else {
                  await state.stopTracking();
                }
                if (mounted) setState(() => _busy = false);
              },
            ),
        ]),
        if (vehicles.length > 1 && tracking == null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selected.id,
            decoration: const InputDecoration(labelText: 'Vehicle on this device'),
            items: [for (final v in vehicles) DropdownMenuItem(value: v.id, child: Text(v.displayName, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _picked = v),
          ),
        ],
        if (tracking != null && state.trackingError != null) ...[
          const SizedBox(height: 8),
          Text(state.trackingError!, style: text.bodySmall?.copyWith(color: AppColors.red)),
        ],
      ]),
    );
  }
}

/// Map of the partner's vehicles and routes. Positions refresh every few seconds.
class LiveFleetMap extends StatefulWidget {
  const LiveFleetMap({super.key, required this.vehicles, required this.routes, this.height = 340});
  final List<Vehicle> vehicles;
  final List<TransitRoute> routes;
  final double height;

  @override
  State<LiveFleetMap> createState() => _LiveFleetMapState();
}

class _LiveFleetMapState extends State<LiveFleetMap> {
  Timer? _tick;
  Vehicle? _selected;

  @override
  void initState() {
    super.initState();
    // Tests and offline builds switch tiles off; skip the ticker there too.
    if (MapTiles.enabled) {
      var ticks = 0;
      _tick = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        // Every 20 seconds, fetch the GPS fixes vehicles have reported.
        if (++ticks % 5 == 0) context.read<AppState>().refreshPositions();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = context.watch<AppState>();
    // Real GPS where a vehicle's driver is reporting; the timetable estimate everywhere else.
    final positions = [
      for (final p in FleetPositions.estimate(vehicles: widget.vehicles, routes: widget.routes, now: state.now))
        state.livePosition(p.vehicle.id) == null ? p : FleetPosition(vehicle: p.vehicle, point: state.livePosition(p.vehicle.id)!.point, route: p.route),
    ];
    final gps = widget.vehicles.where((v) => state.livePosition(v.id) != null).length;
    final points = [for (final p in positions) p.point, for (final r in widget.routes) for (final s in r.stops) LatLng(s.lat, s.lng)];
    final moving = positions.where((p) => p.vehicle.status == VehicleStatus.onTrip || p.route != null).length;
    final sel = _selected == null ? null : positions.where((p) => p.vehicle.id == _selected!.id).firstOrNull;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle(
          'Live fleet',
          subtitle: gps == 0
              ? '$moving of ${widget.vehicles.length} on the road · positions estimated from timetables'
              : '$moving of ${widget.vehicles.length} on the road · $gps reporting live GPS, the rest estimated from timetables',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.leaf, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Live', style: text.labelSmall?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: widget.height,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40), maxZoom: 14) : null,
                initialCenter: points.isEmpty ? const LatLng(9.0579, 7.4951) : points.first,
                initialZoom: 12,
                backgroundColor: const Color(0xFFEAF1EC),
                // The page scrolls with the mouse wheel; the map zooms with pinch or double-click.
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.scrollWheelZoom),
                onTap: (_, __) => setState(() => _selected = null),
              ),
              children: [
                if (MapTiles.enabled)
                  TileLayer(urlTemplate: MapTiles.urlTemplate, subdomains: MapTiles.subdomains, retinaMode: RetinaMode.isHighDensity(context), userAgentPackageName: 'com.taparide.app'),
                PolylineLayer(simplificationTolerance: 0, polylines: [
                  for (final r in widget.routes)
                    Polyline(points: [for (final s in r.stops) LatLng(s.lat, s.lng)], strokeWidth: 4, color: AppColors.forest.withValues(alpha: 0.28)),
                ]),
                MarkerLayer(markers: [
                  for (final p in positions)
                    Marker(
                      point: p.point,
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => setState(() => _selected = p.vehicle),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          decoration: BoxDecoration(
                            color: statusColor(p.vehicle.status),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: _selected?.id == p.vehicle.id ? 3.5 : 2),
                            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
                          ),
                          child: Icon(
                            p.vehicle.kind.isBookableCar ? Icons.directions_car_rounded : (p.vehicle.electric ? Icons.electric_bolt_rounded : Icons.directions_bus_rounded),
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ]),
                if (sel != null)
                  Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 260),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.96), borderRadius: BorderRadius.circular(AppRadius.md), boxShadow: AppShadow.raised),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(sel.vehicle.displayName, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text([sel.vehicle.status.label, if (sel.route != null) sel.route!.title, if (sel.vehicle.driverName != null) sel.vehicle.driverName!, if (sel.vehicle.batteryPct != null) '${sel.vehicle.batteryPct}% battery'].join(' · '), style: text.bodySmall),
                        const SizedBox(height: 4),
                        Text('${Fmt.naira(sel.vehicle.monthEarnings)} this month', style: text.labelLarge?.copyWith(color: AppColors.forest)),
                      ]),
                    ),
                  ),
                const MapCredit(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final s in VehicleStatus.values)
            if (widget.vehicles.any((v) => v.status == s))
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: statusColor(s), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('${s.label} ${widget.vehicles.where((v) => v.status == s).length}', style: text.bodySmall),
              ]),
        ]),
      ]),
    );
  }
}

/// One thing a partner should act on.
class PartnerAlert {
  const PartnerAlert({required this.icon, required this.tone, required this.title, required this.detail, this.action, this.onAction});
  final IconData icon;
  final Tone tone;
  final String title;
  final String detail;
  final String? action;
  final VoidCallback? onAction;
}

List<PartnerAlert> partnerAlerts(BuildContext context, InsightsReport report) {
  final state = context.read<AppState>();
  final alerts = <PartnerAlert>[];
  for (final v in report.vehicles.where((v) => v.status == VehicleStatus.maintenance || v.status == VehicleStatus.inactive).take(3)) {
    alerts.add(PartnerAlert(
      icon: Icons.build_circle_rounded,
      tone: v.status == VehicleStatus.inactive ? Tone.danger : Tone.warning,
      title: '${v.displayName} is off the road',
      detail: '${v.status.label}. Each idle day costs about ${Fmt.naira((report.idleCostPerMonth / (report.idleVehicles.isEmpty ? 1 : report.idleVehicles.length) / 30).round())}.',
      action: 'Mark active',
      onAction: () => attemptOk(context, () => state.setVehicleStatus(v, VehicleStatus.active), success: '${v.displayName} is back in service'),
    ));
  }
  for (final v in report.vehicles.where((v) => (v.batteryPct ?? 100) < 25 && v.status != VehicleStatus.charging).take(2)) {
    alerts.add(PartnerAlert(
      icon: Icons.battery_alert_rounded,
      tone: Tone.warning,
      title: '${v.displayName} battery at ${v.batteryPct}%',
      detail: 'Send it to charge before the evening peak.',
      action: 'Send to charge',
      onAction: () => attemptOk(context, () => state.setVehicleStatus(v, VehicleStatus.charging), success: '${v.displayName} is charging'),
    ));
  }
  final pending = report.vehicles.where((v) => v.verification == Verification.pending).length;
  if (pending > 0) {
    alerts.add(PartnerAlert(icon: Icons.hourglass_top_rounded, tone: Tone.info, title: '$pending vehicle${pending == 1 ? '' : 's'} awaiting FCTA verification', detail: 'They can take bookings once verified on the register.'));
  }
  for (final r in report.routeIncome.where((r) => r.tripsPerDeparture > 40).take(2)) {
    alerts.add(PartnerAlert(
      icon: Icons.groups_rounded,
      tone: Tone.info,
      title: 'Crowding on ${r.route.title}',
      detail: 'About ${r.tripsPerDeparture.round()} riders per departure. Add peak departures.',
      action: 'Routes',
      onAction: () => context.go('/portal/routes'),
    ));
  }
  return alerts;
}

class PartnerAlertsPanel extends StatelessWidget {
  const PartnerAlertsPanel({super.key, required this.alerts});
  final List<PartnerAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle('Needs attention', subtitle: alerts.isEmpty ? 'All clear' : '${alerts.length} item${alerts.length == 1 ? '' : 's'}'),
        if (alerts.isEmpty)
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.leafText),
            const SizedBox(width: 10),
            Expanded(child: Text('Every vehicle is on the road and no route is overcrowded.', style: text.bodyMedium)),
          ]),
        for (final a in alerts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              IconBadge(a.icon, size: 36, radius: 10, color: _soft(a.tone), iconColor: _strong(a.tone)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, style: text.titleSmall),
                  Text(a.detail, style: text.bodySmall),
                ]),
              ),
              if (a.action != null) TextButton(onPressed: a.onAction, child: Text(a.action!)),
            ]),
          ),
      ]),
    );
  }

  static Color _soft(Tone t) => switch (t) { Tone.danger => AppColors.redSoft, Tone.warning => AppColors.amberSoft, Tone.info => AppColors.blueSoft, _ => AppColors.mint };
  static Color _strong(Tone t) => switch (t) { Tone.danger => AppColors.red, Tone.warning => AppColors.amber, Tone.info => AppColors.blue, _ => AppColors.forest };
}

/// Shortcuts at the top of operator and fleet dashboards.
class PartnerQuickActions extends StatelessWidget {
  const PartnerQuickActions({super.key, required this.report, this.canEditFares = true});
  final InsightsReport report;
  final bool canEditFares;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.auto_awesome_rounded, 'AI insights', () => context.go('/portal/insights')),
      (Icons.add_road_rounded, 'Register vehicle', () => context.go('/portal/vehicles')),
      if (canEditFares) (Icons.price_change_rounded, 'Routes & fares', () => context.go('/portal/routes')),
      (Icons.download_rounded, 'Download report', () => exportReport(context, report)),
    ];
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final (i, item) in items.indexed)
        i == 0
            ? FilledButton.icon(onPressed: item.$3, icon: Icon(item.$1, size: 18), label: Text(item.$2))
            : OutlinedButton.icon(onPressed: item.$3, icon: Icon(item.$1, size: 18), label: Text(item.$2)),
    ]);
  }
}

/// Monthly report (routes + vehicles) as a CSV the partner can open in Excel.
Future<void> exportReport(BuildContext context, InsightsReport report) async {
  final today = DateTime.now();
  final stamp = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final rows = <List<Object?>>[
    ['Tap A Ride report', report.scopeName, stamp],
    [],
    ['Revenue this month (NGN)', report.monthlyRevenue],
    ['Revenue today (NGN)', report.revenueToday],
    ['Bookings today', report.bookingsToday],
    ['Fleet working (%)', (report.utilisation * 100).round()],
    ['Idle cost per month (NGN)', report.idleCostPerMonth],
    [],
    ['Route', 'Fare (NGN)', 'Trips (30 days)', 'Departures per day', 'Riders per departure', 'Est. monthly revenue (NGN)'],
    for (final r in report.routeIncome) [r.route.title, r.route.fare, r.route.monthlyTrips, r.route.departures.length, r.tripsPerDeparture.round(), r.monthlyRevenue],
    [],
    ['Vehicle', 'Plate', 'Type', 'Status', 'FCTA register', 'Driver', 'Earnings this month (NGN)'],
    for (final v in report.vehicles) [v.model, v.plate, v.kind.label, v.status.label, v.verification.label, v.driverName ?? '', v.monthEarnings],
  ];
  final safe = report.scopeName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase();
  final ok = await downloadCsv('taparide-$safe-$stamp.csv', rows);
  if (context.mounted) showMessage(context, ok ? 'Report downloaded' : 'Download is available in the web app.', error: !ok);
}

/// A one-line nudge from the AI analyst, linking to the full insights page.
class AiTeaser extends StatelessWidget {
  const AiTeaser({super.key, required this.report});
  final InsightsReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final top = report.opportunities.firstOrNull;
    return Panel(
      color: AppColors.forestDeep,
      border: false,
      onTap: () => context.go('/portal/insights'),
      child: Row(children: [
        const Icon(Icons.auto_awesome_rounded, color: AppColors.leaf),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI analyst', style: text.labelMedium?.copyWith(color: AppColors.leaf, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(top?.title ?? 'Your routes and fleet look healthy today.', style: text.titleMedium?.copyWith(color: Colors.white)),
            if (top != null) Text(top.detail, style: text.bodySmall?.copyWith(color: AppColors.onForestMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: Colors.white),
      ]),
    );
  }
}
