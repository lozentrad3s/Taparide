import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/live_models.dart';
import '../../shared/brand.dart';

/// Second sign-in step for platform admins and FCTA staff: a 6-digit code from an
/// authenticator app (Google Authenticator, Microsoft Authenticator, Authy…).
/// The first time, the person adds Tap A Ride to their app by scanning a QR code.
class TwoStepPage extends StatefulWidget {
  const TwoStepPage({super.key});

  @override
  State<TwoStepPage> createState() => _TwoStepPageState();
}

class _TwoStepPageState extends State<TwoStepPage> {
  final _code = TextEditingController();
  TwoStepStatus? _status;
  TwoStepSetup? _setup;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    try {
      final status = await state.twoStepStatus();
      TwoStepSetup? setup;
      if (status.factorId == null) setup = await state.twoStepSetup();
      if (mounted) {
        setState(() {
          _status = status;
          _setup = setup;
          _busy = false;
        });
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _verify() async {
    final factorId = _setup?.factorId ?? _status?.factorId;
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (factorId == null) return;
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().twoStepVerify(factorId: factorId, code: code);
      // The router opens the dashboard as soon as the step is passed.
    } on BackendException {
      if (mounted) setState(() => _error = 'That code did not work. Codes change every 30 seconds; try the newest one.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final setup = _setup;
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Align(alignment: Alignment.centerLeft, child: BrandLockup(height: 30)),
                  const SizedBox(height: 24),
                  Text(setup != null ? 'Protect your dashboard' : 'Two-step sign-in', style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    setup != null
                        ? 'Admin and FCTA accounts need a second step. Add Tap A Ride to an authenticator app (Google Authenticator, Microsoft Authenticator or Authy), then enter the 6-digit code it shows.'
                        : 'Enter the 6-digit code from your authenticator app.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  if (_busy && _status == null)
                    const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                  else ...[
                    if (setup != null) ...[
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(AppRadius.md)),
                          child: QrImageView(data: setup.uri, size: 190, semanticsLabel: 'QR code to add Tap A Ride to your authenticator app'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text("Can't scan? Type this key into the app:", style: text.bodySmall, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Flexible(child: SelectableText(setup.secret, style: text.titleSmall?.copyWith(letterSpacing: 1.5, fontFeatures: tabular), textAlign: TextAlign.center)),
                        IconButton(
                          tooltip: 'Copy key',
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () => Clipboard.setData(ClipboardData(text: setup.secret)),
                        ),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _code,
                      autofocus: setup == null,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      onSubmitted: (_) => _verify(),
                      style: text.headlineSmall?.copyWith(letterSpacing: 8, fontFeatures: tabular),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(hintText: '000000', labelText: '6-digit code'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.red, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _verify,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: Text(setup != null ? 'Turn on and continue' : 'Continue'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(onPressed: () => context.read<AppState>().signOut(), child: const Text('Sign out')),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
