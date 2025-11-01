// lib/widgets/logout_action.dart
import 'package:flutter/material.dart';
import '../api/client.dart';

class LogoutAction extends StatelessWidget {
  final ApiClient api;
  final VoidCallback? onLoggedOut;

  const LogoutAction({super.key, required this.api, this.onLoggedOut});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Abmelden',
      icon: const Icon(Icons.logout),
      onPressed: () async {
        api.logout();
        // Wenn der Aufrufer etwas spezielles tun will (z. B. zur AuthPage navigieren):
        if (onLoggedOut != null) {
          onLoggedOut!();
          return;
        }
        // Fallback: Zur Startseite / ersten Route zurück
        Navigator.of(context).popUntil((r) => r.isFirst);
      },
    );
  }
}
