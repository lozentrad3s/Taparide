import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
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
    final rides = state.rides;

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
          onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _OfferRideSheet()),
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
                        const Expanded(child: SizedBox(height: 400, child: PhotoView(AppPhoto.brtLifeCamp, radius: AppRadius.xl, alignment: Alignment(-0.1, -0.2), semanticLabel: 'Commuters boarding a green bus at Life Camp, Abuja'))),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const SizedBox(height: 210, child: PhotoView(AppPhoto.brtLifeCamp, radius: AppRadius.xl, alignment: Alignment(-0.1, -0.35), semanticLabel: 'Commuters boarding a green bus at Life Camp, Abuja')),
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
                  SectionHeader(title: 'Rides leaving soon', subtitle: '${rides.length} shared rides from verified colleagues'),
                  if (rides.isEmpty)
                    const EmptyState(icon: Icons.groups_rounded, title: 'No rides yet today', message: 'Be the first: offer your empty seats to colleagues going your way.')
                  else
                    Wrap(spacing: 14, runSpacing: 14, children: [
                      for (final ride in rides)
                        SizedBox(
                          width: wide ? (1080 - 64 - 14) / 2 : double.infinity,
                          child: _RideCard(ride: ride, mine: ride.hostId == me.id, request: state.bookingForRide(ride.id)),
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

class _RideCard extends StatefulWidget {
  const _RideCard({required this.ride, required this.mine, required this.request});
  final SharedRide ride;
  final bool mine;
  final Booking? request;

  @override
  State<_RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<_RideCard> {
  bool _busy = false;

  Future<void> _join() async {
    setState(() => _busy = true);
    await attempt(context, () => context.read<AppState>().requestSharedRide(widget.ride), success: 'Request sent to ${widget.ride.hostName}');
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
      action = const StatusPill('Your ride', tone: Tone.brand);
    } else if (request != null) {
      action = TextButton(
        onPressed: () => context.push('/ticket/${request.id}'),
        child: StatusPill(request.status.label, tone: BookingTile.toneFor(request.status)),
      );
    } else {
      action = FilledButton(
        onPressed: full || _busy ? null : _join,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(full ? 'Full' : 'Request to join'),
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
                Flexible(child: Text(ride.hostName, style: text.titleMedium, overflow: TextOverflow.ellipsis)),
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
          Text(full ? 'No seats left' : '${ride.seatsLeft} of ${ride.seatsTotal} seats left', style: text.labelMedium?.copyWith(color: full ? AppColors.red : AppColors.leafText)),
          const Spacer(),
          action,
        ]),
      ]),
    );
  }
}

class _OfferRideSheet extends StatefulWidget {
  const _OfferRideSheet();

  @override
  State<_OfferRideSheet> createState() => _OfferRideSheetState();
}

class _OfferRideSheetState extends State<_OfferRideSheet> {
  final _form = GlobalKey<FormState>();
  final _origin = TextEditingController();
  final _destination = TextEditingController();
  final _vehicle = TextEditingController();
  final _note = TextEditingController();
  int _seats = 2;
  int _share = 1000;
  TimeOfDay _time = const TimeOfDay(hour: 17, minute: 30);
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
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(context, 'Your ride is listed. Colleagues can now ask to join.');
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
            Text('Offer a ride', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text('Share your empty seats with verified colleagues going your way.', style: text.bodySmall),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: TextFormField(controller: _origin, decoration: const InputDecoration(labelText: 'From', hintText: 'Wuse 2'), validator: required)),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _destination, decoration: const InputDecoration(labelText: 'To', hintText: 'Gwarinpa'), validator: required)),
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
                  label: Text('Leaves ${Fmt.time(_departure())}'),
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
            TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Meeting point (optional)', hintText: 'Federal Secretariat car park')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('List my ride'),
            ),
          ]),
        ),
      ),
    );
  }
}
