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
  static const attribution = '© OpenStreetMap contributors © CARTO';
}

/// Real map of the route: the line in brand green with its stops.
class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.stops, this.interactive = true, this.padding = const EdgeInsets.all(56)});
  final List<RouteStop> stops;
  final bool interactive;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final points = [for (final s in stops) LatLng(s.lat, s.lng)];
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
          MarkerLayer(markers: [
            for (var i = 0; i < points.length; i++)
              Marker(
                point: points[i],
                width: i == points.length - 1 ? 40 : 22,
                height: i == points.length - 1 ? 40 : 22,
                alignment: i == points.length - 1 ? Alignment.topCenter : Alignment.center,
                child: i == points.length - 1 ? const _DestinationPin() : _StopDot(start: i == 0),
              ),
          ]),
          const SimpleAttributionWidget(
            source: Text(MapTiles.attribution, style: TextStyle(fontSize: 10)),
            backgroundColor: Color(0xCCFFFFFF),
            alignment: Alignment.topRight,
          ),
        ],
      ),
    );
  }
}

class _StopDot extends StatelessWidget {
  const _StopDot({required this.start});
  final bool start;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.forest, width: start ? 5 : 3.5),
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
