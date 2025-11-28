import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

const supportedLangCodes = <String>['de', 'en', 'fr', 'it', 'es'];

const deeplLangCodes = <String>[
  'bg',
  'cs',
  'da',
  'de',
  'el',
  'en',
  'es',
  'et',
  'fi',
  'fr',
  'hu',
  'id',
  'it',
  'ja',
  'ko',
  'lt',
  'lv',
  'nb',
  'nl',
  'pl',
  'pt-pt',
  'pt-br',
  'ro',
  'ru',
  'sk',
  'sl',
  'sv',
  'tr',
  'uk',
  'zh',
];

const deeplLangLabels = <String, String>{
  'bg': 'Bulgarisch',
  'cs': 'Tschechisch',
  'da': 'Dänisch',
  'de': 'Deutsch',
  'el': 'Griechisch',
  'en': 'Englisch',
  'es': 'Spanisch',
  'et': 'Estnisch',
  'fi': 'Finnisch',
  'fr': 'Französisch',
  'hu': 'Ungarisch',
  'id': 'Indonesisch',
  'it': 'Italienisch',
  'ja': 'Japanisch',
  'ko': 'Koreanisch',
  'lt': 'Litauisch',
  'lv': 'Lettisch',
  'nb': 'Norwegisch (Bokmål)',
  'nl': 'Niederländisch',
  'pl': 'Polnisch',
  'pt-pt': 'Portugiesisch (EU)',
  'pt-br': 'Portugiesisch (BR)',
  'ro': 'Rumänisch',
  'ru': 'Russisch',
  'sk': 'Slowakisch',
  'sl': 'Slowenisch',
  'sv': 'Schwedisch',
  'tr': 'Türkisch',
  'uk': 'Ukrainisch',
  'zh': 'Chinesisch',
};

const supportedLangLocales = <Locale>[
  Locale('de'),
  Locale('en'),
  Locale('fr'),
  Locale('it'),
  Locale('es'),
];

String normalizeLangCode(String? code) {
  final lc = (code ?? '').trim().toLowerCase();
  return supportedLangCodes.contains(lc) ? lc : 'de';
}

bool isSupportedLangCode(String? code) {
  final lc = (code ?? '').trim().toLowerCase();
  return supportedLangCodes.contains(lc);
}

Locale localeFromLangCode(String? code) => Locale(normalizeLangCode(code));

String langNameFor(AppLocalizations? t, String code) {
  switch (code.toLowerCase()) {
    case 'de':
      return t?.langNameDE ?? 'German';
    case 'en':
      return t?.langNameEN ?? 'English';
    case 'fr':
      return t?.langNameFR ?? 'French';
    case 'it':
      return t?.langNameIT ?? 'Italian';
    case 'es':
      return t?.langNameES ?? 'Spanish';
    default:
      return t?.langNameEN ?? 'English';
  }
}

String deeplLangLabel(String code) {
  return deeplLangLabels[code.toLowerCase()] ?? code.toUpperCase();
}
