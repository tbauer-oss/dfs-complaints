// lib/data/country_geography.dart
// Hilfsfunktionen für Regions- und Positionsdaten der Länder.
import 'dart:math' as math;
import 'dart:ui';

import 'package:dfs_mobile/models/country.dart';

/// Zuordnung von ISO-3166-1 alpha-2 Codes zu groben Weltregionen.
///
/// Die Liste basiert auf der bestehenden Länderdefinition der App und deckt
/// alle angezeigten Optionen ab. Die Regionen dienen ausschließlich dazu, die
/// Pins für die Weltkarte gleichmäßig zu verteilen.
const Map<String, String> kCountryRegions = {
  'AD': 'europe',
  'AE': 'middle_east',
  'AF': 'middle_east',
  'AG': 'north_america',
  'AI': 'north_america',
  'AL': 'europe',
  'AM': 'europe',
  'AO': 'africa',
  'AQ': 'polar',
  'AR': 'south_america',
  'AS': 'oceania',
  'AT': 'europe',
  'AU': 'oceania',
  'AW': 'north_america',
  'AX': 'europe',
  'AZ': 'europe',
  'BA': 'europe',
  'BB': 'north_america',
  'BD': 'asia',
  'BE': 'europe',
  'BF': 'africa',
  'BG': 'europe',
  'BH': 'middle_east',
  'BI': 'africa',
  'BJ': 'africa',
  'BL': 'north_america',
  'BM': 'north_america',
  'BN': 'asia',
  'BO': 'south_america',
  'BQ': 'north_america',
  'BR': 'south_america',
  'BS': 'north_america',
  'BT': 'asia',
  'BV': 'polar',
  'BW': 'africa',
  'BY': 'europe',
  'BZ': 'north_america',
  'CA': 'north_america',
  'CC': 'asia',
  'CD': 'africa',
  'CF': 'africa',
  'CG': 'africa',
  'CH': 'europe',
  'CI': 'africa',
  'CK': 'oceania',
  'CL': 'south_america',
  'CM': 'africa',
  'CN': 'asia',
  'CO': 'south_america',
  'CR': 'north_america',
  'CU': 'north_america',
  'CV': 'africa',
  'CW': 'north_america',
  'CX': 'asia',
  'CY': 'europe',
  'CZ': 'europe',
  'DE': 'europe',
  'DJ': 'africa',
  'DK': 'europe',
  'DM': 'north_america',
  'DO': 'north_america',
  'DZ': 'africa',
  'EC': 'south_america',
  'EE': 'europe',
  'EG': 'africa',
  'EH': 'africa',
  'ER': 'africa',
  'ES': 'europe',
  'ET': 'africa',
  'FI': 'europe',
  'FJ': 'oceania',
  'FK': 'south_america',
  'FM': 'oceania',
  'FO': 'europe',
  'FR': 'europe',
  'GA': 'africa',
  'GB': 'europe',
  'GD': 'north_america',
  'GE': 'middle_east',
  'GF': 'south_america',
  'GG': 'europe',
  'GH': 'africa',
  'GI': 'europe',
  'GL': 'north_america',
  'GM': 'africa',
  'GN': 'africa',
  'GP': 'north_america',
  'GQ': 'africa',
  'GR': 'europe',
  'GT': 'north_america',
  'GU': 'oceania',
  'GW': 'africa',
  'GY': 'south_america',
  'HK': 'asia',
  'HN': 'north_america',
  'HR': 'europe',
  'HT': 'north_america',
  'HU': 'europe',
  'ID': 'asia',
  'IE': 'europe',
  'IL': 'middle_east',
  'IM': 'europe',
  'IN': 'asia',
  'IO': 'asia',
  'IQ': 'middle_east',
  'IR': 'middle_east',
  'IS': 'europe',
  'IT': 'europe',
  'JE': 'europe',
  'JM': 'north_america',
  'JO': 'middle_east',
  'JP': 'asia',
  'KE': 'africa',
  'KG': 'middle_east',
  'KH': 'asia',
  'KI': 'oceania',
  'KM': 'africa',
  'KN': 'north_america',
  'KP': 'asia',
  'KR': 'asia',
  'KW': 'middle_east',
  'KY': 'north_america',
  'KZ': 'middle_east',
  'LA': 'asia',
  'LB': 'middle_east',
  'LC': 'north_america',
  'LI': 'europe',
  'LK': 'asia',
  'LR': 'africa',
  'LS': 'africa',
  'LT': 'europe',
  'LU': 'europe',
  'LV': 'europe',
  'LY': 'africa',
  'MA': 'africa',
  'MC': 'europe',
  'MD': 'europe',
  'ME': 'europe',
  'MF': 'north_america',
  'MG': 'africa',
  'MH': 'oceania',
  'MK': 'europe',
  'ML': 'africa',
  'MM': 'asia',
  'MN': 'asia',
  'MO': 'asia',
  'MP': 'oceania',
  'MQ': 'north_america',
  'MR': 'africa',
  'MS': 'north_america',
  'MT': 'europe',
  'MU': 'africa',
  'MV': 'asia',
  'MW': 'africa',
  'MX': 'north_america',
  'MY': 'asia',
  'MZ': 'africa',
  'NA': 'africa',
  'NC': 'oceania',
  'NE': 'africa',
  'NF': 'oceania',
  'NG': 'africa',
  'NI': 'north_america',
  'NL': 'europe',
  'NO': 'europe',
  'NP': 'asia',
  'NR': 'oceania',
  'NU': 'oceania',
  'NZ': 'oceania',
  'OM': 'middle_east',
  'PA': 'north_america',
  'PE': 'south_america',
  'PF': 'oceania',
  'PG': 'oceania',
  'PH': 'asia',
  'PK': 'middle_east',
  'PL': 'europe',
  'PM': 'north_america',
  'PN': 'oceania',
  'PR': 'north_america',
  'PS': 'middle_east',
  'PT': 'europe',
  'PW': 'oceania',
  'PY': 'south_america',
  'QA': 'middle_east',
  'RE': 'africa',
  'RO': 'europe',
  'RS': 'europe',
  'RU': 'europe',
  'RW': 'africa',
  'SA': 'middle_east',
  'SB': 'oceania',
  'SC': 'africa',
  'SD': 'africa',
  'SE': 'europe',
  'SG': 'asia',
  'SH': 'africa',
  'SI': 'europe',
  'SJ': 'europe',
  'SK': 'europe',
  'SL': 'africa',
  'SM': 'europe',
  'SN': 'africa',
  'SO': 'africa',
  'SR': 'south_america',
  'SS': 'africa',
  'ST': 'africa',
  'SV': 'north_america',
  'SX': 'north_america',
  'SY': 'middle_east',
  'SZ': 'africa',
  'TC': 'north_america',
  'TD': 'africa',
  'TG': 'africa',
  'TH': 'asia',
  'TJ': 'middle_east',
  'TK': 'oceania',
  'TL': 'asia',
  'TM': 'middle_east',
  'TN': 'africa',
  'TO': 'oceania',
  'TR': 'middle_east',
  'TT': 'north_america',
  'TV': 'oceania',
  'TW': 'asia',
  'TZ': 'africa',
  'UA': 'europe',
  'UG': 'africa',
  'UM': 'north_america',
  'US': 'north_america',
  'UY': 'south_america',
  'UZ': 'middle_east',
  'VA': 'europe',
  'VC': 'north_america',
  'VE': 'south_america',
  'VG': 'north_america',
  'VI': 'north_america',
  'VN': 'asia',
  'VU': 'oceania',
  'WF': 'oceania',
  'WS': 'oceania',
  'XK': 'europe',
  'YE': 'middle_east',
  'YT': 'africa',
  'ZA': 'africa',
  'ZM': 'africa',
  'ZW': 'africa',
};

const Map<String, Rect> _regionRects = {
  'north_america': Rect.fromLTRB(0.05, 0.12, 0.35, 0.48),
  'south_america': Rect.fromLTRB(0.28, 0.44, 0.42, 0.9),
  'europe': Rect.fromLTRB(0.45, 0.14, 0.68, 0.35),
  'africa': Rect.fromLTRB(0.47, 0.33, 0.64, 0.76),
  'asia': Rect.fromLTRB(0.63, 0.14, 0.95, 0.56),
  'middle_east': Rect.fromLTRB(0.55, 0.24, 0.72, 0.5),
  'oceania': Rect.fromLTRB(0.74, 0.55, 0.94, 0.9),
  'polar': Rect.fromLTRB(0.35, 0.82, 0.65, 0.98),
  'world': Rect.fromLTRB(0.08, 0.18, 0.92, 0.82),
};

const Map<String, String> _manualCodeOverrides = {
  'UK': 'GB',
  'GBR': 'GB',
  'UKM': 'GB',
  'USA': 'US',
  'UAE': 'AE',
  'KOR': 'KR',
  'PRC': 'CN',
};

class CountryGeography {
  static final Map<String, Country> _countryByCode = {
    for (final country in kCountries) country.code.toUpperCase(): country,
  };

  static final Map<String, String> _nameLookup = {
    for (final country in kCountries)
      _normalize(country.names['en'] ?? country.code): country.code,
  };

  static String? resolveCode(String raw) {
    if (raw.isEmpty) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lettersOnly = trimmed.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    final override = _manualCodeOverrides[lettersOnly];
    if (override != null) return override;
    if (lettersOnly.length == 2 && _countryByCode.containsKey(lettersOnly)) {
      return lettersOnly;
    }
    final normalized = _normalize(trimmed);
    if (normalized.isEmpty) return null;
    return _nameLookup[normalized];
  }

  static String labelForCode(String code) {
    final country = _countryByCode[code.toUpperCase()];
    if (country == null) return code.toUpperCase();
    return country.names['en'] ?? country.code;
  }

  static Offset? normalizedPositionFor(String code) {
    final region = kCountryRegions[code] ?? 'world';
    final rect = _regionRects[region] ?? _regionRects['world'];
    if (rect == null) return null;
    final hash = _hash(code);
    final fx = (hash % 997) / 997.0;
    final fy = ((hash ~/ 997) % 997) / 997.0;
    final dx = rect.left + fx * rect.width;
    final dy = rect.top + fy * rect.height;
    return Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
  }

  static String _normalize(String input) {
    final lower = input.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      final replacement = _diacritics[char];
      if (replacement != null) {
        buffer.write(replacement);
      } else if (_allowedPattern.hasMatch(char)) {
        buffer.write(char);
      } else if (char == '-' || char == '_') {
        buffer.write(' ');
      }
    }
    final cleaned = buffer.toString().trim();
    if (cleaned.isEmpty) return '';
    return cleaned.split(RegExp(r'\s+')).join(' ');
  }

  static int _hash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return math.max(hash, 1);
  }
}

final RegExp _allowedPattern = RegExp(r'[a-z0-9 ]');

const Map<String, String> _diacritics = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'č': 'c',
  'ć': 'c',
  'ď': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ś': 's',
  'ş': 's',
  'š': 's',
  'ß': 'ss',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  '’': ' ',
  '–': ' ',
};
