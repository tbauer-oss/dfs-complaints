import 'package:flutter/material.dart';

class LangAction extends StatelessWidget {
  final void Function(Locale)? onLocaleChanged;
  const LangAction({super.key, this.onLocaleChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Sprache',
      icon: const Icon(Icons.language),
      onSelected: (code) {
        onLocaleChanged?.call(Locale(code));
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'de', child: Text('Deutsch')),
        PopupMenuItem(value: 'en', child: Text('English')),
        PopupMenuItem(value: 'fr', child: Text('Français')),
        PopupMenuItem(value: 'it', child: Text('Italiano')),
        PopupMenuItem(value: 'es', child: Text('Español')),
      ],
    );
  }
}
