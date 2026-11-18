import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/photos.dart';
import '../../shared/ui.dart';
import 'dashboard_pages.dart';
import 'portal_widgets.dart';

String _routeLabel(TransitRoute r) => r.name ?? '${r.origin} – ${r.destination}';

// ------------------------------------------------------------------ providers

class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  Verification? _filter;

  Future<void> _set(TransportProvider p, Verification status) async {
    if (status == Verification.suspended) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Suspend ${p.name}?'),
          content: const Text('Their routes and vehicles stop taking bookings immediately. Riders with existing tickets keep them.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), style: FilledButton.styleFrom(backgroundColor: AppColors.red), child: const Text('Suspend')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await attemptOk(context, () => context.read<AppState>().setProviderStatus(p, status), success: '${p.name}: ${status.label.toLowerCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final admin = state.user!.role == UserRole.admin;
    final text = Theme.of(context).textTheme;
    final list = [for (final p in state.providers) if (_filter == null || p.status == _filter) p];
    int count(String id, bool routes) => routes ? state.routes.where((r) => r.providerId == id).length : state.vehicles.where((v) => v.operatorId == id || v.ownerId == id).length;

    return PortalScaffold(
      title: 'Transport providers',
      subtitle: 'Operators, fleet owners, rail, EV and keke partners across the FCT',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in <Verification?>[null, ...Verification.values])
            ChoiceChip(
              label: Text(f == null ? 'All (${state.providers.length})' : '${f.label} (${state.providers.where((p) => p.status == f).length})'),
              selected: _filter == f,
              showCheckmark: false,
              labelStyle: TextStyle(color: _filter == f ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
              onSelected: (_) => setState(() => _filter = f),
            ),
        ]),
        const SizedBox(height: 14),
        DataList<TransportProvider>(
          items: list,
          columns: [
            Col('Provider', flex: 4, (p) => Row(children: [
                  IconBadge(p.kind.icon, size: 36, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                      Text(p.kind.label, style: text.bodySmall),
                    ]),
                  ),
                ])),
            Col('Area', (p) => Text(p.area, style: text.bodyMedium)),
            Col('Routes', flex: 1, numeric: true, (p) => Text('${count(p.id, true)}', style: text.titleSmall)),
            Col('Vehicles', flex: 1, numeric: true, (p) => Text('${count(p.id, false)}', style: text.titleSmall)),
            Col('Joined', (p) => Text(Fmt.date(p.joinedAt), style: text.bodySmall)),
            Col('Status', (p) => StatusPill(p.status.label, tone: verificationTone(p.status))),
          ],
          trailing: (p) => Row(mainAxisSize: MainAxisSize.min, children: [
            if (p.status != Verification.verified) TextButton(onPressed: () => _set(p, Verification.verified), child: Text(p.status == Verification.suspended ? 'Reinstate' : 'Approve')),
            if (admin && p.status != Verification.suspended)
              TextButton(onPressed: () => _set(p, Verification.suspended), style: TextButton.styleFrom(foregroundColor: AppColors.red), child: const Text('Suspend')),
          ]),
          onTap: (p) => showDialog<void>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text(p.name),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                StatusPill(p.status.label, tone: verificationTone(p.status)),
                const SizedBox(height: 12),
                Text(p.description),
                const SizedBox(height: 12),
                Text('Contact: ${p.contactName} · ${p.contactEmail}', style: text.bodySmall),
                Text('${p.kind.label} · ${p.area} · joined ${Fmt.date(p.joinedAt)}', style: text.bodySmall),
              ]),
              actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ electric vehicles

class EvFleetPage extends StatelessWidget {
  const EvFleetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final text = Theme.of(context).textTheme;
    final evs = [
      for (final v in state.vehicles)
        if (v.electric && v.kind != VehicleKind.train && (user.role != UserRole.operator || v.operatorId == user.providerId)) v,
    ];
    final available = evs.where((v) => v.status == VehicleStatus.active).length;
    final charging = evs.where((v) => v.status == VehicleStatus.charging).length;
    final avg = evs.isEmpty ? 0 : evs.fold<int>(0, (s, v) => s + (v.batteryPct ?? 0)) ~/ evs.length;
    final canManage = user.role == UserRole.admin || user.role == UserRole.operator;

    return PortalScaffold(
      title: 'Electric vehicles',
      subtitle: 'EV cars, e-shuttles and e-keke on the platform',
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => showRegisterVehicleDialog(context, electric: true),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Register EV'),
          ),
      ],
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Container(
            color: AppColors.forestDeep,
            child: LayoutBuilder(builder: (context, c) {
              final figures = [
                Figure(label: 'Electric vehicles', value: '${evs.length}', onDark: true, large: true),
                Figure(label: 'Available now', value: '$available', onDark: true, large: true),
                Figure(label: 'Charging', value: '$charging', onDark: true, large: true),
                Figure(label: 'Avg battery', value: '$avg%', onDark: true, large: true),
              ];
              final grid = Padding(
                padding: const EdgeInsets.all(22),
                child: c.maxWidth >= 700
                    ? Row(children: [for (final f in figures) Expanded(child: f)])
                    : Wrap(runSpacing: 18, children: [for (final f in figures) SizedBox(width: (c.maxWidth - 44) / 2, child: f)]),
              );
              if (c.maxWidth < 700) return grid;
              // Figures sit on solid green; the photo only fills the right-hand third.
              return SizedBox(
                height: 170,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 65, child: Center(child: grid)),
                  const Expanded(
                    flex: 35,
                    child: PhotoView(
                      AppPhoto.evPlug,
                      alignment: Alignment(0.2, 0),
                      overlay: LinearGradient(colors: [AppColors.forestDeep, Color(0x0006331F)], stops: [0, 0.35]),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ),
        const SizedBox(height: PortalSpace.gap),
        DataList<Vehicle>(
          items: evs,
          empty: const EmptyState(icon: Icons.electric_car_rounded, title: 'No electric vehicles yet', message: 'Registered EVs appear here once added.'),
          columns: [
            Col('Vehicle', flex: 4, (v) => Row(children: [
                  IconBadge(v.kind.icon, size: 36, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${v.model} · ${v.plate}', style: text.titleSmall, overflow: TextOverflow.ellipsis),
                      Text(state.providerById(v.operatorId)?.name ?? '', style: text.bodySmall, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ])),
            Col('Battery', flex: 3, (v) => Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: (v.batteryPct ?? 0) / 100, minHeight: 7, color: (v.batteryPct ?? 0) > 30 ? AppColors.leaf : AppColors.amber, backgroundColor: AppColors.mint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 74, child: Text('${v.batteryPct ?? 0}% · ${v.rangeKm ?? 0}km', style: text.labelMedium)),
                ])),
            Col('Location', (v) => Text(v.area, style: text.bodyMedium)),
            Col('Status', (v) => StatusPill(v.status.label, tone: vehicleTone(v.status))),
            Col('Register', (v) => StatusPill(v.verification.label, tone: verificationTone(v.verification))),
          ],
          trailing: canManage ? (v) => _StatusMenu(vehicle: v) : null,
        ),
        const SizedBox(height: 22),
        Text('Charging stations', style: text.titleLarge),
        const SizedBox(height: 10),
        Cols(min: 240, max: 4, children: [
          for (final s in state.stations)
            Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.ev_station_rounded, color: AppColors.forest),
                const SizedBox(width: 8),
                Expanded(child: Text(s.name, style: text.titleSmall)),
              ]),
              const SizedBox(height: 4),
              Text(s.area, style: text.bodySmall),
              const SizedBox(height: 12),
              ShareBar(parts: [(s.ports - s.available, AppColors.forest), (s.available, AppColors.mintStrong)]),
              const SizedBox(height: 6),
              Text('${s.available} of ${s.ports} ports free', style: text.labelMedium),
            ])),
        ]),
      ],
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VehicleStatus>(
        tooltip: 'Change status',
        onSelected: (s) => attemptOk(context, () => context.read<AppState>().setVehicleStatus(vehicle, s), success: '${vehicle.plate} set to ${s.label.toLowerCase()}'),
        itemBuilder: (_) => [
          for (final s in VehicleStatus.values)
            if (s != vehicle.status && (s != VehicleStatus.charging || vehicle.electric)) PopupMenuItem(value: s, child: Text(s.label)),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Set status', style: TextStyle(color: AppColors.forest, fontWeight: FontWeight.w700)),
            Icon(Icons.arrow_drop_down_rounded, color: AppColors.forest),
          ]),
        ),
      );
}

// ------------------------------------------------------------------ routes & fares

class PortalRoutesPage extends StatelessWidget {
  const PortalRoutesPage({super.key});

  Future<void> _editFare(BuildContext context, TransitRoute route) async {
    final controller = TextEditingController(text: '${route.fare}');
    final fare = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Fare for ${route.code}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_routeLabel(route)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Fixed fare', prefixText: '₦ '),
          ),
          const SizedBox(height: 8),
          Text('Riders see the new fare straight away. Existing tickets keep the fare they paid.', style: Theme.of(d).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(controller.text)), child: const Text('Save fare')),
        ],
      ),
    );
    controller.dispose();
    if (fare == null || !context.mounted) return;
    await attemptOk(context, () => context.read<AppState>().updateRouteFare(route, fare), success: '${route.code} fare is now ${Fmt.naira(fare)}');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final text = Theme.of(context).textTheme;
    final routes = [
      for (final r in state.routes)
        if (user.role != UserRole.operator || r.providerId == user.providerId) r,
    ]..sort((a, b) => a.code.compareTo(b.code));
    bool canEdit(TransitRoute r) => user.role == UserRole.admin || (user.role == UserRole.operator && r.providerId == user.providerId);

    return PortalScaffold(
      title: 'Routes & fares',
      subtitle: user.role == UserRole.operator ? 'Your published routes, fixed fares and timetables' : 'All routes registered on the platform',
      children: [
        DataList<TransitRoute>(
          items: routes,
          columns: [
            Col('Route', flex: 5, (r) => Row(children: [
                  StatusPill(r.code, tone: Tone.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_routeLabel(r), style: text.titleSmall, overflow: TextOverflow.ellipsis),
                      Text('${r.stops.length} stops · ${r.mode.label}', style: text.bodySmall),
                    ]),
                  ),
                ])),
            Col('Operator', flex: 3, (r) => Text(state.providerById(r.providerId)?.name ?? '—', style: text.bodyMedium, overflow: TextOverflow.ellipsis)),
            Col('Fare', numeric: true, (r) => Text(Fmt.naira(r.fare), style: text.titleSmall?.copyWith(fontFeatures: tabular))),
            Col('Time', numeric: true, (r) => Text(Fmt.minutes(r.durationMin), style: text.bodyMedium)),
            Col('Departures', numeric: true, (r) => Text('${r.departures.length}/day', style: text.bodyMedium)),
            Col('Trips · 30d', numeric: true, (r) => Text(Fmt.count(r.monthlyTrips), style: text.bodyMedium?.copyWith(fontFeatures: tabular))),
          ],
          trailing: (r) => canEdit(r) ? TextButton.icon(onPressed: () => _editFare(context, r), icon: const Icon(Icons.edit_rounded, size: 16), label: const Text('Edit fare')) : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ vehicles

class PortalVehiclesPage extends StatefulWidget {
  const PortalVehiclesPage({super.key});

  @override
  State<PortalVehiclesPage> createState() => _PortalVehiclesPageState();
}

class _PortalVehiclesPageState extends State<PortalVehiclesPage> {
  final _search = TextEditingController();
  Verification? _verification;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final text = Theme.of(context).textTheme;
    final q = _search.text.trim().toLowerCase();
    final scoped = [
      for (final v in state.vehicles)
        if (user.role.canVerify || v.operatorId == user.providerId || v.ownerId == user.providerId) v,
    ];
    final list = [
      for (final v in scoped)
        if ((_verification == null || v.verification == _verification) && (q.isEmpty || '${v.plate} ${v.model} ${v.area} ${v.driverName ?? ''}'.toLowerCase().contains(q))) v,
    ]..sort((a, b) => a.plate.compareTo(b.plate));
    final canManage = user.role != UserRole.government;

    return PortalScaffold(
      title: user.role.canVerify ? 'Vehicle register' : 'Your vehicles',
      subtitle: '${scoped.length} vehicles · ${scoped.where((v) => v.verification == Verification.verified).length} verified',
      actions: [
        if (canManage) FilledButton.icon(onPressed: () => showRegisterVehicleDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('Register vehicle')),
      ],
      children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Search plate, model, area or driver', prefixIcon: Icon(Icons.search_rounded), contentPadding: EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          for (final f in <Verification?>[null, ...Verification.values])
            ChoiceChip(
              label: Text(f?.label ?? 'All'),
              selected: _verification == f,
              showCheckmark: false,
              labelStyle: TextStyle(color: _verification == f ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
              onSelected: (_) => setState(() => _verification = f),
            ),
        ]),
        const SizedBox(height: 14),
        DataList<Vehicle>(
          items: list,
          empty: const EmptyState(icon: Icons.search_off_rounded, title: 'No vehicles match', message: 'Try another search or filter.'),
          columns: [
            Col('Vehicle', flex: 4, (v) => Row(children: [
                  IconBadge(v.kind.icon, size: 36, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v.displayName, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                      Text('${v.model} · ${v.capacity} seats', style: text.bodySmall, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ])),
            Col('Operator', flex: 3, (v) => Text([state.providerById(v.operatorId)?.name, if (v.ownerId != null) 'owned by ${state.providerById(v.ownerId)?.name ?? '—'}'].whereType<String>().join('\n'), style: text.bodySmall)),
            Col('Driver', (v) => Text(v.driverName ?? '—', style: text.bodyMedium)),
            Col('Earnings · month', numeric: true, (v) => Text(Fmt.naira(v.monthEarnings), style: text.bodyMedium?.copyWith(fontFeatures: tabular))),
            Col('Status', (v) => StatusPill(v.status.label, tone: vehicleTone(v.status))),
            Col('Register', (v) => StatusPill(v.verification.label, tone: verificationTone(v.verification))),
          ],
          trailing: (v) {
            if (user.role.canVerify && v.verification != Verification.verified) {
              return TextButton(
                onPressed: () => attemptOk(context, () => context.read<AppState>().setVehicleVerification(v, Verification.verified), success: '${v.displayName} verified'),
                child: const Text('Verify'),
              );
            }
            if (canManage) return _StatusMenu(vehicle: v);
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

Future<void> showRegisterVehicleDialog(BuildContext context, {bool electric = false}) {
  return showDialog<void>(context: context, builder: (_) => _RegisterVehicleDialog(electric: electric));
}

class _RegisterVehicleDialog extends StatefulWidget {
  const _RegisterVehicleDialog({required this.electric});
  final bool electric;

  @override
  State<_RegisterVehicleDialog> createState() => _RegisterVehicleDialogState();
}

class _RegisterVehicleDialogState extends State<_RegisterVehicleDialog> {
  final _form = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _model = TextEditingController();
  late VehicleKind _kind = widget.electric ? VehicleKind.evCar : VehicleKind.bus;
  int _capacity = 4;
  String? _provider;
  bool _busy = false;

  @override
  void dispose() {
    _plate.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final admin = user.role == UserRole.admin;
    final providerId = admin ? (_provider ?? state.providers.firstOrNull?.id) : user.providerId;
    final kinds = widget.electric ? const [VehicleKind.evCar, VehicleKind.evShuttle, VehicleKind.evKeke] : VehicleKind.values.where((k) => k != VehicleKind.train).toList();
    return AlertDialog(
      title: Text(widget.electric ? 'Register an electric vehicle' : 'Register a vehicle'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (admin) ...[
              DropdownButtonFormField<String>(
                initialValue: providerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: [for (final p in state.providers) DropdownMenuItem(value: p.id, child: Text(p.name))],
                onChanged: (v) => setState(() => _provider = v),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<VehicleKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(k.label))],
              onChanged: (v) => setState(() {
                _kind = v ?? _kind;
                _capacity = switch (_kind) { VehicleKind.bus => 48, VehicleKind.minibus => 18, VehicleKind.evShuttle => 22, VehicleKind.evKeke => 3, _ => 4 };
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Plate number', hintText: 'ABJ 245 KD'),
              validator: (v) => (v == null || v.trim().length < 4) ? 'Enter the plate number.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Make and model', hintText: 'Hyundai Kona Electric'),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the make and model.' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text('Seats: $_capacity', style: Theme.of(context).textTheme.titleSmall),
              Expanded(child: Slider(value: _capacity.toDouble(), min: 2, max: 60, divisions: 58, activeColor: AppColors.forest, onChanged: (v) => setState(() => _capacity = v.round()))),
            ]),
            Text('New vehicles start as "Pending review" and cannot take bookings until the FCTA verifies them.', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy || providerId == null
              ? null
              : () async {
                  if (!_form.currentState!.validate()) return;
                  setState(() => _busy = true);
                  final provider = state.providerById(providerId);
                  final ok = await attemptOk(
                    context,
                    () => context.read<AppState>().registerVehicle(
                          operatorId: providerId,
                          ownerId: provider?.kind == ProviderKind.fleetOwner ? providerId : null,
                          kind: _kind,
                          plate: _plate.text,
                          model: _model.text,
                          capacity: _capacity,
                        ),
                    success: '${_plate.text.toUpperCase()} registered and sent for verification',
                  );
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (ok) Navigator.of(this.context).pop();
                },
          child: const Text('Register'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ bookings

class PortalBookingsPage extends StatelessWidget {
  const PortalBookingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final bookings = state.partnerBookings;
    final now = state.now;
    final today = bookings.where((b) => b.createdAt.year == now.year && b.createdAt.month == now.month && b.createdAt.day == now.day && b.status != BookingStatus.cancelled).toList();
    final revenue = bookings.where((b) => b.status != BookingStatus.cancelled && b.paymentMethod != PaymentMethod.splitCost).fold<int>(0, (s, b) => s + b.fare);

    return PortalScaffold(
      title: 'Bookings & trips',
      subtitle: 'Seats booked in the rider app, scoped to what your role can see',
      children: [
        Cols(min: 220, max: 3, children: [
          FigureCard(label: 'Bookings today', value: '${today.length}', icon: Icons.today_rounded),
          FigureCard(label: 'All bookings', value: '${bookings.length}', icon: Icons.confirmation_number_rounded),
          FigureCard(label: 'Fares collected', value: Fmt.naira(revenue), icon: Icons.payments_rounded),
        ]),
        const SizedBox(height: PortalSpace.gap),
        DataList<Booking>(
          items: bookings,
          empty: const EmptyState(icon: Icons.confirmation_number_outlined, title: 'No bookings yet', message: 'Seats booked in the rider app appear here instantly.'),
          columns: [
            Col('Passenger', flex: 3, (b) => Text(b.passengerName, style: text.titleSmall)),
            Col('Trip', flex: 4, (b) => RouteStrip(origin: b.origin, destination: b.destination, dense: true)),
            Col('Departure', flex: 3, (b) => Text(Fmt.dayTime(b.departureAt), style: text.bodyMedium)),
            Col('Type', (b) => Text(b.kind.label, style: text.bodySmall)),
            Col('Fare', numeric: true, (b) => Text(Fmt.naira(b.fare), style: text.titleSmall?.copyWith(fontFeatures: tabular))),
            Col('Status', (b) => StatusPill(b.status.label, tone: b.status.isOpen ? Tone.success : (b.status == BookingStatus.completed ? Tone.neutral : Tone.danger))),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ verification

class VerificationPage extends StatelessWidget {
  const VerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final providers = state.providers.where((p) => p.status == Verification.pending).toList();
    final vehicles = state.vehicles.where((v) => v.verification == Verification.pending).toList();
    final app = context.read<AppState>();

    return PortalScaffold(
      title: 'Verification queue',
      subtitle: 'Approve providers and vehicles before they can take bookings',
      children: [
        Cols(min: 200, max: 3, children: [
          FigureCard(label: 'Providers waiting', value: '${providers.length}', icon: Icons.apartment_rounded),
          FigureCard(label: 'Vehicles waiting', value: '${vehicles.length}', icon: Icons.directions_car_filled_rounded),
          FigureCard(label: 'Verified vehicles', value: '${state.vehicles.where((v) => v.verification == Verification.verified).length}', icon: Icons.verified_rounded, caption: 'on the platform'),
        ]),
        SectionLabel('Providers', subtitle: '${providers.length} waiting for review'),
        if (providers.isEmpty)
          const Panel(child: EmptyState(icon: Icons.task_alt_rounded, title: 'All caught up', message: 'No providers are waiting for review.'))
        else
          for (final p in providers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                radius: AppRadius.md,
                child: LayoutBuilder(builder: (context, c) {
                  final details = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    IconBadge(p.kind.icon, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: text.titleMedium),
                        const SizedBox(height: 2),
                        Text('${p.kind.label} · ${p.area} · applied ${Fmt.date(p.joinedAt)}', style: text.bodySmall),
                        const SizedBox(height: 4),
                        Text(p.description, style: text.bodySmall?.copyWith(color: AppColors.inkSoft)),
                      ]),
                    ),
                  ]);
                  final approve = FilledButton.icon(
                    onPressed: () => attemptOk(context, () => app.setProviderStatus(p, Verification.verified), success: '${p.name} approved'),
                    icon: const Icon(Icons.verified_rounded, size: 18),
                    label: const Text('Approve'),
                  );
                  return c.maxWidth >= 560
                      ? Row(children: [Expanded(child: details), const SizedBox(width: 16), approve])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [details, const SizedBox(height: 12), approve]);
                }),
              ),
            ),
        SectionLabel('Vehicles', subtitle: '${vehicles.length} waiting for checks'),
        DataList<Vehicle>(
          items: vehicles,
          empty: const Panel(child: EmptyState(icon: Icons.task_alt_rounded, title: 'All caught up', message: 'Every registered vehicle has been checked.')),
          columns: [
            Col('Vehicle', flex: 4, (v) => Text(v.displayName, style: text.titleSmall)),
            Col('Type', (v) => Text(v.kind.label, style: text.bodyMedium)),
            Col('Provider', flex: 3, (v) => Text(state.providerById(v.operatorId)?.name ?? '—', style: text.bodyMedium)),
            Col('Provider status', (v) {
              final p = state.providerById(v.operatorId);
              return p == null ? const SizedBox.shrink() : StatusPill(p.status.label, tone: verificationTone(p.status));
            }),
          ],
          trailing: (v) => Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              onPressed: () => attemptOk(context, () => app.setVehicleVerification(v, Verification.suspended), success: '${v.displayName} rejected'),
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () => attemptOk(context, () => app.setVehicleVerification(v, Verification.verified), success: '${v.displayName} verified'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Verify'),
            ),
          ]),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ users

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  Future<void> _changeRole(BuildContext context, AppUser target) async {
    final state = context.read<AppState>();
    var role = target.role;
    String? provider = target.providerId;
    final result = await showDialog<(UserRole, String?)>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setLocal) => AlertDialog(
          title: Text('Role for ${target.fullName}'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (v) => setLocal(() => role = v ?? role),
              ),
              if (role == UserRole.operator || role == UserRole.fleetOwner) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: provider,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: [for (final p in state.providers) DropdownMenuItem(value: p.id, child: Text(p.name))],
                  onChanged: (v) => setLocal(() => provider = v),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, (role, provider)), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    await attemptOk(context, () => state.setUserRole(target, result.$1, providerId: result.$2), success: '${target.fullName} is now ${result.$1.label.toLowerCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final me = state.user!;
    return PortalScaffold(
      title: 'Users & roles',
      subtitle: 'Who can see and change what. Roles are enforced by the server.',
      children: [
        DataList<AppUser>(
          items: state.users,
          columns: [
            Col('Name', flex: 4, (u) => Row(children: [
                  Avatar(initials: u.initials, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.fullName, style: text.titleSmall),
                      Text(u.email, style: text.bodySmall, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ])),
            Col('Role', flex: 3, (u) => Row(children: [Icon(u.role.icon, size: 18, color: AppColors.muted), const SizedBox(width: 6), Flexible(child: Text(u.role.label, style: text.bodyMedium))])),
            Col('Organisation', flex: 3, (u) => Text(state.providerById(u.providerId)?.name ?? u.organisation ?? '—', style: text.bodyMedium, overflow: TextOverflow.ellipsis)),
            Col('Joined', (u) => Text(Fmt.date(u.createdAt), style: text.bodySmall)),
          ],
          trailing: (u) => u.id == me.id ? const StatusPill('You', tone: Tone.brand) : TextButton(onPressed: () => _changeRole(context, u), child: const Text('Change role')),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ audit

class AuditPage extends StatelessWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return PortalScaffold(
      title: 'Audit log',
      subtitle: 'Every approval, suspension, fare change and role change, with who made it',
      children: [
        Panel(
          child: state.audit.isEmpty
              ? const EmptyState(icon: Icons.history_rounded, title: 'No changes yet', message: 'Administrative actions are recorded here.')
              : Column(children: [
                  for (var i = 0; i < state.audit.length; i++) ...[
                    if (i > 0) const Divider(),
                    AuditTile(entry: state.audit[i]),
                  ],
                ]),
        ),
      ],
    );
  }
}
