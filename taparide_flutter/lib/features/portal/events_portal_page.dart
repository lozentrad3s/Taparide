import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';
import '../events/events_page.dart' show EventDateBlock;
import 'money_page.dart' show SeatBookingsPanel;
import 'portal_widgets.dart';

/// Events in the partner portal.
/// - Event partners post events and follow tickets, bus seats and arrivals by area and time.
/// - Bus operators put buses on events and confirm the departure time riders chose.
/// - FCTA and admins see everything.
class EventsPortalPage extends StatelessWidget {
  const EventsPortalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final role = state.user!.role;
    return switch (role) {
      UserRole.eventPartner => const _PartnerEvents(),
      UserRole.operator => const _OperatorEvents(),
      _ => const _AllEvents(),
    };
  }
}

// ---------------------------------------------------------------- event partner

class _PartnerEvents extends StatelessWidget {
  const _PartnerEvents();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.user!;
    final org = state.providerById(me.providerId);
    final mine = [for (final e in state.events) if (e.providerId != null && e.providerId == me.providerId) e]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final ids = {for (final e in mine) e.id};
    final buses = [for (final b in state.eventBuses) if (ids.contains(b.eventId)) b];
    final tickets = mine.fold<int>(0, (a, e) => a + e.ticketsSold);
    final ticketRevenue = mine.fold<int>(0, (a, e) => a + e.ticketsSold * e.ticketPrice);
    final seats = buses.fold<int>(0, (a, b) => a + b.riders);
    final verified = org?.status == Verification.verified;

    return PortalScaffold(
      title: 'Your events',
      subtitle: '${org?.name ?? me.organisation ?? me.fullName} · tickets, buses and who is coming when',
      actions: [
        FilledButton.icon(
          onPressed: verified ? () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _PostEventSheet()) : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Post an event'),
        ),
      ],
      children: [
        if (!verified)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Panel(child: Text('Your organisation is waiting for verification. You can post events once an admin or FCTA approves it.')),
          ),
        Cols(children: [
          FigureCard(label: 'Upcoming events', value: '${mine.where((e) => e.startsAt.isAfter(state.now)).length}', icon: Icons.event_rounded),
          FigureCard(label: 'Tickets sold', value: Fmt.count(tickets), icon: Icons.local_activity_rounded),
          FigureCard(label: 'Ticket revenue', value: Fmt.naira(ticketRevenue), icon: Icons.payments_rounded),
          FigureCard(label: 'Bus seats booked', value: Fmt.count(seats), icon: Icons.directions_bus_rounded, caption: '${buses.length} buses from ${{for (final b in buses) b.origin}.length} areas'),
        ]),
        const SizedBox(height: PortalSpace.gap),
        // Free buses Tap A Ride runs for this organiser's events (booked on taparide.com).
        const SeatBookingsPanel(),
        const SizedBox(height: PortalSpace.gap),
        if (mine.isEmpty)
          const Panel(child: EmptyState(icon: Icons.celebration_rounded, title: 'No events yet', message: 'Post your first event. Riders see it on the Events page, buy tickets and book buses from their area.'))
        else
          for (final e in mine) Padding(padding: const EdgeInsets.only(bottom: 14), child: _EventAnalytics(event: e, buses: [for (final b in buses) if (b.eventId == e.id) b])),
      ],
    );
  }
}

/// Tickets, buses and arrivals by area and time for one event.
class _EventAnalytics extends StatelessWidget {
  const _EventAnalytics({required this.event, required this.buses});
  final RideEvent event;
  final List<EventBus> buses;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    // Arrivals: riders per departure time, across every bus.
    final byTime = <DateTime, int>{};
    for (final b in buses) {
      for (final s in b.slots) {
        final n = b.status == EventBusStatus.confirmed ? (s.isAtSameMomentAs(b.confirmedAt!) ? b.riders : 0) : b.seatsAt(s);
        if (n > 0) byTime[s] = (byTime[s] ?? 0) + n;
      }
    }
    final times = byTime.keys.toList()..sort();
    final peak = byTime.values.fold<int>(1, (a, b) => a > b ? a : b);

    return Panel(
      radius: AppRadius.md,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EventDateBlock(event.startsAt),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, style: text.titleLarge),
              Text('${Fmt.dayTime(event.startsAt)} · ${event.venue}, ${event.area}', style: text.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                StatusPill(event.sellsTickets ? '${Fmt.count(event.ticketsSold)} / ${Fmt.count(event.ticketsTotal)} tickets' : 'No ticket sales', tone: Tone.brand, icon: Icons.local_activity_rounded),
                if (event.sellsTickets) StatusPill(Fmt.naira(event.ticketsSold * event.ticketPrice), tone: Tone.success, icon: Icons.payments_rounded),
                StatusPill('${buses.fold<int>(0, (a, b) => a + b.riders)} bus riders', tone: Tone.info, icon: Icons.directions_bus_rounded),
              ]),
            ]),
          ),
          IconButton(
            tooltip: 'Remove event',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Remove this event?'),
                  content: const Text('It leaves the Events page. Everyone with a ticket or bus seat is refunded automatically.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove and refund')),
                  ],
                ),
              );
              if (ok == true && context.mounted) await attemptOk(context, () => state.removeEvent(event), success: 'Event removed. Riders refunded.');
            },
          ),
        ]),
        if (event.sellsTickets) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: event.ticketsTotal == 0 ? 0 : event.ticketsSold / event.ticketsTotal, minHeight: 8, backgroundColor: AppColors.surfaceSunk, color: AppColors.leaf),
          ),
        ],
        const Divider(height: 28),
        Text('Who is coming, and when', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(buses.isEmpty ? 'No buses yet. Bus operators see your event and add buses from their areas.' : 'Riders per bus departure time.', style: text.bodySmall),
        const SizedBox(height: 10),
        for (final t in times)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 72, child: Text(Fmt.time(t), style: text.labelLarge)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: byTime[t]! / peak, minHeight: 14, backgroundColor: AppColors.surfaceSunk, color: AppColors.forest),
                ),
              ),
              SizedBox(width: 56, child: Text('${byTime[t]}', textAlign: TextAlign.right, style: text.labelLarge)),
            ]),
          ),
        if (buses.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('By area', style: text.titleSmall),
          const SizedBox(height: 6),
          for (final b in buses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.directions_bus_rounded, size: 18, color: AppColors.forest),
                const SizedBox(width: 8),
                Expanded(child: Text('${b.origin} · ${b.providerName}', style: text.bodyMedium)),
                StatusPill(
                  b.status == EventBusStatus.confirmed ? 'Leaves ${Fmt.time(b.confirmedAt!)}' : '${b.riders}/${b.minRiders} to go ahead',
                  tone: b.status == EventBusStatus.confirmed ? Tone.success : (b.riders >= b.minRiders ? Tone.info : Tone.warning),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _PostEventSheet extends StatefulWidget {
  const _PostEventSheet();

  @override
  State<_PostEventSheet> createState() => _PostEventSheetState();
}

class _PostEventSheetState extends State<_PostEventSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _venue = TextEditingController();
  final _area = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController(text: '0');
  final _count = TextEditingController(text: '0');
  EventCategory _category = EventCategory.conference;
  late DateTime _date = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _venue, _area, _description, _price, _count]) {
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
      final found = await state.api.geocode('${_venue.text.trim()} ${_area.text.trim()}');
      final point = found.firstOrNull?.point;
      await state.createEvent(
        title: _title.text,
        venue: _venue.text,
        area: _area.text,
        startsAt: _startsAt,
        category: _category,
        description: _description.text,
        lat: point?.latitude,
        lng: point?.longitude,
        ticketPrice: int.tryParse(_price.text.trim()) ?? 0,
        ticketsTotal: int.tryParse(_count.text.trim()) ?? 0,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, 'Event posted. Riders can see it now, and bus operators can add buses.');
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
    String? whole(String? v) => int.tryParse((v ?? '').trim()) == null ? 'Whole number' : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Post an event', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text('It appears on the Events page for every rider. Bus operators can then add buses to it.', style: text.bodySmall),
            const SizedBox(height: PortalSpace.gap),
            TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Event name'), validator: (v) => (v == null || v.trim().length < 3) ? 'At least 3 letters' : null),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(flex: 3, child: TextFormField(controller: _venue, decoration: const InputDecoration(labelText: 'Venue', hintText: 'Moshood Abiola National Stadium'), validator: required)),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: TextFormField(controller: _area, decoration: const InputDecoration(labelText: 'Area', hintText: 'Kukwaba'), validator: required)),
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
              onChanged: (v) => setState(() => _category = v ?? EventCategory.other),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ticket price (₦)', helperText: '0 = free'), validator: whole)),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tickets to sell', helperText: '0 = not sold here'), validator: whole)),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Details (optional)', hintText: 'Gates open at 5 pm'), maxLines: 2),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Post event'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- bus operator

class _OperatorEvents extends StatelessWidget {
  const _OperatorEvents();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.user!;
    final upcoming = [for (final e in state.events) if (e.startsAt.isAfter(state.now)) e]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final mine = [for (final b in state.eventBuses) if (b.providerId == me.providerId) b];
    return PortalScaffold(
      title: 'Event buses',
      subtitle: 'Put buses on partner events. Riders pick a time; you confirm the most popular one.',
      children: [
        Cols(children: [
          FigureCard(label: 'Your event buses', value: '${mine.length}', icon: Icons.directions_bus_rounded),
          FigureCard(label: 'Riders booked', value: Fmt.count(mine.fold<int>(0, (a, b) => a + b.riders)), icon: Icons.groups_rounded),
          FigureCard(label: 'Expected takings', value: Fmt.naira(mine.fold<int>(0, (a, b) => a + b.riders * b.fare)), icon: Icons.payments_rounded),
          FigureCard(label: 'Upcoming events', value: '${upcoming.length}', icon: Icons.event_rounded),
        ]),
        const SizedBox(height: PortalSpace.gap),
        if (upcoming.isEmpty)
          const Panel(child: EmptyState(icon: Icons.event_busy_rounded, title: 'No upcoming events', message: 'Partner events appear here as soon as they are posted.'))
        else
          for (final e in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _OperatorEventPanel(event: e, buses: [for (final b in mine) if (b.eventId == e.id) b], others: state.busesForEvent(e.id).where((b) => b.providerId != me.providerId).length),
            ),
      ],
    );
  }
}

class _OperatorEventPanel extends StatelessWidget {
  const _OperatorEventPanel({required this.event, required this.buses, required this.others});
  final RideEvent event;
  final List<EventBus> buses;
  final int others;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final add = FilledButton.icon(
      onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _OfferBusSheet(event: event)),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Add a bus'),
    );
    return Panel(
      radius: AppRadius.md,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final head = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            EventDateBlock(event.startsAt),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(event.title, style: text.titleLarge),
                Text('${Fmt.dayTime(event.startsAt)} · ${event.venue}, ${event.area}', style: text.bodySmall),
                Text('By ${event.organiserName}${others > 0 ? ' · $others bus${others == 1 ? '' : 'es'} from other operators' : ''}', style: text.bodySmall),
              ]),
            ),
          ]);
          return c.maxWidth >= 560
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: head), const SizedBox(width: 12), add])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, const SizedBox(height: 12), add]);
        }),
        for (final b in buses) ...[const Divider(height: 28), _OperatorBusRow(bus: b)],
      ]),
    );
  }
}

class _OperatorBusRow extends StatefulWidget {
  const _OperatorBusRow({required this.bus});
  final EventBus bus;

  @override
  State<_OperatorBusRow> createState() => _OperatorBusRowState();
}

class _OperatorBusRowState extends State<_OperatorBusRow> {
  DateTime? _slot;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final text = Theme.of(context).textTheme;
    final bus = widget.bus;
    final confirmed = bus.status == EventBusStatus.confirmed;
    final pick = _slot ?? bus.popularSlot;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.directions_bus_filled_rounded, color: AppColors.forest),
        const SizedBox(width: 10),
        Expanded(child: Text('From ${bus.origin} · ${Fmt.naira(bus.fare)} · ${bus.capacity} seats${bus.vehicleLabel.isEmpty ? '' : ' · ${bus.vehicleLabel}'}', style: text.titleSmall)),
        const SizedBox(width: 8),
        StatusPill(confirmed ? 'Confirmed ${Fmt.time(bus.confirmedAt!)}' : '${bus.riders}/${bus.minRiders} riders', tone: confirmed ? Tone.success : (bus.riders >= bus.minRiders ? Tone.info : Tone.warning)),
      ]),
      const SizedBox(height: 10),
      if (!confirmed) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in bus.slots)
            ChoiceChip(
              label: Text('${Fmt.time(s)} · ${bus.seatsAt(s)}'),
              selected: pick != null && s.isAtSameMomentAs(pick),
              onSelected: (_) => setState(() => _slot = s),
            ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton(
            onPressed: pick == null || bus.riders == 0 ? null : () => attemptOk(context, () => state.confirmEventBus(bus, pick), success: 'Departure confirmed for ${Fmt.time(pick)}. Riders are notified in the app.'),
            child: Text(pick == null ? 'Confirm time' : 'Confirm ${Fmt.time(pick)}'),
          ),
          OutlinedButton(onPressed: () => _cancel(context, state), child: const Text('Cancel bus')),
        ]),
      ] else
        OutlinedButton(onPressed: () => _cancel(context, state), child: const Text('Cancel bus and refund riders')),
    ]);
  }

  Future<void> _cancel(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Cancel this bus?'),
        content: Text('${widget.bus.riders} riders are refunded to their wallets automatically.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep the bus')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cancel bus')),
        ],
      ),
    );
    if (ok == true && context.mounted) await attemptOk(context, () => state.cancelEventBus(widget.bus), success: 'Bus cancelled. Riders refunded.');
  }
}

class _OfferBusSheet extends StatefulWidget {
  const _OfferBusSheet({required this.event});
  final RideEvent event;

  @override
  State<_OfferBusSheet> createState() => _OfferBusSheetState();
}

class _OfferBusSheetState extends State<_OfferBusSheet> {
  final _form = GlobalKey<FormState>();
  final _origin = TextEditingController();
  final _fare = TextEditingController(text: '1200');
  final _capacity = TextEditingController(text: '30');
  final _min = TextEditingController(text: '15');
  String? _vehicleId;
  late final List<DateTime> _slots = [
    for (final h in [3, 2, 1])
      if (widget.event.startsAt.subtract(Duration(hours: h)).isAfter(DateTime.now())) widget.event.startsAt.subtract(Duration(hours: h)),
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_origin, _fare, _capacity, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addSlot() async {
    final e = widget.event.startsAt;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(e.subtract(const Duration(hours: 2))));
    if (picked == null) return;
    final t = DateTime(e.year, e.month, e.day, picked.hour, picked.minute);
    if (!t.isBefore(e)) {
      setState(() => _error = 'Departures must be before the event starts at ${Fmt.time(e)}.');
      return;
    }
    setState(() {
      _error = null;
      if (!_slots.any((s) => s.isAtSameMomentAs(t))) _slots.add(t);
      _slots.sort();
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_slots.isEmpty) {
      setState(() => _error = 'Add at least one departure time.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      await state.offerEventBus(
        event: widget.event,
        origin: _origin.text,
        fare: int.parse(_fare.text.trim()),
        capacity: int.parse(_capacity.text.trim()),
        minRiders: int.parse(_min.text.trim()),
        slots: _slots,
        vehicleId: _vehicleId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, 'Bus added. Riders can book seats and pick a time now.');
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
    final me = state.user!;
    final vehicles = [for (final v in state.vehicles) if (v.operatorId == me.providerId && v.verification == Verification.verified && !v.kind.isBookableCar) v];
    String? number(String? v, int lo, int hi) {
      final n = int.tryParse((v ?? '').trim());
      return n == null || n < lo || n > hi ? 'Between $lo and $hi' : null;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add a bus to ${widget.event.title}', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text('To ${widget.event.venue} · event starts ${Fmt.dayTime(widget.event.startsAt)}', style: text.bodySmall),
            const SizedBox(height: PortalSpace.gap),
            TextFormField(controller: _origin, decoration: const InputDecoration(labelText: 'Leaves from', hintText: 'Kubwa'), validator: (v) => (v == null || v.trim().length < 2) ? 'Required' : null),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _fare, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fare (₦)'), validator: (v) => number(v, 100, 20000))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _capacity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Seats'), validator: (v) => number(v, 4, 90))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _min, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Goes ahead at'), validator: (v) => number(v, 1, 90))),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _vehicleId,
              decoration: const InputDecoration(labelText: 'Vehicle (optional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Assign later')),
                for (final v in vehicles) DropdownMenuItem<String?>(value: v.id, child: Text('${v.model} · ${v.plate} · ${v.capacity} seats')),
              ],
              onChanged: (v) => setState(() => _vehicleId = v),
            ),
            const SizedBox(height: 14),
            Text('Departure times riders can pick (up to 4)', style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in _slots) InputChip(label: Text(Fmt.time(s)), onDeleted: () => setState(() => _slots.remove(s))),
              if (_slots.length < 4) ActionChip(avatar: const Icon(Icons.add_rounded, size: 16), label: const Text('Add time'), onPressed: _addSlot),
            ]),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Add bus'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- FCTA and admin

class _AllEvents extends StatelessWidget {
  const _AllEvents();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final events = [...state.events]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final admin = state.user!.role == UserRole.admin;
    return PortalScaffold(
      title: 'Events & event buses',
      subtitle: 'Every partner event, its tickets and the buses going there',
      actions: [
        if (admin)
          FilledButton.icon(
            onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _PostEventSheet()),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Post sponsored event'),
          ),
      ],
      children: [
        Cols(children: [
          FigureCard(label: 'Listed events', value: '${events.length}', icon: Icons.event_rounded),
          FigureCard(label: 'Tickets sold', value: Fmt.count(events.fold<int>(0, (a, e) => a + e.ticketsSold)), icon: Icons.local_activity_rounded),
          FigureCard(label: 'Event buses', value: '${state.eventBuses.length}', icon: Icons.directions_bus_rounded),
          FigureCard(label: 'Bus riders', value: Fmt.count(state.eventBuses.fold<int>(0, (a, b) => a + b.riders)), icon: Icons.groups_rounded),
        ]),
        const SizedBox(height: PortalSpace.gap),
        if (admin || state.user!.role == UserRole.government) ...[const SeatBookingsPanel(), const SizedBox(height: PortalSpace.gap)],
        if (events.isEmpty)
          const Panel(child: EmptyState(icon: Icons.event_busy_rounded, title: 'No events', message: 'Partner events appear here.'))
        else
          for (final e in events) Padding(padding: const EdgeInsets.only(bottom: 14), child: _EventAnalytics(event: e, buses: state.busesForEvent(e.id))),
      ],
    );
  }
}
