import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/places.dart';
import '../../shared/ui.dart';

// ------------------------------------------------------------------ verification status bits

/// "Verified" / "Under review" / … as a pill.
class VerificationPill extends StatelessWidget {
  const VerificationPill(this.status, {super.key});
  final VerificationStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        VerificationStatus.verified => const StatusPill('Verified', tone: Tone.success, icon: Icons.verified_rounded),
        VerificationStatus.pending => const StatusPill('Under review', tone: Tone.info, icon: Icons.hourglass_top_rounded),
        VerificationStatus.rejected => const StatusPill('Declined', tone: Tone.danger, icon: Icons.error_outline_rounded),
        VerificationStatus.unverified => const StatusPill('Not verified', tone: Tone.warning, icon: Icons.shield_outlined),
      };
}

/// The profile's call to action for verification (hidden once verified).
class VerificationCard extends StatelessWidget {
  const VerificationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().user;
    if (user == null || user.role != UserRole.passenger || user.isVerified) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final status = user.verificationStatus;
    final (title, body, action) = switch (status) {
      VerificationStatus.pending => (
          'Verification under review',
          'Thanks! We are checking your details, usually within a day. You can keep booking and topping up meanwhile.',
          null,
        ),
      VerificationStatus.rejected => (
          'Verification declined',
          user.verificationNote?.isNotEmpty == true ? user.verificationNote! : 'We could not confirm your details. Check them and send them again.',
          'Check and resend',
        ),
      _ => (
          'Get verified',
          'Add your NIN and date of birth so hosts and other riders know who they are travelling with. It takes a minute.',
          'Get verified',
        ),
    };
    return Panel(
      color: status == VerificationStatus.rejected ? AppColors.redSoft : AppColors.mint,
      border: false,
      shadow: false,
      onTap: action == null ? null : () => context.push('/profile/verify'),
      child: Row(children: [
        Icon(status == VerificationStatus.pending ? Icons.hourglass_top_rounded : Icons.verified_user_outlined, color: status == VerificationStatus.rejected ? AppColors.red : AppColors.forest),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: 2),
            Text(body, style: text.bodySmall?.copyWith(color: AppColors.inkSoft)),
          ]),
        ),
        if (action != null) ...[const SizedBox(width: 8), const Icon(Icons.chevron_right_rounded)],
      ]),
    );
  }
}

// ------------------------------------------------------------------ edit profile

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _form = GlobalKey<FormState>();
  late final AppUser _user;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  String? _area;

  @override
  void initState() {
    super.initState();
    _user = context.read<AppState>().user!;
    _name = TextEditingController(text: _user.fullName);
    _phone = TextEditingController(text: _user.phone ?? '');
    _emergencyName = TextEditingController(text: _user.emergencyName ?? '');
    _emergencyPhone = TextEditingController(text: _user.emergencyPhone ?? '');
    _area = (_user.homeArea?.isNotEmpty ?? false) ? _user.homeArea : null;
  }
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _emergencyName, _emergencyPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _phoneCheck(String? v, {bool required = false}) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return required ? 'Enter a phone number.' : null;
    return digits.length < 10 || digits.length > 13 ? 'Enter a valid Nigerian number, e.g. 0803 123 4567.' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final renamed = _user.isVerified && _user.role == UserRole.passenger && _name.text.trim().toLowerCase() != _user.fullName.toLowerCase();
    if (renamed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Change your verified name?'),
          content: const Text('Your name was checked against your NIN. Changing it sends your account back for review, and the Verified badge is removed until we check again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep my name')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Change and review')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().updateMyProfile(
            fullName: _name.text,
            phone: _phone.text,
            homeArea: _area,
            emergencyName: _emergencyName.text,
            emergencyPhone: _emergencyPhone.text,
          );
      if (!mounted) return;
      showMessage(context, 'Your details are saved.');
      context.pop();
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const locked = _LockedField.new;
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Edit profile')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
            children: [
              MaxWidth(
                width: 560,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Your details', style: text.titleLarge),
                  const SizedBox(height: 4),
                  Text('Used on your tickets and shown to Tag Along hosts you ride with.', style: text.bodySmall),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
                    validator: (v) => (v ?? '').trim().split(RegExp(r'\s+')).length < 2 ? 'Enter your first and last name.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                    decoration: const InputDecoration(labelText: 'Phone number', hintText: '0803 123 4567', prefixIcon: Icon(Icons.phone_outlined)),
                    validator: (v) => _phoneCheck(v, required: true),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _area != null && abujaPlaces.containsKey(_area) ? _area : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Home area (optional)', prefixIcon: Icon(Icons.home_outlined)),
                    items: [for (final p in abujaPlaces.keys.where((k) => !k.contains('Airport') && k != 'Central Station')) DropdownMenuItem(value: p, child: Text(p))],
                    onChanged: (v) => setState(() => _area = v),
                  ),
                  const SizedBox(height: 22),
                  Text('Emergency contact', style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text('Someone we can call if something happens on a trip. Optional.', style: text.bodySmall),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _emergencyName,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Contact name', prefixIcon: Icon(Icons.person_outline_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emergencyPhone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                    decoration: const InputDecoration(labelText: 'Contact phone', prefixIcon: Icon(Icons.contact_phone_outlined)),
                    validator: (v) => _phoneCheck(v),
                  ),
                  const SizedBox(height: 22),
                  Text('Can\'t be changed here', style: text.titleMedium),
                  const SizedBox(height: 8),
                  locked(label: 'Email', value: _user.email, note: 'Your sign-in email. Contact support to change it.'),
                  if (_user.nin != null) locked(label: 'NIN', value: '•••••••${_user.nin!.substring(_user.nin!.length - 4)}', note: 'Set when you verified your account.'),
                  if (_user.dateOfBirth != null) locked(label: 'Date of birth', value: Fmt.date(_user.dateOfBirth!), note: 'Set when you verified your account.'),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.red, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: Text(_busy ? 'Saving…' : 'Save changes'),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedField extends StatelessWidget {
  const _LockedField({required this.label, required this.value, this.note});
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.surfaceSunk, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.line)),
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: text.labelMedium?.copyWith(color: AppColors.muted)),
              Text(value, style: text.bodyLarge, overflow: TextOverflow.ellipsis),
              if (note != null) Text(note!, style: text.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ verification

class RiderVerificationPage extends StatefulWidget {
  const RiderVerificationPage({super.key});

  @override
  State<RiderVerificationPage> createState() => _RiderVerificationPageState();
}

class _RiderVerificationPageState extends State<RiderVerificationPage> {
  final _form = GlobalKey<FormState>();
  // Created up front (not lazily): a lazy field first touched in dispose() would read the app
  // state from a widget that is already leaving the tree.
  late final AppUser _user;
  late final TextEditingController _nin;
  late final TextEditingController _phone;
  DateTime? _dob;
  bool _agree = false;

  @override
  void initState() {
    super.initState();
    _user = context.read<AppState>().user!;
    _nin = TextEditingController(text: _user.nin ?? '');
    _phone = TextEditingController(text: _user.phone ?? '');
    _dob = _user.dateOfBirth;
  }
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nin.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final last = DateTime(now.year - 16, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1920),
      lastDate: last,
      helpText: 'Your date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (_dob == null) return setState(() => _error = 'Choose your date of birth.');
    if (!_agree) return setState(() => _error = 'Confirm that the details are yours and correct.');
    setState(() => _busy = true);
    try {
      await context.read<AppState>().submitVerification(nin: _nin.text.replaceAll(RegExp(r'\D'), ''), dateOfBirth: _dob!, phone: _phone.text);
      if (!mounted) return;
      showMessage(context, 'Sent. We will review your details, usually within a day.');
      context.pop();
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final user = context.watch<AppState>().user ?? _user;
    final status = user.verificationStatus;
    final canSubmit = status == VerificationStatus.unverified || status == VerificationStatus.rejected;
    final ninLocked = user.nin != null;
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Verification')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
            MaxWidth(
              width: 560,
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const IconBadge(Icons.verified_user_rounded, size: 48),
                    const SizedBox(width: 12),
                    Expanded(child: Text(status == VerificationStatus.verified ? 'Your account is verified' : 'Verify your account', style: text.headlineSmall)),
                    VerificationPill(status),
                  ]),
                  const SizedBox(height: 14),
                  Panel(
                    color: AppColors.surfaceSunk,
                    shadow: false,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Why we ask', style: text.titleSmall),
                      const SizedBox(height: 8),
                      for (final (icon, line) in [
                        (Icons.groups_rounded, 'Tag Along hosts and riders see that you are a real, checked person.'),
                        (Icons.receipt_long_rounded, 'It helps us confirm refunds and support requests are really yours.'),
                        (Icons.lock_rounded, 'Your NIN is only seen by the Tap A Ride team, never by drivers or other riders.'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(icon, size: 18, color: AppColors.forest),
                            const SizedBox(width: 10),
                            Expanded(child: Text(line, style: text.bodySmall?.copyWith(color: AppColors.inkSoft))),
                          ]),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  if (status == VerificationStatus.verified)
                    Text('Your account is verified. Thank you!', style: text.bodyLarge)
                  else if (status == VerificationStatus.pending)
                    Text(
                      'We received your details${user.verificationSubmittedAt == null ? '' : ' on ${Fmt.dayTime(user.verificationSubmittedAt!)}'}. A reviewer will check them, usually within a day. Top-ups and bookings keep working meanwhile.',
                      style: text.bodyLarge,
                    )
                  else ...[
                    if (status == VerificationStatus.rejected && (user.verificationNote ?? '').isNotEmpty) ...[
                      Panel(
                        color: AppColors.redSoft,
                        border: false,
                        shadow: false,
                        child: Text('Reviewer\'s note: ${user.verificationNote}', style: text.bodyMedium?.copyWith(color: AppColors.red)),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _nin,
                      enabled: !ninLocked,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                      decoration: InputDecoration(
                        labelText: 'NIN (National Identification Number)',
                        helperText: ninLocked ? 'Already on file. Contact support to change it.' : '11 digits, from your NIN slip or the NIMC app.',
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                      validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length == 11 ? null : 'Your NIN has 11 digits.',
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: user.dateOfBirth != null ? null : _pickDob,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date of birth',
                          prefixIcon: const Icon(Icons.cake_outlined),
                          enabled: user.dateOfBirth == null,
                          helperText: 'You must be 16 or older.',
                        ),
                        child: Text(_dob == null ? 'Choose a date' : Fmt.date(_dob!), style: text.bodyLarge?.copyWith(color: _dob == null ? AppColors.muted : AppColors.ink)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                      decoration: const InputDecoration(labelText: 'Phone number', hintText: '0803 123 4567', prefixIcon: Icon(Icons.phone_outlined)),
                      validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length >= 10 ? null : 'Enter your phone number.',
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _agree,
                      onChanged: (v) => setState(() => _agree = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('These details are mine and correct. I understand a false NIN closes my account.', style: text.bodySmall),
                    ),
                    if (_error != null) Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.red, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _busy || !canSubmit ? null : _submit,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: Text(_busy ? 'Sending…' : 'Send for review'),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
