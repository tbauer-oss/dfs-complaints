// lib/widgets/logout_button.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class LogoutButton extends StatelessWidget implements PreferredSizeWidget {
  final ApiClient api;
  final VoidCallback onLoggedOut;

  const LogoutButton({
    super.key,
    required this.api,
    required this.onLoggedOut,
  });

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: FilledButton.icon(
          icon: const Icon(Icons.logout),
          label: Text(t.logout),
          onPressed: () async {
            await api.logout();
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(t.loggedOut)));
            }
            onLoggedOut();
          },
        ),
      ),
    );
  }
}
