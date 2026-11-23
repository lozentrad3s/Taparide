import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../shared/ui.dart';
import 'portal_widgets.dart';

/// Master admin: every naira on the platform. Rider wallets (and the free ride credit inside them),
/// card/bank top-ups, tap-to-pay fares held until each trip ends, and partners' collection wallets.
class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key});

  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends State<MoneyPage> {
  late Future<MoneyOverview> _load = context.read<AppState>().fetchMoney();

  void _reload() => setState(() => _load = context.read<AppState>().fetchMoney());

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<MoneyOverview>(
      future: _load,
      builder: (context, snap) {
        final m = snap.data ?? MoneyOverview.empty;
        return PortalScaffold(
          title: 'Money',
          icon: Icons.payments_rounded,
          subtitle: 'Wallets, top-ups, held fares and partner collection wallets',
          actions: [OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh'))],
          children: [
            if (snap.connectionState != ConnectionState.done)
              const Panel(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
            else if (snap.hasError)
              Panel(child: LoadFailure(message: snap.error is BackendException ? (snap.error as BackendException).message : 'Could not load money figures.', onRetry: _reload))
            else ...[
              const SectionLabel('Riders', subtitle: 'Money riders have added, ready to tap and pay'),
              Cols(children: [
                FigureCard(
                    label: 'In rider wallets',
                    value: Fmt.naira(m.walletBalance - m.rideCredit),
                    icon: Icons.account_balance_wallet_rounded,
                    caption: '${Fmt.count(m.walletCount)} wallet${m.walletCount == 1 ? '' : 's'}'),
                FigureCard(label: 'Ride credit outstanding', value: Fmt.naira(m.rideCredit), icon: Icons.local_activity_rounded, caption: 'Older sign-up credit still unspent'),
                FigureCard(label: 'Top-ups paid', value: Fmt.naira(m.topupsPaidAmount), icon: Icons.credit_card_rounded, caption: '${Fmt.count(m.topupsPaid)} payments'),
                FigureCard(
                    label: 'Top-ups not finished',
                    value: Fmt.count(m.topupsPending + m.topupsFailed),
                    icon: Icons.hourglass_bottom_rounded,
                    caption: '${m.topupsPending} pending · ${m.topupsFailed} failed'),
              ]),
              const SectionLabel('Tap to pay', subtitle: 'Each fare is held until the trip ends, then moves to the partner\'s collection wallet'),
              Cols(max: 3, children: [
                FigureCard(label: 'Held for trips not finished', value: Fmt.naira(m.held), icon: Icons.lock_clock_rounded),
                FigureCard(label: 'Released to partners', value: Fmt.naira(m.released), icon: Icons.call_made_rounded),
                FigureCard(label: 'Refunded to riders', value: Fmt.naira(m.refunded), icon: Icons.undo_rounded),
              ]),
              const SizedBox(height: PortalSpace.gap),
              TwoUp(
                left: Panel(
                  radius: AppRadius.md,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const PanelTitle('Latest top-ups', subtitle: 'Newest 25'),
                    if (m.recentTopups.isEmpty)
                      Text('No card or bank top-ups yet. Riders add money from Profile → Top up (Bachs).', style: text.bodyMedium)
                    else
                      for (final t in m.recentTopups) _TopUpRow(row: t),
                  ]),
                ),
                right: Panel(
                  radius: AppRadius.md,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const PanelTitle('Partner collection wallets', subtitle: 'Withdrawals to bank are coming soon'),
                    if (m.collection.isEmpty)
                      Text('Nothing collected yet. Operators, fleet owners and private drivers each get a collection wallet automatically.', style: text.bodyMedium)
                    else
                      for (final c in m.collection)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(children: [
                            const IconBadge(Icons.apartment_rounded, size: 34),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(c.provider, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(c.paidOut > 0 ? '${Fmt.naira(c.paidOut)} paid out' : c.kind.replaceAll('_', ' '), style: text.bodySmall),
                              ]),
                            ),
                            Text(Fmt.naira(c.available), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                          ]),
                        ),
                  ]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TopUpRow extends StatelessWidget {
  const _TopUpRow({required this.row});
  final TopUpRow row;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tone = switch (row.status) { 'paid' => Tone.success, 'failed' => Tone.danger, _ => Tone.warning };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.name ?? 'Rider', style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${Fmt.dayTime(row.createdAt)} · ${row.reference}${row.channel == null ? '' : ' · ${row.channel}'}', style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Fmt.naira(row.amount), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular)),
          const SizedBox(height: 4),
          StatusPill(row.status, tone: tone),
        ]),
      ]),
    );
  }
}

/// A partner's own collection wallet: what tap to pay has brought in, what is still held until
/// trips end, and the latest payments. Shown on the operator, fleet owner and driver dashboards.
class CollectionWalletPanel extends StatefulWidget {
  const CollectionWalletPanel({super.key});

  @override
  State<CollectionWalletPanel> createState() => _CollectionWalletPanelState();
}

class _CollectionWalletPanelState extends State<CollectionWalletPanel> {
  late Future<CollectionWallet> _load = context.read<AppState>().fetchCollectionWallet();

  void _reload() => setState(() => _load = context.read<AppState>().fetchCollectionWallet());

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<CollectionWallet>(
      future: _load,
      builder: (context, snap) {
        final w = snap.data ?? CollectionWallet.empty;
        final loading = snap.connectionState != ConnectionState.done;
        return Panel(
          radius: AppRadius.md,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle(
              'Collection wallet',
              subtitle: 'Fares riders pay with tap to pay',
              trailing: IconButton(tooltip: 'Refresh', onPressed: loading ? null : _reload, icon: const Icon(Icons.refresh_rounded, size: 20)),
            ),
            if (loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (snap.hasError)
              LoadFailure(message: snap.error is BackendException ? (snap.error as BackendException).message : 'Could not load your collection wallet.', onRetry: _reload)
            else ...[
              Wrap(spacing: 28, runSpacing: 12, children: [
                _Amount(label: 'Available', value: Fmt.naira(w.available), strong: true),
                _Amount(label: 'Held until trips end', value: Fmt.naira(w.held)),
                if (w.paidOut > 0) _Amount(label: 'Paid out', value: Fmt.naira(w.paidOut)),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: AppColors.surfaceSunk, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('A fare is held from the moment the rider pays and released to you after the trip, so cancelled trips can be refunded. Withdrawals to your bank are coming soon.',
                        style: text.bodySmall),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              if (w.recent.isEmpty)
                Text('No tap-to-pay fares yet. They appear here the moment a rider pays.', style: text.bodyMedium)
              else
                for (final p in w.recent.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.title ?? 'Booking ${p.bookingId}', style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            switch (p.status) {
                              'released' => 'Paid to your wallet · ${Fmt.dayTime(p.createdAt)}',
                              'refunded' => 'Refunded to the rider · ${Fmt.dayTime(p.createdAt)}',
                              _ => p.releaseAt == null ? 'Held until the trip ends' : 'Held until about ${Fmt.dayTime(p.releaseAt!)}',
                            },
                            style: text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${p.status == 'refunded' ? '−' : ''}${Fmt.naira(p.amount)}',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: tabular,
                          color: p.status == 'released' ? AppColors.forest : (p.status == 'refunded' ? AppColors.muted : AppColors.ink),
                        ),
                      ),
                    ]),
                  ),
            ],
          ]),
        );
      },
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: text.labelMedium?.copyWith(color: AppColors.muted)),
      const SizedBox(height: 2),
      Text(value, style: (strong ? text.headlineSmall : text.titleLarge)?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular, color: strong ? AppColors.forestDeep : AppColors.ink)),
    ]);
  }
}

/// Free-bus bookings for the events an organiser runs: how many people, from which pick-up point,
/// on which day and at what time. Counts only, never names (the boarding lists stay with Tap A Ride).
class SeatBookingsPanel extends StatefulWidget {
  const SeatBookingsPanel({super.key});

  @override
  State<SeatBookingsPanel> createState() => _SeatBookingsPanelState();
}

class _SeatBookingsPanelState extends State<SeatBookingsPanel> {
  late Future<List<EventSeatBookings>> _load = context.read<AppState>().fetchOrganiserSeatBookings();

  void _reload() => setState(() => _load = context.read<AppState>().fetchOrganiserSeatBookings());

  static String _slot(String s) {
    final parts = s.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? parts[1] : '00';
    return '${h == 0 ? 12 : (h > 12 ? h - 12 : h)}:$m ${h < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EventSeatBookings>>(
      future: _load,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final events = snap.data ?? const <EventSeatBookings>[];
        return Panel(
          radius: AppRadius.md,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PanelTitle(
              'Free bus bookings',
              subtitle: 'People booked from each pick-up point, by day',
              trailing: OutlinedButton.icon(onPressed: loading ? null : _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
            ),
            if (loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (snap.hasError)
              LoadFailure(message: snap.error is BackendException ? (snap.error as BackendException).message : 'Could not load bus bookings.', onRetry: _reload)
            else if (events.isEmpty)
              const EmptyState(
                icon: Icons.directions_bus_rounded,
                title: 'No free-bus events linked yet',
                message: 'When Tap A Ride runs free buses for one of your events, bookings from taparide.com appear here as they come in.',
              )
            else
              for (final e in events) _EventSeats(event: e, slot: _slot),
          ]),
        );
      },
    );
  }
}

class _EventSeats extends StatelessWidget {
  const _EventSeats({required this.event, required this.slot});
  final EventSeatBookings event;
  final String Function(String) slot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = event;
    final areas = e.areas.isNotEmpty ? e.areas : {for (final r in e.rows) r.area}.toList();
    final days = e.days.isNotEmpty ? e.days : ({for (final r in e.rows) r.day}.toList()..sort());
    final times = e.slots.isEmpty ? '' : e.slots.map(slot).join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(e.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          [
            e.venue,
            'Starts ${Fmt.time(e.startsAt)}',
            if (times.isNotEmpty) 'Buses leave pick-up points at $times',
            if (e.lastBooking != null) 'Last booking ${Fmt.relative(e.lastBooking!)}',
          ].join(' · '),
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _Chip(label: 'People booked', value: Fmt.count(e.people)),
          for (final d in days) _Chip(label: '${Fmt.weekday(d)} ${d.day}', value: '${e.ridersOn(d)} riders'),
        ]),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 48,
            columnSpacing: 22,
            columns: [
              const DataColumn(label: Text('Pick-up point')),
              const DataColumn(label: Text('Time')),
              for (final d in days) DataColumn(numeric: true, label: Text('${Fmt.weekday(d)} ${d.day}')),
            ],
            rows: [
              for (final a in areas)
                DataRow(cells: [
                  DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: Text(a, maxLines: 2, overflow: TextOverflow.ellipsis))),
                  DataCell(Text(times.isEmpty ? '—' : times)),
                  for (final d in days) DataCell(Text('${e.ridersOn(d, a)}', style: const TextStyle(fontFeatures: tabular))),
                ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: text.labelMedium?.copyWith(color: AppColors.forest)),
        Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular, color: AppColors.forestDeep)),
      ]),
    );
  }
}
