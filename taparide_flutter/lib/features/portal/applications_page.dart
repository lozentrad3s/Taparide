import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/partner_models.dart';
import '../../shared/ui.dart';
import '../partner/partner_apply_page.dart';
import 'portal_widgets.dart';

/// FCTA / admin review queue for partner applications (drivers, companies, agencies).
class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key});

  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  ApplicationStatus? _filter = ApplicationStatus.submitted;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final all = state.partnerApplications;
    final list = [for (final a in all) if (_filter == null || a.status == _filter || (_filter == ApplicationStatus.submitted && a.status == ApplicationStatus.underReview)) a];
    return PortalScaffold(
      title: 'Partner applications',
      subtitle: 'Private drivers, transport companies and government agencies asking to join',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in <ApplicationStatus?>[ApplicationStatus.submitted, ApplicationStatus.needsChanges, ApplicationStatus.approved, ApplicationStatus.rejected, null])
            ChoiceChip(
              label: Text(f == null ? 'All (${all.length})' : '${f == ApplicationStatus.submitted ? 'To review' : f.label} (${all.where((a) => f == ApplicationStatus.submitted ? a.status.isOpen : a.status == f).length})'),
              selected: _filter == f,
              showCheckmark: false,
              labelStyle: TextStyle(color: _filter == f ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
              onSelected: (_) => setState(() => _filter = f),
            ),
        ]),
        const SizedBox(height: 14),
        DataList<PartnerApplication>(
          items: list,
          empty: const EmptyState(icon: Icons.inbox_rounded, title: 'Nothing to review', message: 'New partner applications appear here as soon as they are submitted.'),
          onTap: (a) => showDialog<void>(context: context, builder: (_) => ApplicationReviewDialog(app: a)),
          columns: [
            Col('Applicant', flex: 4, (a) => Row(children: [
                  IconBadge(a.type.icon, size: 36, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.displayName, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                      Text(a.type.label, style: text.bodySmall),
                    ]),
                  ),
                ])),
            Col('Key details', flex: 3, (a) => Text(a.type.isOrganisation ? '${a.rcNumber ?? '—'} · ${a.fleetSize ?? 0} vehicles' : '${a.plateNumber} · ${a.vehicleMake} ${a.vehicleModel}', style: text.bodyMedium, overflow: TextOverflow.ellipsis)),
            Col('AI check', (a) => a.aiCheck == null ? Text('Not run', style: text.bodySmall) : AiVerdictPill(overall: a.aiCheck!.overall)),
            Col('Submitted', (a) => Text(Fmt.relative(a.createdAt), style: text.bodySmall)),
            Col('Status', (a) => StatusPill(a.status.label, tone: switch (a.status) {
                  ApplicationStatus.approved => Tone.success,
                  ApplicationStatus.rejected => Tone.danger,
                  ApplicationStatus.needsChanges => Tone.warning,
                  _ => Tone.info,
                })),
          ],
          trailing: (a) => TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => ApplicationReviewDialog(app: a)), child: const Text('Review')),
        ),
      ],
    );
  }
}

class ApplicationReviewDialog extends StatefulWidget {
  const ApplicationReviewDialog({super.key, required this.app});
  final PartnerApplication app;

  @override
  State<ApplicationReviewDialog> createState() => _ApplicationReviewDialogState();
}

class _ApplicationReviewDialogState extends State<ApplicationReviewDialog> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(ApplicationStatus decision) async {
    setState(() => _busy = true);
    final ok = await attemptOk(
      context,
      () => context.read<AppState>().reviewApplication(widget.app, decision, _note.text),
      success: switch (decision) {
        ApplicationStatus.approved => '${widget.app.displayName} approved. Their dashboard is ready.',
        ApplicationStatus.rejected => 'Application declined',
        _ => 'Changes requested',
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _open(DocumentFile doc) async {
    final opened = await attempt(context, () => context.read<AppState>().backend.openDocument(doc));
    if (opened == null || !mounted) return;
    if (opened.url != null) {
      await launchUrl(Uri.parse(opened.url!), webOnlyWindowName: '_blank');
    } else if (opened.bytes != null && opened.isImage) {
      showDialog<void>(context: context, builder: (d) => Dialog(child: InteractiveViewer(child: Image.memory(opened.bytes!))));
    } else {
      showMessage(context, 'This document is no longer stored on this device (demo mode).', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = widget.app;
    final open = a.status != ApplicationStatus.approved;
    final rows = a.type.isOrganisation
        ? [
            ('Business', a.displayName),
            ('CAC RC number', a.rcNumber ?? '—'),
            ('TIN', a.tin ?? '—'),
            ('Fleet size', '${a.fleetSize ?? 0} vehicles'),
            ('Area / address', '${a.area} · ${a.address}'),
            ('Contact', '${a.fullName} (${a.contactRole ?? ''}) · ${a.phone} · ${a.email}'),
          ]
        : [
            ('Name', a.fullName),
            ('Contact', '${a.phone} · ${a.email}'),
            ('Date of birth', Fmt.date(a.dateOfBirth)),
            ('Address', '${a.address}, ${a.area}'),
            if (a.nin != null) ('NIN', a.nin!),
            ('Next of kin', '${a.nextOfKinName ?? '—'} · ${a.nextOfKinPhone ?? ''}'),
            ('Licence', '${a.licenceNumber} · class ${a.licenceClass} · expires ${Fmt.date(a.licenceExpiry)}'),
            ('Vehicle', '${a.vehicleLabel} · ${a.seats} seats'),
            ('Plate', a.plateNumber),
            ('Chassis (VIN)', a.chassisNumber),
            if (a.engineNumber != null) ('Engine number', a.engineNumber!),
          ];
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              IconBadge(a.type.icon, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.displayName, style: text.headlineSmall),
                  Text('${a.type.label} · submitted ${Fmt.date(a.createdAt)}', style: text.bodySmall),
                ]),
              ),
              StatusPill(a.status.label, tone: a.status == ApplicationStatus.approved ? Tone.success : Tone.info),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          const Divider(),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 140, child: Text(r.$1, style: text.bodySmall)),
                    Expanded(child: SelectableText(r.$2, style: text.titleSmall)),
                  ]),
                ),
              const SizedBox(height: 14),
              Text('Documents', style: text.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in a.documents) ActionChip(avatar: Icon(d.slot.icon, size: 16, color: AppColors.forest), label: Text(d.slot.label), onPressed: () => _open(d)),
                if (a.documents.isEmpty) Text('No documents uploaded.', style: text.bodySmall),
              ]),
              const SizedBox(height: 16),
              Panel(
                shadow: false,
                color: AppColors.surfaceSunk,
                child: a.aiCheck == null
                    ? Text('The applicant did not run the AI document check. Review the documents manually.', style: text.bodyMedium)
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [Text('AI document check', style: text.titleMedium), const Spacer(), AiVerdictPill(overall: a.aiCheck!.overall)]),
                        const SizedBox(height: 4),
                        Text(a.aiCheck!.summary, style: text.bodySmall),
                        const SizedBox(height: 8),
                        AiChecksList(checks: a.aiCheck!.checks),
                        const SizedBox(height: 4),
                        Text('The AI only advises. You make the decision.', style: text.labelSmall),
                      ]),
              ),
              if (a.reviewerNote != null) ...[const SizedBox(height: 12), Text('Previous note: ${a.reviewerNote} (${a.reviewedBy ?? ''})', style: text.bodySmall)],
              if (open) ...[
                const SizedBox(height: 16),
                TextField(controller: _note, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Note to the applicant (required to decline or request changes)')),
              ],
            ]),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                TextButton(onPressed: _busy ? null : () => _decide(ApplicationStatus.rejected), style: TextButton.styleFrom(foregroundColor: AppColors.red), child: const Text('Decline')),
                OutlinedButton(onPressed: _busy ? null : () => _decide(ApplicationStatus.needsChanges), child: const Text('Request changes')),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _decide(ApplicationStatus.approved),
                  icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('Approve & create dashboard'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
