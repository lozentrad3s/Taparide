import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../core/models.dart';
import '../../core/photos.dart';
import '../../shared/ui.dart';
import '../passenger/rider_widgets.dart';

/// Tag Along: verified professionals sharing the ride home (mockup screen).
class TagAlongPage extends StatefulWidget {
  const TagAlongPage({super.key});

  @override
  State<TagAlongPage> createState() => _TagAlongPageState();
}

class _TagAlongPageState extends State<TagAlongPage> {
  final _ridesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().refreshRider());
  }

  void _findRide() {
    final target = _ridesKey.currentContext;
    if (target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 480), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final wide = isWide(context, 980);
    final me = state.user!;
    // Rides to events are listed on their event page.
    final rides = [for (final r in state.rides) if (r.eventId == null || r.hostId == me.id) r];
    final hosted = [for (final r in state.rides) if (r.hostId == me.id) r];

    final intro = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Share Rides. Save More.', style: wide ? text.displaySmall : text.headlineLarge),
      const SizedBox(height: 10),
      Text('Tag Along lets verified professionals share rides home with colleagues who live in the same area.', style: text.bodyLarge),
      const SizedBox(height: 16),
      for (final (icon, label) in const [
        (Icons.verified_user_rounded, 'Verified users only'),
        (Icons.shield_rounded, 'Safe & convenient'),
        (Icons.payments_rounded, 'Split cost, save more'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            IconBadge(icon, size: 34, radius: 17),
            const SizedBox(width: 12),
            Text(label, style: text.titleMedium),
          ]),
        ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton(onPressed: _findRide, style: FilledButton.styleFrom(minimumSize: const Size(160, 52)), child: const Text('Find a Ride')),
        OutlinedButton.icon(
          onPressed: () => showOfferRideSheet(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Offer a ride'),
        ),
      ]),
    ]);

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Tag Along')),
      body: DataGate(
        builder: (context) => RefreshIndicator(
          color: AppColors.forest,
          onRefresh: state.refreshRider,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              MaxWidth(
                width: 1080,
                padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 4, wide ? 32 : 18, 0),
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Expanded(child: intro),
                        const SizedBox(width: 36),
                        const Expanded(
                            child: SizedBox(
                                height: 400,
                                child: PhotoView(AppPhoto.taxis,
                                    radius: AppRadius.xl, alignment: Alignment(-0.2, 0), semanticLabel: 'Green and white Abuja taxis on the road'))),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const SizedBox(
                            height: 210,
                            child: PhotoView(AppPhoto.taxis,
                                radius: AppRadius.xl, alignment: Alignment(-0.2, 0.2), semanticLabel: 'Green and white Abuja taxis on the road')),
                        const SizedBox(height: 20),
                        intro,
                      ]),
              ),
              const SizedBox(height: 30),
              MaxWidth(
                key: _ridesKey,
                width: 1080,
                padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (hosted.isNotEmpty) ...[
                    HostRequestsPanel(rides: hosted),
                    const SizedBox(height: 22),
                  ],
                  SectionHeader(title: 'Rides leaving soon', subtitle: '${rides.length} shared rides from verified colleagues'),
                  if (rides.isEmpty)
                    const EmptyState(
                        icon: Icons.groups_rounded, title: 'No rides yet today', message: 'Be the first: offer your empty seats to colleagues going your way.')
                  else
                    Column(children: [
                      for (var i = 0; i < rides.length; i += wide ? 2 : 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              for (var j = i; j < i + (wide ? 2 : 1); j++) ...[
                                if (j > i) const SizedBox(width: 14),
                                Expanded(
                                  child: j < rides.length
                                      ? RideCard(ride: rides[j], mine: rides[j].hostId == me.id, request: state.bookingForRide(rides[j].id))
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ]),
                          ),
                        ),
                    ]),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One shared ride: join it, see your request, or (as host) withdraw it.
class RideCard extends StatefulWidget {
  const RideCard({super.key, required this.ride, required this.mine, required this.request});
  final SharedRide ride;
  final bool mine;
  final Booking? request;

  @override
  State<RideCard> createState() => RideCardState();
}

class RideCardState extends State<RideCard> {
  bool _busy = false;

  Future<void> _join() async {
    setState(() => _busy = true);
    await attempt(context, () => context.read<AppState>().requestSharedRide(widget.ride), success: 'Request sent to ${widget.ride.hostName}');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _withdraw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Withdraw this ride?'),
        content: const Text('Riders you accepted get their share back, and waiting requests are declined.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep ride')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await attemptOk(context, () => context.read<AppState>().cancelSharedRide(widget.ride), success: 'Ride withdrawn');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ride = widget.ride;
    final request = widget.request;
    final full = ride.seatsLeft == 0;
    Widget action;
    if (widget.mine) {
      action = TextButton(
        onPressed: _busy ? null : _withdraw,
        style: TextButton.styleFrom(foregroundColor: AppColors.red),
        child: const Text('Withdraw ride'),
      );
    } else if (request != null) {
      action = TextButton(
        onPressed: () => context.push('/ticket/${request.id}'),
        child: StatusPill(request.status.label, tone: BookingTile.toneFor(request.status)),
      );
    } else {
      action = FilledButton(
        onPressed: full || _busy ? null : _join,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        child: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(full ? 'Full' : 'Request to join'),
      );
    }

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(initials: ride.hostName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join(), size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(widget.mine ? 'You are hosting' : ride.hostName, style: text.titleMedium, overflow: TextOverflow.ellipsis)),
                if (ride.hostVerified) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, size: 16, color: AppColors.forest)],
              ]),
              Text(ride.hostOrg, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(Fmt.naira(ride.costShare), style: text.titleMedium?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
            Text('per seat', style: text.labelSmall),
          ]),
        ]),
        const SizedBox(height: 14),
        RouteStrip(origin: ride.origin, destination: ride.destination),
        const SizedBox(height: 10),
        Text('${Fmt.dayTime(ride.departAt)} · ${ride.vehicleLabel}', style: text.bodySmall),
        if (ride.note.isNotEmpty) ...[const SizedBox(height: 4), Text(ride.note, style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic))],
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.event_seat_rounded, size: 18, color: full ? AppColors.red : AppColors.leafText),
          const SizedBox(width: 6),
          Text(full ? 'No seats left' : '${ride.seatsLeft} of ${ride.seatsTotal} seats left',
              style: text.labelMedium?.copyWith(color: full ? AppColors.red : AppColors.leafText)),
          const Spacer(),
          action,
        ]),
      ]),
    );
  }
}

/// Requests waiting on the rides this user hosts, with accept and decline.
class HostRequestsPanel extends StatelessWidget {
  const HostRequestsPanel({super.key, required this.rides});
  final List<SharedRide> rides;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final ids = {for (final r in rides) r.id};
    final requests = [for (final b in state.rideRequests) if (ids.contains(b.rideId) && (b.status == BookingStatus.requested || b.status == BookingStatus.accepted)) b];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconBadge(Icons.how_to_reg_rounded, size: 38, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your ride requests', style: text.titleMedium),
              Text(
                requests.isEmpty ? 'No one has asked to join yet. Requests appear here.' : 'A rider\'s share is taken when you accept and paid to your Tap Card once the ride leaves.',
                style: text.bodySmall,
              ),
            ]),
          ),
        ]),
        for (final b in requests) ...[
          const Divider(height: 22),
          _RequestRow(request: b),
        ],
      ]),
    );
  }
}

class _RequestRow extends StatefulWidget {
  const _RequestRow({required this.request});
  final Booking request;

  @override
  State<_RequestRow> createState() => _RequestRowState();
}

class _RequestRowState extends State<_RequestRow> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    setState(() => _busy = true);
    await attemptOk(context, () => context.read<AppState>().respondToRideRequest(widget.request, accept: accept),
        success: accept ? '${widget.request.passengerName} is in. ${Fmt.naira(widget.request.fare)} is held for you.' : 'Request declined');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = widget.request;
    final waiting = b.status == BookingStatus.requested;
    return Row(children: [
      Avatar(initials: b.passengerName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join(), size: 38),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.passengerName, style: text.titleSmall, overflow: TextOverflow.ellipsis),
          Text('${b.origin} → ${b.destination} · ${Fmt.dayTime(b.departureAt)} · ${Fmt.naira(b.fare)}', style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
      const SizedBox(width: 8),
      if (!waiting)
        const StatusPill('Accepted', tone: Tone.success)
      else if (_busy)
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
      else ...[
        IconButton(tooltip: 'Decline ${b.passengerName}', onPressed: () => _answer(false), icon: const Icon(Icons.close_rounded, color: AppColors.red)),
        FilledButton(onPressed: () => _answer(true), style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)), child: const Text('Accept')),
      ],
    ]);
  }
}

/// Opens the offer sheet; with an [event] the ride goes to that event's venue.
Future<void> showOfferRideSheet(BuildContext context, {RideEvent? event}) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => OfferRideSheet(event: event));

class OfferRideSheet extends StatefulWidget {
  const OfferRideSheet({super.key, this.event});
  final RideEvent? event;

  @override
  State<OfferRideSheet> createState() => OfferRideSheetState();
}

class OfferRideSheetState extends State<OfferRideSheet> {
  final _form = GlobalKey<FormState>();
  final _origin = TextEditingController();
  late final _destination = TextEditingController(text: widget.event?.venue ?? '');
  final _vehicle = TextEditingController();
  final _note = TextEditingController();
  int _seats = 2;
  int _share = 1000;
  late TimeOfDay _time = widget.event == null ? const TimeOfDay(hour: 17, minute: 30) : TimeOfDay.fromDateTime(widget.event!.startsAt.subtract(const Duration(minutes: 90)));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_origin, _destination, _vehicle, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _departure() {
    final event = widget.event;
    // Event rides leave on the day of the event.
    if (event != null) return DateTime(event.startsAt.year, event.startsAt.month, event.startsAt.day, _time.hour, _time.minute);
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, _time.hour, _time.minute);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().offerSharedRide(
            origin: _origin.text,
            destination: _destination.text,
            departAt: _departure(),
            seats: _seats,
            costShare: _share,
            vehicleLabel: _vehicle.text,
            note: _note.text,
            eventId: widget.event?.id,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, widget.event == null ? 'Your ride is listed. Colleagues can now ask to join.' : 'Your ride to ${widget.event!.title} is listed.');
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
            Text(widget.event == null ? 'Offer a ride' : 'Offer a ride to this event', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(widget.event == null ? 'Share your empty seats with verified colleagues going your way.' : '${widget.event!.title} · ${Fmt.dayTime(widget.event!.startsAt)}. Riders pay their share through the app.', style: text.bodySmall),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                  child: TextFormField(controller: _origin, decoration: const InputDecoration(labelText: 'From', hintText: 'Wuse 2'), validator: required)),
              const SizedBox(width: 10),
              Expanded(
                  child:
                      TextFormField(controller: _destination, decoration: const InputDecoration(labelText: 'To', hintText: 'Gwarinpa'), validator: required)),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: _vehicle, decoration: const InputDecoration(labelText: 'Car', hintText: 'Toyota Corolla · silver'), validator: required),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: _time);
                    if (picked != null) setState(() => _time = picked);
                  },
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(widget.event == null ? 'Leaves ${Fmt.time(_departure())}' : 'Leaves ${Fmt.dayTime(_departure())}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _seats,
                  decoration: const InputDecoration(labelText: 'Seats'),
                  items: [for (var i = 1; i <= 4; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _seats = v ?? 2),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Text('Cost share per seat: ${Fmt.naira(_share)}', style: text.titleSmall),
            Slider(
              value: _share.toDouble(),
              min: 300,
              max: 3000,
              divisions: 27,
              activeColor: AppColors.forest,
              label: Fmt.naira(_share),
              onChanged: (v) => setState(() => _share = v.round()),
            ),
            TextFormField(
                controller: _note, decoration: const InputDecoration(labelText: 'Meeting point (optional)', hintText: 'Federal Secretariat car park')),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('List my ride'),
            ),
          ]),
        ),
      ),
    );
  }
}
