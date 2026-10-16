import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';
import 'rider_widgets.dart';

/// Payment step from the mockup: Tap Card, or a QR ticket shown to the conductor.
class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key, required this.routeId, required this.departure});
  final String routeId;
  final DateTime? departure;

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  PaymentMethod _method = PaymentMethod.tapCard;
  bool _busy = false;
  String? _error;

  Future<void> _confirm(TransitRoute route, DateTime at) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final booking = await context.read<AppState>().bookTransit(route, at, _method);
      if (!mounted) return;
      context.pushReplacement('/ticket/${booking.id}');
      showMessage(context, 'Seat booked · ${Fmt.naira(booking.fare)} paid');
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
    final route = state.routeById(widget.routeId);
    final at = widget.departure;
    final wallet = state.wallet;

    if (route == null || at == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(fallback: '/app/routes'), title: const Text('Payment')),
        body: EmptyState(
          icon: Icons.event_busy_rounded,
          title: 'Choose a departure first',
          message: 'Pick a route and a departure time, then come back here to pay.',
          action: 'Browse routes',
          onAction: () => context.go('/app/routes'),
        ),
      );
    }

    final short = wallet != null && wallet.balance < route.fare;

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(fallback: '/app/routes'), title: const Text('Payment')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              child: MaxWidth(
                width: 560,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Your trip', style: text.labelMedium?.copyWith(color: AppColors.muted)),
                      const SizedBox(height: 10),
                      RouteStrip(origin: route.origin, destination: route.destination, stops: route.stops.length),
                      const SizedBox(height: 12),
                      Row(children: [
                        const Icon(Icons.schedule_rounded, size: 16, color: AppColors.muted),
                        const SizedBox(width: 6),
                        Text(Fmt.dayTime(at), style: text.titleSmall),
                        const Spacer(),
                        Text(Fmt.naira(route.fare), style: text.titleLarge?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  Text('Pay with', style: text.titleLarge),
                  const SizedBox(height: 10),
                  TapCardView(
                    wallet: wallet,
                    selected: _method == PaymentMethod.tapCard,
                    onTap: () => setState(() => _method = PaymentMethod.tapCard),
                    trailing: Icon(_method == PaymentMethod.tapCard ? Icons.check_circle_rounded : Icons.contactless_rounded, color: _method == PaymentMethod.tapCard ? AppColors.leaf : Colors.white, size: 30),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: text.labelMedium)),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 14),
                  _QrOption(
                    selected: _method == PaymentMethod.qr,
                    onTap: () => setState(() => _method = PaymentMethod.qr),
                    cardNumber: wallet?.cardNumber ?? '',
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.go('/app/profile'),
                      icon: const Icon(Icons.credit_card_rounded, size: 18),
                      label: const Text('Manage Payment Methods'),
                    ),
                  ),
                  if (short) ...[
                    const SizedBox(height: 6),
                    _Notice(
                      tone: Tone.warning,
                      message: 'Your balance is ${Fmt.naira(wallet.balance)}. Top up at least ${Fmt.naira(route.fare - wallet.balance)} to pay for this seat.',
                      action: 'Top up',
                      onAction: () => showTopUpSheet(context, suggested: route.fare - wallet.balance),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _Notice(tone: Tone.danger, message: _error!),
                  ],
                ]),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: MaxWidth(
              width: 560,
              padding: EdgeInsets.zero,
              child: FilledButton(
                onPressed: _busy || short || wallet == null ? null : () => _confirm(route, at),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text('Confirm & pay ${Fmt.naira(route.fare)}'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _QrOption extends StatelessWidget {
  const _QrOption({required this.selected, required this.onTap, required this.cardNumber});
  final bool selected;
  final VoidCallback onTap;
  final String cardNumber;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Pay with QR code',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: selected ? AppColors.leaf : AppColors.line, width: selected ? 3 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: ExcludeSemantics(child: TicketQr(data: 'TAPARIDE:CARD:$cardNumber', size: 92)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Scan to Pay', style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text('Show this QR code to the conductor or at the terminal. The fare comes from your Tap Card balance.', style: text.bodySmall),
                ]),
              ),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? AppColors.forest : AppColors.faint),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.tone, required this.message, this.action, this.onAction});
  final Tone tone;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = StatusPill.colors(tone);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(children: [
        Icon(tone == Tone.danger ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: fg, fontWeight: FontWeight.w600, height: 1.35))),
        if (action != null) TextButton(onPressed: onAction, style: TextButton.styleFrom(foregroundColor: fg), child: Text(action!)),
      ]),
    );
  }
}
