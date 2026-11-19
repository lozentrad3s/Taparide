import 'package:flutter/material.dart';

import '../app/theme.dart';

/// The password rules for new accounts (riders and partners). Supabase enforces the same set
/// server-side once "Password requirements" is set to lowercase, uppercase, digits and symbols.
abstract final class PasswordRules {
  static const minLength = 8;
  static final _upper = RegExp(r'[A-Z]');
  static final _lower = RegExp(r'[a-z]');
  static final _digit = RegExp(r'\d');
  static final _symbol = RegExp(r'[^A-Za-z0-9\s]');

  static List<(String, bool)> check(String v) => [
        ('At least $minLength characters', v.length >= minLength),
        ('A capital letter (A–Z)', _upper.hasMatch(v)),
        ('A small letter (a–z)', _lower.hasMatch(v)),
        ('A number (0–9)', _digit.hasMatch(v)),
        (r'A symbol, like ! @ # $ % & *', _symbol.hasMatch(v)),
      ];

  static bool ok(String v) => check(v).every((r) => r.$2);
}

/// Password input with a show/hide toggle. With [isNew] it shows a live checklist of the rules
/// and refuses a password that misses any of them.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.isNew = false,
    this.label = 'Password',
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
    this.prefixIcon = true,
  });

  final TextEditingController controller;
  final bool isNew;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final bool prefixIcon;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (widget.isNew && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    final field = TextFormField(
      controller: widget.controller,
      obscureText: !_show,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      autofillHints: [widget.isNew ? AutofillHints.newPassword : AutofillHints.password],
      onFieldSubmitted: widget.onSubmitted,
      autovalidateMode: widget.isNew ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: widget.prefixIcon ? const Icon(Icons.lock_outline_rounded) : null,
        suffixIcon: IconButton(
          tooltip: _show ? 'Hide password' : 'Show password',
          icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _show = !_show),
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Enter your password.';
        if (widget.isNew && !PasswordRules.ok(v)) return 'Your password needs every item in the list below.';
        return null;
      },
    );
    if (!widget.isNew) return field;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      field,
      const SizedBox(height: 8),
      Semantics(
        container: true,
        label: 'Password rules',
        child: Wrap(spacing: 14, runSpacing: 4, children: [
          for (final (label, met) in PasswordRules.check(value))
            Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(met),
                  size: 16,
                  color: met ? AppColors.leafText : AppColors.faint,
                ),
              ),
              const SizedBox(width: 5),
              Text(label, style: text.bodySmall?.copyWith(color: met ? AppColors.leafText : AppColors.muted)),
            ]),
        ]),
      ),
    ]);
  }
}
