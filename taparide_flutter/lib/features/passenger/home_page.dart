import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/photos.dart';
import '../../shared/brand.dart';
import '../../shared/ui.dart';
import 'rider_widgets.dart';

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
                          Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _secondary(context, state))),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [..._primary(context, state, wide), ..._secondary(context, state)]),
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
      SizedBox(height: wide ? 12 : 18),
      Text('${Fmt.greeting(state.now)}, ${user.firstName}', style: wide ? text.displaySmall : text.headlineLarge),
      const SizedBox(height: 4),
      Text('Where are you headed today?', style: text.bodyLarge),
      const SizedBox(height: 18),
      _SearchField(onSubmit: (q) => context.go(Uri(path: '/app/routes', queryParameters: q.isEmpty ? null : {'q': q}).toString())),
      const SizedBox(height: 18),
      _QuickActions(
        onBook: () => context.go('/app/routes'),
        onTapPay: () => showTapAndPaySheet(context),
        onTrips: () => context.go('/app/trips'),
        onMore: () => _showMore(context),
      ),
      const SizedBox(height: 22),
      if (state.upcomingTrips.isNotEmpty) ...[
        _UpcomingTrip(booking: state.upcomingTrips.first),
        const SizedBox(height: 22),
      ],
      SectionHeader(title: 'Popular Routes', action: 'View all', onAction: () => context.go('/app/routes')),
      for (final r in routes)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RouteRow(route: r, onTap: () => context.push('/ride/${r.id}')),
        ),
      const SizedBox(height: 14),
      _TravelSmart(onLearnMore: () => showTapAndPaySheet(context)),
      const SizedBox(height: 22),
    ];
  }

  List<Widget> _secondary(BuildContext context, AppState state) {
    final evs = state.availableEvs.where((v) => v.status == VehicleStatus.active).take(3).toList();
    return [
      _EvSection(vehicles: evs),
      const SizedBox(height: 22),
      _TagAlongBanner(onOpen: () => context.push('/tag-along')),
      const SizedBox(height: 22),
      const _SafetyStrip(),
    ];
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final item in [
              (Icons.electric_car_rounded, 'Book an electric vehicle', 'Zero-emission rides from verified EV operators', '/ev'),
              (Icons.groups_rounded, 'Tag Along', 'Share the ride home with colleagues nearby', '/tag-along'),
              (Icons.health_and_safety_outlined, 'Safety centre', 'Emergency numbers and trip sharing', '/app/profile'),
            ])
              ListTile(
                leading: IconBadge(item.$1, size: 42),
                title: Text(item.$2),
                subtitle: Text(item.$3),
                trailing: const Icon(Icons.chevron_right_rounded),
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

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onSubmit});
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return TextField(
      textInputAction: TextInputAction.search,
      onSubmitted: (v) => onSubmit(v.trim()),
      decoration: InputDecoration(
        hintText: 'Search for routes, destinations...',
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.forest),
        suffixIcon: IconButton(tooltip: 'Browse all routes', icon: const Icon(Icons.tune_rounded), onPressed: () => onSubmit('')),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: const BorderSide(color: AppColors.forest, width: 1.8)),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onBook, required this.onTapPay, required this.onTrips, required this.onMore});
  final VoidCallback onBook;
  final VoidCallback onTapPay;
  final VoidCallback onTrips;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.directions_bus_rounded, 'Book a Ride', onBook),
      (Icons.contactless_rounded, 'Tap & Pay', onTapPay),
      (Icons.confirmation_number_rounded, 'My Trips', onTrips),
      (Icons.more_horiz_rounded, 'More', onMore),
    ];
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            button: true,
            label: items[i].$2,
            child: InkWell(
              onTap: items[i].$3,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: i == 0 ? AppColors.forest : AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: i == 0 ? AppColors.forest : AppColors.line),
                      boxShadow: AppShadow.card,
                    ),
                    child: Icon(items[i].$1, color: i == 0 ? Colors.white : AppColors.forest, size: 26),
                  ),
                  const SizedBox(height: 8),
                  ExcludeSemantics(child: Text(items[i].$2, style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _UpcomingTrip extends StatelessWidget {
  const _UpcomingTrip({required this.booking});
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
          StatusPill(booking.status.label, tone: booking.status == BookingStatus.requested ? Tone.warning : Tone.success),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title: 'Book Electric Vehicle', action: 'All EVs', onAction: () => context.push('/ev')),
      Panel(
        padding: EdgeInsets.zero,
        onTap: () => context.push('/ev'),
        semanticLabel: 'Book an electric vehicle, ${vehicles.length} available nearby',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 150, child: PhotoView(AppPhoto.evSuv, alignment: Alignment(0, 0.2), semanticLabel: 'White electric SUV')),
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
  const _TagAlongBanner({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      semanticLabel: 'Tag Along. Share rides, save more.',
      child: Row(children: [
        const SizedBox(width: 128, height: 156, child: PhotoView(AppPhoto.taxis, alignment: Alignment(-0.3, 0.1))),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tag Along', style: text.titleLarge),
              const SizedBox(height: 6),
              Text('Share rides, save more: ride home with verified colleagues who live near you.', style: text.bodySmall),
              const SizedBox(height: 10),
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
