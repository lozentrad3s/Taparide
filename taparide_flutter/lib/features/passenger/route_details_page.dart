import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/route_operators.dart';
import '../../shared/route_map.dart';
import '../../shared/ui.dart';

class RouteDetailsPage extends StatefulWidget {
  const RouteDetailsPage({super.key, required this.routeId});
  final String routeId;

  @override
  State<RouteDetailsPage> createState() => _RouteDetailsPageState();
}

class _RouteDetailsPageState extends State<RouteDetailsPage> {
  DateTime? _selected;

  void _book(TransitRoute route, DateTime at) {
    context.push(Uri(path: '/ride/${route.id}/pay', queryParameters: {'at': at.toUtc().toIso8601String()}).toString());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final route = state.routeById(widget.routeId);
    final wide = isWide(context, 960);

    if (route == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(fallback: '/app/routes'), title: const Text('Route Details')),
        body: DataGate(
          builder: (context) => EmptyState(
            icon: Icons.wrong_location_outlined,
            title: 'Route not available',
            message: 'This route is not taking bookings right now. It may be paused or its operator is under review.',
            action: 'See other routes',
            onAction: () => context.go('/app/routes'),
          ),
        ),
      );
    }

    final departures = route.upcomingDepartures(state.now, count: 8);
    final chosen = _selected ?? (departures.isEmpty ? null : departures.first);
    final provider = state.providerById(route.providerId);
    final details = _Details(
      route: route,
      provider: provider,
      departures: departures,
      selected: chosen,
      onSelect: (d) => setState(() => _selected = d),
    );
    final bookBar = _BookBar(route: route, at: chosen, onBook: chosen == null ? null : () => _book(route, chosen));

    if (wide) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(fallback: '/app/routes'), title: const Text('Route Details')),
        body: Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 0, 20), child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.xl), child: RouteMap(stops: route.stops, roadPath: context.read<AppState>().api.roadPath)))),
          SizedBox(
            width: 440,
            child: Column(children: [
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 16), child: details)),
              Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20), child: bookBar),
            ]),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(fallback: '/app/routes'), title: const Text('Route Details')),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: 280, child: RouteMap(stops: route.stops, padding: const EdgeInsets.fromLTRB(40, 72, 120, 56), roadPath: context.read<AppState>().api.roadPath)),
              Transform.translate(
                offset: const Offset(0, -18),
                child: Container(
                  decoration: const BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
                  child: details,
                ),
              ),
            ]),
          ),
        ),
        Container(
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
          padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + MediaQuery.paddingOf(context).bottom),
          child: bookBar,
        ),
      ]),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.route, required this.provider, required this.departures, required this.selected, required this.onSelect});
  final TransitRoute route;
  final TransportProvider? provider;
  final List<DateTime> departures;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.location_on_rounded, color: AppColors.forest, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(route.name ?? '${route.origin} – ${route.destination}', style: text.headlineSmall),
                if (route.name != null) Text('${route.origin} – ${route.destination}', style: text.bodySmall),
              ]),
            ),
            StatusPill(route.code, tone: Tone.brand),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Text(Fmt.naira(route.fare), style: text.headlineMedium?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800, fontFeatures: tabular)),
            const SizedBox(width: 12),
            const Icon(Icons.schedule_rounded, size: 18, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(Fmt.minutes(route.durationMin), style: text.titleSmall?.copyWith(color: AppColors.muted)),
            const Spacer(),
            Icon(route.mode.icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(route.mode.label, style: text.labelMedium?.copyWith(color: AppColors.muted)),
          ]),
          if (provider != null) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text(provider!.name, style: text.titleSmall)),
              StatusPill(provider!.status.label, tone: provider!.status == Verification.verified ? Tone.success : Tone.warning, icon: Icons.verified_rounded),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 22),
      Text('Stops', style: text.titleLarge),
      const SizedBox(height: 10),
      _StopsTimeline(route: route, departure: selected),
      const SizedBox(height: 22),
      Text('Departure Times', style: text.titleLarge),
      const SizedBox(height: 10),
      if (departures.isEmpty)
        Text('No more departures are scheduled.', style: text.bodyMedium)
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in departures)
            ChoiceChip(
              label: Text(Fmt.day(d) == 'Today' ? Fmt.time(d) : '${Fmt.time(d)} · ${Fmt.day(d)}'),
              selected: d == selected,
              showCheckmark: false,
              labelStyle: TextStyle(color: d == selected ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700, fontFeatures: tabular),
              onSelected: (_) => onSelect(d),
            ),
        ]),
      const SizedBox(height: 16),
      _CorridorOperators(route: route),
    ]);
  }
}

/// Public information on who runs vehicles on the corridor today. These are not Tap A Ride partners.
class _CorridorOperators extends StatelessWidget {
  const _CorridorOperators({required this.route});
  final TransitRoute route;

  @override
  Widget build(BuildContext context) {
    final operators = route.servedBy.isNotEmpty ? route.servedBy : (corridorOperators[route.id] ?? const <CorridorOperator>[]);
    if (operators.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final rail = route.mode == TransitMode.rail;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 6),
      Text(rail ? 'Who runs trains on this line today' : 'Who runs buses on this corridor today', style: text.titleLarge),
      const SizedBox(height: 4),
      Text('Public information from news reports. These operators are not Tap A Ride partners; bookings on Tap A Ride are only with verified partners.', style: text.bodySmall?.copyWith(color: AppColors.muted)),
      const SizedBox(height: 10),
      Panel(
        padding: EdgeInsets.zero,
        shadow: false,
        child: Column(children: [
          for (var i = 0; i < operators.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _CorridorOperatorTile(operator: operators[i]),
          ],
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }
}

class _CorridorOperatorTile extends StatelessWidget {
  const _CorridorOperatorTile({required this.operator});
  final CorridorOperator operator;

  IconData get _icon {
    final type = operator.type.toLowerCase();
    if (type.contains('rail')) return Icons.tram_rounded;
    if (type.contains('taxi') || type.contains('commercial vehicle')) return Icons.local_taxi_rounded;
    if (type.contains('minibus') || type.contains('coaster')) return Icons.airport_shuttle_rounded;
    return Icons.directions_bus_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final uri = Uri.tryParse(operator.source);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Icon(_icon, size: 20, color: AppColors.forest),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(operator.name, style: text.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusPill(operator.type),
              if (operator.uncertain) const StatusPill('Not confirmed for 2026', tone: Tone.warning),
            ]),
            if (operator.note != null && operator.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(operator.note!, style: text.bodySmall),
            ],
            const SizedBox(height: 4),
            Semantics(
              link: uri != null,
              child: InkWell(
                onTap: uri == null ? null : () => launchUrl(uri),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('As reported ${operator.asOf} · ${operator.publisher}', style: text.labelMedium?.copyWith(color: AppColors.forest, decoration: uri == null ? null : TextDecoration.underline)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _StopsTimeline extends StatelessWidget {
  const _StopsTimeline({required this.route, required this.departure});
  final TransitRoute route;
  final DateTime? departure;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stops = route.stops;
    const rowHeight = 46.0;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shadow: false,
      child: SizedBox(
        height: rowHeight * stops.length,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 18, child: Padding(padding: EdgeInsets.symmetric(vertical: rowHeight / 2 - 8), child: RouteLine(stops: stops.length, vertical: true))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(children: [
              for (var i = 0; i < stops.length; i++)
                SizedBox(
                  height: rowHeight,
                  child: Row(children: [
                    Expanded(child: Text(stops[i].name, style: (i == 0 || i == stops.length - 1) ? text.titleSmall : text.bodyMedium)),
                    if (departure != null)
                      Text(
                        Fmt.time(departure!.add(Duration(minutes: (route.durationMin * i / (stops.length - 1)).round()))),
                        style: text.labelMedium?.copyWith(color: AppColors.muted, fontFeatures: tabular),
                      ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BookBar extends StatelessWidget {
  const _BookBar({required this.route, required this.at, required this.onBook});
  final TransitRoute route;
  final DateTime? at;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(at == null ? 'No departure selected' : Fmt.dayTime(at!), style: text.titleSmall),
          Text('${Fmt.naira(route.fare)} · 1 seat', style: text.bodySmall),
        ]),
      ),
      FilledButton(onPressed: onBook, style: FilledButton.styleFrom(minimumSize: const Size(150, 52)), child: const Text('Book Seat')),
    ]);
  }
}
