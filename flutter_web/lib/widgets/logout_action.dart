// lib/widgets/logout_action.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

class LogoutAction extends StatelessWidget {
  final ApiClient api;
  final VoidCallback? onLoggedOut;

  const LogoutAction({super.key, required this.api, this.onLoggedOut});

  Future<bool> _confirm(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.logoutTitle),
        content: Text(t.logoutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.logout)),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'logout' && await _confirm(context)) {
          await api.logout();
          onLoggedOut?.call();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.loggedOut)));
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: Text(t.logout),
          ),
        ),
      ],
    );
  }
}
