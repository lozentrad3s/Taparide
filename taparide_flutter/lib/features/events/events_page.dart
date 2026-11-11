import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../shared/ui.dart';
import '../tag_along/tag_along_page.dart';

/// Event rides: what's on in Abuja, and shared rides going there.
class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  EventCategory? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().refreshRider());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final wide = isWide(context, 980);
    final all = state.events;
    final events = [for (final e in all) if (_filter == null || e.category == _filter) e];
    final categories = {for (final e in all) e.category}.toList()..sort((a, b) => a.index.compareTo(b.index));

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Event rides')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _ListEventSheet()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('List an event'),
      ),
      body: DataGate(
        builder: (context) => RefreshIndicator(
          color: AppColors.forest,
          onRefresh: state.refreshRider,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              MaxWidth(
                width: 1080,
                padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 8, wide ? 32 : 18, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Going out? Go together.', style: wide ? text.displaySmall : text.headlineLarge),
                  const SizedBox(height: 8),
                  Text('Pick an event, then join a shared ride there or offer your empty seats. Everyone pays their share through the app.', style: text.bodyLarge),
                  const SizedBox(height: 16),
                  if (categories.length > 1)
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                      for (final c in categories)
                        ChoiceChip(label: Text(c.label), avatar: Icon(c.icon, size: 16), selected: _filter == c, onSelected: (_) => setState(() => _filter = c)),
                    ]),
                  const SizedBox(height: 18),
                  if (events.isEmpty)
                    EmptyState(
                      icon: Icons.event_available_rounded,
                      title: all.isEmpty ? 'No events listed yet' : 'Nothing in this category',
                      message: 'Hosting something? List it so people can share rides to it.',
                    )
                  else
                    for (var i = 0; i < events.length; i += wide ? 2 : 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            for (var j = i; j < i + (wide ? 2 : 1); j++) ...[
                              if (j > i) const SizedBox(width: 14),
                              Expanded(child: j < events.length ? _EventCard(event: events[j], rides: state.ridesForEvent(events[j].id).length) : const SizedBox.shrink()),
                            ],
                          ]),
                        ),
                      ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The date block shown on event cards and the detail page.
class _DateBlock extends StatelessWidget {
  const _DateBlock(this.date);
  final DateTime date;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_months[date.month - 1], style: text.labelSmall?.copyWith(color: AppColors.leafText, fontWeight: FontWeight.w800, letterSpacing: 1)),
        Text('${date.day}', style: text.headlineSmall?.copyWith(color: AppColors.forest, height: 1.1)),
        Text(Fmt.weekday(date), style: text.labelSmall),
      ]),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.rides});
  final RideEvent event;
  final int rides;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      onTap: () => context.push('/events/${event.id}'),
      semanticLabel: '${event.title}, ${Fmt.dayTime(event.startsAt)} at ${event.venue}',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DateBlock(event.startsAt),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(event.category.icon, size: 15, color: AppColors.muted),
              const SizedBox(width: 5),
              Text(event.category.label, style: text.labelSmall),
            ]),
            const SizedBox(height: 2),
            Text(event.title, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${Fmt.time(event.startsAt)} · ${event.venue}, ${event.area}', style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Row(children: [
              StatusPill(rides == 0 ? 'No rides yet' : '$rides ride${rides == 1 ? '' : 's'} going', tone: rides == 0 ? Tone.neutral : Tone.success, icon: Icons.directions_car_rounded),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// One event: details and the shared rides going there.
class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final event = state.eventById(eventId);
    if (event == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(fallback: '/events'), title: const Text('Event')),
        body: DataGate(
          builder: (context) => EmptyState(icon: Icons.event_busy_rounded, title: 'Event not found', message: 'It may have ended or been removed.', action: 'All events', onAction: () => context.go('/events')),
        ),
      );
    }
    final me = state.user!;
    final rides = state.ridesForEvent(event.id);
    final mine = event.organiserId == me.id;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/events'),
        title: const Text('Event rides'),
        actions: [
          if (mine)
            IconButton(
              tooltip: 'Remove this event',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Remove this event?'),
                    content: const Text('It leaves the list. Rides already offered to it stay open for their riders.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                final done = await attemptOk(context, () => state.removeEvent(event), success: 'Event removed');
                if (done && context.mounted) context.go('/events');
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.forest,
        onRefresh: state.refreshRider,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            MaxWidth(
              width: 760,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _DateBlock(event.startsAt),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          StatusPill(event.category.label, tone: Tone.brand, icon: event.category.icon),
                          const SizedBox(height: 6),
                          Text(event.title, style: text.headlineSmall),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _Line(icon: Icons.schedule_rounded, text: event.endsAt == null ? Fmt.dayTime(event.startsAt) : '${Fmt.dayTime(event.startsAt)} – ${Fmt.time(event.endsAt!)}'),
                    _Line(icon: Icons.place_rounded, text: '${event.venue}, ${event.area}'),
                    _Line(icon: Icons.campaign_rounded, text: 'Listed by ${event.organiserName}'),
                    if (event.description.isNotEmpty) ...[const SizedBox(height: 8), Text(event.description, style: text.bodyMedium)],
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      FilledButton.icon(onPressed: () => showOfferRideSheet(context, event: event), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Offer a ride there')),
                      OutlinedButton.icon(
                        onPressed: () => context.push(Uri(path: '/app/routes', queryParameters: {'q': event.area}).toString()),
                        icon: const Icon(Icons.directions_bus_rounded, size: 18),
                        label: Text('Buses to ${event.area}'),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 22),
                SectionHeader(title: 'Rides to this event', subtitle: rides.isEmpty ? 'Be the first to offer one' : '${rides.length} shared ride${rides.length == 1 ? '' : 's'} from verified members'),
                if (rides.any((r) => r.hostId == me.id)) ...[
                  HostRequestsPanel(rides: [for (final r in rides) if (r.hostId == me.id) r]),
                  const SizedBox(height: 14),
                ],
                if (rides.isEmpty)
                  const EmptyState(icon: Icons.groups_rounded, title: 'No rides yet', message: 'Driving there? Offer your empty seats and split the cost.')
                else
                  for (final r in rides)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: RideCard(ride: r, mine: r.hostId == me.id, request: state.bookingForRide(r.id)),
                    ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}

class _ListEventSheet extends StatefulWidget {
  const _ListEventSheet();

  @override
  State<_ListEventSheet> createState() => _ListEventSheetState();
}

class _ListEventSheetState extends State<_ListEventSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _venue = TextEditingController();
  final _area = TextEditingController();
  final _description = TextEditingController();
  EventCategory _category = EventCategory.community;
  late DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 16, minute: 0);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _venue, _area, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _startsAt => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      // Pin the venue when the place search knows it, so rides and maps can use it.
      final found = await state.api.geocode('${_venue.text.trim()} ${_area.text.trim()}');
      final point = found.firstOrNull?.point;
      final event = await state.createEvent(
        title: _title.text,
        venue: _venue.text,
        area: _area.text,
        startsAt: _startsAt,
        category: _category,
        description: _description.text,
        lat: point?.latitude,
        lng: point?.longitude,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push('/events/${event.id}');
      showMessage(context, 'Your event is listed. Offer a ride or share it with guests.');
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String? required(String? v) => (v == null || v.trim().length < 2) ? 'Required' : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('List an event', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text('Guests can then share rides to it. Events are public to signed-in riders.', style: text.bodySmall),
            const SizedBox(height: 18),
            TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Event name', hintText: 'Graduation party'), validator: (v) => (v == null || v.trim().length < 3) ? 'At least 3 letters' : null, maxLength: 120, buildCounter: _noCounter),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(flex: 3, child: TextFormField(controller: _venue, decoration: const InputDecoration(labelText: 'Venue', hintText: 'Millennium Park'), validator: required)),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: TextFormField(controller: _area, decoration: const InputDecoration(labelText: 'Area', hintText: 'Maitama'), validator: required)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: now, lastDate: now.add(const Duration(days: 365)));
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text('${Fmt.weekday(_date)} ${_date.day}/${_date.month}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: _time);
                    if (picked != null) setState(() => _time = picked);
                  },
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text('Starts ${Fmt.time(_startsAt)}'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<EventCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final c in EventCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (v) => setState(() => _category = v ?? EventCategory.community),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Details (optional)', hintText: 'Gate opens at 3 pm'), maxLines: 2, maxLength: 400, buildCounter: _noCounter),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('List my event'),
            ),
          ]),
        ),
      ),
    );
  }

  static Widget? _noCounter(BuildContext context, {required int currentLength, required bool isFocused, required int? maxLength}) => null;
}

/// Home-screen entry point: the next few events.
class EventsBanner extends StatelessWidget {
  const EventsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final next = state.events.where((e) => e.startsAt.isAfter(state.now)).take(2).toList();
    return Panel(
      onTap: () => context.push('/events'),
      semanticLabel: 'Event rides. Share a ride to events in Abuja.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconBadge(Icons.celebration_rounded, size: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Event rides', style: text.titleLarge),
              Text('Going out? Share the ride there and back.', style: text.bodySmall),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
        for (final e in next) ...[
          const Divider(height: 20),
          Row(children: [
            Icon(e.category.icon, size: 18, color: AppColors.forest),
            const SizedBox(width: 10),
            Expanded(child: Text(e.title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text('${Fmt.weekday(e.startsAt)} ${Fmt.time(e.startsAt)}', style: text.bodySmall),
          ]),
        ],
      ]),
    );
  }
}
