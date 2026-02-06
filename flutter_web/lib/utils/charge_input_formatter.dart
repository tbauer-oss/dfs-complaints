import 'package:flutter/services.dart';

class ChargeInputFormatter extends TextInputFormatter {
  ChargeInputFormatter();

  static final RegExp pattern = RegExp(r'^\d{4}-\d{2}-\d{2}([A-Z])?$');
  static final _letterRegExp = RegExp(r'[A-Z]');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.toUpperCase();
    final digits = StringBuffer();
    String? suffix;

    for (final rune in raw.runes) {
      final char = String.fromCharCode(rune);
      if (_isDigit(char)) {
        if (digits.length < 8) digits.write(char);
      } else if (_letterRegExp.hasMatch(char) && suffix == null && digits.length == 8) {
        suffix = char;
      }
    }

    final formatted = _format(digits.toString(), suffix);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  String _format(String digits, String? suffix) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 3 && digits.length >= 4) buffer.write('-');
      if (i == 5 && digits.length >= 6) buffer.write('-');
    }
    if (suffix != null) buffer.write(suffix);
    return buffer.toString();
  }
}
