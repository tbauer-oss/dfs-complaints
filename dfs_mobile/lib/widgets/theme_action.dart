// lib/widgets/theme_action.dart
import 'package:flutter/material.dart';
import '../services/app_prefs_scope.dart';
import '../services/app_prefs.dart';
import '../l10n/app_localizations.dart';

class ThemeAction extends StatelessWidget {
  const ThemeAction({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefsScope.of(context);
    final t = AppLocalizations.of(context)!;

    IconData iconFor(ThemeMode m) => switch (m) {
      ThemeMode.dark   => Icons.dark_mode,
      ThemeMode.light  => Icons.light_mode,
      _                => Icons.brightness_auto,
    };

    Widget row(String val, IconData icon, String label, bool selected) => Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        if (selected) const Icon(Icons.check, color: Colors.green),
      ],
    );

    final mode = prefs.themeMode;

    return PopupMenuButton<String>(
      tooltip: 'Theme', // kurzer Tooltip; passt in dein Schema
      icon: Icon(iconFor(mode)),
      onSelected: (val) => prefs.setTheme(val), // -> notifyListeners()
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'system',
          child: row('system', Icons.brightness_auto, t.theme_system, mode == ThemeMode.system),
        ),
        PopupMenuItem(
          value: 'light',
          child: row('light', Icons.light_mode, t.theme_light, mode == ThemeMode.light),
        ),
        PopupMenuItem(
          value: 'dark',
          child: row('dark', Icons.dark_mode, t.theme_dark, mode == ThemeMode.dark),
        ),
      ],
    );
  }
}
