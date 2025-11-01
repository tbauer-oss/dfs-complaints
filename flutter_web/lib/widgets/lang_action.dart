import 'package:flutter/material.dart';
import '../i18n/locale_controller.dart';

/// Kleine Sprach-Auswahl als AppBar-Action.
/// Einfach in `actions: [LangAction()]` einfügen.
class LangAction extends StatelessWidget {
  const LangAction({super.key});

  @override
  Widget build(BuildContext context) {
    final current = LocaleController.I.locale.value?.languageCode;

    String labelFor(String code) {
      switch (code) {
        case 'de': return 'DE';
        case 'en': return 'EN';
        case 'fr': return 'FR';
        case 'it': return 'IT';
        case 'es': return 'ES';
        default:   return code.toUpperCase();
      }
    }

    return PopupMenuButton<String>(
      tooltip: 'Sprache',
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language),
          const SizedBox(width: 6),
          Text(labelFor(current ?? 'sys')),
        ],
      ),
      onSelected: (value) {
        if (value == 'sys') {
          LocaleController.I.set(null);      // Systemsprache
        } else {
          LocaleController.I.set(Locale(value));
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'sys', child: Text('System')),
        const PopupMenuItem(value: 'de',  child: Text('Deutsch')),
        const PopupMenuItem(value: 'en',  child: Text('English')),
        const PopupMenuItem(value: 'fr',  child: Text('Français')),
        const PopupMenuItem(value: 'it',  child: Text('Italiano')),
        const PopupMenuItem(value: 'es',  child: Text('Español')),
      ],
    );
  }
}
