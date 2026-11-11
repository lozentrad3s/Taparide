import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart' show apiBase, cleanPath;
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../core/models.dart';
import '../../shared/brand.dart';
import '../../shared/route_map.dart';
import '../../shared/ui.dart';

/// The link a rider sends to a trusted contact. On the web it points at this site.
String tripShareUrl(String token) => '${apiBase()}/#/trip/$token';

/// "Share my ride": opened by a trusted contact from a link, with no account needed.
/// Shows who is travelling, the verified vehicle and driver, and where they are now.
class SharedTripPage extends StatefulWidget {
  const SharedTripPage({super.key, required this.token});
  final String token;

  @override
  State<SharedTripPage> createState() => _SharedTripPageState();
}

class _SharedTripPageState extends State<SharedTripPage> {
  SharedTrip? _trip;
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final trip = await context.read<AppState>().backend.fetchSharedTrip(widget.token);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _loading = false;
        _error = null;
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Keep showing the last known trip if a refresh fails.
        if (_trip == null) _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final trip = _trip;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 18,
        title: const BrandLockup(height: 26),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)), const SizedBox(width: 6)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : trip == null
              ? EmptyState(
                  icon: Icons.link_off_rounded,
                  title: _error == null ? 'This trip link has ended' : 'Could not load this trip',
                  message: _error ?? 'Shared trips close a few hours after the ride, or when the rider stops sharing.',
                  action: 'Try again',
                  onAction: _load,
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    MaxWidth(
                      width: 620,
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('${trip.passenger} is sharing this trip with you', style: text.headlineSmall),
                        const SizedBox(height: 4),
                        Text('Updates on its own every 20 seconds.', style: text.bodySmall),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: SizedBox(height: 300, child: TripMap(stops: trip.stops, rider: trip.rider, vehicle: trip.vehiclePoint)),
                        ),
                        const SizedBox(height: 8),
                        _LocationLine(trip: trip),
                        const SizedBox(height: 16),
                        Panel(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(trip.kind.icon, size: 20, color: AppColors.forest),
                              const SizedBox(width: 8),
                              Text(trip.kind.label, style: text.labelLarge),
                              const Spacer(),
                              StatusPill(trip.status.label, tone: trip.status.isOpen ? Tone.success : Tone.neutral),
                            ]),
                            const SizedBox(height: 14),
                            RouteStrip(origin: trip.origin, destination: trip.destination),
                            const SizedBox(height: 12),
                            _Row(icon: Icons.schedule_rounded, label: 'Departs', value: Fmt.dayTime(trip.departureAt)),
                            if (trip.operatorName != null)
                              _Row(icon: Icons.business_rounded, label: 'Operator', value: trip.operatorName!, pill: trip.operatorVerified ? 'Verified' : null),
                            if (trip.vehicle != null)
                              _Row(icon: Icons.directions_car_rounded, label: 'Vehicle', value: trip.vehicle!, pill: trip.vehicleVerified ? 'On FCTA register' : null),
                            if (trip.driver != null) _Row(icon: Icons.badge_outlined, label: trip.kind == BookingKind.tagAlong ? 'Host' : 'Driver', value: trip.driver!),
                            _Row(icon: Icons.confirmation_number_outlined, label: 'Ticket', value: trip.ticketCode),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: '112')),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.redSoft, width: 1.5), minimumSize: const Size.fromHeight(48)),
                          icon: const Icon(Icons.sos_rounded, size: 18),
                          label: const Text('Call emergency 112'),
                        ),
                        const SizedBox(height: 10),
                        Text('Only people with this link can see this page. It closes at ${Fmt.dayTime(trip.expiresAt)}.', style: text.bodySmall, textAlign: TextAlign.center),
                      ]),
                    ),
                  ],
                ),
    );
  }
}

class _LocationLine extends StatelessWidget {
  const _LocationLine({required this.trip});
  final SharedTrip trip;

  static String _ago(DateTime at) {
    final s = DateTime.now().difference(at).inSeconds;
    return s < 60 ? 'just now' : (s < 3600 ? '${s ~/ 60} min ago' : '${s ~/ 3600} h ago');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parts = [
      if (trip.riderLocatedAt != null) '${trip.passenger}\'s phone: ${_ago(trip.riderLocatedAt!)}',
      if (trip.vehicleLocatedAt != null) 'Vehicle GPS: ${_ago(trip.vehicleLocatedAt!)}',
    ];
    return Row(children: [
      Icon(parts.isEmpty ? Icons.location_off_outlined : Icons.my_location_rounded, size: 16, color: parts.isEmpty ? AppColors.muted : AppColors.leafText),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          parts.isEmpty ? 'No live location yet. It appears once ${trip.passenger} has the app open or the vehicle reports GPS.' : parts.join(' · '),
          style: text.bodySmall,
        ),
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value, this.pill});
  final IconData icon;
  final String label;
  final String value;
  final String? pill;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 10),
        SizedBox(width: 72, child: Text(label, style: text.bodySmall)),
        Expanded(child: Text(value, style: text.titleSmall)),
        if (pill != null) StatusPill(pill!, tone: Tone.success, icon: Icons.verified_rounded),
      ]),
    );
  }
}

/// A trip on the map: the route's stops, the rider's phone and the vehicle's GPS when known.
class TripMap extends StatelessWidget {
  const TripMap({super.key, required this.stops, this.rider, this.vehicle});
  final List<RouteStop> stops;
  final LatLng? rider;
  final LatLng? vehicle;

  @override
  Widget build(BuildContext context) {
    final line = cleanPath([for (final s in stops) LatLng(s.lat, s.lng)]);
    final points = [...line, if (rider != null) rider!, if (vehicle != null) vehicle!];
    return Stack(children: [
      FlutterMap(
        // Re-fit when a first location arrives.
        key: ValueKey('${points.length}'),
        options: MapOptions(
          initialCameraFit: points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 15) : null,
          initialCenter: points.isEmpty ? const LatLng(9.0579, 7.4951) : points.first,
          initialZoom: points.length == 1 ? 14.5 : 12,
          backgroundColor: const Color(0xFFEAF1EC),
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.scrollWheelZoom),
        ),
        children: [
          if (MapTiles.enabled)
            TileLayer(urlTemplate: MapTiles.urlTemplate, subdomains: MapTiles.subdomains, retinaMode: RetinaMode.isHighDensity(context), userAgentPackageName: 'com.taparide.app'),
          if (line.length > 1)
            PolylineLayer(simplificationTolerance: 0, polylines: [
              Polyline(points: line, strokeWidth: 5, color: AppColors.forest, borderStrokeWidth: 2, borderColor: Colors.white),
            ]),
          MarkerLayer(markers: [
            for (final (i, p) in line.indexed)
              Marker(
                point: p,
                width: 14,
                height: 14,
                child: Container(decoration: BoxDecoration(color: i == line.length - 1 ? AppColors.leaf : Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.forest, width: 3))),
              ),
            if (vehicle != null) Marker(point: vehicle!, width: 40, height: 40, child: const _Pin(icon: Icons.directions_bus_rounded, color: AppColors.forest, label: 'Vehicle')),
            if (rider != null) Marker(point: rider!, width: 40, height: 40, child: const _Pin(icon: Icons.person_rounded, color: AppColors.blue, label: 'Rider')),
          ]),
        ],
      ),
      const MapCredit(),
    ]);
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label location',
        child: Container(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: AppShadow.card),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}

/// Bottom sheet on the ticket: switch the private link on, copy it, or stop sharing.
Future<void> showShareTripSheet(BuildContext context, Booking booking) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _ShareTripSheet(booking: booking));

class _ShareTripSheet extends StatefulWidget {
  const _ShareTripSheet({required this.booking});
  final Booking booking;

  @override
  State<_ShareTripSheet> createState() => _ShareTripSheetState();
}

class _ShareTripSheetState extends State<_ShareTripSheet> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (context.read<AppState>().tripShares[widget.booking.id] == null) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().shareTrip(widget.booking);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final share = state.tripShares[widget.booking.id];
    final url = share == null ? null : tripShareUrl(share.token);
    final message = url == null ? '' : 'Follow my Tap A Ride trip from ${widget.booking.origin} to ${widget.booking.destination}: $url';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Share my ride', style: text.headlineSmall),
        const SizedBox(height: 6),
        Text('Send this private link to someone you trust. They see your trip, the verified vehicle and driver, and where you are, without needing an account.', style: text.bodyMedium),
        const SizedBox(height: 16),
        if (_busy && share == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: CircularProgressIndicator()))
        else if (share == null)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_error ?? 'Sharing is off.', style: TextStyle(color: _error == null ? AppColors.muted : AppColors.red, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _start, child: const Text('Turn on sharing')),
          ])
        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(children: [
              const Icon(Icons.link_rounded, color: AppColors.forest, size: 20),
              const SizedBox(width: 10),
              Expanded(child: SelectableText(url!, style: text.bodySmall?.copyWith(color: AppColors.forestDeep), maxLines: 2)),
            ]),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (context.mounted) showMessage(context, 'Link copied. Paste it in a message to your contact.');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy link'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('WhatsApp'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri(scheme: 'sms', queryParameters: {'body': message})),
                icon: const Icon(Icons.sms_outlined, size: 18),
                label: const Text('SMS'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.my_location_rounded, size: 16, color: AppColors.leafText),
            const SizedBox(width: 6),
            Expanded(child: Text('Your location is sent while Tap A Ride is open. The link closes at ${Fmt.dayTime(share.expiresAt)}.', style: text.bodySmall)),
          ]),
          TextButton(
            onPressed: () async {
              final ok = await attemptOk(context, () => state.stopSharingTrip(widget.booking), success: 'Sharing stopped. The link no longer works.');
              if (ok && context.mounted) Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Stop sharing'),
          ),
        ],
      ]),
    );
  }
}
