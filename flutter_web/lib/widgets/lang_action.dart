// lib/widgets/lang_action.dart
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class LangAction extends StatelessWidget {
  final void Function(Locale)? onLocaleChanged;
  const LangAction({super.key, this.onLocaleChanged});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      tooltip: t.langMenuTooltip, // NEU: ARB-Key
      icon: const Icon(Icons.language),
      onSelected: (code) => onLocaleChanged?.call(Locale(code)),
      itemBuilder: (ctx) => [
        PopupMenuItem(value: 'de', child: Text(t.langNameDE)),
        PopupMenuItem(value: 'en', child: Text(t.langNameEN)),
        PopupMenuItem(value: 'fr', child: Text(t.langNameFR)),
        PopupMenuItem(value: 'it', child: Text(t.langNameIT)),
        PopupMenuItem(value: 'es', child: Text(t.langNameES)),
      ],
    );
  }
}
