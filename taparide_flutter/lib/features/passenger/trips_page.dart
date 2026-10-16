import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';
import 'rider_widgets.dart';

class TripsPage extends StatelessWidget {
  const TripsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final wide = isWide(context, 900);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: DataGate(
            builder: (context) => Column(children: [
              MaxWidth(
                width: 900,
                padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 18, wide ? 32 : 18, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('My Trips', style: text.headlineLarge),
                  const SizedBox(height: 10),
                  TabBar(
                    labelColor: AppColors.forest,
                    unselectedLabelColor: AppColors.muted,
                    indicatorColor: AppColors.forest,
                    dividerColor: AppColors.line,
                    labelStyle: text.titleSmall,
                    tabs: [
                      Tab(text: 'Upcoming (${state.upcomingTrips.length})'),
                      Tab(text: 'Past (${state.pastTrips.length})'),
                    ],
                  ),
                ]),
              ),
              Expanded(
                child: TabBarView(children: [
                  _TripList(
                    bookings: state.upcomingTrips,
                    empty: EmptyState(
                      icon: Icons.confirmation_number_outlined,
                      title: 'No upcoming trips',
                      message: 'Book a seat on a route and your ticket will be here, ready to show the conductor.',
                      action: 'Book a ride',
                      onAction: () => context.go('/app/routes'),
                    ),
                  ),
                  _TripList(
                    bookings: state.pastTrips,
                    empty: const EmptyState(icon: Icons.history_rounded, title: 'No past trips yet', message: 'Completed and cancelled trips appear here.'),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TripList extends StatelessWidget {
  const _TripList({required this.bookings, required this.empty});
  final List<Booking> bookings;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    if (bookings.isEmpty) return ListView(children: [empty]);
    final wide = isWide(context, 900);
    return RefreshIndicator(
      color: AppColors.forest,
      onRefresh: state.refreshRider,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 14, bottom: 24),
        itemCount: bookings.length,
        itemBuilder: (context, i) => MaxWidth(
          width: 900,
          padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 0, wide ? 32 : 18, 10),
          child: BookingTile(booking: bookings[i], onTap: () => context.push('/ticket/${bookings[i].id}')),
        ),
      ),
    );
  }
}
