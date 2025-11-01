// lib/widgets/logout_action.dart
import 'package:flutter/material.dart';
import '../api/client.dart';

class LogoutAction extends StatelessWidget {
  final ApiClient api;
  final VoidCallback? onLoggedOut; // optionaler Hook

  const LogoutAction({
    super.key,
    required this.api,
    this.onLoggedOut,
  });

  Future<bool> _confirm(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Abmelden?'),
            content: const Text('Möchtest du dich wirklich abmelden?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Abmelden'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Konto',
      icon: const Icon(Icons.account_circle),
      onSelected: (v) async {
        if (v == 'logout') {
          final yes = await _confirm(context);
          if (!yes) return;

          api.logout();                // Token aus LocalStorage entfernen
          onLoggedOut?.call();         // optionalen Callback feuern
          // Zur Startseite/Gate zurück:
          Navigator.of(context).popUntil((r) => r.isFirst);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Abgemeldet.')),
          );
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Abmelden'),
          ),
        ),
      ],
    );
  }
}
