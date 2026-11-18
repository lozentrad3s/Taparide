import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../shared/ui.dart';
import 'portal_widgets.dart';

const _techWeek = 'abuja-tech-week-2026';
const _pickups = [
  'University of Abuja, Gwagwalada',
  'Nnamdi Azikiwe Airport',
  'Old Parade Ground (corps members)',
  'Nile University',
  'Police Signboard, Lugbe',
  'Checkpoint, Maraba–Nyanya',
];
final _days = [DateTime(2026, 11, 24), DateTime(2026, 11, 25), DateTime(2026, 11, 26)];

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'[\s@.]+')).where((p) => p.isNotEmpty).toList();
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Everything collected on taparide.com: waitlist sign-ups, invite codes and the
/// Abuja Tech Week boarding lists per pick-up point and day. Platform admins only.
class WaitlistPage extends StatefulWidget {
  const WaitlistPage({super.key});

  @override
  State<WaitlistPage> createState() => _WaitlistPageState();
}

class _WaitlistPageState extends State<WaitlistPage> {
  late Future<List<WaitlistEntry>> _load = context.read<AppState>().fetchWaitlist();
  final _search = TextEditingController();
  DateTime _day = _days.first;
  String? _pickup;
  bool _techWeekOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _load = context.read<AppState>().fetchWaitlist());

  List<WaitlistEntry> _filtered(List<WaitlistEntry> all) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final e in all)
        if ((!_techWeekOnly || e.seats.any((s) => s.event == _techWeek)) &&
            (q.isEmpty || [e.name, e.email, e.phone, e.area, e.code].any((v) => (v ?? '').toLowerCase().contains(q))))
          e,
    ];
  }

  /// Boarding list for one day (and optionally one pick-up point), ready to paste into a sheet.
  String _boardingCsv(List<WaitlistEntry> all) {
    String cell(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    final rows = <String>['Day,Pick-up point,Time,Name,Phone,Email'];
    for (final e in all) {
      for (final s in e.seats) {
        if (s.event != _techWeek || !_sameDay(s.day, _day) || (_pickup != null && s.pickup != _pickup)) continue;
        rows.add([Fmt.date(s.day), s.pickup, s.time, e.name, e.phone, e.email].map(cell).join(','));
      }
    }
    return rows.join('\n');
  }

  String _allCsv(List<WaitlistEntry> all) {
    String cell(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    final rows = <String>['Joined,Name,Email,Phone,Area,Wants to,Invite code,Invited by,Invites,Source,Free ride paid,Tech Week seats'];
    for (final e in all) {
      final seats = [for (final s in e.seats) '${Fmt.date(s.day)} ${s.pickup}'].join('; ');
      rows.add([e.joinedAt.toIso8601String(), e.name, e.email, e.phone, e.area, e.role, e.code, e.referredBy, '${e.referrals}', e.source, e.creditedAt == null ? 'no' : 'yes', seats].map(cell).join(','));
    }
    return rows.join('\n');
  }

  Future<void> _copy(String csv, String what) async {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied. Paste it into Excel or Google Sheets.')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<List<WaitlistEntry>>(
      future: _load,
      builder: (context, snap) {
        final all = snap.data ?? const <WaitlistEntry>[];
        final seats = [for (final e in all) for (final s in e.seats) if (s.event == _techWeek) (e, s)];
        final today = [for (final p in seats) if (_sameDay(p.$2.day, _day)) p];
        final list = _filtered(all);
        return PortalScaffold(
          title: 'Website sign-ups',
          subtitle: 'Waitlist, invites and Abuja Tech Week seats from taparide.com',
          actions: [
            OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
            FilledButton.icon(
              onPressed: all.isEmpty ? null : () => _copy(_allCsv(all), 'All ${all.length} sign-ups'),
              icon: const Icon(Icons.table_view_rounded, size: 18),
              label: const Text('Copy all as CSV'),
            ),
          ],
          children: [
            if (snap.connectionState != ConnectionState.done)
              const Panel(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
            else if (snap.hasError)
              Panel(child: LoadFailure(message: snap.error is BackendException ? (snap.error as BackendException).message : 'Could not load sign-ups.', onRetry: _reload))
            else ...[
              Cols(children: [
                FigureCard(label: 'Joined the waitlist', value: Fmt.count(all.length), icon: Icons.how_to_reg_rounded),
                FigureCard(label: 'Tech Week seats', value: Fmt.count(seats.length), icon: Icons.directions_bus_rounded, caption: '${{for (final p in seats) p.$1.id}.length} people'),
                FigureCard(label: 'Joined by invite', value: Fmt.count(all.where((e) => e.referredBy != null).length), icon: Icons.share_rounded),
                FigureCard(label: 'Free rides paid', value: Fmt.count(all.where((e) => e.creditedAt != null).length), icon: Icons.account_balance_wallet_rounded, caption: 'Opened an account'),
              ]),
              const SizedBox(height: PortalSpace.gap),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
                    Text('Tech Week boarding lists · 7:00 AM', style: text.titleLarge),
                    Wrap(spacing: 8, children: [
                      for (final d in _days)
                        ChoiceChip(label: Text('${Fmt.weekday(d)} ${d.day} Nov'), selected: _sameDay(d, _day), onSelected: (_) => setState(() => _day = d)),
                    ]),
                  ]),
                  const SizedBox(height: 14),
                  for (final p in _pickups)
                    _PickupRow(
                      name: p,
                      count: today.where((x) => x.$2.pickup == p).length,
                      max: _pickups.map((q) => today.where((x) => x.$2.pickup == q).length).fold(1, (a, b) => b > a ? b : a),
                      selected: _pickup == p,
                      onTap: () => setState(() => _pickup = _pickup == p ? null : p),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: today.isEmpty ? null : () => _copy(_boardingCsv(all), 'Boarding list for ${Fmt.weekday(_day)} ${_day.day} Nov${_pickup == null ? '' : ' at $_pickup'}'),
                      icon: const Icon(Icons.content_copy_rounded, size: 18),
                      label: Text(_pickup == null ? 'Copy boarding list (all points)' : 'Copy boarding list for this point'),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: PortalSpace.gap),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(
                      width: 320,
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name, email, phone or code'),
                      ),
                    ),
                    FilterChip(label: const Text('Tech Week only'), selected: _techWeekOnly, onSelected: (v) => setState(() => _techWeekOnly = v)),
                    Text('${list.length} of ${all.length}', style: text.bodySmall),
                  ]),
                  const SizedBox(height: 10),
                  if (list.isEmpty)
                    const EmptyState(icon: Icons.inbox_rounded, title: 'No sign-ups yet', message: 'People who join on taparide.com or reserve a Tech Week seat appear here.')
                  else
                    for (final e in list.take(300)) _EntryRow(entry: e),
                  if (list.length > 300) Padding(padding: const EdgeInsets.all(12), child: Text('Showing the newest 300. Use search, or copy all as CSV.', style: text.bodySmall)),
                ]),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PickupRow extends StatelessWidget {
  const _PickupRow({required this.name, required this.count, required this.max, required this.selected, required this.onTap});
  final String name;
  final int count;
  final int max;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: selected ? AppColors.mint : null, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          const Icon(Icons.place_rounded, size: 20, color: AppColors.forest),
          const SizedBox(width: 10),
          SizedBox(width: 260, child: Text(name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: max == 0 ? 0 : count / max, minHeight: 8, color: AppColors.forest, backgroundColor: AppColors.line),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 72, child: Text('$count ${count == 1 ? 'seat' : 'seats'}', textAlign: TextAlign.right, style: text.titleSmall?.copyWith(fontFeatures: tabular))),
        ]),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final WaitlistEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(initials: _initials(e.name ?? e.email)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.name ?? 'No name given', style: text.titleSmall),
            Text([e.email, if (e.phone != null) e.phone!, if (e.area != null) e.area!].join(' · '), style: text.bodySmall),
            if (e.seats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in e.seats) StatusPill('Tech Week ${s.day.day} Nov · ${s.pickup.split(',').first}', tone: Tone.warning),
                ]),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Fmt.day(e.joinedAt), style: text.bodySmall),
          Text('Code ${e.code} · ${e.referrals} invited', style: text.bodySmall),
          if (e.creditedAt != null) const StatusPill('Free ride paid', tone: Tone.success),
        ]),
      ]),
    );
  }
}
