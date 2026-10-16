import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/theme.dart';
import '../core/models.dart';

/// Map provider settings in one place so a commercial tile service can be swapped in.
abstract final class MapTiles {
  /// Tests and offline builds switch network tiles off; the route still draws.
  static bool enabled = true;
  static const urlTemplate = 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  static const subdomains = ['a', 'b', 'c', 'd'];
}

/// Real map of the route: the line in brand green with its named stops.
class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.stops, this.interactive = true, this.padding = const EdgeInsets.fromLTRB(56, 72, 150, 56)});
  final List<RouteStop> stops;
  final bool interactive;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
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
          PolylineLayer(polylines: [
            Polyline(points: points, strokeWidth: 6, color: AppColors.forest, borderStrokeWidth: 2.5, borderColor: Colors.white),
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
          const RichAttributionWidget(
            showFlutterMapAttribution: false,
            alignment: AttributionAlignment.bottomRight,
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
              TextSourceAttribution('CARTO'),
            ],
          ),
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
