import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/partner_models.dart';
import '../../core/places.dart';
import '../../shared/brand.dart';
import '../../shared/mascot/mascot.dart';
import '../../shared/password_field.dart';
import '../../shared/ui.dart';

/// Partner registration: private drivers (licence + vehicle) and organisations
/// (CAC registration, fleet size, compliance documents), with an AI document pre-check.
class PartnerApplyPage extends StatefulWidget {
  const PartnerApplyPage({super.key, this.initialType});

  /// Preselects a partner type (`?type=privateDriver`, `fleetOwner`, …).
  final String? initialType;

  @override
  State<PartnerApplyPage> createState() => _PartnerApplyPageState();
}

class _PartnerApplyPageState extends State<PartnerApplyPage> {
  final _forms = List.generate(5, (_) => GlobalKey<FormState>());
  int _step = 0;
  PartnerType? _type;

  // account (only when signed out)
  final _password = TextEditingController();

  // person / business
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _nin = TextEditingController();
  final _kinName = TextEditingController();
  final _kinPhone = TextEditingController();
  final _company = TextEditingController();
  final _rc = TextEditingController();
  final _tin = TextEditingController();
  final _fleetSize = TextEditingController();
  final _contactRole = TextEditingController();
  String? _area;
  DateTime? _dob;

  // licence
  final _licence = TextEditingController();
  String _licenceClass = 'B';
  DateTime? _licenceExpiry;

  // vehicle
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _colour = TextEditingController();
  final _seats = TextEditingController(text: '4');
  final _plate = TextEditingController();
  final _chassis = TextEditingController();
  final _engine = TextEditingController();

  final Map<DocSlot, DocumentFile> _docs = {};
  AiDocumentCheck? _ai;
  bool _checking = false;
  bool _declared = false;
  bool _busy = false;
  String? _error;

  bool get _org => _type?.isOrganisation ?? false;
  List<String> get _stepNames => _org ? const ['Partner type', 'Business', 'Documents', 'Review'] : const ['Partner type', 'About you', "Driver's licence", 'Vehicle', 'Review'];
  bool get _lastStep => _step == _stepNames.length - 1;

  @override
  void initState() {
    super.initState();
    _type = PartnerType.values.where((t) => t.name == widget.initialType).firstOrNull;
    final user = context.read<AppState>().user;
    if (user != null) {
      _fullName.text = user.fullName;
      _email.text = user.email;
      _phone.text = user.phone ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_password, _fullName, _email, _phone, _address, _nin, _kinName, _kinPhone, _company, _rc, _tin, _fleetSize, _contactRole, _licence, _make, _model, _year, _colour, _seats, _plate, _chassis, _engine]) {
      c.dispose();
    }
    super.dispose();
  }

  PartnerApplication _draft() {
    final user = context.read<AppState>().user;
    return PartnerApplication(
      id: 'draft',
      userId: user?.id ?? '',
      type: _type ?? PartnerType.privateDriver,
      status: ApplicationStatus.submitted,
      fullName: _fullName.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      dateOfBirth: _dob ?? DateTime(1990),
      address: _address.text.trim(),
      area: _area ?? 'Central Area',
      companyName: _org ? _company.text.trim() : null,
      rcNumber: _org ? _rc.text.trim() : null,
      tin: _org ? _tin.text.trim() : null,
      fleetSize: _org ? int.tryParse(_fleetSize.text.trim()) : 1,
      contactRole: _org ? _contactRole.text.trim() : null,
      nin: _nin.text.trim().isEmpty ? null : _nin.text.trim(),
      nextOfKinName: _kinName.text.trim().isEmpty ? null : _kinName.text.trim(),
      nextOfKinPhone: _kinPhone.text.trim().isEmpty ? null : _kinPhone.text.trim(),
      licenceNumber: _licence.text.trim().toUpperCase(),
      licenceClass: _licenceClass,
      licenceExpiry: _licenceExpiry ?? DateTime(2000),
      vehicleMake: _make.text.trim(),
      vehicleModel: _model.text.trim(),
      vehicleYear: int.tryParse(_year.text.trim()) ?? 0,
      vehicleColour: _colour.text.trim(),
      plateNumber: _plate.text.trim().toUpperCase(),
      chassisNumber: PartnerRules.normalise(_chassis.text),
      engineNumber: _engine.text.trim().isEmpty ? null : _engine.text.trim(),
      seats: int.tryParse(_seats.text.trim()) ?? 4,
      documents: _docs.values.toList(),
      createdAt: DateTime.now(),
      aiCheck: _ai,
    );
  }

  // ---------------------------------------------------------------- navigation

  Future<void> _next() async {
    setState(() => _error = null);
    if (_step == 0) {
      if (_type == null) return setState(() => _error = 'Choose the kind of partner you are.');
      final state = context.read<AppState>();
      if (state.user == null) {
        if (!_forms[0].currentState!.validate()) return;
        setState(() => _busy = true);
        try {
          await state.register(fullName: _fullName.text, email: _email.text, phone: _phone.text, password: _password.text);
        } on BackendException catch (e) {
          setState(() => _error = e.message);
          return;
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
    } else if (!(_forms[_step].currentState?.validate() ?? true)) {
      return;
    }
    // Required documents for the step just finished.
    final stepDocs = _docsForStep(_step);
    final missing = stepDocs.where((s) => _type!.requiredDocs.contains(s) && !_docs.containsKey(s)).toList();
    if (missing.isNotEmpty) return setState(() => _error = 'Add your ${missing.first.label.toLowerCase()}.');
    if (!_lastStep) setState(() => _step++);
  }

  List<DocSlot> _docsForStep(int step) {
    if (_type == null) return const [];
    if (_org) return step == 2 ? [..._type!.requiredDocs, ..._type!.optionalDocs] : const [];
    return switch (step) {
      2 => const [DocSlot.licenceFront, DocSlot.licenceBack],
      3 => const [DocSlot.proofOfOwnership, DocSlot.vehiclePhoto, DocSlot.roadworthiness, DocSlot.insurance],
      _ => const [],
    };
  }

  Future<void> _runAiCheck() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final ai = await context.read<AppState>().checkDocuments(_draft(), _docs.values.toList());
      if (mounted) setState(() => _ai = ai);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = 'AI check unavailable: ${e.message} You can still submit; a reviewer will check your documents.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _submit() async {
    if (!_declared) return setState(() => _error = 'Confirm that the information and documents are genuine.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().submitApplication(_draft(), _docs.values.toList());
      if (!mounted) return;
      context.go('/partner/status');
      showMessage(context, 'Application submitted. We will review it shortly.');
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- documents

  Future<void> _pick(DocSlot slot, ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1800, maxHeight: 1800, imageQuality: 80);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 3500000) {
        if (mounted) showMessage(context, 'That photo is too large. Try again with a smaller one.', error: true);
        return;
      }
      final mime = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      setState(() {
        _docs[slot] = DocumentFile(slot: slot, fileName: file.name, mimeType: mime, bytes: bytes);
        _ai = null; // documents changed; the check must run again
      });
    } catch (_) {
      if (mounted) showMessage(context, 'Could not open the camera or files. Check browser permissions.', error: true);
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final wide = isWide(context, 980);
    final body = Form(key: _forms[_step], child: _stepBody(context));
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/'),
        title: const BrandLockup(height: 26),
        actions: [if (context.watch<AppState>().myApplications.isNotEmpty) TextButton(onPressed: () => context.go('/partner/status'), child: const Text('My application')), const SizedBox(width: 8)],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            MaxWidth(
              width: 760,
              padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Become a Tap A Ride partner', style: wide ? text.displaySmall : text.headlineLarge),
                      const SizedBox(height: 6),
                      Text('Drive with us, or bring your company or agency fleet onto the platform. Every partner is verified before taking bookings.', style: text.bodyMedium),
                    ]),
                  ),
                  if (wide) const Mascot(mood: MascotMood.wave, size: 120),
                ]),
                const SizedBox(height: 20),
                _Progress(names: _stepNames, step: _step),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim), child: child)),
                  child: KeyedSubtree(key: ValueKey('$_step-${_type?.name}'), child: body),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFF7A231A), fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                Row(children: [
                  if (_step > 0) OutlinedButton(onPressed: _busy ? null : () => setState(() => _step--), child: const Text('Back')),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : (_lastStep ? _submit : _next),
                    style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(_lastStep ? 'Submit application' : (_step == 0 && context.read<AppState>().user == null ? 'Create account & continue' : 'Continue')),
                  ),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    if (_step == 0) return _typeStep(context);
    if (_org) {
      return switch (_step) { 1 => _businessStep(context), 2 => _docsStep(context, 'Compliance documents', 'Upload clear photos. Government agencies may upload their mandate letter as the operating permit.'), _ => _reviewStep(context) };
    }
    return switch (_step) { 1 => _personStep(context), 2 => _licenceStep(context), 3 => _vehicleStep(context), _ => _reviewStep(context) };
  }

  Widget _typeStep(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final signedOut = context.watch<AppState>().user == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Who is joining?', style: text.titleLarge),
      const SizedBox(height: 10),
      for (final t in PartnerType.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            shadow: false,
            color: _type == t ? AppColors.mint : AppColors.surface,
            onTap: () => setState(() {
              _type = t;
              _error = null;
            }),
            semanticLabel: t.label,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              IconBadge(t.icon, size: 44, color: _type == t ? AppColors.forest : AppColors.mint, iconColor: _type == t ? Colors.white : AppColors.forest),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.label, style: text.titleMedium),
                  Text(t.blurb, style: text.bodySmall),
                ]),
              ),
              Icon(_type == t ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _type == t ? AppColors.forest : AppColors.muted),
            ]),
          ),
        ),
      if (_type != null) ...[
        const SizedBox(height: 8),
        Text(
          _org ? 'You will need: CAC registration (RC) number, TIN, number of vehicles, CAC certificate, FCT operating permit and insurance.' : "You will need: your driver's licence, the vehicle's plate and original chassis number (VIN), proof of ownership and a photo of the vehicle.",
          style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
        ),
      ],
      if (signedOut) ...[
        const SizedBox(height: 20),
        Text('Create your account', style: text.titleLarge),
        const SizedBox(height: 4),
        Text('You will use it to track your application and, once approved, to sign in to your dashboard.', style: text.bodySmall),
        const SizedBox(height: 12),
        _field(_fullName, _org ? 'Contact person full name' : 'Full name (as on your licence)', validator: _required, caps: TextCapitalization.words),
        _field(_email, 'Email', keyboard: TextInputType.emailAddress, validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email.'),
        _field(_phone, 'Phone number', keyboard: TextInputType.phone, validator: _phoneCheck),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: PasswordField(controller: _password, isNew: true, prefixIcon: false, textInputAction: TextInputAction.next)),
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => context.go('/login?from=/partner/apply'), child: const Text('Already have an account? Sign in'))),
      ],
    ]);
  }

  Widget _personStep(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(context, 'About you', 'Use your details exactly as they appear on your licence.'),
        _field(_fullName, 'Full name', validator: _required, caps: TextCapitalization.words),
        _field(_email, 'Email', keyboard: TextInputType.emailAddress, validator: _required),
        _field(_phone, 'Phone number', keyboard: TextInputType.phone, validator: _phoneCheck),
        _dateField(context, 'Date of birth', _dob, (d) => setState(() => _dob = d), first: DateTime(1940), last: DateTime.now().subtract(const Duration(days: 365 * 18)), required: true),
        _field(_address, 'Home address', validator: _required),
        _areaField(),
        _field(_nin, 'NIN (optional)', keyboard: TextInputType.number, validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^\d{11}$').hasMatch(v!.trim()) ? null : 'A NIN has 11 digits.'),
        Row(children: [
          Expanded(child: _field(_kinName, 'Next of kin name', validator: _required, caps: TextCapitalization.words)),
          const SizedBox(width: 10),
          Expanded(child: _field(_kinPhone, 'Next of kin phone', keyboard: TextInputType.phone, validator: _phoneCheck)),
        ]),
      ]);

  Widget _businessStep(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(context, 'Business details', 'As registered with the Corporate Affairs Commission (CAC).'),
        _field(_company, _type == PartnerType.governmentAgency ? 'Agency or scheme name' : 'Registered business name', validator: _required, caps: TextCapitalization.words),
        Row(children: [
          Expanded(child: _field(_rc, 'CAC RC number', validator: _type == PartnerType.governmentAgency ? (v) => (v ?? '').trim().isEmpty ? null : OrgRules.rcNumber(v) : OrgRules.rcNumber, caps: TextCapitalization.characters)),
          const SizedBox(width: 10),
          Expanded(child: _field(_tin, 'Tax ID (TIN)', keyboard: TextInputType.number, validator: OrgRules.tin)),
        ]),
        Row(children: [
          Expanded(child: _field(_fleetSize, 'Number of vehicles', keyboard: TextInputType.number, digits: true, validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter how many vehicles you run.')),
          const SizedBox(width: 10),
          Expanded(child: _areaField(label: 'Main operating area')),
        ]),
        _field(_address, 'Business address', validator: _required),
        const SizedBox(height: 6),
        Text('Contact person', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _field(_fullName, 'Full name', validator: _required, caps: TextCapitalization.words),
        Row(children: [
          Expanded(child: _field(_contactRole, 'Role (e.g. Fleet manager)', validator: _required)),
          const SizedBox(width: 10),
          Expanded(child: _field(_phone, 'Phone', keyboard: TextInputType.phone, validator: _phoneCheck)),
        ]),
        _field(_email, 'Work email', keyboard: TextInputType.emailAddress, validator: _required),
        _dateField(context, 'Contact date of birth', _dob, (d) => setState(() => _dob = d), first: DateTime(1940), last: DateTime.now().subtract(const Duration(days: 365 * 18)), required: false),
      ]);

  Widget _licenceStep(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(context, "Driver's licence", 'A valid Nigerian driver\'s licence issued by the FRSC.'),
        _field(_licence, 'Licence number', validator: PartnerRules.licence, caps: TextCapitalization.characters),
        Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                initialValue: _licenceClass,
                decoration: const InputDecoration(labelText: 'Class'),
                items: const [
                  DropdownMenuItem(value: 'B', child: Text('B · Car / light vehicle')),
                  DropdownMenuItem(value: 'C', child: Text('C · Car + small bus')),
                  DropdownMenuItem(value: 'D', child: Text('D · Bus / commercial')),
                  DropdownMenuItem(value: 'E', child: Text('E · Heavy vehicle')),
                ],
                onChanged: (v) => setState(() => _licenceClass = v ?? 'B'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _dateField(context, 'Expiry date', _licenceExpiry, (d) => setState(() => _licenceExpiry = d), first: DateTime.now(), last: DateTime.now().add(const Duration(days: 365 * 10)), required: true)),
        ]),
        const SizedBox(height: 4),
        for (final slot in _docsForStep(2)) _DocTile(slot: slot, doc: _docs[slot], required: _type!.requiredDocs.contains(slot), onPick: (src) => _pick(slot, src), onRemove: () => setState(() => _docs.remove(slot))),
      ]);

  Widget _vehicleStep(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(context, 'Your vehicle', 'Copy the plate and chassis number (VIN) exactly as printed on the vehicle papers.'),
        Row(children: [
          Expanded(child: _field(_make, 'Make (e.g. Toyota)', validator: _required, caps: TextCapitalization.words)),
          const SizedBox(width: 10),
          Expanded(child: _field(_model, 'Model (e.g. Corolla)', validator: _required, caps: TextCapitalization.words)),
        ]),
        Row(children: [
          Expanded(child: _field(_year, 'Year', keyboard: TextInputType.number, digits: true, validator: (v) {
            final y = int.tryParse(v ?? '') ?? 0;
            return y >= 1990 && y <= DateTime.now().year + 1 ? null : 'Enter the model year.';
          })),
          const SizedBox(width: 10),
          Expanded(child: _field(_colour, 'Colour', validator: _required, caps: TextCapitalization.words)),
          const SizedBox(width: 10),
          Expanded(child: _field(_seats, 'Seats', keyboard: TextInputType.number, digits: true, validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Seats?')),
        ]),
        _field(_plate, 'Plate number (e.g. ABJ 123 AB)', validator: PartnerRules.plate, caps: TextCapitalization.characters),
        _field(_chassis, 'Chassis number / VIN (17 characters)', validator: PartnerRules.chassis, caps: TextCapitalization.characters, maxLength: 20),
        _field(_engine, 'Engine number (optional)', caps: TextCapitalization.characters),
        for (final slot in _docsForStep(3)) _DocTile(slot: slot, doc: _docs[slot], required: _type!.requiredDocs.contains(slot), onPick: (src) => _pick(slot, src), onRemove: () => setState(() => _docs.remove(slot))),
      ]);

  Widget _docsStep(BuildContext context, String title, String subtitle) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(context, title, subtitle),
        for (final slot in _docsForStep(_step)) _DocTile(slot: slot, doc: _docs[slot], required: _type!.requiredDocs.contains(slot), onPick: (src) => _pick(slot, src), onRemove: () => setState(() => _docs.remove(slot))),
      ]);

  Widget _reviewStep(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final d = _draft();
    final rows = _org
        ? [
            ('Business', d.displayName),
            ('CAC RC number', d.rcNumber ?? '—'),
            ('TIN', (d.tin?.isEmpty ?? true) ? '—' : d.tin!),
            ('Vehicles', '${d.fleetSize ?? 0}'),
            ('Area', d.area),
            ('Contact', '${d.fullName} · ${d.contactRole ?? ''}'),
            ('Email / phone', '${d.email} · ${d.phone}'),
          ]
        : [
            ('Name', d.fullName),
            ('Email / phone', '${d.email} · ${d.phone}'),
            ('Date of birth', _dob == null ? '—' : Fmt.date(_dob!)),
            ('Area', d.area),
            ('Licence', '${d.licenceNumber} · class ${d.licenceClass} · expires ${_licenceExpiry == null ? '—' : Fmt.date(_licenceExpiry!)}'),
            ('Vehicle', d.vehicleLabel),
            ('Plate', d.plateNumber),
            ('Chassis (VIN)', d.chassisNumber),
          ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(context, 'Check and submit', 'Review your details. The AI check reads your documents and compares them with what you typed.'),
      Panel(
        child: Column(children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(r.$1, style: text.bodySmall)),
                Expanded(child: Text(r.$2, style: text.titleSmall)),
              ]),
            ),
          const Divider(),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final doc in _docs.values) Chip(avatar: Icon(doc.slot.icon, size: 16, color: AppColors.forest), label: Text(doc.slot.label))]),
        ]),
      ),
      const SizedBox(height: 16),
      _AiPanel(check: _ai, checking: _checking, onRun: _docs.isEmpty ? null : _runAiCheck),
      const SizedBox(height: 16),
      CheckboxListTile(
        value: _declared,
        onChanged: (v) => setState(() => _declared = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: AppColors.forest,
        title: Text('I confirm the information and documents are genuine and belong to me${_org ? ' or my organisation' : ''}. False information may be reported to the FCTA.', style: text.bodySmall?.copyWith(color: AppColors.inkSoft)),
      ),
    ]);
  }

  // ---------------------------------------------------------------- field helpers

  static String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
  static String? _phoneCheck(String? v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length >= 10 ? null : 'Enter a valid phone number.';

  Widget _heading(BuildContext context, String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  Widget _field(TextEditingController c, String label, {String? Function(String?)? validator, TextInputType? keyboard, bool obscure = false, bool digits = false, TextCapitalization caps = TextCapitalization.none, int? maxLength}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          obscureText: obscure,
          keyboardType: keyboard,
          textCapitalization: caps,
          maxLength: maxLength,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(labelText: label, counterText: ''),
          validator: validator,
        ),
      );

  Widget _areaField({String label = 'Area of Abuja'}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: _area,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final p in abujaPlaces.keys.where((k) => !k.contains('Airport') && k != 'Central Station')) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: (v) => setState(() => _area = v),
          validator: (v) => v == null ? 'Choose an area' : null,
        ),
      );

  Widget _dateField(BuildContext context, String label, DateTime? value, ValueChanged<DateTime> onPick, {required DateTime first, required DateTime last, required bool required}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FormField<DateTime>(
          validator: (_) => required && value == null ? 'Choose a date' : null,
          builder: (field) => InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () async {
              final picked = await showDatePicker(context: context, firstDate: first, lastDate: last, initialDate: value ?? (last.isBefore(DateTime.now()) ? last : first));
              if (picked != null) {
                onPick(picked);
                field.didChange(picked);
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: label, errorText: field.errorText, suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18)),
              child: Text(value == null ? 'Select' : Fmt.date(value), style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: value == null ? AppColors.muted : AppColors.ink)),
            ),
          ),
        ),
      );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.names, required this.step});
  final List<String> names;
  final int step;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Step ${step + 1} of ${names.length}: ${names[step]}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Step ${step + 1} of ${names.length} · ${names[step]}', style: text.labelMedium?.copyWith(color: AppColors.forest)),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < names.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                height: 6,
                decoration: BoxDecoration(color: i <= step ? AppColors.forest : AppColors.mintStrong, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.slot, required this.doc, required this.required, required this.onPick, required this.onRemove});
  final DocSlot slot;
  final DocumentFile? doc;
  final bool required;
  final ValueChanged<ImageSource> onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final d = doc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        shadow: false,
        padding: const EdgeInsets.all(12),
        color: d != null ? AppColors.mint : AppColors.surface,
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 56,
              height: 56,
              child: d?.bytes != null && d!.isImage ? Image.memory(d.bytes!, fit: BoxFit.cover) : Container(color: AppColors.surfaceSunk, child: Icon(slot.icon, color: AppColors.forest)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(slot.label, style: text.titleSmall),
              Text(d != null ? 'Added · ${d.fileName}' : (required ? 'Required' : 'Optional'), style: text.bodySmall?.copyWith(color: d != null ? AppColors.leafText : (required ? AppColors.amber : AppColors.muted)), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (d != null) IconButton(tooltip: 'Remove', onPressed: onRemove, icon: const Icon(Icons.delete_outline_rounded)),
          IconButton(tooltip: 'Take photo', onPressed: () => onPick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined)),
          IconButton(tooltip: 'Choose file', onPressed: () => onPick(ImageSource.gallery), icon: const Icon(Icons.upload_file_rounded)),
        ]),
      ),
    );
  }
}

/// AI document check results: per-field match / mismatch, with the reviewer summary.
class _AiPanel extends StatelessWidget {
  const _AiPanel({required this.check, required this.checking, required this.onRun});
  final AiDocumentCheck? check;
  final bool checking;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = check;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Mascot(mood: checking ? MascotMood.think : (c?.overall == 'pass' ? MascotMood.celebrate : MascotMood.idle), size: 56),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI document check', style: text.titleMedium),
              Text(c == null ? 'Optional, but it speeds up approval.' : c.summary, style: text.bodySmall),
            ]),
          ),
          if (c != null) AiVerdictPill(overall: c.overall),
        ]),
        if (c != null) ...[const SizedBox(height: 10), AiChecksList(checks: c.checks)],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: checking ? null : onRun,
            icon: checking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(checking ? 'Reading your documents…' : (c == null ? 'Run AI check' : 'Run again')),
          ),
        ),
      ]),
    );
  }
}

class AiVerdictPill extends StatelessWidget {
  const AiVerdictPill({super.key, required this.overall});
  final String overall;

  @override
  Widget build(BuildContext context) => StatusPill(
        switch (overall) { 'pass' => 'Looks good', 'fail' => 'Problems found', _ => 'Needs a look' },
        tone: switch (overall) { 'pass' => Tone.success, 'fail' => Tone.danger, _ => Tone.warning },
        icon: Icons.auto_awesome_rounded,
      );
}

class AiChecksList extends StatelessWidget {
  const AiChecksList({super.key, required this.checks});
  final List<AiFieldCheck> checks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(children: [
      for (final c in checks)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              switch (c.result) { 'match' => Icons.check_circle_rounded, 'partial' => Icons.remove_circle_rounded, _ => Icons.error_rounded },
              size: 18,
              color: switch (c.result) { 'match' => AppColors.leafText, 'partial' => AppColors.amber, 'not_found' => AppColors.muted, _ => AppColors.red },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c.label} · ${c.result.replaceAll('_', ' ')}', style: text.titleSmall),
                if (c.note.isNotEmpty) Text(c.note, style: text.bodySmall),
              ]),
            ),
          ]),
        ),
    ]);
  }
}
