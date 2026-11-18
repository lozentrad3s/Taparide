import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/fleet_drivers.dart';
import '../../core/fleet_positions.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../core/models.dart';
import '../../shared/route_map.dart';
import '../../shared/ui.dart';
import 'partner_widgets.dart' show LiveTrackerPanel;
import 'portal_widgets.dart';

const _lime = Color(0xFF8CE01F);

/// Dashboard for a driver employed by a fleet owner or operator: today's vehicle and route,
/// the riders booked on it, event-bus seats to board, where demand is on the route, and
/// live GPS sharing. Drivers see only their own vehicle; admins can preview any driver.
class FleetDriverDashboard extends StatefulWidget {
  const FleetDriverDashboard({super.key, this.driverId});
  final String? driverId;

  @override
  State<FleetDriverDashboard> createState() => _FleetDriverDashboardState();
}

class _FleetDriverDashboardState extends State<FleetDriverDashboard> {
  String? _picked;
  int? _hour;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final admin = user.role == UserRole.admin;
    final withLogin = [for (final d in state.fleetDrivers) if (d.hasLogin) d];
    final driver = admin ? (state.fleetDriverById(_picked ?? widget.driverId) ?? withLogin.firstOrNull ?? state.fleetDrivers.firstOrNull) : state.myDriverRecord;
    final picker = admin && state.fleetDrivers.length > 1 && driver != null
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: DropdownButtonFormField<String>(
              initialValue: driver.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Preview driver', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              items: [for (final d in state.fleetDrivers) DropdownMenuItem(value: d.id, child: Text(d.fullName, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _picked = v),
            ),
          )
        : null;

    if (driver == null) {
      return PortalScaffold(
        title: 'Driver dashboard',
        children: [
          Panel(
            child: EmptyState(
              icon: Icons.badge_rounded,
              title: admin ? 'No fleet drivers yet' : 'Not linked to a fleet yet',
              message: admin ? 'Drivers appear here once a fleet owner or operator adds them.' : 'Ask your fleet manager to add you as a driver with ${user.email}. Your vehicle and riders show up here once they do.',
            ),
          ),
        ],
      );
    }

    final company = state.providerById(driver.providerId);
    final vehicle = state.vehicleById(driver.vehicleId);
    final subtitle = [company?.name ?? user.organisation ?? 'Fleet driver', if (vehicle != null) vehicle.displayName].join(' · ');
    if (!driver.active || vehicle == null) {
      return PortalScaffold(
        title: 'Driver dashboard',
        subtitle: subtitle,
        actions: [if (picker != null) picker],
        children: [
          Panel(
            child: EmptyState(
              icon: driver.active ? Icons.no_transfer_rounded : Icons.block_rounded,
              title: driver.active ? 'No vehicle assigned yet' : 'Your driver access is suspended',
              message: driver.active
                  ? '${company?.name ?? 'Your fleet manager'} has not put you on a vehicle yet. Your route, riders and departures show up here once they do.'
                  : 'You cannot see riders or share your location until ${company?.name ?? 'your fleet manager'} reactivates you. Contact them if you think this is a mistake.',
            ),
          ),
        ],
      );
    }

    final route = state.routeById(driver.routeId);
    // Without a fixed route, demand is shown for the operator's busiest route (the area they work).
    final demandRoute = route ?? ([for (final r in state.routes) if (r.active && r.providerId == vehicle.operatorId && r.stops.length > 1) r]..sort((a, b) => b.monthlyTrips.compareTo(a.monthlyTrips))).firstOrNull;
    final buses = [for (final b in state.eventBuses) if (b.vehicleId == vehicle.id && b.status != EventBusStatus.cancelled) b];
    final busIds = {for (final b in buses) b.id};
    final bookings = [for (final b in state.partnerBookings) if (b.vehicleId == vehicle.id || busIds.contains(b.eventBusId)) b];
    final rides = [for (final b in bookings) if (b.kind != BookingKind.eventBus && b.kind != BookingKind.eventTicket) b];
    final now = state.now;
    bool isToday(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
    final waiting = rides.where((b) => b.status == BookingStatus.confirmed && b.departureAt.isAfter(now.subtract(const Duration(hours: 1)))).length;
    final boarded = rides.where((b) => b.status == BookingStatus.accepted).length;
    final doneToday = rides.where((b) => b.status == BookingStatus.completed && isToday(b.departureAt)).length;
    final eventSeats = buses.fold<int>(0, (s, b) => s + b.riders);
    final departures = route?.upcomingDepartures(now, count: 6) ?? const <DateTime>[];
    final demand = demandRoute == null ? null : RouteDemand.build(route: demandRoute, bookings: [for (final b in rides) if (b.routeId == demandRoute.id) b]);
    final hour = (_hour ?? now.hour).clamp(RouteDemand.firstHour, RouteDemand.lastHour);

    Widget twoUp(Widget left, Widget right, {int leftFlex = 1, int rightFlex = 1}) => LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 980
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: leftFlex, child: left), const SizedBox(width: 16), Expanded(flex: rightFlex, child: right)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 16), right]),
        );

    return PortalScaffold(
      title: 'Driver dashboard',
      subtitle: subtitle,
      actions: [if (picker != null) picker],
      children: [
        _ShiftHero(driver: driver, vehicle: vehicle, route: route, next: departures.firstOrNull, readOnly: admin),
        const SizedBox(height: 16),
        Cols(min: 160, max: 4, children: [
          FigureCard(label: 'Riders waiting', value: '$waiting', icon: Icons.hail_rounded, caption: 'booked on your vehicle'),
          FigureCard(label: 'On board', value: '$boarded', icon: Icons.airline_seat_recline_normal_rounded, caption: 'boarded or accepted'),
          FigureCard(label: 'Completed today', value: '$doneToday', icon: Icons.flag_rounded, caption: 'trips dropped off'),
          FigureCard(label: 'Event seats', value: '$eventSeats', icon: Icons.celebration_rounded, caption: buses.isEmpty ? 'no event buses yet' : 'on ${buses.length} event bus${buses.length == 1 ? '' : 'es'}'),
        ]),
        const SizedBox(height: 16),
        twoUp(
          _DeparturesPanel(route: route, departures: departures, rides: rides, now: now),
          _RidesPanel(rides: rides, now: now, readOnly: admin),
          leftFlex: 2,
          rightFlex: 3,
        ),
        const SizedBox(height: 16),
        _EventRidesPanel(buses: buses, bookings: bookings, readOnly: admin),
        const SizedBox(height: 16),
        if (demand != null) ...[
          twoUp(
            _DemandMap(demand: demand, hour: hour, vehicle: vehicle, assigned: route != null),
            _DemandGrid(demand: demand, hour: hour, now: now, onHour: (h) => setState(() => _hour = h)),
            leftFlex: 5,
            rightFlex: 6,
          ),
          const SizedBox(height: 16),
        ],
        if (!admin) LiveTrackerPanel(vehicles: [vehicle]),
      ],
    );
  }
}

// ---------------------------------------------------------------- shift hero

class _ShiftHero extends StatefulWidget {
  const _ShiftHero({required this.driver, required this.vehicle, required this.route, required this.next, required this.readOnly});
  final FleetDriver driver;
  final Vehicle vehicle;
  final TransitRoute? route;
  final DateTime? next;
  final bool readOnly;

  @override
  State<_ShiftHero> createState() => _ShiftHeroState();
}

class _ShiftHeroState extends State<_ShiftHero> {
  bool _busy = false;

  Future<void> _toggle(bool start) async {
    setState(() => _busy = true);
    await attemptOk(context, () => context.read<AppState>().driverSetTrip(start: start), success: start ? 'Trip started. Drive safely.' : 'Trip ended. Boarded riders are dropped off.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final v = widget.vehicle;
    final route = widget.route;
    final onTrip = v.status == VehicleStatus.onTrip;
    final next = widget.next;
    final live = state.livePosition(v.id) != null;
    final minutes = next?.difference(state.now).inMinutes;

    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${Fmt.greeting(state.now)}, ${widget.driver.firstName}', style: text.headlineSmall?.copyWith(color: Colors.white)),
      const SizedBox(height: 4),
      Text("Today's assignment", style: text.labelLarge?.copyWith(color: AppColors.onForestMuted)),
      const SizedBox(height: 12),
      Row(children: [
        IconBadge(v.kind.icon, size: 44, color: Colors.white.withValues(alpha: 0.12), iconColor: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.displayName, style: text.titleMedium?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${v.model} · ${v.capacity} seats', style: text.bodySmall?.copyWith(color: AppColors.onForestMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: _lime, borderRadius: BorderRadius.circular(8)),
          child: Text(route?.code ?? 'ANY', style: const TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w800, fontSize: 14)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(route?.title ?? 'No fixed route today', style: text.titleSmall?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(route == null ? 'Your fleet manager sends you where riders are' : '${route.stops.length} stops · ${Fmt.minutes(route.durationMin)} · ${Fmt.naira(route.fare)} fare', style: text.bodySmall?.copyWith(color: AppColors.onForestMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    ]);

    final trip = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Next departure', style: text.labelLarge?.copyWith(color: AppColors.onForestMuted)),
      const SizedBox(height: 2),
      Text(next == null ? '—' : Fmt.time(next), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, height: 1.1, fontFeatures: tabular)),
      Text(
        next == null ? 'No timetable for today' : (minutes! <= 0 ? 'Now' : 'in ${Fmt.minutes(minutes)}${next.day != state.now.day ? ' (tomorrow)' : ''}'),
        style: text.bodySmall?.copyWith(color: AppColors.onForestMuted),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        StatusPill(onTrip ? 'On trip' : v.status.label, tone: onTrip ? Tone.success : (v.status == VehicleStatus.active ? Tone.info : Tone.warning)),
        StatusPill(live ? 'Sharing GPS' : 'GPS off', tone: live ? Tone.success : Tone.neutral, icon: live ? Icons.my_location_rounded : Icons.location_disabled_rounded),
      ]),
      if (!widget.readOnly) ...[
        const SizedBox(height: 12),
        if (_busy)
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: _lime))
        else if (onTrip)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
            onPressed: () => _toggle(false),
            icon: const Icon(Icons.flag_rounded, size: 18),
            label: const Text('End trip'),
          )
        else
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: AppColors.forestDeep),
            onPressed: () => _toggle(true),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Start trip'),
          ),
      ],
    ]);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0E6B45), AppColors.forestDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 720
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: info),
                Container(width: 1, height: 170, margin: const EdgeInsets.symmetric(horizontal: 24), color: Colors.white.withValues(alpha: 0.18)),
                SizedBox(width: 260, child: trip),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, Divider(height: 32, color: Colors.white.withValues(alpha: 0.18)), trip]),
      ),
    );
  }
}

// ---------------------------------------------------------------- departures

class _DeparturesPanel extends StatelessWidget {
  const _DeparturesPanel({required this.route, required this.departures, required this.rides, required this.now});
  final TransitRoute? route;
  final List<DateTime> departures;
  final List<Booking> rides;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = route;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle('Departures', subtitle: r == null ? 'You are not on a timetable today' : '${r.origin} → ${r.destination} · every ${_gap(r)} min'),
        if (departures.isEmpty)
          Text('Riders book your vehicle directly; their requests appear under Bookings.', style: text.bodyMedium)
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (i, d) in departures.indexed) _DepartureTile(at: d, booked: rides.where((b) => b.status.isOpen && b.departureAt.isAtSameMomentAs(d)).length, next: i == 0),
          ]),
        if (r != null) ...[
          const SizedBox(height: 14),
          Text('Stops', style: text.titleSmall),
          const SizedBox(height: 6),
          for (final (i, s) in r.stops.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: i == 0 || i == r.stops.length - 1 ? AppColors.forest : Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.forest, width: 2)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.name, style: text.bodyMedium?.copyWith(color: AppColors.ink))),
                Text('${rides.where((b) => b.status.isOpen && b.origin == s.name).length} waiting', style: text.bodySmall),
              ]),
            ),
        ],
      ]),
    );
  }

  static int _gap(TransitRoute r) {
    if (r.departures.length < 2) return 60;
    int m(String t) => int.parse(t.split(':')[0]) * 60 + int.parse(t.split(':')[1]);
    return m(r.departures[1]) - m(r.departures[0]);
  }
}

class _DepartureTile extends StatelessWidget {
  const _DepartureTile({required this.at, required this.booked, required this.next});
  final DateTime at;
  final int booked;
  final bool next;

  @override
  Widget build(BuildContext context) => Container(
        width: 98,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: next ? _lime : AppColors.surfaceSunk,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: next ? _lime : AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Fmt.time(at), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.forestDeep, fontFeatures: tabular)),
          Text('$booked booked', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: next ? AppColors.forestDeep : AppColors.muted)),
        ]),
      );
}

// ---------------------------------------------------------------- bookings and ride requests

class _RidesPanel extends StatelessWidget {
  const _RidesPanel({required this.rides, required this.now, required this.readOnly});
  final List<Booking> rides;
  final DateTime now;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final open = [for (final b in rides) if (b.status == BookingStatus.confirmed || b.status == BookingStatus.accepted) b]..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    final done = [for (final b in rides) if (b.status == BookingStatus.completed) b]..sort((a, b) => b.departureAt.compareTo(a.departureAt));
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle('Bookings & ride requests', subtitle: open.isEmpty ? 'Nobody waiting right now' : '${open.length} rider${open.length == 1 ? '' : 's'} booked on your vehicle'),
        if (open.isEmpty) Text('New bookings on your vehicle appear here as riders make them.', style: text.bodyMedium),
        for (final (i, b) in open.take(12).indexed) ...[
          if (i > 0) const Divider(height: 1),
          _BookingRow(booking: b, now: now, readOnly: readOnly),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Completed: ${done.take(4).map((b) => '${b.passengerName.split(' ').first} ${Fmt.time(b.departureAt)}').join(' · ')}${done.length > 4 ? ' and ${done.length - 4} more' : ''}', style: text.bodySmall),
        ],
      ]),
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.booking, required this.now, required this.readOnly});
  final Booking booking;
  final DateTime now;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = booking;
    final car = b.kind == BookingKind.electric;
    final boarded = b.status == BookingStatus.accepted;
    final when = isSameDay(b.departureAt, now) ? Fmt.time(b.departureAt) : Fmt.dayTime(b.departureAt);
    final action = readOnly
        ? null
        : boarded
            ? _ActionButton(label: car ? 'Complete' : 'Drop off', icon: Icons.flag_rounded, booking: b, action: DriverBookingAction.complete, filled: false)
            : _ActionButton(label: car ? 'Accept' : 'Board', icon: car ? Icons.check_rounded : Icons.login_rounded, booking: b, action: DriverBookingAction.accept, filled: true);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Avatar(initials: b.passengerName.split(' ').where((p) => p.isNotEmpty && p[0] != '(').map((p) => p[0]).take(2).join(), size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.passengerName, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(car ? '${b.origin} → ${b.destination} · $when' : 'From ${b.origin} · $when${b.seat == null ? '' : ' · seat ${b.seat}'}', style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          StatusPill(boarded ? (car ? 'Accepted' : 'On board') : (car ? 'Request' : 'Booked'), tone: boarded ? Tone.success : Tone.info),
          if (action != null) ...[const SizedBox(height: 6), action],
        ]),
      ]),
    );
  }
}

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _ActionButton extends StatefulWidget {
  const _ActionButton({required this.label, required this.icon, required this.booking, required this.action, required this.filled});
  final String label;
  final IconData icon;
  final Booking booking;
  final DriverBookingAction action;
  final bool filled;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    final name = widget.booking.passengerName.split(' ').first;
    await attemptOk(context, () => context.read<AppState>().driverBookingAction(widget.booking, widget.action), success: widget.action == DriverBookingAction.accept ? '$name is on board' : '$name dropped off');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    const size = Size(0, 34);
    if (_busy) return const SizedBox(width: 34, height: 34, child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)));
    return widget.filled
        ? FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.forest, foregroundColor: Colors.white, padding: pad, minimumSize: size, visualDensity: VisualDensity.compact),
            onPressed: _run,
            icon: Icon(widget.icon, size: 16),
            label: Text(widget.label),
          )
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(padding: pad, minimumSize: size, visualDensity: VisualDensity.compact),
            onPressed: _run,
            icon: Icon(widget.icon, size: 16),
            label: Text(widget.label),
          );
  }
}

// ---------------------------------------------------------------- event rides

class _EventRidesPanel extends StatelessWidget {
  const _EventRidesPanel({required this.buses, required this.bookings, required this.readOnly});
  final List<EventBus> buses;
  final List<Booking> bookings;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle('Event rides', subtitle: buses.isEmpty ? 'No event buses on your vehicle yet' : 'Seats per departure time and who to board'),
        if (buses.isEmpty) Text('When your company puts your vehicle on an event bus, riders and their pick-up times appear here.', style: text.bodyMedium),
        for (final (i, bus) in buses.indexed) ...[
          if (i > 0) const Divider(height: 28),
          _EventBusCard(bus: bus, event: state.eventById(bus.eventId), riders: [for (final b in bookings) if (b.eventBusId == bus.id && b.status != BookingStatus.cancelled) b]..sort((a, b) => a.passengerName.compareTo(b.passengerName)), readOnly: readOnly),
        ],
      ]),
    );
  }
}

class _EventBusCard extends StatelessWidget {
  const _EventBusCard({required this.bus, required this.event, required this.riders, required this.readOnly});
  final EventBus bus;
  final RideEvent? event;
  final List<Booking> riders;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final confirmed = bus.status == EventBusStatus.confirmed && bus.confirmedAt != null;
    final named = riders.length;
    final guests = math.max(0, bus.riders - named);
    final seats = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Seats by departure time', style: text.titleSmall),
      const SizedBox(height: 8),
      for (final s in bus.slots)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 64, child: Text(Fmt.time(s), style: text.titleSmall?.copyWith(fontFeatures: tabular))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: bus.capacity == 0 ? 0 : (bus.seatsAt(s) / bus.capacity).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: AppColors.surfaceSunk,
                  color: confirmed && bus.confirmedAt!.isAtSameMomentAs(s) ? AppColors.leaf : AppColors.forest,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 56, child: Text('${bus.seatsAt(s)}/${bus.capacity}', textAlign: TextAlign.right, style: text.bodySmall?.copyWith(fontFeatures: tabular))),
          ]),
        ),
      const SizedBox(height: 4),
      Text(confirmed ? 'Leaves at ${Fmt.time(bus.confirmedAt!)}. Board riders below.' : 'The operator fixes the time once ${bus.minRiders} riders have booked (${bus.riders} so far).', style: text.bodySmall),
    ]);
    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Riders to board', style: text.titleSmall),
      const SizedBox(height: 4),
      if (riders.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('No named riders yet.', style: text.bodySmall)),
      for (final b in riders)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(6)),
              child: Text(b.seat ?? '—', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.forest)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.passengerName, style: text.bodyMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${b.ticketCode} · ${Fmt.time(b.departureAt)}', style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (b.status == BookingStatus.confirmed && !readOnly)
              _ActionButton(label: 'Board', icon: Icons.login_rounded, booking: b, action: DriverBookingAction.accept, filled: true)
            else
              StatusPill(b.status == BookingStatus.accepted ? 'On board' : b.statusLabel, tone: b.status == BookingStatus.accepted || b.status == BookingStatus.completed ? Tone.success : Tone.warning),
          ]),
        ),
      if (guests > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('+ $guests more booked through partners; check their tickets at the door.', style: text.bodySmall)),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const IconBadge(Icons.celebration_rounded, size: 40, radius: 12),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event?.title ?? 'Event bus', style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${bus.origin} → ${event?.venue ?? 'venue'}${event == null ? '' : ' · ${Fmt.day(event!.startsAt)}'}', style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        StatusPill(confirmed ? 'Confirmed' : 'Collecting riders', tone: confirmed ? Tone.success : Tone.warning),
      ]),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 760
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: seats), const SizedBox(width: 24), Expanded(child: list)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [seats, const SizedBox(height: 16), list]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- demand

Color _heat(double t) {
  if (t < 0.34) return Color.lerp(AppColors.mintStrong, _lime, t / 0.34)!;
  if (t < 0.67) return Color.lerp(_lime, const Color(0xFFF2B233), (t - 0.34) / 0.33)!;
  return Color.lerp(const Color(0xFFF2B233), const Color(0xFFD9452B), (t - 0.67) / 0.33)!;
}

class _DemandMap extends StatelessWidget {
  const _DemandMap({required this.demand, required this.hour, required this.vehicle, required this.assigned});
  final RouteDemand demand;
  final int hour;
  final Vehicle vehicle;
  final bool assigned;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final route = demand.route;
    final points = [for (final s in route.stops) LatLng(s.lat, s.lng)];
    final hourPeak = math.max(1, [for (var s = 0; s < route.stops.length; s++) demand.atStop(s, hour)].reduce(math.max));
    final live = state.livePosition(vehicle.id);
    final here = live?.point ?? FleetPositions.along(route.stops, ((state.now.minute + state.now.second / 60) % route.durationMin.clamp(10, 120)) / route.durationMin.clamp(10, 120));
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle(
          assigned ? 'Demand on your route' : 'Demand in your area',
          subtitle: '${route.code} · ${route.title} · ${hour.toString().padLeft(2, '0')}:00–${(hour + 1).toString().padLeft(2, '0')}:00',
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 300,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(44), maxZoom: 14) : null,
                initialCenter: points.isEmpty ? const LatLng(9.0579, 7.4951) : points.first,
                initialZoom: 12,
                backgroundColor: const Color(0xFFEAF1EC),
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.scrollWheelZoom),
              ),
              children: [
                if (MapTiles.enabled)
                  TileLayer(urlTemplate: MapTiles.urlTemplate, subdomains: MapTiles.subdomains, retinaMode: RetinaMode.isHighDensity(context), userAgentPackageName: 'com.taparide.app'),
                PolylineLayer(polylines: [Polyline(points: points, strokeWidth: 5, color: AppColors.forest.withValues(alpha: 0.7), borderStrokeWidth: 2, borderColor: Colors.white)]),
                CircleLayer(circles: [
                  for (var s = 0; s < route.stops.length; s++)
                    CircleMarker(
                      point: points[s],
                      radius: 10 + 24 * math.sqrt(demand.atStop(s, hour) / hourPeak),
                      color: _heat(demand.atStop(s, hour) / demand.peak).withValues(alpha: 0.55),
                      borderColor: _heat(demand.atStop(s, hour) / demand.peak),
                      borderStrokeWidth: 2,
                    ),
                ]),
                MarkerLayer(markers: [
                  for (var s = 0; s < route.stops.length; s++)
                    Marker(
                      point: points[s],
                      width: 34,
                      height: 22,
                      child: Center(
                        child: Text('${demand.atStop(s, hour)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.forestDeep)),
                      ),
                    ),
                  Marker(
                    point: here,
                    width: 32,
                    height: 32,
                    child: Container(
                      decoration: BoxDecoration(
                        color: live != null ? AppColors.forest : AppColors.muted,
                        shape: BoxShape.circle,
                        border: Border.all(color: _lime, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 5, offset: Offset(0, 1))],
                      ),
                      child: Icon(vehicle.kind.icon, size: 16, color: Colors.white),
                    ),
                  ),
                ]),
                const MapCredit(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final (label, t) in const [('Quiet', 0.1), ('Busy', 0.5), ('Peak', 0.95)])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: _heat(t), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: text.bodySmall),
            ]),
          Text(live != null ? 'Your bus: live GPS' : 'Your bus: estimated (share GPS below)', style: text.bodySmall),
        ]),
      ]),
    );
  }
}

class _DemandGrid extends StatelessWidget {
  const _DemandGrid({required this.demand, required this.hour, required this.now, required this.onHour});
  final RouteDemand demand;
  final int hour;
  final DateTime now;
  final ValueChanged<int> onHour;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stops = demand.route.stops;
    final busiest = demand.busiestHour;
    const cell = 30.0;
    const labelWidth = 118.0;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelTitle('When riders board', subtitle: 'Riders per stop and hour · busiest ${busiest.toString().padLeft(2, '0')}:00 · tap an hour to map it'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(width: labelWidth),
              for (final h in demand.hours)
                InkWell(
                  onTap: () => onHour(h),
                  child: SizedBox(
                    width: cell,
                    height: 24,
                    child: Center(
                      child: Text(
                        h.toString().padLeft(2, '0'),
                        style: TextStyle(fontSize: 11, fontWeight: h == hour ? FontWeight.w800 : FontWeight.w600, color: h == hour ? AppColors.forest : AppColors.muted, fontFeatures: tabular),
                      ),
                    ),
                  ),
                ),
            ]),
            for (var s = 0; s < stops.length; s++)
              Row(children: [
                SizedBox(width: labelWidth, child: Text(stops[s].name, style: text.bodySmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                for (final h in demand.hours)
                  Tooltip(
                    message: '${stops[s].name} · ${h.toString().padLeft(2, '0')}:00 · ${demand.atStop(s, h)} riders${demand.cell(s, h).booked > 0 ? ' (${demand.cell(s, h).booked} booked)' : ''}',
                    child: InkWell(
                      onTap: () => onHour(h),
                      child: Container(
                        width: cell - 2,
                        height: cell - 2,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: _heat(demand.atStop(s, h) / demand.peak),
                          borderRadius: BorderRadius.circular(5),
                          border: h == hour ? Border.all(color: AppColors.forestDeep, width: 2) : null,
                        ),
                        child: demand.cell(s, h).booked > 0 ? const Center(child: Icon(Icons.circle, size: 6, color: AppColors.forestDeep)) : null,
                      ),
                    ),
                  ),
              ]),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
          'Estimated from the route\'s last 30 days of ridership and a typical Abuja weekday; dots mark hours with riders booked on your vehicle. '
          'Peak now: ${_topStop(demand, (now.hour).clamp(RouteDemand.firstHour, RouteDemand.lastHour))}.',
          style: text.bodySmall,
        ),
      ]),
    );
  }

  static String _topStop(RouteDemand d, int hour) {
    var best = 0;
    for (var s = 1; s < d.route.stops.length; s++) {
      if (d.atStop(s, hour) > d.atStop(best, hour)) best = s;
    }
    return '${d.route.stops[best].name} (${d.atStop(best, hour)} riders this hour)';
  }
}
