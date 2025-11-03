// flutter_web/lib/widgets/lang_action.dart
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import '../i18n/locale_controller.dart';
import '../l10n/app_localizations.dart';

/// Mapping: Sprachcode -> Flaggen-Ländercode
/// Für EN nutze ich 'gb' (neutraler als 'us', typischer für UI-Sprache Englisch).
const _langToCountry = <String, String>{
  'de': 'de',
  'en': 'gb',
  'fr': 'fr',
  'it': 'it',
  'es': 'es',
};

/// Verfügbare Sprachen (de/en/fr/it/es)
const _supported = <Locale>[
  Locale('de'),
  Locale('en'),
  Locale('fr'),
  Locale('it'),
  Locale('es'),
];

class LangAction extends StatelessWidget {
  const LangAction({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ctrl = LocaleController.of(context); // dein bestehender Controller
    final current = ctrl.locale ?? Localizations.localeOf(context);
    final currentLang = (current.languageCode).toLowerCase();
    final currentFlag = _langToCountry[currentLang] ?? 'gb';

    return Tooltip(
      message: t?.langMenuTooltip ?? 'Language',
      child: PopupMenuButton<Locale>(
        tooltip: t?.langMenuTooltip ?? 'Language',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        itemBuilder: (context) {
          return _supported.map((loc) {
            final code = (loc.languageCode).toLowerCase();
            final flagCode = _langToCountry[code] ?? 'gb';
            final isActive = code == currentLang;

            return PopupMenuItem<Locale>(
              value: loc,
              child: Row(
                children: [
                  // Flagge
                  CountryFlag.fromCountryCode(
                    flagCode,
                    height: 16,
                    width: 24,
                    borderRadius: 2,
                  ),
                  const SizedBox(width: 10),
                  // Optionaler Text – wenn du wirklich NUR Flaggen willst,
                  // kannst du den Text komplett entfernen.
                  Expanded(
                    child: Text(
                      _localizedLangName(t, code), // „Deutsch“, „English“, …
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (isActive) const Icon(Icons.check, size: 16),
                ],
              ),
            );
          }).toList();
        },
        onSelected: (loc) => ctrl.setLocale(loc),
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

  String _localizedLangName(AppLocalizations? t, String code) {
    // Greift auf deine vorhandenen ARB-Keys zurück, fällt sonst auf Englisch zurück.
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
