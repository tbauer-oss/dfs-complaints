import 'package:flutter/material.dart';

/// A compact password text field with a subtle visibility toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode,
    this.enabled,
    this.useTextFormField = false,
    this.style,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final bool? enabled;
  final bool useTextFormField;
  final TextStyle? style;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  Widget _buildToggle(BuildContext context) {
    final color = Theme.of(context).hintColor.withOpacity(0.7);
    return IconButton(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      splashRadius: 18,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: widget.enabled == false
          ? null
          : () => setState(() => _visible = !_visible),
      icon: Icon(
        _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: color,
      ),
    );
  }

  InputDecoration _decorate(BuildContext context) {
    return widget.decoration.copyWith(
      suffixIcon: _buildToggle(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoration = _decorate(context);
    final obscure = !_visible;

    if (widget.useTextFormField || widget.validator != null) {
      return TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: obscure,
        decoration: decoration,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        validator: widget.validator,
        autovalidateMode: widget.autovalidateMode,
        enabled: widget.enabled,
        style: widget.style,
      );
    }

    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: obscure,
      decoration: decoration,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      enabled: widget.enabled,
      style: widget.style,
    );
  }
}
