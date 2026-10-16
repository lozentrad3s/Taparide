import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/backend/demo_seed.dart';
import '../../core/models.dart';
import '../../core/photos.dart';
import '../../shared/brand.dart';
import '../../shared/ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.portal, this.from, this.startInRegister = false});
  final Portal portal;
  final String? from;
  final bool startInRegister;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _organisation = TextEditingController();

  late Portal _portal = widget.portal;
  late bool _register = widget.startInRegister && widget.portal == Portal.passenger;
  bool _showPassword = false;
  bool _agreed = false;
  bool _busy = false;
  BackendException? _error;

  @override
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The router reuses this page when only the query changes (e.g. ?portal=partner).
    if (oldWidget.portal != widget.portal || oldWidget.startInRegister != widget.startInRegister) {
      _setPortal(widget.portal);
      _register = widget.startInRegister && widget.portal == Portal.passenger;
    }
  }

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _phone, _organisation]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setPortal(Portal portal) => setState(() {
        _portal = portal;
        _register = false;
        _error = null;
      });

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (_register && !_agreed) {
      setState(() => _error = const BackendException(BackendErrorKind.validation, 'Please accept the terms and privacy policy to continue.'));
      return;
    }
    setState(() => _busy = true);
    final state = context.read<AppState>();
    try {
      if (_register) {
        await state.register(fullName: _name.text, email: _email.text, phone: _phone.text, password: _password.text, organisation: _organisation.text);
      } else {
        await state.signIn(email: _email.text, password: _password.text, portal: _portal);
      }
      // The router moves on as soon as the session changes.
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (_) {
      if (mounted) setState(() => _error = const BackendException(BackendErrorKind.unknown, 'Something went wrong. Please try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text);
    final sent = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Reset your password', style: Theme.of(sheet).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Enter the email on your account and we will send you a reset link.', style: Theme.of(sheet).textTheme.bodyMedium),
          const SizedBox(height: 18),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(sheet, controller.text.trim()), child: const Text('Send reset link')),
        ]),
      ),
    );
    controller.dispose();
    if (sent == null || sent.isEmpty || !mounted) return;
    await attempt(context, () => context.read<AppState>().sendPasswordReset(sent), success: 'If an account exists for $sent, a reset link is on its way.');
  }

  void _fillDemo(String email) {
    setState(() {
      _register = false;
      _email.text = email;
      _password.text = DemoSeed.password;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context, 940);
    final form = _buildForm(context);
    if (!wide) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(children: [
              _MobileHeader(onHome: () => context.go('/')),
              Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), child: form),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Row(children: [
        Expanded(flex: 11, child: _SidePhoto(partner: _portal == Portal.partner, onHome: () => context.go('/'))),
        Expanded(
          flex: 10,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: form),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildForm(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final backend = context.read<AppState>().backend;
    final partner = _portal == Portal.partner;
    final title = partner ? 'Partner portal' : (_register ? 'Create your rider account' : 'Welcome back');
    final subtitle = partner
        ? 'For transport operators, fleet owners, FCTA staff and platform admins.'
        : (_register ? 'Book seats, pay by tap card or QR, and keep every trip in one place.' : 'Sign in to book, pay and ride across Abuja.');

    return AutofillGroup(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<Portal>(
              segments: const [
                ButtonSegment(value: Portal.passenger, icon: Icon(Icons.person_outline_rounded), label: Text('Passenger')),
                ButtonSegment(value: Portal.partner, icon: Icon(Icons.business_center_outlined), label: Text('Partner portal')),
              ],
              selected: {_portal},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _setPortal(s.first),
            ),
            const SizedBox(height: 28),
            Text(title, style: text.headlineLarge),
            const SizedBox(height: 6),
            Text(subtitle, style: text.bodyMedium),
            const SizedBox(height: 24),
            if (_register) ...[
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) => (v == null || v.trim().split(RegExp(r'\s+')).length < 2) ? 'Enter your first and last name.' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Phone number', hintText: '+234 803 000 0000', prefixIcon: Icon(Icons.phone_outlined)),
                validator: (v) => (v == null || v.replaceAll(RegExp(r'[^0-9]'), '').length < 10) ? 'Enter a valid Nigerian phone number.' : null,
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _email,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              decoration: InputDecoration(labelText: partner ? 'Work email' : 'Email', prefixIcon: const Icon(Icons.mail_outline_rounded)),
              validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'Enter a valid email address.' : null,
            ),
            if (_register) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _organisation,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Workplace (optional)',
                  helperText: 'Shown on Tag Along so colleagues can recognise you.',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _register ? 'At least 8 characters, with a number.' : null,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter your password.';
                if (_register && (v.length < 8 || !RegExp(r'\d').hasMatch(v))) return 'Use at least 8 characters, including a number.';
                return null;
              },
            ),
            if (!_register)
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgotPassword, child: const Text('Forgot password?')))
            else ...[
              const SizedBox(height: 10),
              _TermsCheck(value: _agreed, onChanged: (v) => setState(() => _agreed = v)),
            ],
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _error == null ? const SizedBox(width: double.infinity) : _ErrorBanner(error: _error!, onSwitch: () => _setPortal(partner ? Portal.passenger : Portal.partner)),
            ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(_register ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 10),
            if (!partner)
              TextButton(
                onPressed: () => setState(() {
                  _register = !_register;
                  _error = null;
                }),
                child: Text(_register ? 'Already have an account? Sign in' : 'New to Tap A Ride? Create an account'),
              )
            else
              Text('Partner accounts are created by the platform team after your organisation is verified.', style: text.bodySmall, textAlign: TextAlign.center),
            if (backend.isDemo) ...[
              const SizedBox(height: 24),
              _DemoAccounts(partner: partner, onPick: _fillDemo),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onSwitch});
  final BackendException error;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final wrongPortal = error.kind == BackendErrorKind.permission && error.message.contains('Use ');
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(error.message, style: const TextStyle(color: Color(0xFF7A231A), fontWeight: FontWeight.w600, height: 1.35)),
            if (wrongPortal)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: onSwitch,
                  child: const Text('Switch and try again', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _TermsCheck extends StatelessWidget {
  const _TermsCheck({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  void _show(BuildContext context, String title, String body) => showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), activeColor: AppColors.forest),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(children: [
            Text('I agree to the ', style: text.bodySmall),
            GestureDetector(
              onTap: () => _show(context, 'Terms of use', 'Tap A Ride is a prototype for the ATDEW 2026 National Innovation Challenge. Bookings, payments and balances in demo mode are simulated and carry no real charge.'),
              child: Text('Terms', style: text.bodySmall?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
            ),
            Text(' and ', style: text.bodySmall),
            GestureDetector(
              onTap: () => _show(context, 'Privacy', 'We use your name, phone and trips only to run your bookings and keep rides safe. Partners only see the data their role needs; trip data shared with the FCTA is aggregated.'),
              child: Text('Privacy Policy', style: text.bodySmall?.copyWith(color: AppColors.forest, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts({required this.partner, required this.onPick});
  final bool partner;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accounts = [for (final a in DemoSeed.demoAccounts) if (a.$3.isPartner == partner) a];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.amberSoft.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.science_outlined, size: 18, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text('Demo accounts · password ${DemoSeed.password}', style: text.labelMedium?.copyWith(color: const Color(0xFF6E4A06)))),
        ]),
        const SizedBox(height: 8),
        for (final a in accounts)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => onPick(a.$2),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(children: [
                Icon(a.$3.icon, size: 18, color: AppColors.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.$1, style: text.labelLarge),
                    Text(a.$2, style: text.bodySmall),
                  ]),
                ),
                Text('Use', style: text.labelMedium?.copyWith(color: AppColors.forest)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _SidePhoto extends StatelessWidget {
  const _SidePhoto({required this.partner, required this.onHome});
  final bool partner;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Stack(fit: StackFit.expand, children: [
      PhotoView(
        partner ? AppPhoto.expressway : AppPhoto.cityGateAerial,
        alignment: partner ? Alignment.center : const Alignment(0.3, 0),
        semanticLabel: partner ? 'Abuja expressway with Aso Rock in the distance' : 'Abuja City Gate with green lawns and flags',
        overlay: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xA606331F), Color(0x1106331F), Color(0x2206331F), Color(0xEE06331F)], stops: [0, 0.22, 0.5, 1]),
      ),
      Padding(
        padding: const EdgeInsets.all(40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(onTap: onHome, borderRadius: BorderRadius.circular(8), child: const Padding(padding: EdgeInsets.all(4), child: BrandLockup(height: 38, onDark: true))),
          const Spacer(),
          Text(partner ? 'Every trip.\nEvery naira.\nEvery verified vehicle.' : 'Ride. Connect. Go.', style: text.displayMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              partner ? 'Run routes, fleets and oversight for the FCT from one place.' : 'Fixed fares, published departures and cashless boarding across Abuja.',
              style: text.bodyLarge?.copyWith(color: AppColors.onForestMuted),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.onHome});
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: 190 + top,
      child: Stack(fit: StackFit.expand, children: [
        const PhotoView(
          AppPhoto.cityGateAerial,
          alignment: Alignment(0.3, 0),
          overlay: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x8806331F), Color(0xCC06331F)]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 8, 16, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconButton(onPressed: onHome, tooltip: 'Back to home', icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
            const Spacer(),
            const BrandLockup(height: 34, onDark: true, showDescriptor: true),
          ]),
        ),
      ]),
    );
  }
}
