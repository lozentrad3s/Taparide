import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../shared/brand.dart';
import '../../shared/password_field.dart';

/// Shown after someone opens a password-reset email: they are signed in by the link and choose
/// a new password before anything else opens.
class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({super.key});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The router moves on to the account's home once the password is saved.
      await context.read<AppState>().setNewPassword(_password.text);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final email = context.watch<AppState>().user?.email;
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
                child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Align(alignment: Alignment.centerLeft, child: BrandLockup(height: 30)),
                    const SizedBox(height: 24),
                    Text('Choose a new password', style: text.headlineSmall),
                    const SizedBox(height: 8),
                    Text(email == null ? 'Use it the next time you sign in.' : 'For $email. Use it the next time you sign in.', style: text.bodyMedium),
                    const SizedBox(height: 20),
                    PasswordField(controller: _password, isNew: true, label: 'New password', onSubmitted: (_) => _save()),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.red, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: Text(_busy ? 'Saving…' : 'Save and continue'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
