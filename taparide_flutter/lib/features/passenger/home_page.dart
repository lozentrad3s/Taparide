import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/photos.dart';
import '../../shared/brand.dart';
import '../../shared/coming_soon.dart';
import '../../shared/ui.dart';
import '../../shared/mascot/mascot.dart';
import '../assistant/assistant_sheet.dart';
import '../events/events_page.dart';
import '../live/live_map_page.dart';
import 'ad_strip.dart';
import 'rider_widgets.dart';
import 'smart_cards.dart';
import 'where_to.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wide = isWide(context, 1100);
    return Scaffold(
      body: SafeArea(
        child: DataGate(
          builder: (context) => RefreshIndicator(
            color: AppColors.forest,
            onRefresh: state.refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                MaxWidth(
                  width: 1180,
                  padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 14, wide ? 32 : 18, 0),
                  child: wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _primary(context, state, wide))),
                          const SizedBox(width: 28),
                          Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _secondary(context, state, wide))),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [..._primary(context, state, wide), ..._secondary(context, state, wide)]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _primary(BuildContext context, AppState state, bool wide) {
    final text = Theme.of(context).textTheme;
    final user = state.user!;
    final routes = state.bookableRoutes.take(4).toList();
    return [
      if (!wide)
        Row(children: [
          const BrandLockup(height: 28, showDescriptor: true),
          const Spacer(),
          IconButton(
            tooltip: 'Tap & Pay',
            onPressed: () => showTapAndPaySheet(context),
            icon: const Icon(Icons.contactless_outlined),
          ),
        ]),
      SizedBox(height: wide ? 12 : 14),
      // Sponsored slot in the header: one ad at a time, never covering the screen.
      const AdStrip(),
      const SizedBox(height: 16),
      const ReminderBanner(),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${Fmt.greeting(state.now)}, ${user.firstName}', style: wide ? text.displaySmall : text.headlineLarge),
            const SizedBox(height: 4),
            Text(_tapiLine(state), style: text.bodyLarge),
          ]),
        ),
        const SizedBox(width: 8),
        // Tapi greets the rider; tapping Tapi opens the assistant.
        Tooltip(
          message: 'Ask Tapi',
          child: Mascot(mood: MascotMood.wave, size: wide ? 120 : 92, semanticLabel: 'Tapi, your ride assistant. Tap to ask.', onTap: () => openAssistant(context)),
        ),
      ]),
      // The website sign-up reward sits right under the greeting on phones (in the side column on wide screens).
      if (!wide && state.signupReward.granted) ...[const SizedBox(height: 16), const RideRewardCard()],
      const SizedBox(height: 18),
      const WhereToCard(),
      const SizedBox(height: 18),
      // Every feature up front, open ones first, so riders find Event rides and Tag Along without digging.
      _FeatureGrid(items: [
        _Feature(Icons.directions_bus_rounded, 'Bus routes', () => context.go('/app/routes'), primary: true),
        _Feature(Icons.celebration_rounded, 'Event rides', () => context.push('/events')),
        _Feature(Icons.groups_rounded, 'Tag Along', () => context.push('/tag-along'), badge: state.pendingRideRequests.length),
        _Feature(Icons.contactless_rounded, 'Tap & Pay', () => showTapAndPaySheet(context)),
        _Feature(Icons.confirmation_number_rounded, 'My trips', () => context.go('/app/trips')),
        _Feature(Icons.radar_rounded, 'Live map', () => context.push('/live'), soon: !Launch.liveMap),
        _Feature(Icons.electric_car_rounded, 'Electric', () => context.push('/ev'), soon: !Launch.electric),
        _Feature(Icons.more_horiz_rounded, 'More', () => _showMore(context)),
      ]),
      const SizedBox(height: 22),
      if (state.upcomingTrips.isNotEmpty) ...[
        _UpcomingTrip(booking: state.upcomingTrips.first, leaveBy: leaveByLine(state, state.upcomingTrips.first)),
        const SizedBox(height: 22),
      ],
      if (state.suggestions.isNotEmpty) ...[SmartSuggestions(suggestions: state.suggestions), const SizedBox(height: 12)],
      SectionHeader(title: 'Popular routes', action: 'All routes', onAction: () => context.go('/app/routes')),
      for (final r in routes)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RouteRow(route: r, verifiedOperator: state.canBook(r), onTap: () => context.push('/ride/${r.id}')),
        ),
      const SizedBox(height: 14),
      _TravelSmart(onLearnMore: () => showTapAndPaySheet(context)),
      const SizedBox(height: 22),
    ];
  }

  List<Widget> _secondary(BuildContext context, AppState state, bool wide) {
    final evs = state.availableEvs.where((v) => v.status == VehicleStatus.active).take(3).toList();
    return [
      if (wide && state.signupReward.granted) ...[const RideRewardCard(), const SizedBox(height: 22)],
      // Launch focus first: event rides and Tag Along; the rest follows as it opens.
      const EventsBanner(),
      const SizedBox(height: 22),
      _TagAlongBanner(onOpen: () => context.push('/tag-along'), requests: state.pendingRideRequests.length),
      const SizedBox(height: 22),
      if (Launch.liveMap) ...[
        const SectionHeader(title: 'Around you now'),
        const LiveNearbyCard(),
        const SizedBox(height: 22),
      ],
      const AskTapiCard(),
      const SizedBox(height: 22),
      _EvSection(vehicles: evs),
      const SizedBox(height: 22),
      const NearbySafetyCard(),
      const SizedBox(height: 14),
      const _SafetyStrip(),
    ];
  }

  /// Tapi's one-line hello: the next trip if there is one, otherwise an invitation.
  static String _tapiLine(AppState state) {
    final next = state.upcomingTrips.firstOrNull;
    if (next != null && next.departureAt.difference(state.now).inHours < 12) {
      return 'Your ${Fmt.time(next.departureAt)} to ${next.destination} is booked. I\'ll remind you when to leave.';
    }
    return 'Where are you headed today? Tap me to plan it.';
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final item in [
              (Icons.celebration_rounded, 'Event rides', 'Buses from your area to events, and tickets', '/events'),
              (Icons.groups_rounded, 'Tag Along', 'Share the ride home with colleagues nearby', '/tag-along'),
              (Icons.electric_car_rounded, 'Book an electric vehicle', 'Zero-emission rides from verified EV operators', '/ev'),
              (Icons.radar_rounded, 'Live map', 'Buses and electric cars near you, with arrival times', '/live'),
              (Icons.radar_rounded, 'Nearby & safety', 'Live traffic, places near you and SOS (FindMe AI)', '/nearby'),
              (Icons.handshake_rounded, 'Become a partner', 'Drive with Tap A Ride or register your company', '/partner/apply'),
              (Icons.health_and_safety_outlined, 'Safety centre', 'Emergency numbers and trip sharing', '/app/profile'),
            ])
              ListTile(
                leading: IconBadge(item.$1, size: 42),
                title: Text(item.$2),
                subtitle: Text(item.$3),
                trailing: (item.$4 == '/ev' && !Launch.electric) || (item.$4 == '/live' && !Launch.liveMap) ? const SoonTag() : const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheet);
                  item.$4.startsWith('/app') ? context.go(item.$4) : context.push(item.$4);
                },
              ),
          ]),
        ),
      ),
    );
  }
}

class _Feature {
  const _Feature(this.icon, this.label, this.onTap, {this.primary = false, this.badge = 0, this.soon = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final int badge;

  /// Not open yet: the tile is quieter and says "Soon".
  final bool soon;
}

/// All rider features as one grid: four across on phones, eight across on wide screens.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.items});
  final List<_Feature> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final perRow = c.maxWidth >= 640 ? 8 : 4;
      final width = (c.maxWidth - (perRow - 1) * 8) / perRow;
      return Wrap(spacing: 8, runSpacing: 12, children: [
        for (final f in items)
          SizedBox(
            width: width,
            child: Semantics(
              button: true,
              label: f.soon ? '${f.label}, coming soon' : (f.badge > 0 ? '${f.label}, ${f.badge} waiting' : f.label),
              child: InkWell(
                onTap: f.onTap,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    Badge(
                      isLabelVisible: f.badge > 0 || f.soon,
                      backgroundColor: f.soon ? AppColors.amberSoft : null,
                      textColor: f.soon ? AppColors.amber : null,
                      label: Text(f.soon ? 'Soon' : '${f.badge}', style: f.soon ? const TextStyle(fontSize: 9, fontWeight: FontWeight.w800) : null),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: f.primary ? AppColors.forest : (f.soon ? AppColors.surfaceSunk : AppColors.surface),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: f.primary ? AppColors.forest : AppColors.line),
                          boxShadow: f.soon ? null : AppShadow.card,
                        ),
                        child: Icon(f.icon, color: f.primary ? Colors.white : (f.soon ? AppColors.faint : AppColors.forest), size: 25),
                      ),
                    ),
                    const SizedBox(height: 7),
                    ExcludeSemantics(child: Text(f.label, style: text.labelMedium?.copyWith(color: f.soon ? AppColors.muted : null), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _UpcomingTrip extends StatelessWidget {
  const _UpcomingTrip({required this.booking, required this.leaveBy});
  final String leaveBy;
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      color: AppColors.forest,
      border: false,
      onTap: () => context.push('/ticket/${booking.id}'),
      semanticLabel: 'Your next trip, ${booking.origin} to ${booking.destination}, ${Fmt.dayTime(booking.departureAt)}. Open ticket.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Your next trip', style: text.labelMedium?.copyWith(color: AppColors.onForestMuted)),
          const Spacer(),
          StatusPill(booking.statusLabel, tone: booking.status == BookingStatus.requested ? Tone.warning : Tone.success),
        ]),
        const SizedBox(height: 12),
        RouteStrip(origin: booking.origin, destination: booking.destination, color: AppColors.leaf, textColor: Colors.white),
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.schedule_rounded, size: 16, color: AppColors.onForestMuted),
          const SizedBox(width: 6),
          Text('${Fmt.dayTime(booking.departureAt)} · ${Fmt.relative(booking.departureAt)}', style: text.bodyMedium?.copyWith(color: Colors.white)),
          const Spacer(),
          Text('Show ticket', style: text.labelLarge?.copyWith(color: Colors.white)),
          const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ]),
        if (booking.kind == BookingKind.transit) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Row(children: [
              const Icon(Icons.directions_walk_rounded, size: 16, color: AppColors.leaf),
              const SizedBox(width: 6),
              Expanded(child: Text(leaveBy, style: text.bodySmall?.copyWith(color: Colors.white))),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _TravelSmart extends StatelessWidget {
  const _TravelSmart({required this.onLearnMore});
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: SizedBox(
        height: 168,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 6,
            child: Container(
              color: AppColors.forest,
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Travel Smart', style: text.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text('Tap. Scan. Ride.', style: text.titleMedium?.copyWith(color: AppColors.onForestMuted)),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: onLearnMore,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.leaf, foregroundColor: AppColors.forestDeep, minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                  child: const Text('Learn More'),
                ),
              ]),
            ),
          ),
          const Expanded(
            flex: 5,
            child: PhotoView(AppPhoto.lightRail, alignment: Alignment(0.3, 0), semanticLabel: 'Abuja light rail train at a station platform'),
          ),
        ]),
      ),
    );
  }
}

class _EvSection extends StatelessWidget {
  const _EvSection({required this.vehicles});
  final List<Vehicle> vehicles;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!Launch.electric) {
      return Panel(
        padding: EdgeInsets.zero,
        onTap: () => context.push('/ev'),
        semanticLabel: 'Electric rides, coming soon',
        child: Row(children: [
          const SizedBox(width: 112, height: 112, child: PhotoView(evPhoto, alignment: Alignment(0.5, 0.2), semanticLabel: 'Electric car plugged in at a charging point')),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text('Electric rides', style: text.titleMedium)), const SizedBox(width: 8), const SoonTag()]),
                const SizedBox(height: 4),
                Text('Quiet, clean cars door to door. Opening as verified EV operators join.', style: text.bodySmall),
              ]),
            ),
          ),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title: 'Book Electric Vehicle', action: 'All EVs', onAction: () => context.push('/ev')),
      Panel(
        padding: EdgeInsets.zero,
        onTap: () => context.push('/ev'),
        semanticLabel: 'Book an electric vehicle, ${vehicles.length} available nearby',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 150, child: PhotoView(evPhoto, alignment: Alignment(0.5, 0.2), semanticLabel: 'Electric car plugged in at a charging point')),
          Padding(
            padding: const EdgeInsets.all(14),
            child: vehicles.isEmpty
                ? Text('No electric vehicles are free right now. Check again in a few minutes.', style: text.bodyMedium)
                : Column(children: [
                    for (final v in vehicles)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          const Icon(Icons.electric_car_rounded, color: AppColors.forest, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(v.model, style: text.titleSmall),
                              Text('${v.capacity} seats · ${v.area} · ${v.batteryPct ?? 0}% battery', style: text.bodySmall),
                            ]),
                          ),
                          Text('from ${Fmt.naira(v.baseFare ?? 1200)}', style: text.labelLarge?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                  ]),
          ),
        ]),
      ),
    ]);
  }
}

class _TagAlongBanner extends StatelessWidget {
  const _TagAlongBanner({required this.onOpen, this.requests = 0});
  final VoidCallback onOpen;

  /// Riders waiting for this user's answer on rides they host.
  final int requests;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      semanticLabel: 'Tag Along. Share rides, save more.',
      child: Row(children: [
        const SizedBox(width: 128, height: 156, child: PhotoView(AppPhoto.shareRideRider, alignment: Alignment(0.1, -0.2), semanticLabel: 'A smiling rider looking back from the front seat of a shared car')),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tag Along', style: text.titleLarge),
              const SizedBox(height: 6),
              Text('Share rides, save more: ride home with verified colleagues who live near you.', style: text.bodySmall),
              const SizedBox(height: 10),
              if (requests > 0)
                StatusPill('$requests request${requests == 1 ? '' : 's'} to answer', tone: Tone.warning, icon: Icons.how_to_reg_rounded)
              else
                Row(children: [
                  Text('Find a Ride', style: text.labelLarge?.copyWith(color: AppColors.forest)),
                  const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.forest),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SafetyStrip extends StatelessWidget {
  const _SafetyStrip();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_rounded, color: AppColors.forest),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Safe & verified', style: text.titleMedium),
            const SizedBox(height: 4),
            Text('Only vehicles verified on the FCTA register can take bookings. Your ticket shows the plate, so you know which vehicle to board.', style: text.bodySmall?.copyWith(color: AppColors.inkSoft)),
          ]),
        ),
      ]),
    );
  }
}
