// lib/widgets/lang_action.dart
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import '../l10n/app_localizations.dart';
import '../utils/lang_utils.dart';

const _langToCountry = <String, String>{
  'de': 'de',
  'en': 'gb',
  'fr': 'fr',
  'it': 'it',
  'es': 'es',
};

class LangAction extends StatelessWidget {
  final void Function(Locale)? onLocaleChanged;
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
    final currentLang = normalizeLangCode(current.languageCode);
    final currentFlag = _langToCountry[currentLang] ?? 'gb';

    return Tooltip(
      message: t?.langMenuTooltip ?? 'Language',
      child: PopupMenuButton<Locale>(
        tooltip: t?.langMenuTooltip ?? 'Language',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        itemBuilder: (context) {
          return supportedLangLocales.map((loc) {
            final code = loc.languageCode.toLowerCase();
            final flagCode = _langToCountry[code] ?? 'gb';
            final isActive = code == currentLang;

            return PopupMenuItem<Locale>(
              value: loc,
              child: Row(
                children: [
                  CountryFlag.fromCountryCode(
                    flagCode,
                    theme: ImageTheme(
                      width: 24,
                      height: 16,
                      shape: const RoundedRectangle(2), // <- const hier ist ok
                    ),
                  ),
                  if (!flagsOnly) ...[
                    const SizedBox(width: 10),
                    Expanded(child: Text(langNameFor(t, code))),
                  ],
                  if (isActive)
                    const Padding(
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
            theme: ImageTheme(
              width: 26,
              height: 18,
              shape: const RoundedRectangle(3),
            ),
          ),
        ),
      ),
    );
  }
}
