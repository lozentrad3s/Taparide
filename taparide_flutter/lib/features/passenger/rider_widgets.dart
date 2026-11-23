import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/coming_soon.dart';
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
      label: w == null ? 'Tap card, balance loading' : 'Tap card, wallet ${Fmt.naira(w.cash)}${w.rideCredit > 0 ? ', plus ${Fmt.naira(w.rideCredit)} ride credit, used first' : ''}',
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
                  Text('Wallet', style: text.labelSmall?.copyWith(color: AppColors.onForestMuted)),
                  const SizedBox(height: 2),
                  Text(w == null ? '—' : Fmt.naira(w.cash), style: text.headlineLarge?.copyWith(color: Colors.white, fontFeatures: tabular)),
                  if (w != null && w.rideCredit > 0) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.local_activity_rounded, size: 16, color: AppColors.leaf),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('+ ${Fmt.naira(w.rideCredit)} ride credit · used first',
                            style: text.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ],
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

/// "Ride reward granted": the website sign-up reward. It carries no money until full launch, so it
/// shows no amount. Riders whose email isn't on the website list see a short hint instead (if [hint]).
class RideRewardCard extends StatelessWidget {
  const RideRewardCard({super.key, this.hint = false});

  /// Show "Joined on taparide.com?" when this account has no reward.
  final bool hint;

  @override
  Widget build(BuildContext context) {
    final reward = context.watch<AppState>().signupReward;
    final text = Theme.of(context).textTheme;
    if (!reward.granted) {
      if (!hint) return const SizedBox.shrink();
      return Row(children: [
        const Icon(Icons.card_giftcard_rounded, size: 18, color: AppColors.muted),
        const SizedBox(width: 8),
        Expanded(child: Text('Joined on taparide.com? Use the same email for this account to get your ride reward.', style: text.bodySmall)),
      ]);
    }
    return Semantics(
      container: true,
      label: '${reward.label}. Your sign-up reward is saved to your account and unlocks at full launch.',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.mintStrong),
        ),
        child: ExcludeSemantics(
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: const Icon(Icons.card_giftcard_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(reward.label, style: text.titleMedium?.copyWith(color: AppColors.forestDeep, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 6),
                  const Icon(Icons.verified_rounded, size: 18, color: AppColors.leafText),
                ]),
                const SizedBox(height: 2),
                Text('Thanks for joining early. Your sign-up reward is saved to your account and unlocks at full launch.', style: text.bodySmall?.copyWith(color: AppColors.inkSoft)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
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
    if (!AppState.walletTopUpsOpen) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Adding money is coming soon', style: text.headlineSmall)),
            const SoonTag(),
          ]),
          const SizedBox(height: 8),
          Text(
            'Card and bank top-ups open shortly. We will let you know in the app the moment they are on.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ]),
      );
    }
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
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(state.realPayments ? Icons.lock_rounded : Icons.science_outlined, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.realPayments
                  ? 'You pay by card, bank transfer or USSD on the secure Bachs payment page, then come straight back here. Your card details never reach Tap A Ride.'
                  : 'Demo: this adds sample money on this device only. No real money moves.',
              style: text.bodySmall,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final app = context.read<AppState>();
                  if (app.realPayments) {
                    // Leave for the payment page; the app confirms the payment when the rider comes back.
                    final start = await attempt(context, () => app.api.startTopUp(_amount));
                    final url = start == null ? null : Uri.tryParse(start.url);
                    if (url != null && url.hasScheme) {
                      await launchUrl(url, webOnlyWindowName: '_self');
                    } else if (start != null && context.mounted) {
                      showMessage(context, 'The payment page could not be opened. Please try again.', error: true);
                    }
                    if (mounted) setState(() => _busy = false);
                    return;
                  }
                  final ok = await attemptOk(context, () => app.topUp(_amount), success: '${Fmt.naira(_amount)} added to your Tap Card');
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (ok) Navigator.of(context).pop();
                },
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(state.realPayments ? 'Pay ${Fmt.naira(_amount)}' : 'Add ${Fmt.naira(_amount)}'),
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
          if (AppState.walletTopUpsOpen)
            OutlinedButton.icon(onPressed: () => showTopUpSheet(sheet), icon: const Icon(Icons.add_rounded), label: const Text('Top up card'))
          else
            Text('Adding money by card or bank is coming soon.', style: text.bodySmall, textAlign: TextAlign.center),
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
      semanticLabel: '${booking.kind.label} ${booking.origin} to ${booking.destination}, ${booking.statusLabel}',
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
          StatusPill(booking.statusLabel, tone: toneFor(booking.status)),
        ]),
      ]),
    );
  }
}
