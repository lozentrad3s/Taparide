import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/photos.dart';
import '../../core/places.dart';
import '../../shared/ui.dart';
import '../passenger/rider_widgets.dart';



class EvPage extends StatelessWidget {
  const EvPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final wide = isWide(context, 900);
    final evs = state.availableEvs;
    final free = evs.where((v) => v.status == VehicleStatus.active).toList();
    final busy = evs.where((v) => v.status != VehicleStatus.active).toList();

    return Scaffold(
      body: DataGate(
        builder: (context) => CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: wide ? 300 : 240,
            backgroundColor: AppColors.forestDeep,
            foregroundColor: Colors.white,
            leading: const AppBackButton(color: Colors.white),
            systemOverlayStyle: SystemUiOverlayStyle.light,
            title: Text('Electric vehicles', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
            flexibleSpace: const FlexibleSpaceBar(
              background: PhotoView(
                AppPhoto.evPlug,
                semanticLabel: 'An electric car plugged into a charging station',
                overlay: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x9906331F), Color(0x2206331F), Color(0xCC06331F)]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: MaxWidth(
              width: 980,
              padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 22, wide ? 32 : 18, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Zero-emission rides, booked in seconds', style: text.headlineMedium),
                const SizedBox(height: 6),
                Text('Verified electric cars with their live battery level. The fare is fixed before you confirm.', style: text.bodyMedium),
                const SizedBox(height: 18),
                SectionHeader(title: 'Available now', subtitle: '${free.length} of ${evs.length} cars free'),
              ]),
            ),
          ),
          if (free.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(icon: Icons.ev_station_rounded, title: 'All cars are busy', message: 'Every electric car is on a trip or charging. Check again in a few minutes.'),
            )
          else
            SliverList.builder(
              itemCount: free.length,
              itemBuilder: (context, i) => MaxWidth(
                width: 980,
                padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 0, wide ? 32 : 18, 12),
                child: _EvCard(vehicle: free[i], provider: state.providerById(free[i].operatorId)?.name),
              ),
            ),
          if (busy.isNotEmpty)
            SliverToBoxAdapter(
              child: MaxWidth(
                width: 980,
                padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 12, wide ? 32 : 18, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SectionHeader(title: 'Busy or charging'),
                  for (final v in busy)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Panel(
                        shadow: false,
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          IconBadge(v.status == VehicleStatus.charging ? Icons.ev_station_rounded : Icons.electric_car_rounded, size: 40, color: AppColors.surfaceSunk, iconColor: AppColors.muted),
                          const SizedBox(width: 12),
                          Expanded(child: Text('${v.model} · ${v.plate}', style: text.titleSmall)),
                          StatusPill(v.status.label, tone: v.status == VehicleStatus.charging ? Tone.info : Tone.neutral),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          SliverToBoxAdapter(
            child: MaxWidth(
              width: 980,
              padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 18, wide ? 32 : 18, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionHeader(title: 'Charging stations'),
                for (final s in state.stations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      shadow: false,
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const IconBadge(Icons.ev_station_rounded, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, style: text.titleSmall),
                            Text(s.area, style: text.bodySmall),
                          ]),
                        ),
                        Text('${s.available}/${s.ports} free', style: text.labelLarge?.copyWith(color: s.available > 0 ? AppColors.leafText : AppColors.red)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _EvCard extends StatelessWidget {
  const _EvCard({required this.vehicle, required this.provider});
  final Vehicle vehicle;
  final String? provider;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final battery = vehicle.batteryPct ?? 0;
    return Panel(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(builder: (context, c) {
        final row = c.maxWidth > 560;
        final photo = SizedBox(width: row ? 220 : double.infinity, height: row ? 168 : 150, child: const PhotoView(AppPhoto.evCharging, alignment: Alignment(0.2, 0.3)));
        final body = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(vehicle.model, style: text.titleLarge)),
              if (vehicle.verification == Verification.verified) const StatusPill('Verified', tone: Tone.success, icon: Icons.verified_rounded),
            ]),
            const SizedBox(height: 2),
            Text([vehicle.plate, '${vehicle.capacity} seats', vehicle.area, if (provider != null) provider!].join(' · '), style: text.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              Icon(battery > 50 ? Icons.battery_5_bar_rounded : Icons.battery_3_bar_rounded, size: 18, color: battery > 30 ? AppColors.leafText : AppColors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: battery / 100, minHeight: 7, color: battery > 30 ? AppColors.leaf : AppColors.amber, backgroundColor: AppColors.mint),
                ),
              ),
              const SizedBox(width: 10),
              Text('$battery% · ${vehicle.rangeKm ?? 0} km range', style: text.labelMedium),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Text('from ${Fmt.naira(vehicle.baseFare ?? 1200)}', style: text.titleMedium?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
              const Spacer(),
              FilledButton(onPressed: () => _book(context), child: const Text('Book')),
            ]),
          ]),
        );
        return row ? Row(children: [photo, Expanded(child: body)]) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [photo, body]);
      }),
    );
  }

  void _book(BuildContext context) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _EvBookingSheet(vehicle: vehicle));
  }
}

class _EvBookingSheet extends StatefulWidget {
  const _EvBookingSheet({required this.vehicle});
  final Vehicle vehicle;

  @override
  State<_EvBookingSheet> createState() => _EvBookingSheetState();
}

class _EvBookingSheetState extends State<_EvBookingSheet> {
  String _pickup = 'Wuse 2';
  String _dropoff = 'Gwarinpa';
  bool _busy = false;
  String? _error;

  Future<void> _confirm(int fare) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final booking = await context.read<AppState>().bookElectric(widget.vehicle, pickup: _pickup, dropoff: _dropoff, fare: fare, method: PaymentMethod.tapCard);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push('/ticket/${booking.id}');
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = context.watch<AppState>();
    final same = _pickup == _dropoff;
    final km = same ? 0.0 : roadKm(_pickup, _dropoff);
    final fare = carFare(widget.vehicle, km);
    final eta = carEta(widget.vehicle, _pickup);
    final short = (state.wallet?.balance ?? 0) < fare;
    DropdownButtonFormField<String> place(String label, String value, ValueChanged<String> onChanged, IconData icon) => DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
          items: [for (final p in evPlaceNames) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: (v) => v == null ? null : onChanged(v),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Book ${widget.vehicle.model}', style: text.headlineSmall),
        Text('${widget.vehicle.plate} · driver ${widget.vehicle.driverName ?? 'assigned at pickup'}', style: text.bodySmall),
        const SizedBox(height: 18),
        place('Pickup', _pickup, (v) => setState(() => _pickup = v), Icons.trip_origin_rounded),
        const SizedBox(height: 12),
        place('Drop-off', _dropoff, (v) => setState(() => _dropoff = v), Icons.location_on_rounded),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(children: [
            Expanded(child: Text(same ? 'Choose a different drop-off.' : '${km.toStringAsFixed(1)} km · pickup in about $eta min', style: text.titleSmall)),
            Text(Fmt.naira(fare), style: text.headlineSmall?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(height: 8),
        Text('Paid from your Tap Card (balance ${Fmt.naira(state.wallet?.balance ?? 0)}).', style: text.bodySmall),
        if (short) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.amber),
            const SizedBox(width: 6),
            const Expanded(child: Text('Your balance is too low for this fare.', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600))),
            TextButton(onPressed: () => showTopUpSheet(context, suggested: fare - (state.wallet?.balance ?? 0)), child: const Text('Top up')),
          ]),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || same || short ? null : () => _confirm(fare),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text('Confirm ride · ${Fmt.naira(fare)}'),
        ),
      ]),
    );
  }
}
