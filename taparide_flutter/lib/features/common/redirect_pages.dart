import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_mode.dart';
import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../shared/brand.dart';

/// The rider app and the dashboards are separate sites. A link that belongs to the other
/// one lands here and is sent on (with a button in case the browser blocks it).
class ElsewherePage extends StatefulWidget {
  const ElsewherePage({super.key, required this.toDashboard, this.fragment});
  final bool toDashboard;

  /// Route inside the other site, e.g. `/partner/apply?type=busOperator`.
  final String? fragment;

  String get url => (toDashboard ? AppMode.dashboardUrl : AppMode.riderAppUrl) + (fragment == null ? '' : '#$fragment');

  @override
  State<ElsewherePage> createState() => _ElsewherePageState();
}

class _ElsewherePageState extends State<ElsewherePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() => launchUrl(Uri.parse(widget.url), webOnlyWindowName: '_self');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final where = widget.toDashboard ? 'the Tap A Ride dashboard' : 'the Tap A Ride app';
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandLockup(height: 34),
              const SizedBox(height: 28),
              Text('Opening $where…', style: text.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(onPressed: _go, child: Text(widget.toDashboard ? 'Open the dashboard' : 'Open the app')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Someone arrives to create an account (e.g. from the website) while this browser is still
/// signed in to a different account: sign that one out first, then show sign-up.
class SwitchAccountPage extends StatefulWidget {
  const SwitchAccountPage({super.key, required this.query});
  final Map<String, String> query;

  @override
  State<SwitchAccountPage> createState() => _SwitchAccountPageState();
}

class _SwitchAccountPageState extends State<SwitchAccountPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AppState>().signOut();
      if (mounted) context.go(Uri(path: '/register', queryParameters: widget.query).toString());
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
