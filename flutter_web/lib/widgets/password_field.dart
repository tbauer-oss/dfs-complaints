import 'package:flutter/material.dart';

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;

  const PasswordField({
    super.key,
    required this.controller,
    required this.decoration,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.validator,
    this.autovalidateMode,
    this.autofillHints,
    this.focusNode,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final decoration = widget.decoration.copyWith(
      suffixIcon: IconButton(
        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
        tooltip: _obscure ? 'Passwort anzeigen' : 'Passwort ausblenden',
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );

    if (widget.validator != null || widget.autovalidateMode != null) {
      return TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        decoration: decoration,
        obscureText: _obscure,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        textInputAction: widget.textInputAction,
        validator: widget.validator,
        autovalidateMode: widget.autovalidateMode,
        autofillHints: widget.autofillHints,
      );
    }

    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: decoration,
      obscureText: _obscure,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
    );
  }
}
