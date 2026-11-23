import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/account_models.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';

/// Whether a rider can ask for their money back on this booking (paid from the wallet, not yet
/// refunded or cancelled, within 14 days). Tag Along shares are returned by withdrawing instead.
bool canRequestRefund(Booking b) =>
    b.paidFromWallet &&
    b.kind != BookingKind.tagAlong &&
    b.refundedAt == null &&
    b.status != BookingStatus.cancelled &&
    b.status != BookingStatus.declined &&
    b.createdAt.isAfter(DateTime.now().subtract(const Duration(days: 14)));

/// Refund status (or the button to ask for one) under a ticket.
class RefundSection extends StatelessWidget {
  const RefundSection({super.key, required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final request = state.refundFor(booking.id);
    if (booking.refundedAt != null) {
      return _Box(
        tone: Tone.success,
        icon: Icons.check_circle_rounded,
        title: 'Refunded',
        body: '${Fmt.naira(booking.fare)} went back to your Tap Card on ${Fmt.dayTime(booking.refundedAt!)}.${request?.adminNote == null ? '' : ' ${request!.adminNote}'}',
      );
    }
    if (request != null && request.status == RefundStatus.pending) {
      return _Box(
        tone: Tone.info,
        icon: Icons.hourglass_top_rounded,
        title: 'Refund requested',
        body: 'We are looking at it, usually within a day. If approved, ${Fmt.naira(request.amount)} goes back to your Tap Card.',
      );
    }
    if (request != null && request.status == RefundStatus.declined) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Box(
          tone: Tone.danger,
          icon: Icons.info_outline_rounded,
          title: 'Refund declined',
          body: request.adminNote?.isNotEmpty == true ? request.adminNote! : 'This booking does not qualify for a refund. Message us on WhatsApp if you think that is wrong.',
        ),
      ]);
    }
    if (!canRequestRefund(booking)) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: () => showRefundSheet(context, booking),
        icon: const Icon(Icons.undo_rounded, size: 18),
        label: Text('Something went wrong? Request a refund', style: text.labelLarge),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.tone, required this.icon, required this.title, required this.body});
  final Tone tone;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = StatusPill.colors(tone);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleSmall?.copyWith(color: fg)),
            const SizedBox(height: 2),
            Text(body, style: text.bodySmall?.copyWith(color: AppColors.inkSoft)),
          ]),
        ),
      ]),
    );
  }
}

/// Asks why, then sends the refund request.
Future<void> showRefundSheet(BuildContext context, Booking booking) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _RefundSheet(booking: booking),
  );
  if (sent == true && context.mounted) showMessage(context, 'Refund requested. We will let you know here.');
}

class _RefundSheet extends StatefulWidget {
  const _RefundSheet({required this.booking});
  final Booking booking;

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  static const _reasons = ['The bus or car never came', 'It left before the time on my ticket', 'I was charged twice', 'The trip was cancelled'];
  final _detail = TextEditingController();
  String? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final why = [if (_reason != null) _reason!, if (_detail.text.trim().isNotEmpty) _detail.text.trim()].join('. ');
    if (why.length < 5) return setState(() => _error = 'Pick a reason or tell us briefly what went wrong.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().requestRefund(widget.booking.id, why);
      if (mounted) Navigator.pop(context, true);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = widget.booking;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Request a refund', style: text.headlineSmall),
          const SizedBox(height: 4),
          Text('${b.title ?? '${b.origin} → ${b.destination}'} · ${Fmt.naira(b.fare)}', style: text.bodyMedium),
          const SizedBox(height: 14),
          Text('What happened?', style: text.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in _reasons) ChoiceChip(label: Text(r), selected: _reason == r, onSelected: (on) => setState(() => _reason = on ? r : null)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _detail,
            maxLines: 3,
            maxLength: 400,
            decoration: const InputDecoration(labelText: 'More detail (optional)', hintText: 'e.g. I waited at the stop until 7:30'),
          ),
          Text('A Tap A Ride reviewer checks every request. Approved refunds go back to your Tap Card.', style: text.bodySmall),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.red, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          FilledButton(onPressed: _busy ? null : _send, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: Text(_busy ? 'Sending…' : 'Send request')),
        ]),
      ),
    );
  }
}
