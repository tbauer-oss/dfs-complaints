// lib/widgets/lang_action.dart
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import '../l10n/app_localizations.dart';

/// Sprachcode -> Flaggen-Ländercode (für EN nehme ich GB)
const _langToCountry = <String, String>{
  'de': 'de',
  'en': 'gb',
  'fr': 'fr',
  'it': 'it',
  'es': 'es',
};

const _supported = <Locale>[
  Locale('de'),
  Locale('en'),
  Locale('fr'),
  Locale('it'),
  Locale('es'),
];

class LangAction extends StatelessWidget {
  final void Function(Locale)? onLocaleChanged;
  /// Nur Flaggen anzeigen (kein Text im Menü)
  final bool flagsOnly;

  const LangAction({
    super.key,
    this.onLocaleChanged,
    this.flagsOnly = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final current = Localizations.localeOf(context);
    final currentLang = current.languageCode.toLowerCase();
    final currentFlag = _langToCountry[currentLang] ?? 'gb';

    return Tooltip(
      message: t?.langMenuTooltip ?? 'Language',
      child: PopupMenuButton<Locale>(
        tooltip: t?.langMenuTooltip ?? 'Language',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        itemBuilder: (context) {
          return _supported.map((loc) {
            final code = loc.languageCode.toLowerCase();
            final flagCode = _langToCountry[code] ?? 'gb';
            final isActive = code == currentLang;

            return PopupMenuItem<Locale>(
              value: loc,
              child: Row(
                children: [
                  CountryFlag.fromCountryCode(
                    flagCode,
                    height: 16,
                    width: 24,
                    borderRadius: 2,
                  ),
                  if (!flagsOnly) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_nameFor(t, code)),
                    ),
                  ],
                  if (isActive) const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 14),
                  ),
                ],
              ),
            );
          }).toList();
        },
        onSelected: (loc) => onLocaleChanged?.call(loc),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: CountryFlag.fromCountryCode(
            currentFlag,
            height: 18,
            width: 26,
            borderRadius: 3,
          ),
        ),
      ),
    );
  }

  String _nameFor(AppLocalizations? t, String code) {
    switch (code) {
      case 'de': return t?.langNameDE ?? 'German';
      case 'en': return t?.langNameEN ?? 'English';
      case 'fr': return t?.langNameFR ?? 'French';
      case 'it': return t?.langNameIT ?? 'Italian';
      case 'es': return t?.langNameES ?? 'Spanish';
      default:   return 'English';
    }
  }
}
