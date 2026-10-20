import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/insights.dart';
import '../../core/models.dart';
import '../../core/reminders.dart';
import '../../shared/ui.dart';
import '../assistant/assistant_sheet.dart';

/// "Time to leave" banner: slides down when a trip reminder fires, while the app is open.
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final reminders = context.read<AppState>().reminders;
    final reduce = MediaQuery.of(context).disableAnimations;
    return ListenableBuilder(
      listenable: reminders,
      builder: (context, _) {
        final r = reminders.active;
        return AnimatedSize(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: r == null ? const SizedBox(width: double.infinity) : Padding(padding: const EdgeInsets.only(bottom: 14), child: _BannerBody(reminder: r, onClose: reminders.dismiss)),
        );
      },
    );
  }
}

class _BannerBody extends StatelessWidget {
  const _BannerBody({required this.reminder, required this.onClose});
  final TripReminder reminder;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(color: AppColors.forestDeep, borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: AppShadow.raised),
        child: Row(children: [
          const Icon(Icons.notifications_active_rounded, color: AppColors.leaf),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(reminder.title, style: text.titleSmall?.copyWith(color: Colors.white)),
              Text(reminder.body, style: text.bodySmall?.copyWith(color: AppColors.onForestMuted)),
            ]),
          ),
          TextButton(
            onPressed: () {
              onClose();
              context.push('/ticket/${reminder.bookingId}');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Ticket'),
          ),
          IconButton(tooltip: 'Dismiss', onPressed: onClose, icon: const Icon(Icons.close_rounded, color: AppColors.onForestMuted)),
        ]),
      ),
    );
  }
}

/// When to leave for the next trip: road time from the rider (or an estimate).
String leaveByLine(AppState state, Booking booking) {
  final plan = state.leavePlans[booking.id];
  if (plan != null) {
    return 'Leave by ${Fmt.time(plan.leaveAt)} · ${plan.travelMinutes} min to the stop${plan.fromLocation ? ' from where you are' : ''}';
  }
  return 'Leave by ${Fmt.time(booking.departureAt.subtract(const Duration(minutes: 20)))} to reach the stop on time';
}

/// "Book early" cards learned from the rider's habits.
class SmartSuggestions extends StatelessWidget {
  const SmartSuggestions({super.key, required this.suggestions});
  final List<RideSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.leafText),
        const SizedBox(width: 6),
        Text('Suggested for you', style: text.titleLarge),
      ]),
      const SizedBox(height: 10),
      for (final s in suggestions)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const IconBadge(Icons.event_repeat_rounded, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(s.reason, style: text.bodySmall),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: () => context.push(Uri(path: '/ride/${s.route.id}/pay', queryParameters: {'at': s.departure.toUtc().toIso8601String()}).toString()),
                child: Text('Book ${Fmt.time(s.departure)}'),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Tapi and the assistant's starter questions.
class AskTapiCard extends StatelessWidget {
  const AskTapiCard({super.key});

  static const prompts = [
    'When should I leave for my next trip?',
    'Find me the cheapest ride to Wuse 2 tomorrow at 8am',
    'Remind me 30 minutes before my trip',
    'Book an electric car from Maitama to the airport',
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      color: AppColors.mint,
      border: false,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconBadge(Icons.auto_awesome_rounded, size: 52, color: AppColors.forest, iconColor: Colors.white, radius: 26),
          const SizedBox(width: 6),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ask Tapi', style: text.titleLarge),
              Text('Your AI travel guide plans routes, books seats and reminds you when to leave.', style: text.bodySmall?.copyWith(color: AppColors.inkSoft)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in prompts)
            ActionChip(
              label: Text(p),
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.mintStrong),
              onPressed: () => openAssistant(context, prompt: p),
            ),
        ]),
      ]),
    );
  }
}

/// Entry to FindMe AI (nearby places, live traffic, SOS).
class NearbySafetyCard extends StatelessWidget {
  const NearbySafetyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      onTap: () => context.push('/nearby'),
      semanticLabel: 'Nearby and safety map, powered by FindMe AI',
      child: Row(children: [
        const IconBadge(Icons.radar_rounded, size: 48, color: AppColors.blueSoft, iconColor: AppColors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nearby & safety', style: text.titleMedium),
            Text('Live traffic, places near you, incidents and SOS · FindMe AI', style: text.bodySmall),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.forest),
      ]),
    );
  }
}
