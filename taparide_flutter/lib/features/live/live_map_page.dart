import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/fleet_positions.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/places.dart';
import '../../shared/route_map.dart' show MapTiles, MapCredit;
import '../../shared/ticking.dart';
import '../../shared/ui.dart';

enum NearbyKind { bus, electric, car, myRide }

extension on NearbyKind {
  String get label => switch (this) {
        NearbyKind.bus => 'Buses',
        NearbyKind.electric => 'Electric',
        NearbyKind.car => 'Cars',
        NearbyKind.myRide => 'My ride',
      };
  Color get colour => switch (this) {
        NearbyKind.bus => AppColors.forest,
        NearbyKind.electric => const Color(0xFF0E7C66),
        NearbyKind.car => AppColors.blue,
        NearbyKind.myRide => const Color(0xFFD9480F),
      };
}

/// A vehicle near the rider: where it is, how far, and minutes to reach them.
class NearbyVehicle {
  const NearbyVehicle({required this.vehicle, required this.point, required this.kind, required this.km, required this.minutes, required this.live, this.route});
  final Vehicle vehicle;
  final LatLng point;
  final NearbyKind kind;
  final double km;
  final int minutes;

  /// True when the driver's phone is reporting GPS; otherwise estimated from the timetable.
  final bool live;
  final TransitRoute? route;
}

/// Vehicles around [from], nearest first. City traffic is taken as ~20 km/h door to door.
List<NearbyVehicle> nearbyVehicles(AppState state, LatLng from) {
  final verified = {for (final p in state.providers) if (p.status == Verification.verified) p.id};
  final usable = [
    for (final v in state.vehicles)
      if (v.verification == Verification.verified && verified.contains(v.operatorId) && (v.status == VehicleStatus.active || v.status == VehicleStatus.onTrip)) v,
  ];
  final myRide = state.upcomingTrips.where((b) => b.vehicleId != null && b.departureAt.difference(state.now).inMinutes < 120).firstOrNull?.vehicleId;
  final out = <NearbyVehicle>[];
  for (final p in FleetPositions.estimate(vehicles: usable, routes: state.bookableRoutes, now: state.now)) {
    final gps = state.livePosition(p.vehicle.id);
    final point = gps?.point ?? p.point;
    final km = straightKm(from, point);
    final kind = p.vehicle.id == myRide
        ? NearbyKind.myRide
        : p.vehicle.kind.isBookableCar
            ? (p.vehicle.kind.isElectric ? NearbyKind.electric : NearbyKind.car)
            : NearbyKind.bus;
    out.add(NearbyVehicle(vehicle: p.vehicle, point: point, kind: kind, km: km, minutes: max(1, (km * 1.3 / 20 * 60).round()), live: gps != null, route: p.route));
  }
  out.sort((a, b) => a.kind == NearbyKind.myRide ? -1 : (b.kind == NearbyKind.myRide ? 1 : a.km.compareTo(b.km)));
  return out;
}

String _distance(double km) => km < 1 ? '${(km * 1000 / 50).round() * 50} m' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';

/// Keeps positions moving: estimates tick every few seconds, GPS is re-read every 15 s.
mixin _LiveTicker<T extends StatefulWidget> on State<T> {
  Timer? _tick;
  Timer? _gps;

  void startTicking() {
    final state = context.read<AppState>();
    if (!LiveTicking.enabled) return;
    state.locate();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
    _gps = Timer.periodic(const Duration(seconds: 15), (_) => state.refreshPositions());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _gps?.cancel();
    super.dispose();
  }
}

class _LiveMap extends StatelessWidget {
  const _LiveMap({required this.here, required this.vehicles, required this.located, this.interactive = true, this.onTap});
  final LatLng here;
  final bool located;
  final List<NearbyVehicle> vehicles;
  final bool interactive;
  final ValueChanged<NearbyVehicle>? onTap;

  @override
  Widget build(BuildContext context) {
    final shown = vehicles.where((v) => v.km < 12).take(40).toList();
    final fit = [here, for (final v in shown.take(6)) v.point];
    return FlutterMap(
      key: ValueKey('${here.latitude.toStringAsFixed(3)},${here.longitude.toStringAsFixed(3)}'),
      options: MapOptions(
        initialCameraFit: fit.length > 1 ? CameraFit.coordinates(coordinates: fit, padding: const EdgeInsets.all(48), maxZoom: 15) : null,
        initialCenter: here,
        initialZoom: 14,
        backgroundColor: const Color(0xFFEAF1EC),
        interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
      ),
      children: [
        if (MapTiles.enabled)
          TileLayer(urlTemplate: MapTiles.urlTemplate, subdomains: MapTiles.subdomains, retinaMode: RetinaMode.isHighDensity(context), userAgentPackageName: 'com.taparide.app'),
        MarkerLayer(markers: [
          for (final v in shown)
            Marker(
              point: v.point,
              width: 34,
              height: 34,
              child: Semantics(
                button: onTap != null,
                label: '${v.vehicle.kind.label} ${v.vehicle.plate}, ${_distance(v.km)} away, ${v.minutes} minutes',
                child: GestureDetector(
                  onTap: onTap == null ? null : () => onTap!(v),
                  child: Container(
                    decoration: BoxDecoration(
                      color: v.kind.colour,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: Icon(v.vehicle.kind.icon, size: 17, color: Colors.white),
                  ),
                ),
              ),
            ),
          Marker(
            point: here,
            width: 26,
            height: 26,
            child: Container(
              decoration: BoxDecoration(
                color: located ? const Color(0xFF2B6EF2) : AppColors.muted,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [BoxShadow(color: (located ? const Color(0xFF2B6EF2) : AppColors.muted).withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 8)],
              ),
            ),
          ),
        ]),
        const MapCredit(),
      ],
    );
  }
}

/// Home-screen card: the map around the rider with the nearest few vehicles.
class LiveNearbyCard extends StatefulWidget {
  const LiveNearbyCard({super.key});

  @override
  State<LiveNearbyCard> createState() => _LiveNearbyCardState();
}

class _LiveNearbyCardState extends State<LiveNearbyCard> with _LiveTicker {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => startTicking());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final here = state.here != null && inFct(state.here!) ? state.here! : abujaCentre;
    final located = state.here != null && inFct(state.here!);
    final near = nearbyVehicles(state, here);
    final top = near.take(3).toList();
    return Panel(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/live'),
      semanticLabel: 'Live map of vehicles near you. Open full map.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 190, child: IgnorePointer(child: _LiveMap(here: here, vehicles: near, located: located, interactive: false))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.leaf, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(located ? 'Live near ${state.hereName ?? 'you'}' : 'Live around Central Area', style: text.titleMedium)),
              Text('Full map', style: text.labelLarge?.copyWith(color: AppColors.forest)),
              const Icon(Icons.chevron_right_rounded, color: AppColors.forest),
            ]),
            if (!located)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(state.locating ? 'Finding your location…' : 'Allow location to see what\'s closest to you.', style: text.bodySmall),
              ),
            const SizedBox(height: 6),
            for (final v in top) _NearbyRow(item: v, dense: true),
          ]),
        ),
      ]),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({required this.item, this.dense = false, this.onTap});
  final NearbyVehicle item;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = item.vehicle;
    final title = switch (item.kind) {
      NearbyKind.myRide => 'Your ride · ${v.plate}',
      NearbyKind.bus => item.route == null ? '${v.kind.label} · ${v.plate}' : '${item.route!.code} · ${item.route!.origin} – ${item.route!.destination}',
      _ => '${v.model} · ${v.plate}',
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 5 : 9),
        child: Row(children: [
          Container(
            width: dense ? 30 : 38,
            height: dense ? 30 : 38,
            decoration: BoxDecoration(color: item.kind.colour.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(v.kind.icon, size: dense ? 16 : 20, color: item.kind.colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: dense ? text.titleSmall : text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${_distance(item.km)} away · ${item.live ? 'live GPS' : 'estimated from timetable'}', style: text.bodySmall),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${item.minutes} min', style: (dense ? text.titleSmall : text.titleMedium)?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
            Text('to you', style: text.labelSmall),
          ]),
        ]),
      ),
    );
  }
}

/// Full-screen live map: every bus, electric car and the rider's own ride, with distance and ETA.
class LiveMapPage extends StatefulWidget {
  const LiveMapPage({super.key});

  @override
  State<LiveMapPage> createState() => _LiveMapPageState();
}

class _LiveMapPageState extends State<LiveMapPage> with _LiveTicker {
  NearbyKind? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => startTicking());
  }

  void _open(NearbyVehicle v) {
    if (v.kind == NearbyKind.myRide) {
      final b = context.read<AppState>().upcomingTrips.where((b) => b.vehicleId == v.vehicle.id).firstOrNull;
      if (b != null) context.push('/ticket/${b.id}');
    } else if (v.kind == NearbyKind.bus && v.route != null) {
      context.push('/ride/${v.route!.id}');
    } else {
      context.push('/ev');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final located = state.here != null && inFct(state.here!);
    final here = located ? state.here! : abujaCentre;
    final all = nearbyVehicles(state, here);
    final list = [for (final v in all) if (_filter == null || v.kind == _filter) v];
    final kinds = {for (final v in all) v.kind}.toList()..sort((a, b) => a.index.compareTo(b.index));
    final wide = isWide(context, 980);

    final listPanel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(located ? 'Near ${state.hereName ?? 'you'}' : 'Around Central Area', style: text.titleLarge),
          Text(
            located ? '${list.length} vehicles · minutes are door-to-door estimates in city traffic' : (state.locating ? 'Finding your location…' : 'Location is off, so distances are from the city centre.'),
            style: text.bodySmall,
          ),
          if (!located && !state.locating)
            TextButton.icon(onPressed: () => state.locate(force: true), icon: const Icon(Icons.my_location_rounded, size: 18), label: const Text('Use my location')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
            for (final k in kinds) ChoiceChip(label: Text(k.label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
          ]),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? const EmptyState(icon: Icons.directions_bus_rounded, title: 'Nothing nearby right now', message: 'Vehicles appear here as they come into service.')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _NearbyRow(item: list[i], onTap: () => _open(list[i])),
              ),
      ),
    ]);

    final map = _LiveMap(here: here, vehicles: list, located: located, onTap: _open);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/app'),
        title: const Text('Live map'),
        actions: [IconButton(tooltip: 'Find me again', onPressed: () => state.locate(force: true), icon: const Icon(Icons.my_location_rounded))],
      ),
      body: DataGate(
        builder: (context) => wide
            ? Row(children: [
                Expanded(flex: 3, child: map),
                Container(width: 380, decoration: const BoxDecoration(color: AppColors.surface, border: Border(left: BorderSide(color: AppColors.line))), child: listPanel),
              ])
            : Column(children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.45, child: map),
                Expanded(child: ColoredBox(color: AppColors.surface, child: listPanel)),
              ]),
      ),
    );
  }
}
