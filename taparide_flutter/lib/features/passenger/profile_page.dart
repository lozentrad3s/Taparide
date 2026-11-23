import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/demo_backend.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/live_models.dart';
import '../../core/models.dart';
import '../../core/partner_models.dart';
import '../../shared/ui.dart';
import 'rider_widgets.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.topUpReference});

  /// Set when the rider returns from the payment page (`/app/profile?topup=…`).
  final String? topUpReference;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    final reference = widget.topUpReference;
    if (reference != null && reference.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirmTopUp(reference));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppState>().loadTopUps();
      });
    }
  }

  Future<void> _confirmTopUp(String reference) async {
    setState(() => _confirming = true);
    final state = context.read<AppState>();
    try {
      var result = await state.confirmTopUp(reference);
      // Bank transfers can take a moment to land; look again once.
      if (result.status == TopUpStatus.pending) {
        await Future<void>.delayed(const Duration(seconds: 5));
        result = await state.confirmTopUp(reference);
      }
      if (!mounted) return;
      switch (result.status) {
        case TopUpStatus.paid:
          showMessage(context, '${Fmt.naira(result.amount)} added to your Tap Card');
        case TopUpStatus.pending:
          showMessage(context, 'Your payment is still being confirmed. Your balance updates as soon as it lands.');
        case TopUpStatus.failed:
          showMessage(context, 'The payment did not go through. You were not charged.', error: true);
      }
    } on BackendException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
        // Drop the reference from the address so a refresh does not repeat the check.
        context.go('/app/profile');
      }
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await context.read<AppState>().signOut();
    if (context.mounted) context.go('/');
  }

  Future<void> _resetDemo(BuildContext context) async {
    final state = context.read<AppState>();
    final backend = state.backend;
    if (backend is! DemoBackend) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text('Bookings, top-ups and admin changes made on this device are cleared and the original demo data comes back. You will be signed out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep my data')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await backend.reset();
    await state.signOut();
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final user = state.user!;
    final wide = isWide(context, 900);
    final spent = state.myBookings.where((b) => b.status != BookingStatus.cancelled && b.paymentMethod != PaymentMethod.splitCost).fold<int>(0, (s, b) => s + b.fare);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(0, 18, 0, 32),
          children: [
            MaxWidth(
              width: 760,
              padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Profile', style: text.headlineLarge),
                const SizedBox(height: 16),
                Panel(
                  child: Row(children: [
                    Avatar(initials: user.initials, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(user.fullName, style: text.titleLarge),
                        const SizedBox(height: 2),
                        Text(user.email, style: text.bodySmall),
                        if (user.phone != null) Text(user.phone!, style: text.bodySmall),
                        if (user.organisation != null) Text(user.organisation!, style: text.bodySmall),
                      ]),
                    ),
                    StatusPill(user.verified ? 'Verified' : 'Unverified', tone: user.verified ? Tone.success : Tone.warning, icon: user.verified ? Icons.verified_rounded : Icons.pending_outlined),
                  ]),
                ),
                const SizedBox(height: 22),
                SectionHeader(title: 'Payment methods', subtitle: 'Spent on trips so far: ${Fmt.naira(spent)}'),
                TapCardView(wallet: state.wallet, onTap: () => showTapAndPaySheet(context)),
                const SizedBox(height: 10),
                const RideRewardCard(hint: true),
                if (_confirming)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Confirming your payment…', style: text.bodySmall),
                    ]),
                  ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: AppState.walletTopUpsOpen
                        ? FilledButton.icon(onPressed: () => showTopUpSheet(context), icon: const Icon(Icons.add_rounded), label: const Text('Top up'))
                        : OutlinedButton.icon(onPressed: () => showTopUpSheet(context), icon: const Icon(Icons.schedule_rounded), label: const Text('Top up · soon')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: () => showTapAndPaySheet(context), icon: const Icon(Icons.qr_code_2_rounded), label: const Text('Show my QR'))),
                ]),
                if (state.topUps.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Recent top-ups', style: text.titleSmall),
                  const SizedBox(height: 6),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (final (i, t) in state.topUps.take(5).indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          dense: true,
                          leading: Icon(
                            t.status == 'paid' ? Icons.check_circle_rounded : (t.status == 'failed' ? Icons.cancel_rounded : Icons.schedule_rounded),
                            color: t.status == 'paid' ? AppColors.leafText : (t.status == 'failed' ? AppColors.red : AppColors.amber),
                          ),
                          title: Text(Fmt.naira(t.amount), style: text.titleSmall?.copyWith(fontFeatures: tabular)),
                          subtitle: Text('${Fmt.dayTime(t.createdAt)} · ${t.reference}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: StatusPill(
                            switch (t.status) { 'paid' => 'Added', 'failed' => 'Failed', _ => 'Confirming' },
                            tone: switch (t.status) { 'paid' => Tone.success, 'failed' => Tone.danger, _ => Tone.warning },
                          ),
                        ),
                      ],
                    ]),
                  ),
                  if (state.topUps.any((t) => t.status == 'pending'))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Bank transfers can take a few minutes. "Confirming" top-ups are added automatically once the bank confirms them.', style: text.bodySmall),
                    ),
                ],
                const SizedBox(height: 26),
                const SectionHeader(title: 'Safety centre'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.sos_rounded, color: AppColors.red),
                      title: const Text('Emergency (112)'),
                      subtitle: const Text('Nigeria\'s national emergency number'),
                      trailing: const Icon(Icons.call_rounded),
                      onTap: () => launchUrl(Uri(scheme: 'tel', path: '112')),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    const ListTile(
                      leading: Icon(Icons.verified_user_outlined),
                      title: Text('Board verified vehicles only'),
                      subtitle: Text('Check the plate on your ticket matches the vehicle before boarding.'),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    const ListTile(
                      leading: Icon(Icons.ios_share_rounded),
                      title: Text('Share every trip'),
                      subtitle: Text('Open a ticket and tap "Share trip" to send the details to someone you trust.'),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.radar_rounded, color: AppColors.blue),
                      title: const Text('Nearby & safety map'),
                      subtitle: const Text('Live traffic, incidents and SOS with FindMe AI'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/nearby'),
                    ),
                  ]),
                ),
                const SizedBox(height: 26),
                const SectionHeader(title: 'Earn with Tap A Ride'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const IconBadge(Icons.handshake_rounded, size: 40),
                    title: Text(state.myApplications.isEmpty ? 'Become a partner' : 'My partner application'),
                    subtitle: Text(state.myApplications.isEmpty
                        ? 'Drive your own car, or register your company or agency'
                        : '${state.myApplications.first.displayName} · ${state.myApplications.first.status.label}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(state.myApplications.isEmpty ? '/partner/apply' : '/partner/status'),
                  ),
                ),
                const SizedBox(height: 26),
                const SectionHeader(title: 'About'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('Photo credits'),
                      subtitle: const Text('Openly licensed photographs of Abuja'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/credits'),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.storage_rounded),
                      title: const Text('Data source'),
                      subtitle: Text(state.backend.isDemo ? 'Demo data stored on this device' : 'Live Supabase project'),
                      trailing: const DemoBadge(),
                    ),
                    if (state.backend is DemoBackend) ...[
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.restart_alt_rounded),
                        title: const Text('Reset demo data'),
                        subtitle: const Text('Start the demo again from the original data'),
                        onTap: () => _resetDemo(context),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
