// lib/data/document_languages.dart

class DocumentLanguage {
  final String code;
  final String name;
  final String shortLabel;

  const DocumentLanguage({
    required this.code,
    required this.name,
    required this.shortLabel,
  });
}

const kDocumentLanguages = <DocumentLanguage>[
  DocumentLanguage(code: 'de', name: 'Deutsch', shortLabel: 'DE'),
  DocumentLanguage(code: 'en', name: 'Englisch', shortLabel: 'EN'),
  DocumentLanguage(code: 'fr', name: 'Französisch', shortLabel: 'FR'),
  DocumentLanguage(code: 'it', name: 'Italienisch', shortLabel: 'IT'),
  DocumentLanguage(code: 'es', name: 'Spanisch', shortLabel: 'ES'),
  DocumentLanguage(code: 'pt', name: 'Portugiesisch', shortLabel: 'PT'),
  DocumentLanguage(code: 'nl', name: 'Niederländisch', shortLabel: 'NL'),
  DocumentLanguage(code: 'da', name: 'Dänisch', shortLabel: 'DA'),
  DocumentLanguage(code: 'sv', name: 'Schwedisch', shortLabel: 'SV'),
  DocumentLanguage(code: 'nb', name: 'Norwegisch (Bokmål)', shortLabel: 'NB'),
  DocumentLanguage(code: 'fi', name: 'Finnisch', shortLabel: 'FI'),
  DocumentLanguage(code: 'pl', name: 'Polnisch', shortLabel: 'PL'),
  DocumentLanguage(code: 'cs', name: 'Tschechisch', shortLabel: 'CS'),
  DocumentLanguage(code: 'sk', name: 'Slowakisch', shortLabel: 'SK'),
  DocumentLanguage(code: 'hu', name: 'Ungarisch', shortLabel: 'HU'),
  DocumentLanguage(code: 'ro', name: 'Rumänisch', shortLabel: 'RO'),
  DocumentLanguage(code: 'bg', name: 'Bulgarisch', shortLabel: 'BG'),
  DocumentLanguage(code: 'hr', name: 'Kroatisch', shortLabel: 'HR'),
  DocumentLanguage(code: 'sr', name: 'Serbisch', shortLabel: 'SR'),
  DocumentLanguage(code: 'bs', name: 'Bosnisch', shortLabel: 'BS'),
  DocumentLanguage(code: 'sl', name: 'Slowenisch', shortLabel: 'SL'),
  DocumentLanguage(code: 'sq', name: 'Albanisch', shortLabel: 'SQ'),
  DocumentLanguage(code: 'el', name: 'Griechisch', shortLabel: 'EL'),
  DocumentLanguage(code: 'tr', name: 'Türkisch', shortLabel: 'TR'),
  DocumentLanguage(code: 'lt', name: 'Litauisch', shortLabel: 'LT'),
  DocumentLanguage(code: 'lv', name: 'Lettisch', shortLabel: 'LV'),
  DocumentLanguage(code: 'et', name: 'Estnisch', shortLabel: 'ET'),
  DocumentLanguage(code: 'ga', name: 'Irisch', shortLabel: 'GA'),
  DocumentLanguage(code: 'mt', name: 'Maltesisch', shortLabel: 'MT'),
  DocumentLanguage(code: 'uk', name: 'Ukrainisch', shortLabel: 'UK'),
  DocumentLanguage(code: 'ru', name: 'Russisch', shortLabel: 'RU'),
  DocumentLanguage(code: 'is', name: 'Isländisch', shortLabel: 'IS'),
];

const kDocumentLanguageCodes = <String>{
  'de',
  'en',
  'fr',
  'it',
  'es',
  'pt',
  'nl',
  'da',
  'sv',
  'nb',
  'fi',
  'pl',
  'cs',
  'sk',
  'hu',
  'ro',
  'bg',
  'hr',
  'sr',
  'bs',
  'sl',
  'sq',
  'el',
  'tr',
  'lt',
  'lv',
  'et',
  'ga',
  'mt',
  'uk',
  'ru',
  'is',
};

DocumentLanguage? documentLanguageFor(String? code) {
  final normalized = (code ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return null;
  try {
    return kDocumentLanguages.firstWhere((lang) => lang.code == normalized);
  } catch (_) {
    return null;
  }
}

String documentLanguageLabel(String? code) {
  return documentLanguageFor(code)?.name ?? (code ?? '').toUpperCase();
}
