import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart'; // wird von gen-l10n erzeugt

import 'api/client.dart';
import 'pages/gate_page.dart';
import 'pages/auth_page.dart';
import 'pages/dashboard_page.dart';

void main() {
  runApp(const DFSApp());
}

class DFSApp extends StatefulWidget {
  const DFSApp({super.key});
  @override State<DFSApp> createState() => _DFSAppState();
}

class _DFSAppState extends State<DFSApp> {
  final api = ApiClient();
  Locale _locale = const Locale('de');
  bool _unlocked = false; // <--- neu

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ... wie gehabt ...
      home: Builder(
        builder: (context) {
          final t = AppLocalizations.of(context)!;
          return Scaffold(
            appBar: AppBar(
              title: Text(t.appTitle),
              actions: [
                // ... dein Locale-Dropdown ...
              ],
            ),
            body: Navigator(
              pages: [
                // 1) GatePage
                MaterialPage(
                  child: GatePage(
                    api: api,
                    onUnlocked: () => setState(() => _unlocked = true), // <--- hier umschalten
                  ),
                ),

                // 2) Nach Gate freigeschaltet: AuthPage anzeigen
                if (_unlocked)
                  MaterialPage(
                    child: AuthPage(
                      api: api,
                      onLoggedIn: () => setState((){}),
                    ),
                  ),

                // 3) Nach Login: Dashboard
                if (api.token != null)
                  MaterialPage(child: DashboardPage(api: api)),
              ],
              onPopPage: (route, result) => route.didPop(result),
            ),
          );
        },
      ),
    );
  }
}
