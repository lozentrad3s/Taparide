import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';

/// Events in Abuja from verified event partners, with tickets and event buses.
/// Riders cannot list events or offer rides here: partners post events, registered
/// operators run the buses, and riders book a seat at the time that suits them.
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
    final all = [for (final e in state.events) if (e.startsAt.isAfter(state.now.subtract(const Duration(hours: 3)))) e];
    final events = [for (final e in all) if (_filter == null || e.category == _filter) e];
    final categories = {for (final e in all) e.category}.toList()..sort((a, b) => a.index.compareTo(b.index));

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Events')),
      body: DataGate(
        builder: (context) => RefreshIndicator(
          color: AppColors.forest,
          onRefresh: state.refreshRider,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              MaxWidth(
                width: 1080,
                padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 8, wide ? 32 : 18, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('What\'s on in Abuja', style: wide ? text.displaySmall : text.headlineLarge),
                  const SizedBox(height: 8),
                  Text('Events from verified partners. Get your ticket, then book a seat on a bus from your area and pick the time that suits you.', style: text.bodyLarge),
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
                      message: 'Events appear here when our event partners post them. Organising one? Become an event partner.',
                      action: 'Become an event partner',
                      onAction: () => context.push('/partner/apply'),
                    )
                  else
                    for (var i = 0; i < events.length; i += wide ? 2 : 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            for (var j = i; j < i + (wide ? 2 : 1); j++) ...[
                              if (j > i) const SizedBox(width: 14),
                              Expanded(child: j < events.length ? EventCard(event: events[j], buses: state.busesForEvent(events[j].id)) : const SizedBox.shrink()),
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
class EventDateBlock extends StatelessWidget {
  const EventDateBlock(this.date, {super.key});
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

String _priceLabel(RideEvent e) => !e.sellsTickets ? 'Free entry' : (e.ticketPrice == 0 ? 'Free ticket' : Fmt.naira(e.ticketPrice));

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.buses});
  final RideEvent event;
  final List<EventBus> buses;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final origins = {for (final b in buses) b.origin}.toList();
    return Panel(
      onTap: () => context.push('/events/${event.id}'),
      semanticLabel: '${event.title}, ${Fmt.dayTime(event.startsAt)} at ${event.venue}. ${buses.length} buses.',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        EventDateBlock(event.startsAt),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(event.category.icon, size: 15, color: AppColors.muted),
              const SizedBox(width: 5),
              Flexible(child: Text(event.category.label, style: text.labelSmall)),
              if (event.sponsored) ...[const SizedBox(width: 8), const StatusPill('Sponsored', tone: Tone.info)],
            ]),
            const SizedBox(height: 2),
            Text(event.title, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${Fmt.time(event.startsAt)} · ${event.venue}, ${event.area}', style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusPill(_priceLabel(event), tone: Tone.brand, icon: Icons.local_activity_rounded),
              StatusPill(
                buses.isEmpty ? 'Buses coming soon' : '${buses.length} bus${buses.length == 1 ? '' : 'es'} · ${origins.take(3).join(', ')}',
                tone: buses.isEmpty ? Tone.neutral : Tone.success,
                icon: Icons.directions_bus_rounded,
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// One event: tickets and the buses going there.
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
    final buses = state.busesForEvent(event.id)..sort((a, b) => a.origin.compareTo(b.origin));
    final myTickets = [for (final b in state.myBookings) if (b.eventId == event.id && b.kind == BookingKind.eventTicket && b.status.isOpen) b];

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(fallback: '/events'), title: const Text('Event')),
      body: RefreshIndicator(
        color: AppColors.forest,
        onRefresh: state.refreshRider,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            MaxWidth(
              width: 760,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      EventDateBlock(event.startsAt),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            StatusPill(event.category.label, tone: Tone.brand, icon: event.category.icon),
                            if (event.sponsored) const StatusPill('Sponsored', tone: Tone.info),
                          ]),
                          const SizedBox(height: 6),
                          Text(event.title, style: text.headlineSmall),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _Line(icon: Icons.schedule_rounded, text: event.endsAt == null ? Fmt.dayTime(event.startsAt) : '${Fmt.dayTime(event.startsAt)} – ${Fmt.time(event.endsAt!)}'),
                    _Line(icon: Icons.place_rounded, text: '${event.venue}, ${event.area}'),
                    _Line(icon: Icons.verified_rounded, text: 'Listed by ${event.organiserName}, a verified event partner'),
                    if (event.description.isNotEmpty) ...[const SizedBox(height: 8), Text(event.description, style: text.bodyMedium)],
                  ]),
                ),
                const SizedBox(height: 14),
                _TicketPanel(event: event, held: myTickets.length),
                const SizedBox(height: 22),
                SectionHeader(
                  title: 'Buses to this event',
                  subtitle: buses.isEmpty ? 'Registered operators add buses here' : 'Book a seat and pick your time. The operator confirms the most popular time.',
                ),
                if (buses.isEmpty)
                  EmptyState(
                    icon: Icons.directions_bus_rounded,
                    title: 'No buses yet',
                    message: 'Operators usually add buses in the days before an event. Meanwhile, regular routes go to ${event.area}.',
                    action: 'Routes to ${event.area}',
                    onAction: () => context.push(Uri(path: '/app/routes', queryParameters: {'q': event.area}).toString()),
                  )
                else
                  for (final b in buses)
                    Padding(padding: const EdgeInsets.only(bottom: 14), child: EventBusCard(bus: b, event: event)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketPanel extends StatelessWidget {
  const _TicketPanel({required this.event, required this.held});
  final RideEvent event;
  final int held;

  Future<void> _buy(BuildContext context) async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(event.ticketPrice == 0 ? 'Get a free ticket?' : 'Buy a ticket for ${Fmt.naira(event.ticketPrice)}?'),
        content: Text(event.ticketPrice == 0
            ? 'Your ticket appears in My Trips with a QR code for the gate.'
            : 'Paid from your Tap A Ride wallet (balance ${Fmt.naira(state.wallet?.balance ?? 0)}). Refunded if you cancel before the event or it is called off.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(event.ticketPrice == 0 ? 'Get ticket' : 'Pay ${Fmt.naira(event.ticketPrice)}')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final booking = await attempt(context, () => state.buyEventTicket(event, PaymentMethod.tapCard), success: 'Ticket booked. It\'s in My Trips.');
    if (booking != null && context.mounted) context.push('/ticket/${booking.id}');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!event.sellsTickets) {
      return Panel(
        color: AppColors.mint,
        border: false,
        shadow: false,
        child: Row(children: [
          const Icon(Icons.local_activity_rounded, color: AppColors.forest),
          const SizedBox(width: 12),
          Expanded(child: Text(event.ticketLink == null ? 'Free entry, or tickets sold by the organiser. Book your bus below.' : 'Tickets are sold by the organiser. Book your bus below.', style: text.bodyMedium)),
        ]),
      );
    }
    final soldOut = event.ticketsLeft <= 0;
    return Panel(
      child: Row(children: [
        const IconBadge(Icons.local_activity_rounded, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.ticketPrice == 0 ? 'Free ticket' : '${Fmt.naira(event.ticketPrice)} per ticket', style: text.titleMedium),
            Text(
              [soldOut ? 'Sold out' : '${Fmt.count(event.ticketsLeft)} left', if (held > 0) 'You have $held'].join(' · '),
              style: text.bodySmall,
            ),
          ]),
        ),
        FilledButton(onPressed: soldOut ? null : () => _buy(context), child: Text(held > 0 ? 'Buy another' : 'Get ticket')),
      ]),
    );
  }
}

/// A bus to an event: departure times with how many riders picked each, and the rider's seat.
class EventBusCard extends StatefulWidget {
  const EventBusCard({super.key, required this.bus, required this.event});
  final EventBus bus;
  final RideEvent event;

  @override
  State<EventBusCard> createState() => _EventBusCardState();
}

class _EventBusCardState extends State<EventBusCard> {
  DateTime? _slot;
  bool _busy = false;

  Future<void> _book() async {
    final bus = widget.bus;
    final slot = bus.status == EventBusStatus.confirmed ? bus.confirmedAt! : (_slot ?? bus.popularSlot!);
    final state = context.read<AppState>();
    final confirmed = bus.status == EventBusStatus.confirmed;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Book a seat from ${bus.origin}?'),
        content: Text(confirmed
            ? 'Leaves ${Fmt.dayTime(slot)}. ${Fmt.naira(bus.fare)} is paid from your wallet now.'
            : 'You picked ${Fmt.time(slot)}. ${Fmt.naira(bus.fare)} is held from your wallet. The operator confirms the time most riders pick; if the bus doesn\'t run, you get it back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Pay ${Fmt.naira(bus.fare)}')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await attempt(context, () => state.bookEventBus(bus, slot, PaymentMethod.tapCard), success: confirmed ? 'Seat booked. Your ticket is in My Trips.' : 'Seat held. We\'ll tell you when the time is confirmed.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final bus = widget.bus;
    final mine = state.myEventBusSeat(bus.id);
    final confirmed = bus.status == EventBusStatus.confirmed;
    final riders = bus.riders;
    final progress = (riders / bus.minRiders).clamp(0.0, 1.0);
    final chosen = _slot ?? bus.popularSlot;

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconBadge(Icons.directions_bus_filled_rounded, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${bus.origin} → ${widget.event.venue}', style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text([bus.providerName, if (bus.vehicleLabel.isNotEmpty) bus.vehicleLabel].join(' · '), style: text.bodySmall),
            ]),
          ),
          const SizedBox(width: 8),
          Text(Fmt.naira(bus.fare), style: text.titleLarge?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 14),
        if (confirmed)
          StatusPill('Confirmed · leaves ${Fmt.time(bus.confirmedAt!)}', tone: Tone.success, icon: Icons.check_circle_rounded)
        else ...[
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: AppColors.surfaceSunk, color: AppColors.leaf),
              ),
            ),
            const SizedBox(width: 10),
            Text(riders >= bus.minRiders ? '$riders riders · goal met' : '$riders of ${bus.minRiders} riders', style: text.labelMedium),
          ]),
          const SizedBox(height: 4),
          Text(riders >= bus.minRiders ? 'Enough riders: the operator will confirm a time soon.' : 'Goes ahead once ${bus.minRiders} riders book. ${bus.capacity} seats.', style: text.bodySmall),
          const SizedBox(height: 12),
          Text('Pick your departure time', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in bus.slots)
              ChoiceChip(
                label: Text('${Fmt.time(s)} · ${bus.seatsAt(s)} going'),
                selected: chosen != null && s.isAtSameMomentAs(chosen),
                onSelected: mine == null ? (_) => setState(() => _slot = s) : null,
              ),
          ]),
        ],
        const SizedBox(height: 14),
        if (mine != null)
          Row(children: [
            const Icon(Icons.event_seat_rounded, color: AppColors.forest, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mine.status == BookingStatus.confirmed ? 'Your seat ${mine.seat ?? ''} · leaves ${Fmt.time(mine.departureAt)}' : 'Seat held for ${Fmt.time(mine.departureAt)} · waiting for the operator',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: () => context.push('/ticket/${mine.id}'), child: const Text('Ticket')),
          ])
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _book,
              icon: const Icon(Icons.event_seat_rounded, size: 18),
              label: Text(confirmed ? 'Book a seat · ${Fmt.time(bus.confirmedAt!)}' : 'Book a seat · ${chosen == null ? '' : Fmt.time(chosen)}'),
            ),
          ),
      ]),
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
      semanticLabel: 'Events and event buses in Abuja.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconBadge(Icons.celebration_rounded, size: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Events & event buses', style: text.titleLarge),
              Text('Tickets and a bus seat from your area.', style: text.bodySmall),
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
