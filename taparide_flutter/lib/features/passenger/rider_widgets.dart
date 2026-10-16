import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';

/// A route in a list: the route line, fare, time and next departures.
class RouteRow extends StatelessWidget {
  const RouteRow({super.key, required this.route, required this.onTap, this.providerName, this.showDepartures = true});
  final TransitRoute route;
  final VoidCallback onTap;
  final String? providerName;
  final bool showDepartures;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final next = route.upcomingDepartures(DateTime.now(), count: 3);
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      onTap: onTap,
      semanticLabel: '${route.title}, ${Fmt.naira(route.fare)}, ${Fmt.minutes(route.durationMin)}',
      child: Row(children: [
        IconBadge(route.mode.icon, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (route.name != null) ...[
              Text(route.name!, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${route.origin} – ${route.destination}', style: text.bodySmall),
            ] else
              RouteStrip(origin: route.origin, destination: route.destination, stops: 2, dense: true),
            const SizedBox(height: 6),
            Text(
              [
                Fmt.minutes(route.durationMin),
                if (showDepartures && next.isNotEmpty) next.map(Fmt.time).join(', '),
                if (providerName != null) providerName!,
              ].join(' · '),
              style: text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Text(Fmt.naira(route.fare), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink, fontFeatures: tabular)),
        if (MediaQuery.sizeOf(context).width >= 420) const Icon(Icons.chevron_right_rounded, color: AppColors.faint) else const SizedBox(width: 4),
      ]),
    );
  }
}

/// The rider's Tap Card (wallet), styled like the mockup's green card.
class TapCardView extends StatelessWidget {
  const TapCardView({super.key, required this.wallet, this.selected = false, this.onTap, this.trailing});
  final Wallet? wallet;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final w = wallet;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: 'Tap card, balance ${w == null ? 'loading' : Fmt.naira(w.balance)}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: selected ? AppColors.leaf : Colors.transparent, width: 3),
        ),
        child: Material(
          borderRadius: BorderRadius.circular(AppRadius.xl - 2),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0E6B45), AppColors.forestDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Tap Card', style: text.titleLarge?.copyWith(color: Colors.white)),
                    const Spacer(),
                    if (trailing != null) trailing! else const Icon(Icons.contactless_rounded, color: Colors.white, size: 30),
                  ]),
                  const SizedBox(height: 22),
                  Text('Balance', style: text.labelSmall?.copyWith(color: AppColors.onForestMuted)),
                  const SizedBox(height: 2),
                  Text(w == null ? '—' : Fmt.naira(w.balance), style: text.headlineLarge?.copyWith(color: Colors.white, fontFeatures: tabular)),
                  const SizedBox(height: 10),
                  Text(w == null ? '' : 'Card ${w.maskedCard}', style: text.labelMedium?.copyWith(color: AppColors.onForestMuted, letterSpacing: 1)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TicketQr extends StatelessWidget {
  const TicketQr({super.key, required this.data, this.size = 200});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Boarding QR code',
        image: true,
        child: QrImageView(
          data: data,
          size: size,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.ink),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.ink),
        ),
      );
}

/// Bottom sheet to add money to the tap card.
Future<void> showTopUpSheet(BuildContext context, {int? suggested}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => _TopUpSheet(suggested: suggested),
  );
}

class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet({this.suggested});
  final int? suggested;

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  late int _amount = widget.suggested == null ? 2000 : ((widget.suggested! / 500).ceil() * 500).clamp(500, 50000);
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = context.watch<AppState>();
    const options = [500, 1000, 2000, 5000, 10000];
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Top up your Tap Card', style: text.headlineSmall),
        const SizedBox(height: 6),
        Text('Current balance ${Fmt.naira(state.wallet?.balance ?? 0)}', style: text.bodyMedium),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in {...options, _amount}.toList()..sort())
            ChoiceChip(
              label: Text(Fmt.naira(o)),
              selected: _amount == o,
              onSelected: (_) => setState(() => _amount = o),
              labelStyle: TextStyle(color: _amount == o ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
            ),
        ]),
        const SizedBox(height: 14),
        if (state.backend.isDemo)
          Text('Demo mode: no real money moves. A live build connects a payment provider here.', style: text.bodySmall),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await attemptOk(context, () => context.read<AppState>().topUp(_amount), success: '${Fmt.naira(_amount)} added to your Tap Card');
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (ok) Navigator.of(context).pop();
                },
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text('Add ${Fmt.naira(_amount)}'),
        ),
      ]),
    );
  }
}

/// "Tap & Pay": the rider's card and the QR that identifies it at terminals.
Future<void> showTapAndPaySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final state = sheet.watch<AppState>();
      final text = Theme.of(sheet).textTheme;
      final wallet = state.wallet;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Tap & Pay', style: text.headlineSmall),
          const SizedBox(height: 14),
          TapCardView(wallet: wallet),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: text.labelMedium)),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 14),
          Center(child: TicketQr(data: 'TAPARIDE:CARD:${wallet?.cardNumber ?? ''}', size: 180)),
          const SizedBox(height: 12),
          Text('Scan to Pay', style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Show this QR code to the conductor or at the terminal.', style: text.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: () => showTopUpSheet(sheet), icon: const Icon(Icons.add_rounded), label: const Text('Top up card')),
        ]),
      );
    },
  );
}

class BookingTile extends StatelessWidget {
  const BookingTile({super.key, required this.booking, required this.onTap});
  final Booking booking;
  final VoidCallback onTap;

  static Tone toneFor(BookingStatus status) => switch (status) {
        BookingStatus.confirmed || BookingStatus.accepted => Tone.success,
        BookingStatus.requested => Tone.warning,
        BookingStatus.completed => Tone.neutral,
        BookingStatus.cancelled || BookingStatus.declined => Tone.danger,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      semanticLabel: '${booking.kind.label} ${booking.origin} to ${booking.destination}, ${booking.status.label}',
      child: Row(children: [
        IconBadge(booking.kind.icon, size: 42, color: booking.status.isOpen ? AppColors.mint : AppColors.surfaceSunk, iconColor: booking.status.isOpen ? AppColors.forest : AppColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RouteStrip(origin: booking.origin, destination: booking.destination, dense: true, color: booking.status.isOpen ? AppColors.forest : AppColors.faint),
            const SizedBox(height: 6),
            Text('${Fmt.dayTime(booking.departureAt)} · ${booking.kind.label}', style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Fmt.naira(booking.fare), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular)),
          const SizedBox(height: 6),
          StatusPill(booking.status.label, tone: toneFor(booking.status)),
        ]),
      ]),
    );
  }
}
