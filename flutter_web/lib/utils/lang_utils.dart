import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

const supportedLangCodes = <String>['de', 'en', 'fr', 'it', 'es'];

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
