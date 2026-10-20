import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/theme.dart';
import '../core/api_client.dart' show apiBase, cleanPath;
import '../core/models.dart';

/// Map provider settings in one place so a commercial tile service can be swapped in.
abstract final class MapTiles {
  /// Tests and offline builds switch network tiles off; the route still draws.
  static bool enabled = true;

  /// Tiles come through our server, which adds the CARTO key (kept secret) and caches them.
  static String get urlTemplate => '${apiBase()}/api/tiles/{z}/{x}/{y}{r}.png';
  static const subdomains = <String>[];

  /// Credit line for whichever provider is serving tiles (set from /api/config).
  static final attribution = ValueNotifier<String>('© OpenStreetMap contributors');
}

/// The map credit the tile providers require, bottom-right on every map.
class MapCredit extends StatelessWidget {
  const MapCredit({super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xD9FFFFFF), borderRadius: BorderRadius.all(Radius.circular(4))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: ValueListenableBuilder<String>(
                valueListenable: MapTiles.attribution,
                builder: (context, text, _) => Text(text, style: const TextStyle(fontSize: 10, color: AppColors.inkSoft)),
              ),
            ),
          ),
        ),
      );
}

/// Real map of the route: the line in brand green with its named stops.
/// [roadPath], when given, swaps the straight stop-to-stop line for the road geometry.
class RouteMap extends StatefulWidget {
  const RouteMap({super.key, required this.stops, this.interactive = true, this.padding = const EdgeInsets.fromLTRB(56, 72, 150, 56), this.roadPath});
  final List<RouteStop> stops;
  final bool interactive;
  final EdgeInsets padding;
  final Future<List<LatLng>?> Function(List<LatLng> stops)? roadPath;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  List<LatLng>? _road;

  @override
  void initState() {
    super.initState();
    final stops = [for (final s in widget.stops) LatLng(s.lat, s.lng)];
    if (MapTiles.enabled && widget.roadPath != null && stops.length > 1) {
      widget.roadPath!(stops).then((road) {
        if (mounted && road != null && road.length > 1) setState(() => _road = road);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.stops;
    final interactive = widget.interactive;
    final padding = widget.padding;
    final points = [for (final s in stops) LatLng(s.lat, s.lng)];
    final last = points.length - 1;
    return Semantics(
      label: 'Map of the route through ${stops.map((s) => s.name).join(', ')}',
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: padding, maxZoom: 15) : null,
          initialCenter: points.isEmpty ? const LatLng(9.0579, 7.4951) : points.first,
          initialZoom: 12.5,
          backgroundColor: const Color(0xFFEAF1EC),
          interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
        ),
        children: [
          if (MapTiles.enabled)
            TileLayer(
              urlTemplate: MapTiles.urlTemplate,
              subdomains: MapTiles.subdomains,
              retinaMode: RetinaMode.isHighDensity(context),
              userAgentPackageName: 'com.taparide.app',
            ),
          PolylineLayer(simplificationTolerance: 0, polylines: [
            Polyline(points: _road ?? cleanPath(points), strokeWidth: 6, color: AppColors.forest, borderStrokeWidth: 2.5, borderColor: Colors.white),
          ]),
          // Stop names sit to the right of each stop so the route reads even without tiles.
          MarkerLayer(markers: [
            for (var i = 0; i < points.length; i++)
              Marker(
                point: points[i],
                width: 150,
                height: 26,
                alignment: Alignment.centerRight,
                child: _StopLabel(name: stops[i].name, emphasised: i == 0 || i == last),
              ),
          ]),
          MarkerLayer(markers: [
            for (var i = 0; i < points.length; i++)
              Marker(
                point: points[i],
                width: i == last ? 40 : (i == 0 ? 22 : 14),
                height: i == last ? 40 : (i == 0 ? 22 : 14),
                alignment: i == last ? Alignment.topCenter : Alignment.center,
                child: i == last ? const _DestinationPin() : _StopDot(start: i == 0),
              ),
          ]),
          // Tile credit, always visible as the providers require.
          const MapCredit(),
        ],
      ),
    );
  }
}

class _StopLabel extends StatelessWidget {
  const _StopLabel({required this.name, required this.emphasised});
  final String name;
  final bool emphasised;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 16),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: emphasised ? FontWeight.w800 : FontWeight.w600, color: AppColors.ink),
          ),
        ),
      );
}

class _StopDot extends StatelessWidget {
  const _StopDot({required this.start});
  final bool start;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.forest, width: start ? 5 : 3),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
      );
}

class _DestinationPin extends StatelessWidget {
  const _DestinationPin();

  @override
  Widget build(BuildContext context) => const Icon(
        Icons.location_on_rounded,
        color: AppColors.forest,
        size: 40,
        shadows: [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
      );
}
