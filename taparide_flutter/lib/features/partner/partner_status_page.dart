import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/partner_models.dart';
import '../../shared/brand.dart';
import '../../shared/mascot/mascot.dart';
import '../../shared/ui.dart';
import 'partner_apply_page.dart';

class PartnerStatusPage extends StatelessWidget {
  const PartnerStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final apps = state.myApplications;
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(fallback: '/'), title: const BrandLockup(height: 26)),
      body: RefreshIndicator(
        color: AppColors.forest,
        onRefresh: state.refresh,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          MaxWidth(
            width: 720,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Your partner application', style: text.headlineLarge),
              const SizedBox(height: 16),
              if (apps.isEmpty)
                EmptyState(icon: Icons.handshake_rounded, title: 'No application yet', message: 'Apply as a private driver or register your company or agency.', action: 'Apply now', onAction: () => context.go('/partner/apply'))
              else
                for (final app in apps) Padding(padding: const EdgeInsets.only(bottom: 16), child: _ApplicationCard(app: app)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.app});
  final PartnerApplication app;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final steps = [ApplicationStatus.submitted, ApplicationStatus.underReview, ApplicationStatus.approved];
    final reached = switch (app.status) {
      ApplicationStatus.submitted => 0,
      ApplicationStatus.underReview || ApplicationStatus.needsChanges => 1,
      ApplicationStatus.approved || ApplicationStatus.rejected => 2,
    };
    final mood = switch (app.status) { ApplicationStatus.approved => MascotMood.celebrate, ApplicationStatus.rejected => MascotMood.sleep, _ => MascotMood.think };
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Mascot(mood: mood, size: 72),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.displayName, style: text.titleLarge),
              Text('${app.type.label} · submitted ${Fmt.date(app.createdAt)}', style: text.bodySmall),
            ]),
          ),
          StatusPill(app.status.label, tone: switch (app.status) {
            ApplicationStatus.approved => Tone.success,
            ApplicationStatus.rejected => Tone.danger,
            ApplicationStatus.needsChanges => Tone.warning,
            _ => Tone.info,
          }),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) Expanded(child: Container(height: 3, color: i <= reached ? AppColors.forest : AppColors.mintStrong)),
            Column(children: [
              Icon(i <= reached ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: i <= reached ? AppColors.forest : AppColors.lineStrong),
              const SizedBox(height: 4),
              Text(i == 2 && app.status == ApplicationStatus.rejected ? 'Decision' : steps[i].label, style: text.labelSmall),
            ]),
          ],
        ]),
        if (app.reviewerNote != null && app.reviewerNote!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Text('Reviewer: ${app.reviewerNote}', style: text.bodyMedium?.copyWith(color: AppColors.ink)),
          ),
        ],
        if (app.aiCheck != null) ...[
          const SizedBox(height: 16),
          Row(children: [Text('AI document check', style: text.titleSmall), const Spacer(), AiVerdictPill(overall: app.aiCheck!.overall)]),
          const SizedBox(height: 4),
          Text(app.aiCheck!.summary, style: text.bodySmall),
        ],
        const SizedBox(height: 16),
        if (app.status == ApplicationStatus.approved)
          FilledButton.icon(
            onPressed: () async {
              final state = context.read<AppState>();
              await state.reloadUser();
              if (context.mounted && state.user != null) context.go(homeFor(state.user!));
            },
            icon: const Icon(Icons.space_dashboard_rounded),
            label: const Text('Open my partner dashboard'),
          )
        else if (app.status == ApplicationStatus.needsChanges || app.status == ApplicationStatus.rejected)
          OutlinedButton(onPressed: () => context.go('/partner/apply'), child: const Text('Start a new application'))
        else
          Text('We usually review applications within one working day. You can close this page; your status is saved.', style: text.bodySmall),
      ]),
    );
  }
}
