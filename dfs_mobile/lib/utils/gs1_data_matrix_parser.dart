import 'dart:math';

class Gs1DataMatrixData {
  final String gtin;
  final String? lot;
  final DateTime? manufacturingDate;

  const Gs1DataMatrixData({
    required this.gtin,
    this.lot,
    this.manufacturingDate,
  });
}

class Gs1DataMatrixParser {
  static const _fnc1 = '\u001d';

  static Gs1DataMatrixData? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final source = raw.trim();
    final fields = <String, String>{};

    if (source.contains('(')) {
      _parseWithParentheses(source, fields);
    }

    if (fields.isEmpty) {
      _parseSequential(source, fields);
    }

    final gtin = normalizeGtin(fields['01']);
    if (gtin == null) return null;

    final lot = _cleanVariable(fields['10']);
    final mfg = _parseDate(fields['11']);

    return Gs1DataMatrixData(gtin: gtin, lot: lot, manufacturingDate: mfg);
  }

  static void _parseWithParentheses(String source, Map<String, String> fields) {
    final matches = RegExp(r'\((\d{2,4})\)').allMatches(source).toList();
    for (var i = 0; i < matches.length; i++) {
      final ai = matches[i].group(1);
      if (ai == null) continue;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : source.length;
      var value = source.substring(start, end);
      value = value.replaceAll(_fnc1, '');
      fields[ai] = value;
    }
  }

  static void _parseSequential(String source, Map<String, String> fields) {
    var i = 0;
    while (i < source.length) {
      final ch = source[i];
      if (ch == _fnc1) {
        i++;
        continue;
      }

      if (!_isDigit(ch) || i + 1 >= source.length) break;
      final ai = source.substring(i, i + 2);
      i += 2;

      switch (ai) {
        case '01':
          if (i + 14 <= source.length) {
            fields[ai] = source.substring(i, i + 14);
            i += 14;
          } else {
            i = source.length;
          }
          break;
        case '10':
          final end = _nextSeparator(source, i);
          fields[ai] = source.substring(i, end == -1 ? source.length : end);
          i = end == -1 ? source.length : end + 1;
          break;
        case '11':
          final remaining = source.length - i;
          final take = remaining >= 8 ? 8 : min(6, remaining);
          if (take >= 6) {
            fields[ai] = source.substring(i, i + take);
            i += take;
          } else {
            i = source.length;
          }
          break;
        default:
          final next = _nextSeparator(source, i);
          i = next == -1 ? source.length : next + 1;
      }
    }
  }

  static int _nextSeparator(String source, int start) {
    final gs = source.indexOf(_fnc1, start);
    final paren = source.indexOf('(', start);
    final indexes = [gs, paren].where((i) => i >= 0).toList();
    if (indexes.isEmpty) return -1;
    return indexes.reduce(min);
  }

  static bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static String? normalizeGtin(String? value) {
    if (value == null) return null;
    final digits = digitsOnly(value);
    if (digits.isEmpty) return null;
    if (![8, 12, 13, 14].contains(digits.length)) return null;
    return digits.padLeft(14, '0');
  }

  /// Returns the numeric characters of [value] or `null` when the input is
  /// null.
  static String? digitsOnly(String? value) {
    if (value == null) return null;
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static String? _cleanVariable(String? value) {
    if (value == null) return null;
    final trimmed = value.replaceAll(_fnc1, '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 6 && digits.length != 8) return null;

    final year = digits.length == 8 ? int.tryParse(digits.substring(0, 4)) : 2000 + int.parse(digits.substring(0, 2));
    final month = int.tryParse(digits.substring(digits.length == 8 ? 4 : 2, digits.length == 8 ? 6 : 4));
    final day = int.tryParse(digits.substring(digits.length - 2));
    if (year == null || month == null || day == null) return null;

    try {
      return DateTime.utc(year, month, day);
    } catch (_) {
      return null;
    }
  }
}
