// flutter_web/lib/app_root.dart
import 'package:flutter/material.dart';
import 'api/client.dart';
import 'pages/gate_page.dart';
import 'pages/login_page.dart'; // oder deine nächste Seite

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _api = ApiClient();
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return Scaffold(
        body: GatePage(
          api: _api,
          onUnlocked: () => setState(() => _unlocked = true),
        ),
      );
    }
    // Nächste Seite nach dem Gate:
    return Scaffold(
      body: LoginPage(api: _api),  // oder dein eigentlicher Start
    );
  }
}
