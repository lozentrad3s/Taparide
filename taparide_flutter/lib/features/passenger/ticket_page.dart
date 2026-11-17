import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';
import '../share/shared_trip_page.dart';
import 'rider_widgets.dart';

/// Boarding pass for a transit seat, EV ride or Tag Along request.
class TicketPage extends StatelessWidget {
  const TicketPage({super.key, required this.bookingId});
  final String bookingId;

  Future<void> _cancel(BuildContext context, Booking booking) async {
    final refund = booking.paymentMethod != PaymentMethod.splitCost;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(booking.kind == BookingKind.tagAlong ? 'Withdraw your request?' : 'Cancel this booking?'),
        content: Text(refund ? '${Fmt.naira(booking.fare)} goes back to your Tap Card straight away.' : 'The host will be told you are no longer joining.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(booking.kind == BookingKind.tagAlong ? 'Withdraw' : 'Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await attemptOk(context, () => context.read<AppState>().cancelBooking(booking),
        success: refund ? 'Booking cancelled · ${Fmt.naira(booking.fare)} refunded' : 'Request withdrawn');
  }

  Future<void> _share(BuildContext context, Booking booking, Vehicle? vehicle) async {
    // Upcoming trips get a private live link; finished ones just copy the details.
    if (booking.status.isOpen) return showShareTripSheet(context, booking);
    final details = [
      'My Tap A Ride trip: ${booking.origin} → ${booking.destination}',
      Fmt.dayTime(booking.departureAt),
      if (vehicle != null) 'Vehicle: ${vehicle.displayName}${vehicle.driverName == null ? '' : ' · driver ${vehicle.driverName}'}',
      'Ticket ${booking.ticketCode}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: details));
    if (context.mounted) showMessage(context, 'Trip details copied. Paste them to a friend or family member.');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final booking = state.bookingById(bookingId);
    if (booking == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(fallback: '/app/trips'), title: const Text('Ticket')),
        body: EmptyState(
            icon: Icons.confirmation_number_outlined,
            title: 'Ticket not found',
            message: 'It may belong to another account.',
            action: 'My trips',
            onAction: () => context.go('/app/trips')),
      );
    }
    final vehicle = state.vehicleById(booking.vehicleId);
    final route = state.routeById(booking.routeId);
    final provider = state.providerById(booking.providerId ?? route?.providerId ?? vehicle?.operatorId);
    final ride = booking.rideId == null ? null : state.rides.where((r) => r.id == booking.rideId).firstOrNull;
    final open = booking.status.isOpen;
    final showQr = open && booking.kind != BookingKind.tagAlong;

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(fallback: '/app/trips'), title: Text(booking.kind == BookingKind.tagAlong ? 'Tag Along' : 'Your ticket')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: MaxWidth(
            width: 520,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    color: open ? AppColors.forest : AppColors.inkSoft,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(booking.kind.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(booking.title ?? booking.kind.label, style: text.labelLarge?.copyWith(color: Colors.white)),
                        const Spacer(),
                        StatusPill(booking.statusLabel,
                            tone: open ? (booking.status == BookingStatus.requested ? Tone.warning : Tone.success) : BookingTile.toneFor(booking.status)),
                      ]),
                      const SizedBox(height: 16),
                      RouteStrip(origin: booking.origin, destination: booking.destination, color: AppColors.leaf, textColor: Colors.white),
                      const SizedBox(height: 16),
                      Wrap(spacing: 28, runSpacing: 12, children: [
                        _Fact(label: booking.kind == BookingKind.electric ? 'Pickup' : 'Departs', value: Fmt.dayTime(booking.departureAt)),
                        if (booking.seat != null) _Fact(label: 'Seat', value: booking.seat!),
                        _Fact(label: booking.kind == BookingKind.tagAlong ? 'Your share' : 'Fare paid', value: Fmt.naira(booking.fare)),
                      ]),
                    ]),
                  ),
                  _Perforation(color: open ? AppColors.forest : AppColors.inkSoft),
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      if (showQr) ...[
                        TicketQr(data: booking.qrPayload, size: 210),
                        const SizedBox(height: 12),
                        Text(booking.ticketCode, style: text.titleLarge?.copyWith(letterSpacing: 2, fontFeatures: tabular)),
                        const SizedBox(height: 4),
                        Text('Show this code to the conductor or tap your card at the terminal.', style: text.bodySmall, textAlign: TextAlign.center),
                      ] else if (booking.kind == BookingKind.tagAlong) ...[
                        Icon(booking.status == BookingStatus.accepted ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                            color: AppColors.forest, size: 40),
                        const SizedBox(height: 10),
                        Text(
                          switch (booking.status) {
                            BookingStatus.requested => 'Waiting for ${ride?.hostName ?? 'the host'} to accept. Hosts usually reply within minutes.',
                            BookingStatus.accepted => '${ride?.hostName ?? 'The host'} accepted. Meet at ${booking.origin} a few minutes before departure.',
                            _ => 'This request is ${booking.status.label.toLowerCase()}.',
                          },
                          style: text.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ] else
                        Text('This ticket is ${booking.status.label.toLowerCase()}.', style: text.bodyMedium),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Trip details', style: text.titleMedium),
                  const SizedBox(height: 8),
                  if (provider != null)
                    _DetailRow(
                        icon: Icons.business_rounded,
                        label: 'Operator',
                        value: provider.name,
                        trailing:
                            provider.status == Verification.verified ? const StatusPill('Verified', tone: Tone.success, icon: Icons.verified_rounded) : null),
                  if (vehicle != null)
                    _DetailRow(
                        icon: vehicle.kind.icon,
                        label: 'Vehicle',
                        value: vehicle.displayName,
                        trailing: vehicle.verification == Verification.verified ? const StatusPill('On FCTA register', tone: Tone.success) : null),
                  if (vehicle?.driverName != null) _DetailRow(icon: Icons.badge_outlined, label: 'Driver', value: vehicle!.driverName!),
                  if (ride != null) ...[
                    _DetailRow(icon: Icons.person_rounded, label: 'Host', value: '${ride.hostName} · ${ride.hostOrg}'),
                    _DetailRow(icon: Icons.directions_car_rounded, label: 'Car', value: ride.vehicleLabel),
                  ],
                  _DetailRow(icon: Icons.payments_outlined, label: 'Payment', value: booking.paymentMethod.label),
                ]),
              ),
              if (open && booking.vehicleId != null) _LiveVehicle(booking: booking, stops: route?.stops ?? const []),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => _share(context, booking, vehicle),
                        icon: Icon(state.tripShares.containsKey(booking.id) ? Icons.share_location_rounded : Icons.ios_share_rounded, size: 18),
                        label: Text(state.tripShares.containsKey(booking.id) ? 'Sharing on' : (open ? 'Share my ride' : 'Share trip')))),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: '112')),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.redSoft, width: 1.5)),
                    icon: const Icon(Icons.sos_rounded, size: 18),
                    label: const Text('Emergency 112'),
                  ),
                ),
              ]),
              if (open) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _cancel(context, booking),
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  child: Text(booking.kind == BookingKind.tagAlong ? 'Withdraw request' : 'Cancel booking'),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The booked vehicle on the map while its driver's device is reporting GPS.
class _LiveVehicle extends StatefulWidget {
  const _LiveVehicle({required this.booking, required this.stops});
  final Booking booking;
  final List<RouteStop> stops;

  @override
  State<_LiveVehicle> createState() => _LiveVehicleState();
}

class _LiveVehicleState extends State<_LiveVehicle> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) => state.refreshPositions());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => state.refreshPositions());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final live = state.livePosition(widget.booking.vehicleId);
    if (live == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          const Icon(Icons.schedule_rounded, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text('Running to timetable. The live position shows here when the driver\'s device is reporting.', style: text.bodySmall)),
        ]),
      );
    }
    final seconds = state.now.difference(live.updatedAt).inSeconds;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Panel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
            child: SizedBox(height: 220, child: TripMap(stops: widget.stops, vehicle: live.point)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.leaf, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text('Live vehicle position · updated ${seconds < 60 ? 'just now' : '${seconds ~/ 60} min ago'}', style: text.labelMedium)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: AppColors.onForestMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, fontFeatures: tabular)),
      ]);
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value, this.trailing});
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 10),
        SizedBox(width: 78, child: Text(label, style: text.bodySmall)),
        Expanded(child: Text(value, style: text.titleSmall)),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Tear-off edge between the ticket stub and its QR half.
class _Perforation extends StatelessWidget {
  const _Perforation({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 18,
        child: CustomPaint(painter: _PerforationPainter(color), size: const Size(double.infinity, 18)),
      );
}

class _PerforationPainter extends CustomPainter {
  _PerforationPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height / 2), Paint()..color = color);
    canvas.drawRect(Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2), Paint()..color = Colors.white);
    final notch = Paint()..color = AppColors.ground;
    canvas.drawCircle(Offset(0, size.height / 2), 11, notch);
    canvas.drawCircle(Offset(size.width, size.height / 2), 11, notch);
    final dash = Paint()
      ..color = AppColors.lineStrong
      ..strokeWidth = 1.5;
    for (var x = 18.0; x < size.width - 18; x += 12) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + 6, size.height / 2), dash);
    }
  }

  @override
  bool shouldRepaint(covariant _PerforationPainter old) => old.color != color;
}
