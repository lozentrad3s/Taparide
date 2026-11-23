import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/account_models.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';
import 'portal_widgets.dart';

String _err(Object? e, String fallback) => e is BackendException ? e.message : fallback;

/// Asks for an optional (or required) note; null when cancelled.
Future<String?> _askNote(BuildContext context, {required String title, required String hint, required String confirm, bool required = false, bool danger = false}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            autofocus: true,
            maxLines: 3,
            maxLength: 300,
            onChanged: (_) => set(() {}),
            decoration: InputDecoration(hintText: hint, labelText: required ? 'Reason' : 'Note to the rider (optional)'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: required && c.text.trim().isEmpty ? null : () => Navigator.pop(d, c.text.trim()),
            style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.red) : null,
            child: Text(confirm),
          ),
        ],
      ),
    ),
  );
}

Uri? _whatsApp(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length < 10) return null;
  final intl = d.startsWith('234') ? d : '234${d.substring(d.length - 10)}';
  return Uri.parse('https://wa.me/$intl');
}

// ------------------------------------------------------------------ refunds

class RefundsPage extends StatefulWidget {
  const RefundsPage({super.key});

  @override
  State<RefundsPage> createState() => _RefundsPageState();
}

class _RefundsPageState extends State<RefundsPage> {
  String _status = 'pending';
  late Future<List<AdminRefund>> _load = context.read<AppState>().fetchRefundRequests(_status);
  final Set<int> _busy = {};

  void _reload() => setState(() => _load = context.read<AppState>().fetchRefundRequests(_status));

  Future<void> _review(AdminRefund r, bool approve) async {
    final note = await _askNote(
      context,
      title: approve ? 'Refund ${Fmt.naira(r.amount)} to ${r.rider ?? 'the rider'}?' : 'Decline this refund?',
      hint: approve ? 'e.g. Sorry the bus did not come.' : 'Tell the rider why, e.g. You boarded the bus (scanned 7:02 AM).',
      confirm: approve ? 'Refund' : 'Decline',
      required: !approve,
      danger: !approve,
    );
    if (note == null || !mounted) return;
    setState(() => _busy.add(r.id));
    try {
      final amount = await context.read<AppState>().reviewRefund(r.id, approve: approve, note: note);
      if (mounted) showMessage(context, approve ? '${Fmt.naira(amount)} is back in the rider\'s wallet.' : 'Refund declined. The rider sees your note.');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, _err(e, 'Could not update the refund.'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<List<AdminRefund>>(
      future: _load,
      builder: (context, snap) {
        final list = snap.data ?? const <AdminRefund>[];
        return PortalScaffold(
          title: 'Refunds',
          icon: Icons.undo_rounded,
          subtitle: 'Riders asking for their fare back. Approving puts the money back in their wallet and takes it back from the operator.',
          actions: [OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh'))],
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pending', label: Text('Waiting')),
                  ButtonSegment(value: 'approved', label: Text('Refunded')),
                  ButtonSegment(value: 'declined', label: Text('Declined')),
                ],
                selected: {_status},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  _status = s.first;
                  _reload();
                },
              ),
            ),
            const SizedBox(height: 12),
            if (snap.connectionState != ConnectionState.done)
              const Panel(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
            else if (snap.hasError)
              Panel(child: LoadFailure(message: _err(snap.error, 'Could not load refund requests.'), onRetry: _reload))
            else if (list.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.undo_rounded,
                  title: switch (_status) { 'pending' => 'No refunds waiting', 'approved' => 'No refunds yet', _ => 'Nothing declined' },
                  message: _status == 'pending' ? 'When a rider asks for their money back from a ticket, it shows up here.' : 'Reviewed requests show up here.',
                ),
              )
            else
              for (final r in list) ...[
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.rider ?? 'Rider', style: text.titleMedium),
                          Text([r.email, r.phone].whereType<String>().where((v) => v.isNotEmpty).join(' · '), style: text.bodySmall),
                        ]),
                      ),
                      Text(Fmt.naira(r.amount), style: text.titleLarge?.copyWith(fontFeatures: tabular)),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      StatusPill(r.status.adminLabel, tone: switch (r.status) { RefundStatus.pending => Tone.warning, RefundStatus.approved => Tone.success, RefundStatus.declined => Tone.danger }),
                      if (r.title != null) StatusPill(r.title!, tone: Tone.neutral),
                      if (r.ticket != null) StatusPill('Ticket ${r.ticket}', tone: Tone.neutral),
                      if (r.operator != null) StatusPill(r.operator!, tone: Tone.info),
                    ]),
                    const SizedBox(height: 10),
                    Text('“${r.reason}”', style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                    const SizedBox(height: 6),
                    Text(
                      [
                        'Asked ${Fmt.dayTime(r.createdAt)}',
                        if (r.departureAt != null) 'trip ${Fmt.dayTime(r.departureAt!)}',
                        if (r.reviewedAt != null) 'reviewed ${Fmt.dayTime(r.reviewedAt!)}',
                      ].join(' · '),
                      style: text.bodySmall,
                    ),
                    if ((r.note ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text('Note: ${r.note}', style: text.bodySmall?.copyWith(color: AppColors.inkSoft))],
                    if (r.status == RefundStatus.pending) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, runSpacing: 8, children: [
                        FilledButton.icon(
                            onPressed: _busy.contains(r.id) ? null : () => _review(r, true), icon: const Icon(Icons.check_rounded, size: 18), label: Text('Refund ${Fmt.naira(r.amount)}')),
                        OutlinedButton(onPressed: _busy.contains(r.id) ? null : () => _review(r, false), child: const Text('Decline')),
                        if (_whatsApp(r.phone) != null)
                          TextButton.icon(onPressed: () => launchUrl(_whatsApp(r.phone)!), icon: const Icon(Icons.chat_rounded, size: 18), label: const Text('WhatsApp rider')),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }
}

/// Admin action on a booking row: refund it directly (e.g. the bus never came).
Future<void> refundBookingDialog(BuildContext context, Booking b) async {
  final reason = await _askNote(
    context,
    title: 'Refund ${Fmt.naira(b.fare)} to ${b.passengerName}?',
    hint: 'e.g. The 7:00 AM bus did not run.',
    confirm: 'Refund',
    required: true,
  );
  if (reason == null || !context.mounted) return;
  try {
    final amount = await context.read<AppState>().refundBooking(b.id, reason);
    if (context.mounted) showMessage(context, '${Fmt.naira(amount)} refunded to ${b.passengerName}.');
  } catch (e) {
    if (context.mounted) showMessage(context, _err(e, 'Could not refund this booking.'), error: true);
  }
}

/// Whether an admin can refund this booking straight away.
bool adminCanRefund(Booking b) => b.paidFromWallet && b.refundedAt == null && b.status != BookingStatus.cancelled && b.status != BookingStatus.declined;

// ------------------------------------------------------------------ rider verification

class RiderChecksPage extends StatefulWidget {
  const RiderChecksPage({super.key});

  @override
  State<RiderChecksPage> createState() => _RiderChecksPageState();
}

class _RiderChecksPageState extends State<RiderChecksPage> {
  String _status = 'pending';
  late Future<List<RiderVerification>> _load = context.read<AppState>().fetchRiderVerifications(_status);
  final Set<String> _busy = {};
  final Set<String> _shown = {};

  void _reload() => setState(() => _load = context.read<AppState>().fetchRiderVerifications(_status));

  Future<void> _review(RiderVerification r, bool approve) async {
    final note = await _askNote(
      context,
      title: approve ? 'Verify ${r.name}?' : 'Decline ${r.name}\'s verification?',
      hint: approve ? 'Optional' : 'Tell the rider what to fix, e.g. The name does not match the NIN record.',
      confirm: approve ? 'Verify' : 'Decline',
      required: !approve,
      danger: !approve,
    );
    if (note == null || !mounted) return;
    setState(() => _busy.add(r.id));
    try {
      await context.read<AppState>().reviewVerification(r.id, approve: approve, note: note);
      if (mounted) showMessage(context, approve ? '${r.name} is verified.' : 'Declined. ${r.name} can fix the details and send them again.');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, _err(e, 'Could not update the verification.'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<List<RiderVerification>>(
      future: _load,
      builder: (context, snap) {
        final list = snap.data ?? const <RiderVerification>[];
        return PortalScaffold(
          title: 'Rider verification',
          icon: Icons.badge_rounded,
          subtitle: 'Check each rider\'s NIN and date of birth against their name before verifying. NINs are private: never share them.',
          actions: [OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh'))],
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pending', label: Text('Waiting')),
                    ButtonSegment(value: 'verified', label: Text('Verified')),
                    ButtonSegment(value: 'rejected', label: Text('Declined')),
                    ButtonSegment(value: 'unverified', label: Text('Not started')),
                  ],
                  selected: {_status},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    _status = s.first;
                    _reload();
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (snap.connectionState != ConnectionState.done)
              const Panel(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
            else if (snap.hasError)
              Panel(child: LoadFailure(message: _err(snap.error, 'Could not load rider verifications.'), onRetry: _reload))
            else if (list.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.badge_outlined,
                  title: _status == 'pending' ? 'Nobody waiting' : 'No riders here',
                  message: _status == 'pending' ? 'Riders who send their NIN from the app show up here for review.' : 'Change the filter to see other riders.',
                ),
              )
            else
              for (final r in list) ...[
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(initials: r.name.trim().split(RegExp(r'\s+')).map((p) => p.isEmpty ? '' : p[0]).take(2).join().toUpperCase(), size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.name, style: text.titleMedium),
                          Text(r.email, style: text.bodySmall, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      if (r.phoneShared) const StatusPill('Phone used twice', tone: Tone.warning, icon: Icons.copy_all_rounded),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 24, runSpacing: 10, children: [
                      _Fact('NIN', r.nin == null ? '—' : (_shown.contains(r.id) ? r.nin! : '•••••••${r.nin!.substring(r.nin!.length - 4)}')),
                      _Fact('Date of birth', r.dateOfBirth == null ? '—' : '${Fmt.date(r.dateOfBirth!)}${r.age == null ? '' : ' (${r.age})'}'),
                      _Fact('Phone', r.phone ?? '—'),
                      if ((r.homeArea ?? '').isNotEmpty) _Fact('Area', r.homeArea!),
                      if ((r.emergencyName ?? '').isNotEmpty) _Fact('Emergency contact', '${r.emergencyName}${(r.emergencyPhone ?? '').isEmpty ? '' : ' · ${r.emergencyPhone}'}'),
                      if (r.submittedAt != null) _Fact('Sent', Fmt.dayTime(r.submittedAt!)),
                    ]),
                    if ((r.note ?? '').isNotEmpty) ...[const SizedBox(height: 8), Text('Note: ${r.note}', style: text.bodySmall)],
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      if (r.nin != null)
                        TextButton.icon(
                          onPressed: () => setState(() => _shown.contains(r.id) ? _shown.remove(r.id) : _shown.add(r.id)),
                          icon: Icon(_shown.contains(r.id) ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                          label: Text(_shown.contains(r.id) ? 'Hide NIN' : 'Show NIN'),
                        ),
                      if (r.status == 'pending' || r.status == 'rejected')
                        FilledButton.icon(
                            onPressed: _busy.contains(r.id) || r.nin == null ? null : () => _review(r, true), icon: const Icon(Icons.verified_rounded, size: 18), label: const Text('Verify')),
                      if (r.status == 'pending' || r.status == 'verified') OutlinedButton(onPressed: _busy.contains(r.id) ? null : () => _review(r, false), child: Text(r.status == 'verified' ? 'Withdraw' : 'Decline')),
                      if (_whatsApp(r.phone) != null) TextButton.icon(onPressed: () => launchUrl(_whatsApp(r.phone)!), icon: const Icon(Icons.chat_rounded, size: 18), label: const Text('WhatsApp')),
                    ]),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: text.labelSmall?.copyWith(color: AppColors.muted)),
      const SizedBox(height: 2),
      Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabular)),
    ]);
  }
}
