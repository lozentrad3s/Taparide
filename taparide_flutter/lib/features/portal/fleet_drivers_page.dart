import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/fleet_drivers.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';
import 'portal_widgets.dart';

const _lime = Color(0xFF8CE01F);

/// Companies that employ drivers (not private drivers or event organisers).
bool employsDrivers(TransportProvider p) => p.kind != ProviderKind.privateDriver && p.kind != ProviderKind.eventOrganiser;

/// The company's own vehicles: the ones it operates and the ones it owns.
List<Vehicle> fleetVehiclesOf(AppState state, String providerId) => [for (final v in state.vehicles) if (v.operatorId == providerId || v.ownerId == providerId) v]..sort((a, b) => a.plate.compareTo(b.plate));

/// Routes a vehicle can be put on: its operator's, or the company's own.
List<TransitRoute> routesFor(AppState state, Vehicle? vehicle, String providerId) => vehicle == null
    ? const []
    : ([for (final r in state.routes) if (r.active && (r.providerId == vehicle.operatorId || r.providerId == providerId)) r]..sort((a, b) => a.code.compareTo(b.code)));

/// Fleet owners and operators add the people who drive their vehicles, put each one on a
/// vehicle (and route), and suspend or reactivate them. Admins see every company's drivers.
class FleetDriversPage extends StatefulWidget {
  const FleetDriversPage({super.key, this.providerId});
  final String? providerId;

  @override
  State<FleetDriversPage> createState() => _FleetDriversPageState();
}

class _FleetDriversPageState extends State<FleetDriversPage> {
  String? _company;
  bool _picked = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user!;
    final text = Theme.of(context).textTheme;
    final admin = user.role == UserRole.admin;
    final companies = [for (final p in state.providers) if (employsDrivers(p) && p.status != Verification.suspended) p]..sort((a, b) => a.name.compareTo(b.name));
    final scope = admin ? (_picked ? _company : widget.providerId) : user.providerId;
    final company = state.providerById(scope);
    final drivers = [for (final d in state.fleetDrivers) if (scope == null || d.providerId == scope) d]..sort((a, b) => a.fullName.compareTo(b.fullName));
    final onVehicle = drivers.where((d) => d.active && d.vehicleId != null).length;
    final suspended = drivers.where((d) => !d.active).length;
    final canAdd = admin ? companies.isNotEmpty : (company != null && employsDrivers(company));

    return PortalScaffold(
      title: 'Drivers',
      subtitle: admin ? (company == null ? 'Every company\'s drivers' : company.name) : '${company?.name ?? 'Your company'} · the people who drive your vehicles',
      actions: [
        if (admin)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: DropdownButtonFormField<String?>(
              initialValue: scope,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Company', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All companies')),
                for (final p in companies) DropdownMenuItem<String?>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() {
                _picked = true;
                _company = v;
              }),
            ),
          ),
        if (canAdd) ...[
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: AppColors.forestDeep),
            onPressed: () => showDriverForm(context, providerId: admin ? scope : user.providerId),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add driver'),
          ),
        ],
      ],
      children: [
        Cols(min: 160, max: 4, children: [
          FigureCard(label: 'Drivers', value: '${drivers.length}', icon: Icons.groups_2_rounded, caption: admin && scope == null ? 'across all companies' : 'on your team'),
          FigureCard(label: 'On a vehicle', value: '$onVehicle', icon: Icons.directions_bus_rounded, caption: 'assigned and active'),
          FigureCard(label: 'Unassigned', value: '${drivers.where((d) => d.active && d.vehicleId == null).length}', icon: Icons.event_seat_rounded, caption: 'waiting for a vehicle'),
          FigureCard(label: 'Suspended', value: '$suspended', icon: Icons.block_rounded, caption: 'no vehicle or rider access'),
        ]),
        const SizedBox(height: 16),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PanelTitle('Team', subtitle: 'Drivers sign in on the partner dashboard with the email you add here. They see only their own vehicle, route and riders.'),
            if (drivers.isEmpty)
              EmptyState(
                icon: Icons.badge_rounded,
                title: 'No drivers yet',
                message: canAdd ? 'Add the people who drive your vehicles. Each one gets their own driver dashboard.' : 'Drivers added by fleet owners and operators appear here.',
                action: canAdd ? 'Add driver' : null,
                onAction: canAdd ? () => showDriverForm(context, providerId: admin ? scope : user.providerId) : null,
              ),
            for (final (i, d) in drivers.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _DriverRow(driver: d, showCompany: admin && scope == null),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Text(
          state.backend.isDemo
              ? 'Demo: a new driver signs in with their email and the demo password. Drivers marked (sample) are illustrative.'
              : 'A new driver creates a Tap A Ride account with the same email; once they confirm it, it becomes their driver login.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.driver, required this.showCompany});
  final FleetDriver driver;
  final bool showCompany;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final vehicle = state.vehicleById(driver.vehicleId);
    final route = state.routeById(driver.routeId);
    final company = state.providerById(driver.providerId);
    final status = !driver.active
        ? const StatusPill('Suspended', tone: Tone.danger, icon: Icons.block_rounded)
        : driver.vehicleId == null
            ? const StatusPill('Unassigned', tone: Tone.warning)
            : const StatusPill('Active', tone: Tone.success, icon: Icons.check_circle_rounded);
    final who = Row(children: [
      Avatar(initials: driver.initials, size: 40, color: driver.active ? AppColors.mint : AppColors.redSoft, textColor: driver.active ? AppColors.forest : AppColors.red),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(driver.fullName, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text([driver.phone, driver.email].join(' · '), style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(['Licence ${driver.licenceNumber}', if (showCompany && company != null) company.name, if (!driver.hasLogin) 'no login yet'].join(' · '), style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);
    final assignment = Row(children: [
      Icon(vehicle == null ? Icons.no_transfer_rounded : vehicle.kind.icon, size: 20, color: vehicle == null ? AppColors.faint : AppColors.forest),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(vehicle?.displayName ?? 'No vehicle', style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(route == null ? (vehicle == null ? 'Assign a vehicle to put them on the road' : 'Any route') : '${route.code} · ${route.title}', style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);
    final actions = Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      OutlinedButton.icon(
        onPressed: () => _assign(context),
        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
        label: const Text('Assign'),
      ),
      TextButton(
        style: TextButton.styleFrom(foregroundColor: driver.active ? AppColors.red : AppColors.forest),
        onPressed: () => _toggle(context),
        child: Text(driver.active ? 'Suspend' : 'Reactivate'),
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 820) {
          return Row(children: [
            Expanded(flex: 4, child: who),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: assignment),
            const SizedBox(width: 12),
            SizedBox(width: 120, child: Align(alignment: Alignment.centerLeft, child: status)),
            actions,
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: who), const SizedBox(width: 8), status]),
          const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.only(left: 52), child: assignment),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.only(left: 52), child: Align(alignment: Alignment.centerLeft, child: actions)),
        ]);
      }),
    );
  }

  Future<void> _assign(BuildContext context) async {
    final state = context.read<AppState>();
    final picked = await showDialog<(String?, String?)>(context: context, builder: (_) => _AssignDialog(driver: driver, state: state));
    if (picked == null || !context.mounted) return;
    final v = state.vehicleById(picked.$1);
    await attemptOk(context, () => state.assignFleetDriver(driver, vehicleId: picked.$1, routeId: picked.$2), success: v == null ? '${driver.firstName} has no vehicle now' : '${driver.firstName} now drives ${v.displayName}');
  }

  Future<void> _toggle(BuildContext context) async {
    final state = context.read<AppState>();
    if (driver.active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Suspend ${driver.fullName}?'),
          content: const Text('They keep their login but lose access to the vehicle, its riders and live tracking until you reactivate them.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(d, true), child: const Text('Suspend')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    await attemptOk(context, () => state.setFleetDriverStatus(driver, driver.active ? FleetDriverStatus.suspended : FleetDriverStatus.active), success: driver.active ? '${driver.fullName} is suspended' : '${driver.fullName} is active again');
  }
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.driver, required this.state});
  final FleetDriver driver;
  final AppState state;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  late String? _vehicle = widget.driver.vehicleId;
  late String? _route = widget.driver.routeId;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final vehicles = fleetVehiclesOf(state, widget.driver.providerId);
    final vehicle = state.vehicleById(_vehicle);
    final routes = routesFor(state, vehicle, widget.driver.providerId);
    return AlertDialog(
      title: Text('Assign ${widget.driver.firstName}'),
      content: SizedBox(
        width: 420,
        child: _AssignmentFields(
          vehicles: vehicles,
          routes: routes,
          vehicle: vehicles.any((v) => v.id == _vehicle) ? _vehicle : null,
          route: routes.any((r) => r.id == _route) ? _route : null,
          onVehicle: (v) => setState(() {
            _vehicle = v;
            _route = null;
          }),
          onRoute: (r) => setState(() => _route = r),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, (_vehicle, _route)), child: const Text('Save')),
      ],
    );
  }
}

class _AssignmentFields extends StatelessWidget {
  const _AssignmentFields({required this.vehicles, required this.routes, required this.vehicle, required this.route, required this.onVehicle, required this.onRoute});
  final List<Vehicle> vehicles;
  final List<TransitRoute> routes;
  final String? vehicle;
  final String? route;
  final ValueChanged<String?> onVehicle;
  final ValueChanged<String?> onRoute;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String?>(
          key: ValueKey('vehicle-$vehicle'),
          initialValue: vehicle,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Vehicle'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('No vehicle yet')),
            for (final v in vehicles) DropdownMenuItem<String?>(value: v.id, child: Text('${v.displayName} · ${v.status.label}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onVehicle,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: ValueKey('route-$vehicle-$route'),
          initialValue: route,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Route (optional)', helperText: vehicle == null ? 'Pick a vehicle first' : null),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Any route')),
            for (final r in routes) DropdownMenuItem<String?>(value: r.id, child: Text('${r.code} · ${r.title}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: vehicle == null ? null : onRoute,
        ),
      ]);
}

/// Opens the "Add driver" form for [providerId] (admins pick the company in the form when null).
Future<void> showDriverForm(BuildContext context, {String? providerId}) => showDialog<void>(context: context, builder: (_) => _DriverForm(providerId: providerId));

class _DriverForm extends StatefulWidget {
  const _DriverForm({this.providerId});
  final String? providerId;

  @override
  State<_DriverForm> createState() => _DriverFormState();
}

class _DriverFormState extends State<_DriverForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _licence = TextEditingController();
  late String? _company = widget.providerId;
  String? _vehicle;
  String? _route;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _licence]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _company == null) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final driver = await attempt(
      context,
      () => state.addFleetDriver(fullName: _name.text, phone: _phone.text, email: _email.text, licenceNumber: _licence.text, providerId: _company, vehicleId: _vehicle, routeId: _route),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (driver != null) {
      Navigator.pop(context);
      showMessage(context, state.backend.isDemo ? '${driver.fullName} added. They sign in with ${driver.email} and the demo password.' : '${driver.fullName} added. Ask them to sign up with ${driver.email}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final admin = state.user?.role == UserRole.admin;
    final companies = [for (final p in state.providers) if (employsDrivers(p) && p.status == Verification.verified) p]..sort((a, b) => a.name.compareTo(b.name));
    final vehicles = _company == null ? const <Vehicle>[] : fleetVehiclesOf(state, _company!);
    final routes = _company == null ? const <TransitRoute>[] : routesFor(state, state.vehicleById(_vehicle), _company!);
    String? Function(String?) check(String? Function(String) rule) => (v) => rule(v ?? '');
    return AlertDialog(
      title: const Text('Add driver'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (admin) ...[
                DropdownButtonFormField<String>(
                  initialValue: companies.any((p) => p.id == _company) ? _company : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Company'),
                  validator: (v) => v == null ? 'Choose the company they drive for.' : null,
                  items: [for (final p in companies) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() {
                    _company = v;
                    _vehicle = null;
                    _route = null;
                  }),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name'), validator: check(FleetDriverRules.name)),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', hintText: '+234 803 000 0000'), validator: check(FleetDriverRules.phone)),
              const SizedBox(height: 12),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (their driver login)'), validator: check(FleetDriverRules.email)),
              const SizedBox(height: 12),
              TextFormField(controller: _licence, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "Driver's licence number"), validator: check(FleetDriverRules.licence)),
              const SizedBox(height: 16),
              Text('Assignment', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _AssignmentFields(
                vehicles: vehicles,
                routes: routes,
                vehicle: _vehicle,
                route: _route,
                onVehicle: (v) => setState(() {
                  _vehicle = v;
                  _route = null;
                }),
                onRoute: (r) => setState(() => _route = r),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Add driver'),
        ),
      ],
    );
  }
}

/// One line about the driver's assignment, for other pages.
String driverAssignmentLabel(AppState state, FleetDriver d) {
  final v = state.vehicleById(d.vehicleId);
  final r = state.routeById(d.routeId);
  return [v?.displayName ?? 'No vehicle', if (r != null) r.code, 'since ${Fmt.date(d.createdAt)}'].join(' · ');
}
