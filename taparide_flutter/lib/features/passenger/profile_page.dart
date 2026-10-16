import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/demo_backend.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';
import 'rider_widgets.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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
                Row(children: [
                  Expanded(child: FilledButton.icon(onPressed: () => showTopUpSheet(context), icon: const Icon(Icons.add_rounded), label: const Text('Top up'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: () => showTapAndPaySheet(context), icon: const Icon(Icons.qr_code_2_rounded), label: const Text('Show my QR'))),
                ]),
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
                  ]),
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
