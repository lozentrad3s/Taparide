import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/places.dart';
import '../../shared/mascot/mascot.dart';
import '../../shared/ui.dart';
import '../assistant/assistant_sheet.dart';
import 'portal_widgets.dart';

/// Dashboard for an approved private driver: go online, run the current ride,
/// see earnings and where demand is right now.
class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key, required this.provider, this.picker});
  final TransportProvider provider;
  final Widget? picker;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final car = state.vehicles.where((v) => v.operatorId == provider.id).firstOrNull;
    final rides = [for (final b in state.partnerBookings) if (b.providerId == provider.id && b.kind == BookingKind.electric) b]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final current = rides.where((b) => b.status == BookingStatus.confirmed).firstOrNull;
    bool isToday(DateTime d) => d.year == state.now.year && d.month == state.now.month && d.day == state.now.day;
    final doneToday = rides.where((b) => b.status == BookingStatus.completed && isToday(b.createdAt)).toList();
    final earnedToday = doneToday.fold<int>(0, (s, b) => s + b.fare);
    final online = car != null && (car.status == VehicleStatus.active || car.status == VehicleStatus.onTrip);
    final hot = state.insightsFor(null).areas.take(3).toList();
    final firstName = (state.user?.providerId == provider.id ? state.user!.firstName : provider.contactName.split(' ').first);

    return PortalScaffold(
      title: 'Driver dashboard',
      subtitle: '${provider.name} · Private driver · ${provider.status.label}',
      actions: [if (picker != null) picker!],
      children: [
        // Greeting with Tapi, and the online switch.
        Panel(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: Row(children: [
            Mascot(mood: current != null ? MascotMood.celebrate : (online ? MascotMood.wave : MascotMood.sleep), size: 88, onTap: () => openAssistant(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${Fmt.greeting(state.now)}, $firstName', style: text.headlineSmall),
                const SizedBox(height: 2),
                Text(
                  car == null
                      ? 'Your car is being added to the register.'
                      : current != null
                          ? 'You have a rider on board. Drive safely.'
                          : online
                              ? 'You are online. Ride requests come to you automatically.'
                              : 'You are offline. Go online to receive rides.',
                  style: text.bodyMedium,
                ),
              ]),
            ),
            if (car != null)
              Column(mainAxisSize: MainAxisSize.min, children: [
                Switch(
                  value: online,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.leaf,
                  onChanged: car.status == VehicleStatus.onTrip
                      ? null
                      : (v) => attemptOk(context, () => state.setVehicleStatus(car, v ? VehicleStatus.active : VehicleStatus.inactive), success: v ? 'You are online' : 'You are offline'),
                ),
                Text(online ? 'Online' : 'Offline', style: text.labelMedium?.copyWith(color: online ? AppColors.leafText : AppColors.muted, fontWeight: FontWeight.w800)),
              ]),
          ]),
        ),
        const SizedBox(height: 16),
        Cols(min: 160, max: 4, children: [
          FigureCard(label: 'Earned today', value: Fmt.naira(earnedToday), icon: Icons.payments_rounded, caption: '${doneToday.length} ride${doneToday.length == 1 ? '' : 's'} completed'),
          FigureCard(label: 'This month', value: Fmt.naira(car?.monthEarnings ?? 0), icon: Icons.calendar_month_rounded, caption: 'paid to your account'),
          FigureCard(label: 'Rides', value: '${rides.where((b) => b.status == BookingStatus.completed).length}', icon: Icons.route_rounded, caption: 'all time'),
          FigureCard(label: 'Rating', value: '4.9', icon: Icons.star_rounded, caption: 'from riders'),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final rideCard = current == null ? _NoRide(online: online) : _CurrentRide(booking: current);
          final carCard = car == null ? const SizedBox.shrink() : _CarCard(car: car);
          return c.maxWidth >= 980
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: rideCard), const SizedBox(width: 16), Expanded(flex: 2, child: carCard)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [rideCard, const SizedBox(height: 16), carCard]);
        }),
        const SizedBox(height: 16),
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const PanelTitle('Where riders are', subtitle: 'Busiest areas across Abuja right now'),
          for (final (i, a) in hot.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                IconBadge(i == 0 ? Icons.local_fire_department_rounded : Icons.place_rounded, size: 34, radius: 10, color: i == 0 ? AppColors.amberSoft : AppColors.mint, iconColor: i == 0 ? AppColors.amber : AppColors.forest),
                const SizedBox(width: 12),
                Expanded(child: Text(a.name, style: text.titleSmall)),
                Text('${Fmt.count(a.trips)} trips/month', style: text.bodySmall),
              ]),
            ),
          const SizedBox(height: 6),
          Text('Wait near the top area between 7–9 am and 5–7 pm for the most requests.', style: text.bodySmall),
        ])),
        const SizedBox(height: 16),
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PanelTitle('Ride history', subtitle: '${rides.length} rides'),
          if (rides.isEmpty) Text('Your rides will appear here.', style: text.bodyMedium),
          for (final b in rides.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Avatar(initials: b.passengerName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join(), size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.origin} → ${b.destination}', style: text.titleSmall, overflow: TextOverflow.ellipsis),
                    Text('${b.passengerName} · ${Fmt.dayTime(b.createdAt)}', style: text.bodySmall),
                  ]),
                ),
                StatusPill(b.status == BookingStatus.confirmed ? 'In progress' : b.status.label, tone: b.status == BookingStatus.completed ? Tone.success : (b.status == BookingStatus.confirmed ? Tone.info : Tone.neutral)),
                const SizedBox(width: 10),
                Text(Fmt.naira(b.fare), style: text.labelLarge),
              ]),
            ),
        ])),
      ],
    );
  }
}

class _CurrentRide extends StatelessWidget {
  const _CurrentRide({required this.booking});
  final Booking booking;

  Future<void> _navigate() async {
    final to = resolvePlace(booking.destination);
    final dest = to == null ? Uri.encodeComponent('${booking.destination}, Abuja') : '${to.point.latitude},${to.point.longitude}';
    await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving'), mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      color: AppColors.forest,
      border: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Current ride', style: text.labelLarge?.copyWith(color: AppColors.onForestMuted)),
          const Spacer(),
          const StatusPill('In progress', tone: Tone.success),
        ]),
        const SizedBox(height: 12),
        RouteStrip(origin: booking.origin, destination: booking.destination, color: AppColors.leaf, textColor: Colors.white),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.person_rounded, size: 18, color: AppColors.onForestMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(booking.passengerName, style: text.bodyMedium?.copyWith(color: Colors.white))),
          Text(Fmt.naira(booking.fare), style: text.titleLarge?.copyWith(color: Colors.white)),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.leaf, foregroundColor: AppColors.forestDeep),
            onPressed: () => attemptOk(context, () => context.read<AppState>().completeRide(booking), success: 'Ride completed · ${Fmt.naira(booking.fare)} earned'),
            icon: const Icon(Icons.flag_rounded, size: 18),
            label: const Text('Complete ride'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
            onPressed: _navigate,
            icon: const Icon(Icons.navigation_rounded, size: 18),
            label: const Text('Navigate'),
          ),
        ]),
      ]),
    );
  }
}

class _NoRide extends StatelessWidget {
  const _NoRide({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      child: Row(children: [
        IconBadge(online ? Icons.radar_rounded : Icons.power_settings_new_rounded, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(online ? 'Waiting for a rider' : 'You are offline', style: text.titleMedium),
            Text(online ? 'Riders nearby can book your car in the Tap A Ride app. Bookings are paid up front by tap card.' : 'Switch online to start receiving rides.', style: text.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class _CarCard extends StatelessWidget {
  const _CarCard({required this.car});
  final Vehicle car;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconBadge(Icons.directions_car_rounded, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(car.model, style: text.titleMedium),
              Text('${car.plate} · ${car.capacity} seats · ${car.area}', style: text.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          StatusPill(car.verification == Verification.verified ? 'FCTA verified' : car.verification.label, tone: verificationTone(car.verification), icon: Icons.verified_rounded),
          const SizedBox(width: 8),
          StatusPill(car.status.label, tone: vehicleTone(car.status)),
        ]),
        const SizedBox(height: 12),
        Text('Fares: ${Fmt.naira(car.baseFare ?? 1000)} base + ${Fmt.naira(car.perKmFare ?? 150)}/km', style: text.bodySmall),
        const SizedBox(height: 4),
        Text('Riders see your plate on their ticket before they board.', style: text.bodySmall),
      ]),
    );
  }
}
