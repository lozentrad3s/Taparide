import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/dashboards.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/photos.dart';
import '../../shared/ui.dart';
import 'driver_dashboard.dart';
import 'partner_widgets.dart';
import 'portal_widgets.dart';

// ------------------------------------------------------------------ platform overview (admin)

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final fcta = state.fctaDashboard();
    final text = Theme.of(context).textTheme;
    if (fcta == null) return const SizedBox.shrink();
    final pendingProviders = state.providers.where((p) => p.status == Verification.pending).toList();
    final suspended = state.providers.where((p) => p.status == Verification.suspended).toList();
    final todayRevenue = state.partnerBookings
        .where((b) => b.status != BookingStatus.cancelled && b.createdAt.day == state.now.day && b.createdAt.month == state.now.month && b.paymentMethod != PaymentMethod.splitCost)
        .fold<int>(0, (s, b) => s + b.fare);

    return PortalScaffold(
      title: 'Platform overview',
      subtitle: 'Every provider, vehicle and booking on Tap A Ride · ${Fmt.date(state.now)}',
      children: [
        Cols(min: 200, max: 5, children: [
          FigureCard(label: 'Ridership · 7 days', value: Fmt.count(fcta.totalRidership), delta: fcta.ridershipDelta, icon: Icons.groups_rounded),
          FigureCard(label: 'Bookings today', value: Fmt.count(fcta.bookingsToday), caption: 'live from the rider app', icon: Icons.confirmation_number_rounded, onTap: () => context.go('/portal/bookings')),
          FigureCard(label: 'Fares collected today', value: Fmt.naira(todayRevenue), icon: Icons.payments_rounded),
          FigureCard(label: 'Verified vehicles', value: Fmt.count(fcta.verifiedVehicles), delta: fcta.verifiedDelta, icon: Icons.verified_rounded, onTap: () => context.go('/portal/vehicles')),
          FigureCard(label: 'Providers', value: '${fcta.providersWith(Verification.verified)} verified', caption: '${pendingProviders.length} pending · ${suspended.length} suspended', icon: Icons.apartment_rounded, onTap: () => context.go('/portal/providers')),
        ]),
        const SizedBox(height: 18),
        _TwoUp(
          left: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PanelTitle('Ridership trend', subtitle: 'Last 7 days, all operators'),
            WeekBars(values: fcta.ridershipByDay, labels: fcta.dayLabels, highlightIndex: fcta.todayIndex),
          ])),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Needs attention', trailing: TextButton(onPressed: () => context.go('/portal/verification'), child: const Text('Open queue'))),
            _AttentionRow(icon: Icons.apartment_rounded, label: 'Providers awaiting approval', count: pendingProviders.length, onTap: () => context.go('/portal/verification')),
            _AttentionRow(icon: Icons.directions_car_filled_rounded, label: 'Vehicles awaiting verification', count: fcta.pendingVehicles.length, onTap: () => context.go('/portal/verification')),
            _AttentionRow(icon: Icons.block_rounded, label: 'Suspended providers', count: suspended.length, tone: Tone.danger, onTap: () => context.go('/portal/providers')),
            _AttentionRow(
              icon: Icons.battery_alert_rounded,
              label: 'EVs below 30% battery',
              count: fcta.electricVehicles.where((v) => (v.batteryPct ?? 100) < 30).length,
              tone: Tone.info,
              onTap: () => context.go('/portal/evs'),
            ),
          ])),
        ),
        const SizedBox(height: 18),
        Text('Partner dashboards', style: text.titleLarge),
        const SizedBox(height: 10),
        Cols(min: 260, max: 3, children: [
          _DashLink(photo: AppPhoto.brtBerger, title: 'Operator dashboard', subtitle: 'Abuja Metro Bus Co. and other operators', onTap: () => context.go('/portal/operator')),
          _DashLink(photo: AppPhoto.taxis, title: 'Fleet owner dashboard', subtitle: 'GreenFleet Logistics and other owners', onTap: () => context.go('/portal/fleet')),
          _DashLink(photo: AppPhoto.asoRockExpressway, title: 'FCTA dashboard', subtitle: 'Ridership, register and safety', onTap: () => context.go('/portal/fcta')),
        ]),
        const SizedBox(height: 18),
        _TwoUp(
          left: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Top routes', subtitle: 'Trips in the last 30 days', trailing: TextButton(onPressed: () => context.go('/portal/routes'), child: const Text('All routes'))),
            TopRoutes(volumes: fcta.topRoutes.take(5).toList()),
          ])),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Recent activity', trailing: TextButton(onPressed: () => context.go('/portal/audit'), child: const Text('Audit log'))),
            for (final a in state.audit.take(5)) AuditTile(entry: a),
            if (state.audit.isEmpty) Text('No changes recorded yet.', style: text.bodyMedium),
          ])),
        ),
      ],
    );
  }
}

class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.left, required this.right, this.leftFlex = 3, this.rightFlex = 2});
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 900
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: leftFlex, child: left),
                const SizedBox(width: 18),
                Expanded(flex: rightFlex, child: right),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 18), right]),
      );
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.icon, required this.label, required this.count, required this.onTap, this.tone = Tone.warning});
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;
  final Tone tone;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(children: [
            Icon(icon, size: 20, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink))),
            StatusPill('$count', tone: count == 0 ? Tone.neutral : tone),
          ]),
        ),
      );
}

class _DashLink extends StatelessWidget {
  const _DashLink({required this.photo, required this.title, required this.subtitle, required this.onTap});
  final AppPhoto photo;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: EdgeInsets.zero,
      onTap: onTap,
      semanticLabel: title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 110, child: PhotoView(photo)),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: text.titleMedium),
                Text(subtitle, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.forest),
          ]),
        ),
      ]),
    );
  }
}

/// Top routes drawn as transit lines whose length is the trip volume.
class TopRoutes extends StatelessWidget {
  const TopRoutes({super.key, required this.volumes});
  final List<RouteVolume> volumes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (volumes.isEmpty) return Text('No trips recorded yet.', style: text.bodyMedium);
    final top = volumes.first.trips == 0 ? 1 : volumes.first.trips;
    return Column(children: [
      for (final v in volumes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(v.route.name ?? '${v.route.origin} – ${v.route.destination}', style: text.titleSmall, overflow: TextOverflow.ellipsis)),
              Text('${Fmt.count(v.trips)} trips', style: text.labelLarge?.copyWith(fontFeatures: tabular)),
            ]),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: v.trips / top),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => SizedBox(width: (c.maxWidth * t).clamp(24, c.maxWidth), height: 14, child: RouteLine(stops: v.route.stops.length, thickness: 4)),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class AuditTile extends StatelessWidget {
  const AuditTile({super.key, required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(initials: entry.actorName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join(), size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: entry.actorName, style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' · ${entry.action.toLowerCase()}'),
            ]), style: text.bodyMedium?.copyWith(color: AppColors.ink)),
            Text(entry.target, style: text.bodySmall),
          ]),
        ),
        Text(Fmt.relative(entry.at), style: text.labelSmall),
      ]),
    );
  }
}

// ------------------------------------------------------------------ FCTA

class FctaPage extends StatelessWidget {
  const FctaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final d = state.fctaDashboard();
    final text = Theme.of(context).textTheme;
    if (d == null) return const SizedBox.shrink();
    final evs = d.electricVehicles;
    final avgBattery = evs.isEmpty ? 0 : evs.fold<int>(0, (s, v) => s + (v.batteryPct ?? 0)) ~/ evs.length;
    final freePorts = state.stations.fold<int>(0, (s, c) => s + c.available);

    return PortalScaffold(
      title: 'FCTA Dashboard',
      subtitle: 'Federal Capital Territory transport oversight',
      leading: const IconBadge(Icons.account_balance_rounded, size: 52, color: AppColors.forest, iconColor: Colors.white, radius: 26),
      children: [
        Cols(min: 220, max: 3, children: [
          FigureCard(label: 'Total Ridership', value: Fmt.count(d.totalRidership), delta: d.ridershipDelta, caption: 'last 7 days', icon: Icons.groups_rounded),
          FigureCard(label: 'Verified Vehicles', value: Fmt.count(d.verifiedVehicles), delta: d.verifiedDelta, caption: 'FCT register', icon: Icons.verified_rounded, onTap: () => context.go('/portal/vehicles')),
          FigureCard(label: 'Active Routes', value: Fmt.count(d.activeRoutes), delta: d.routesDelta, icon: Icons.alt_route_rounded, onTap: () => context.go('/portal/routes')),
        ]),
        const SizedBox(height: 18),
        _TwoUp(
          left: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Ridership Trend', trailing: StatusPill('Last 7 days · today ${Fmt.weekday(state.now)}', tone: Tone.neutral)),
            WeekBars(values: d.ridershipByDay, labels: d.dayLabels, highlightIndex: d.todayIndex, height: 220),
            const SizedBox(height: 8),
            Text('Today includes ${Fmt.count(d.bookingsToday)} live bookings from the rider app.', style: text.bodySmall),
          ])),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Top Routes', trailing: TextButton(onPressed: () => context.go('/portal/routes'), child: const Text('View all'))),
            TopRoutes(volumes: d.topRoutes.take(4).toList()),
          ])),
        ),
        const SizedBox(height: 18),
        Cols(min: 300, max: 3, children: [
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Provider register', trailing: TextButton(onPressed: () => context.go('/portal/providers'), child: const Text('Manage'))),
            ShareBar(parts: [
              (d.providersWith(Verification.verified), AppColors.leaf),
              (d.providersWith(Verification.pending), AppColors.amber),
              (d.providersWith(Verification.suspended), AppColors.red),
            ]),
            const SizedBox(height: 8),
            LegendRow(color: AppColors.leaf, label: 'Verified', value: '${d.providersWith(Verification.verified)}'),
            LegendRow(color: AppColors.amber, label: 'Pending review', value: '${d.providersWith(Verification.pending)}'),
            LegendRow(color: AppColors.red, label: 'Suspended', value: '${d.providersWith(Verification.suspended)}'),
          ])),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Safety & verification', trailing: TextButton(onPressed: () => context.go('/portal/verification'), child: const Text('Review'))),
            _AttentionRow(icon: Icons.directions_car_filled_rounded, label: 'Vehicles awaiting checks', count: d.pendingVehicles.length, onTap: () => context.go('/portal/verification')),
            _AttentionRow(icon: Icons.apartment_rounded, label: 'Providers awaiting approval', count: d.providersWith(Verification.pending), onTap: () => context.go('/portal/verification')),
            const SizedBox(height: 6),
            Text('Unverified vehicles cannot take bookings, which keeps unregistered "one chance" cars off the platform.', style: text.bodySmall),
          ])),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Electric mobility', trailing: TextButton(onPressed: () => context.go('/portal/evs'), child: const Text('Fleet'))),
            LegendRow(color: AppColors.leaf, label: 'Electric vehicles on platform', value: '${evs.length}'),
            LegendRow(color: AppColors.blue, label: 'Average battery', value: '$avgBattery%'),
            LegendRow(color: AppColors.forest, label: 'Free charging ports', value: '$freePorts'),
          ])),
        ]),
      ],
    );
  }
}

// ------------------------------------------------------------------ operator

class OperatorPage extends StatefulWidget {
  const OperatorPage({super.key, this.providerId});
  final String? providerId;

  @override
  State<OperatorPage> createState() => _OperatorPageState();
}

class _OperatorPageState extends State<OperatorPage> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final text = Theme.of(context).textTheme;
    final canPick = user.role == UserRole.admin || user.role == UserRole.government;
    final operators = [
      for (final p in state.providers)
        if (p.kind != ProviderKind.fleetOwner && (state.routes.any((r) => r.providerId == p.id) || state.vehicles.any((v) => v.operatorId == p.id))) p,
    ];
    final id = canPick ? (_picked ?? widget.providerId ?? state.baselines?.operatorProviderId ?? operators.firstOrNull?.id) : user.providerId;
    final d = id == null ? null : state.operatorDashboard(id);
    if (d == null) {
      return const PortalScaffold(title: 'Operator dashboard', children: [EmptyState(icon: Icons.directions_bus_rounded, title: 'No provider linked', message: 'Ask a platform admin to link your account to your company.')]);
    }
    final picker = canPick && operators.isNotEmpty ? ProviderPicker(providers: operators, selected: d.provider.id, onChanged: (v) => setState(() => _picked = v)) : null;
    // Private drivers get a driver-focused dashboard (online switch, current ride, earnings).
    if (d.provider.kind == ProviderKind.privateDriver) return DriverDashboard(provider: d.provider, picker: picker);
    final report = state.insightsFor(d.provider.id);

    return PortalScaffold(
      title: 'Operator Dashboard',
      subtitle: '${d.provider.name} · ${d.provider.kind.label}',
      leading: IconBadge(d.provider.kind.icon, size: 52, color: AppColors.forest, iconColor: Colors.white, radius: 26),
      actions: [if (picker != null) picker],
      children: [
        PartnerQuickActions(report: report),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final forest = ForestFigures(figures: [
            Figure(label: 'Total Trips', value: Fmt.count(d.totalTrips), delta: d.tripsDelta, onDark: true, large: true, caption: d.tripsDelta == null ? 'all time' : 'this month'),
            Figure(label: 'Total Revenue', value: Fmt.naira(d.revenue), delta: d.revenueDelta, onDark: true, large: true, caption: d.revenueToday > 0 ? '+${Fmt.naira(d.revenueToday)} today' : 'this month'),
          ]);
          final tiles = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: FigureCard(label: 'Routes', value: '${d.routes.length}', icon: Icons.alt_route_rounded, onTap: () => context.go('/portal/routes'))),
            const SizedBox(width: 12),
            Expanded(child: FigureCard(label: 'Vehicles', value: '${d.vehicles.length}', icon: Icons.directions_bus_rounded, onTap: () => context.go('/portal/vehicles'))),
            const SizedBox(width: 12),
            Expanded(child: FigureCard(label: c.maxWidth < 600 ? 'Drivers' : 'Active Drivers', value: '${d.activeDrivers}', icon: Icons.badge_rounded)),
          ]);
          return c.maxWidth >= 980
              ? IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 5, child: forest), const SizedBox(width: 18), Expanded(flex: 6, child: tiles)]),
                )
              : Column(children: [forest, const SizedBox(height: 12), IntrinsicHeight(child: tiles)]);
        }),
        const SizedBox(height: 18),
        _TwoUp(
          leftFlex: 3,
          rightFlex: 2,
          left: LiveFleetMap(vehicles: d.vehicles, routes: d.routes),
          right: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // The operator's own staff (or an admin) can report a vehicle's GPS from this device.
            if (user.role != UserRole.government) ...[LiveTrackerPanel(vehicles: d.vehicles), const SizedBox(height: 18)],
            AiTeaser(report: report),
            const SizedBox(height: 18),
            PartnerAlertsPanel(alerts: partnerAlerts(context, report)),
          ]),
        ),
        const SizedBox(height: 18),
        _TwoUp(
          left: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Recent Trips', subtitle: 'Departures in the last three hours', trailing: TextButton(onPressed: () => context.go('/portal/bookings'), child: const Text('View all'))),
            if (d.recentTrips.isEmpty) Text('No departures yet today.', style: text.bodyMedium),
            for (final t in d.recentTrips) _TripRow(trip: t),
          ])),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle('Latest bookings', subtitle: '${d.bookingsToday} today · ${Fmt.naira(d.revenueToday)}'),
            if (d.latestBookings.isEmpty) Text('Bookings from the rider app appear here the moment they are made.', style: text.bodyMedium),
            for (final b in d.latestBookings.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Avatar(initials: b.passengerName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join(), size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${b.passengerName} · ${b.seat ?? b.kind.label}', style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${b.origin} – ${b.destination} · ${Fmt.dayTime(b.departureAt)}', style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  Text(Fmt.naira(b.fare), style: text.labelLarge),
                ]),
              ),
          ])),
        ),
      ],
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.trip});
  final TripRecord trip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tone = switch (trip.status) {
      TripStatus.onTime => Tone.success,
      TripStatus.delayed => Tone.warning,
      TripStatus.boarding => Tone.info,
      TripStatus.scheduled => Tone.neutral,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        const Icon(Icons.location_on_rounded, color: AppColors.forest, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trip.route.name ?? '${trip.route.origin} → ${trip.route.destination}', style: text.titleSmall),
            Text(
              [Fmt.time(trip.at), if (trip.vehicle != null) trip.vehicle!.displayName, Fmt.naira(trip.route.fare)].join(' · '),
              style: text.bodySmall,
            ),
          ]),
        ),
        StatusPill(trip.status == TripStatus.delayed ? '+${trip.delayMin} min' : trip.status.label, tone: tone),
      ]),
    );
  }
}

// ------------------------------------------------------------------ fleet owner

class FleetPage extends StatefulWidget {
  const FleetPage({super.key, this.providerId});
  final String? providerId;

  @override
  State<FleetPage> createState() => _FleetPageState();
}

class _FleetPageState extends State<FleetPage> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final text = Theme.of(context).textTheme;
    final canPick = user.role == UserRole.admin;
    final owners = [for (final p in state.providers) if (p.kind == ProviderKind.fleetOwner) p];
    final id = canPick ? (_picked ?? widget.providerId ?? state.baselines?.fleetProviderId ?? owners.firstOrNull?.id) : user.providerId;
    final d = id == null ? null : state.fleetDashboard(id);
    if (d == null) {
      return const PortalScaffold(title: 'Fleet owner dashboard', children: [EmptyState(icon: Icons.local_shipping_rounded, title: 'No fleet linked', message: 'Ask a platform admin to link your account to your fleet.')]);
    }
    final needsAttention = d.vehicles.where((v) => v.status == VehicleStatus.maintenance || v.status == VehicleStatus.inactive).toList();
    final topEarners = [...d.vehicles]..sort((a, b) => b.monthEarnings.compareTo(a.monthEarnings));
    final report = state.insightsFor(d.provider.id);

    return PortalScaffold(
      title: 'Fleet Owner Dashboard',
      subtitle: '${d.provider.name} · Fleet owner',
      leading: const IconBadge(Icons.local_shipping_rounded, size: 52, color: AppColors.forest, iconColor: Colors.white, radius: 26),
      actions: [if (canPick && owners.length > 1) ProviderPicker(providers: owners, selected: d.provider.id, onChanged: (v) => setState(() => _picked = v))],
      children: [
        PartnerQuickActions(report: report, canEditFares: false),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final tiles = [
            FigureCard(label: 'Total Vehicles', value: '${d.vehicles.length}', icon: Icons.directions_bus_rounded, onTap: () => context.go('/portal/vehicles')),
            FigureCard(label: 'Total Revenue', value: Fmt.naira(d.revenue), delta: d.revenueDelta, icon: Icons.payments_rounded, caption: 'this month'),
            FigureCard(label: 'Bookings on your vehicles today', value: '${d.bookingsToday}', icon: Icons.confirmation_number_rounded),
          ];
          return Cols(min: 230, max: 3, children: tiles);
        }),
        const SizedBox(height: 18),
        _TwoUp(
          left: LiveFleetMap(vehicles: d.vehicles, routes: [for (final r in state.routes) if (d.vehicles.any((v) => v.operatorId == r.providerId)) r]),
          right: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AiTeaser(report: report),
            const SizedBox(height: 18),
            PartnerAlertsPanel(alerts: partnerAlerts(context, report)),
          ]),
        ),
        const SizedBox(height: 18),
        _TwoUp(
          leftFlex: 2,
          rightFlex: 3,
          left: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PanelTitle('Vehicle Performance'),
            ShareBar(parts: [(d.active, AppColors.leaf), (d.maintenance, AppColors.amber), (d.inactive, AppColors.red)], height: 12),
            const SizedBox(height: 10),
            LegendRow(color: AppColors.leaf, label: 'Active', value: '${d.active}'),
            LegendRow(color: AppColors.amber, label: 'In Maintenance', value: '${d.maintenance}'),
            LegendRow(color: AppColors.red, label: 'Inactive', value: '${d.inactive}'),
            if (needsAttention.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 10),
              Text('Needs attention', style: text.titleSmall),
              for (final v in needsAttention)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(child: Text(v.displayName, style: text.bodyMedium?.copyWith(color: AppColors.ink))),
                    StatusPill(v.status.label, tone: vehicleTone(v.status)),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () => attemptOk(context, () => context.read<AppState>().setVehicleStatus(v, VehicleStatus.active), success: '${v.displayName} is back in service'),
                      child: const Text('Mark active'),
                    ),
                  ]),
                ),
            ],
          ])),
          right: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PanelTitle('Recent Earnings', subtitle: 'Remittances per vehicle'),
            for (final e in d.earnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  const IconBadge(Icons.directions_bus_rounded, size: 36, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Bus #${e.plate}', style: text.titleSmall)),
                  Text(Fmt.naira(e.amount), style: text.titleSmall?.copyWith(fontFeatures: tabular)),
                  const SizedBox(width: 16),
                  SizedBox(width: 92, child: Text(Fmt.date(e.date), style: text.bodySmall, textAlign: TextAlign.right)),
                ]),
              ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 12),
            Text('Top earners this month', style: text.titleSmall),
            const SizedBox(height: 6),
            for (final v in topEarners.take(3))
              LegendRow(color: AppColors.forest, label: v.displayName, value: Fmt.naira(v.monthEarnings)),
          ])),
        ),
      ],
    );
  }
}
