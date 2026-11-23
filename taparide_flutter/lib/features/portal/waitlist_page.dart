import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../shared/download/download.dart';
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

String _dayShort(DateTime d) => '${Fmt.weekday(d)} ${d.day}';

/// Nigerian number in international form for wa.me (0803… / +234 803… / 234803… → 234803…).
String? _waNumber(String? phone) {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10) return null;
  if (digits.startsWith('234') && digits.length >= 13) return digits;
  if (digits.startsWith('0') && digits.length == 11) return '234${digits.substring(1)}';
  if (digits.length == 10) return '234$digits';
  return digits;
}

enum _Filter {
  all('Everyone'),
  pass('Has a Tech Week pass'),
  notContacted('Not contacted'),
  duplicates('Possible duplicates');

  const _Filter(this.label);
  final String label;
}

/// Everything collected on taparide.com: waitlist sign-ups, invite codes and the Abuja Tech Week
/// passes (one pass per person, valid on the days they picked). Platform admins only.
class WaitlistPage extends StatefulWidget {
  const WaitlistPage({super.key});

  @override
  State<WaitlistPage> createState() => _WaitlistPageState();
}

class _WaitlistPageState extends State<WaitlistPage> {
  late Future<List<WaitlistEntry>> _load = context.read<AppState>().fetchWaitlist();
  final _search = TextEditingController();
  DateTime _day = _days.first;
  String? _boardingPoint;
  _Filter _filter = _Filter.all;
  String? _pointFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _load = context.read<AppState>().fetchWaitlist());

  List<WaitlistEntry> _filtered(List<WaitlistEntry> all) {
    final q = _search.text.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    bool matches(WaitlistEntry e) {
      if (q.isEmpty) return true;
      final fields = [e.name, e.email, e.area, e.code, for (final s in e.seats) s.ticket];
      if (fields.any((v) => (v ?? '').toLowerCase().contains(q))) return true;
      // Phone search ignores spaces and the +234 / 0 prefix.
      if (qDigits.length >= 4) {
        final phone = (e.phone ?? '').replaceAll(RegExp(r'\D'), '');
        return phone.contains(qDigits) || phone.contains(qDigits.replaceFirst(RegExp(r'^(234|0)'), ''));
      }
      return false;
    }

    return [
      for (final e in all)
        if (matches(e) &&
            switch (_filter) {
              _Filter.all => true,
              _Filter.pass => e.seats.any((s) => s.event == _techWeek),
              _Filter.notContacted => e.contactedAt == null,
              _Filter.duplicates => e.possibleDuplicate,
            } &&
            (_pointFilter == null || e.seats.any((s) => s.event == _techWeek && s.pickup == _pointFilter)))
          e,
    ];
  }

  Future<void> _save(String fileName, List<List<Object?>> rows, String what) async {
    final saved = await downloadCsv(fileName, rows);
    if (!saved) await Clipboard.setData(ClipboardData(text: toCsv(rows)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved ? '$what downloaded.' : '$what copied. Paste it into Excel or Google Sheets.')));
  }

  /// Boarding list for one day (and optionally one pick-up point).
  List<List<Object?>> _boardingRows(List<WaitlistEntry> all) => [
        ['Day', 'Pick-up point', 'Time', 'Pass ID', 'Name', 'Phone', 'Email', 'Boarded'],
        for (final e in all)
          for (final s in e.seats)
            if (s.event == _techWeek && _sameDay(s.day, _day) && (_boardingPoint == null || s.pickup == _boardingPoint)) [Fmt.date(s.day), s.pickup, s.time, s.ticket, e.name, e.phone, e.email, ''],
      ];

  List<List<Object?>> _allRows(List<WaitlistEntry> list) => [
        [
          'Joined',
          'Name',
          'Email',
          'Phone',
          'Area',
          'Wants to',
          'Invite code',
          'Invited by',
          'Invites',
          'Source',
          'Ride reward granted',
          'Pass ID',
          'Pass days',
          'Pick-up point',
          'Contacted',
          'Note',
          'Possible duplicate'
        ],
        for (final e in list)
          () {
            final pass = e.passes.where((p) => p.event == _techWeek).firstOrNull;
            return [
              e.joinedAt.toIso8601String(),
              e.name,
              e.email,
              e.phone,
              e.area,
              e.role,
              e.code,
              e.referredBy,
              e.referrals,
              e.source,
              e.creditedAt == null ? 'no' : 'yes',
              pass?.code,
              pass == null ? '' : pass.days.map(_dayShort).join(' '),
              pass?.pickup,
              e.contactedAt == null ? '' : e.contactedAt!.toIso8601String(),
              e.note,
              [if (e.dupPhone) 'same number', if (e.dupName) 'same name'].join(', '),
            ];
          }(),
      ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<List<WaitlistEntry>>(
      future: _load,
      builder: (context, snap) {
        final all = snap.data ?? const <WaitlistEntry>[];
        final seats = [
          for (final e in all)
            for (final s in e.seats)
              if (s.event == _techWeek) (e, s)
        ];
        final today = [
          for (final p in seats)
            if (_sameDay(p.$2.day, _day)) p
        ];
        final people = {for (final p in seats) p.$1.id}.length;
        final list = _filtered(all);
        final stamp = DateTime.now().toIso8601String().substring(0, 10);
        return PortalScaffold(
          title: 'Website sign-ups',
          icon: Icons.how_to_reg_rounded,
          subtitle: 'Waitlist, invites and Abuja Tech Week passes from taparide.com',
          actions: [
            OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
            FilledButton.icon(
              onPressed: list.isEmpty ? null : () => _save('taparide-signups-$stamp.csv', _allRows(list), '${list.length} sign-ups'),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(list.length == all.length ? 'Download CSV' : 'Download ${list.length} shown'),
            ),
          ],
          children: [
            if (snap.connectionState != ConnectionState.done)
              const Panel(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
            else if (snap.hasError)
              Panel(child: LoadFailure(message: snap.error is BackendException ? (snap.error as BackendException).message : 'Could not load sign-ups.', onRetry: _reload))
            else ...[
              Cols(children: [
                FigureCard(label: 'Joined the waitlist', value: Fmt.count(all.length), icon: Icons.how_to_reg_rounded, caption: '${all.where((e) => e.referredBy != null).length} by invite'),
                FigureCard(label: 'Tech Week passes', value: Fmt.count(people), icon: Icons.directions_bus_rounded, caption: '${seats.length} seat-days across 3 days'),
                FigureCard(label: 'Not contacted yet', value: Fmt.count(all.where((e) => e.contactedAt == null).length), icon: Icons.mark_chat_unread_rounded),
                FigureCard(label: 'Possible duplicates', value: Fmt.count(all.where((e) => e.possibleDuplicate).length), icon: Icons.content_copy_rounded, caption: 'Same number or name'),
              ]),
              const SizedBox(height: PortalSpace.gap),
              Panel(
                radius: AppRadius.md,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('Tech Week boarding lists', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Pick-ups at 7:00 AM · tap a point to narrow the list', style: text.bodySmall),
                    ]),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final d in _days) ChoiceChip(label: Text('${Fmt.weekday(d)} ${d.day} Nov'), selected: _sameDay(d, _day), onSelected: (_) => setState(() => _day = d)),
                    ]),
                  ]),
                  const SizedBox(height: 14),
                  for (final p in _pickups)
                    _PickupRow(
                      name: p,
                      count: today.where((x) => x.$2.pickup == p).length,
                      max: _pickups.map((q) => today.where((x) => x.$2.pickup == q).length).fold(1, (a, b) => b > a ? b : a),
                      selected: _boardingPoint == p,
                      onTap: () => setState(() => _boardingPoint = _boardingPoint == p ? null : p),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: today.isEmpty
                          ? null
                          : () => _save(
                                'boarding-${_day.month}-${_day.day}${_boardingPoint == null ? '' : '-${_boardingPoint!.split(',').first.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-')}'}.csv',
                                _boardingRows(all),
                                'Boarding list for ${Fmt.weekday(_day)} ${_day.day} Nov${_boardingPoint == null ? '' : ' at $_boardingPoint'}',
                              ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(_boardingPoint == null ? 'Boarding list (all points)' : 'Boarding list for this point'),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: PortalSpace.gap),
              Panel(
                radius: AppRadius.md,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const PanelTitle('Everyone who signed up', subtitle: 'Newest first'),
                  Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Name, email, phone or pass ID',
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () => setState(_search.clear),
                                ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: DropdownButtonFormField<String?>(
                        initialValue: _pointFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true, labelText: 'Pick-up point'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Any point')),
                          for (final p in _pickups) DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _pointFilter = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final f in _Filter.values) ChoiceChip(label: Text(f.label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                    Padding(padding: const EdgeInsets.only(left: 4), child: Text('${list.length} of ${all.length}', style: text.bodySmall)),
                  ]),
                  const SizedBox(height: 10),
                  if (all.isEmpty)
                    const EmptyState(icon: Icons.inbox_rounded, title: 'No sign-ups yet', message: 'People who join on taparide.com or book a Tech Week pass appear here.')
                  else if (list.isEmpty)
                    const EmptyState(icon: Icons.filter_alt_off_rounded, title: 'Nobody matches', message: 'Try another search, or choose "Everyone" and "Any point".')
                  else
                    for (final e in list.take(300)) _EntryRow(key: ValueKey(e.id), entry: e, onChanged: _reload),
                  if (list.length > 300) Padding(padding: const EdgeInsets.all(12), child: Text('Showing the newest 300. Use search, or download the CSV for everyone.', style: text.bodySmall)),
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
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(value: max == 0 ? 0 : count / max, minHeight: 8, color: AppColors.forest, backgroundColor: AppColors.line),
    );
    final seats = Text('$count ${count == 1 ? 'rider' : 'riders'}', textAlign: TextAlign.right, style: text.titleSmall?.copyWith(fontFeatures: tabular));
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: selected ? AppColors.mint : null, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 560
                ? Row(children: [
                    const Icon(Icons.place_rounded, size: 20, color: AppColors.forest),
                    const SizedBox(width: 10),
                    SizedBox(width: 260, child: Text(name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 12),
                    Expanded(child: bar),
                    const SizedBox(width: 12),
                    SizedBox(width: 80, child: seats),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Icon(Icons.place_rounded, size: 18, color: AppColors.forest),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      seats,
                    ]),
                    const SizedBox(height: 6),
                    bar,
                  ]),
          ),
        ),
      ),
    );
  }
}

enum _RowAction { editPass, cancelPass, note, remove }

class _EntryRow extends StatefulWidget {
  const _EntryRow({super.key, required this.entry, required this.onChanged});
  final WaitlistEntry entry;
  final VoidCallback onChanged;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final ok = await attemptOk(context, action, success: done);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onChanged();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(d, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _action(_RowAction a) async {
    final e = widget.entry;
    final state = context.read<AppState>();
    final who = e.name ?? e.email;
    switch (a) {
      case _RowAction.editPass:
        final result = await showDialog<_PassEdit>(context: context, builder: (_) => _EditPassDialog(entry: e));
        if (result == null || !mounted) return;
        await _run(
          () => state.updateEventPass(id: e.id, event: _techWeek, pickup: result.pickup, days: result.days, name: result.name, phone: result.phone),
          'Pass updated for $who',
        );
      case _RowAction.cancelPass:
        if (!await _confirm('Cancel this bus pass?', '$who loses their Tech Week seat on every day. They can book again on the website.', 'Cancel pass')) return;
        await _run(() => state.cancelEventPass(e.id, _techWeek), 'Pass cancelled for $who');
      case _RowAction.note:
        final note = await showDialog<String>(context: context, builder: (_) => _NoteDialog(initial: e.note));
        if (note == null || !mounted) return;
        await _run(() => state.setSignupContacted(e.id, contacted: e.contactedAt != null, note: note), 'Note saved');
      case _RowAction.remove:
        if (!await _confirm('Remove this sign-up?', 'Removes $who and any bus pass from the waitlist. Use this for duplicates only; it can\'t be undone.', 'Remove')) return;
        await _run(() => state.removeSignup(e.id), 'Sign-up removed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = widget.entry;
    final pass = e.passes.where((p) => p.event == _techWeek).firstOrNull;
    final wa = _waNumber(e.phone);
    final contacted = e.contactedAt != null;
    final actions = _actions(context, e, pass, wa, contacted);
    return LayoutBuilder(builder: (context, c) {
      // On phones the buttons go under the details so names and passes keep the full width.
      final narrow = c.maxWidth < 560;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(initials: _initials(e.name ?? e.email), size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(e.name ?? 'No name given', style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (contacted) StatusPill('Contacted ${Fmt.day(e.contactedAt!)}', tone: Tone.success, icon: Icons.check_rounded),
                if (e.dupPhone) const StatusPill('Duplicate number', tone: Tone.danger, icon: Icons.content_copy_rounded),
                if (e.dupName && !e.dupPhone) const StatusPill('Duplicate name', tone: Tone.warning, icon: Icons.content_copy_rounded),
              ]),
              const SizedBox(height: 2),
              Text([e.email, if (e.phone != null) e.phone!, if (e.area != null) e.area!].join(' · '), style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Joined ${Fmt.day(e.joinedAt)}', style: text.bodySmall),
                Text('Code ${e.code} · ${e.referrals} invited', style: text.bodySmall),
                if (e.creditedAt != null) const StatusPill('Ride reward granted', tone: Tone.success),
              ]),
              if (pass != null)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.directions_bus_rounded, size: 16, color: AppColors.amber)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Pass ${pass.code ?? ''} · ${pass.days.map(_dayShort).join(', ')} · ${pass.pickup}',
                        style: text.bodySmall?.copyWith(color: AppColors.amber, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),
              if ((e.note ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Note: ${e.note}', style: text.bodySmall?.copyWith(color: AppColors.inkSoft, fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              if (narrow) Padding(padding: const EdgeInsets.only(top: 4), child: actions),
            ]),
          ),
          if (!narrow) ...[const SizedBox(width: 8), actions],
        ]),
      );
    });
  }

  Widget _actions(BuildContext context, WaitlistEntry e, EventPass? pass, String? wa, bool contacted) => _busy
      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
      : Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: wa == null ? 'No WhatsApp number' : 'Message on WhatsApp',
            onPressed: wa == null ? null : () => launchUrl(Uri.parse('https://wa.me/$wa'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.chat_rounded, color: Color(0xFF128C7E)),
          ),
          IconButton(
            tooltip: contacted ? 'Mark as not contacted' : 'Mark as contacted',
            isSelected: contacted,
            onPressed: () => _run(() => context.read<AppState>().setSignupContacted(e.id, contacted: !contacted), contacted ? 'Marked as not contacted' : 'Marked as contacted'),
            icon: const Icon(Icons.radio_button_unchecked_rounded),
            selectedIcon: const Icon(Icons.check_circle_rounded, color: AppColors.forest),
          ),
          PopupMenuButton<_RowAction>(
            tooltip: 'More actions',
            onSelected: _action,
            itemBuilder: (_) => [
              PopupMenuItem(value: _RowAction.editPass, child: Text(pass == null ? 'Give a Tech Week pass' : 'Edit pass')),
              if (pass != null) const PopupMenuItem(value: _RowAction.cancelPass, child: Text('Cancel pass')),
              PopupMenuItem(value: _RowAction.note, child: Text((e.note ?? '').isEmpty ? 'Add a note' : 'Edit note')),
              if (e.creditedAt == null) const PopupMenuItem(value: _RowAction.remove, child: Text('Remove duplicate sign-up', style: TextStyle(color: AppColors.red))),
            ],
          ),
        ]);
}

class _PassEdit {
  const _PassEdit({required this.pickup, required this.days, this.name, this.phone});
  final String pickup;
  final List<DateTime> days;
  final String? name;
  final String? phone;
}

class _EditPassDialog extends StatefulWidget {
  const _EditPassDialog({required this.entry});
  final WaitlistEntry entry;

  @override
  State<_EditPassDialog> createState() => _EditPassDialogState();
}

class _EditPassDialogState extends State<_EditPassDialog> {
  late final pass = widget.entry.passes.where((p) => p.event == _techWeek).firstOrNull;
  late String? _pickup = _pickups.contains(pass?.pickup) ? pass!.pickup : null;
  late final Set<DateTime> _picked = {
    for (final d in _days)
      if (pass == null || pass!.days.any((p) => _sameDay(p, d))) d
  };
  late final _name = TextEditingController(text: widget.entry.name ?? '');
  late final _phone = TextEditingController(text: widget.entry.phone ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (_pickup == null) return setState(() => _error = 'Choose a pick-up point.');
    if (_picked.isEmpty) return setState(() => _error = 'Pick at least one day.');
    if (_name.text.trim().split(RegExp(r'\s+')).length < 2) return setState(() => _error = 'Enter a first and last name for the boarding list.');
    Navigator.pop(context, _PassEdit(pickup: _pickup!, days: _days.where(_picked.contains).toList(), name: _name.text.trim(), phone: _phone.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(pass == null ? 'Give a Tech Week pass' : 'Edit pass ${pass!.code ?? ''}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp number')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _pickup,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pick-up point'),
              items: [for (final p in _pickups) DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _pickup = v),
            ),
            const SizedBox(height: 14),
            Text('Valid on', style: text.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in _days)
                FilterChip(
                  label: Text('${Fmt.weekday(d)} ${d.day} Nov'),
                  selected: _picked.contains(d),
                  onSelected: (v) => setState(() => v ? _picked.add(d) : _picked.remove(d)),
                ),
            ]),
            const SizedBox(height: 8),
            Text('The pass ID stays the same, so a pass already saved or printed still works.', style: text.bodySmall),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.red, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save pass')),
      ],
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({this.initial});
  final String? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _note = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Private note'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: _note,
            autofocus: true,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'e.g. Called on WhatsApp, coming all three days'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _note.text.trim()), child: const Text('Save note')),
        ],
      );
}
