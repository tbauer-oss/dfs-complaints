import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart'; // wird von gen-l10n erzeugt

import 'api/client.dart';
import 'pages/gate_page.dart';
import 'pages/auth_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/admin_page.dart';

void main() {
  runApp(const DFSApp());
}

class DFSApp extends StatefulWidget {
  const DFSApp({super.key});
  @override
  State<DFSApp> createState() => _DFSAppState();
}

class _DFSAppState extends State<DFSApp> {
  final api = ApiClient();
  Locale _locale = const Locale('de');
  bool _unlocked = false; // Gate freigeschaltet?

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('de'), Locale('en'), Locale('es'), Locale('fr'), Locale('it')
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appTitle,

      // <<< NEU: Named Routes für Admin (Root-Navigator) >>>
      routes: {
        '/admin': (ctx) => AdminPage(api: api),
      },

      home: Builder(
        builder: (context) {
          final t = AppLocalizations.of(context)!;
          return Scaffold(
            appBar: AppBar(
              title: Text(t.appTitle),
              actions: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<Locale>(
                    value: _locale,
                    items: const [
                      DropdownMenuItem(value: Locale('de'), child: Text('DE')),
                      DropdownMenuItem(value: Locale('en'), child: Text('EN')),
                      DropdownMenuItem(value: Locale('es'), child: Text('ES')),
                      DropdownMenuItem(value: Locale('fr'), child: Text('FR')),
                      DropdownMenuItem(value: Locale('it'), child: Text('IT')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _locale = v);
                    },
                  ),
                ),
              ],
            ),

            // Innerer Navigator für Gate/Auth/Dashboard
            body: Navigator(
              pages: [
                // 1) GatePage immer zuerst
                MaterialPage(
                  key: const ValueKey('page-gate'),
                  child: GatePage(
                    api: api,
                    onUnlocked: () => setState(() => _unlocked = true),
                  ),
                ),

                // 2) Nach Gate freigeschaltet: AuthPage
                if (_unlocked && api.token == null)
                  MaterialPage(
                    key: const ValueKey('page-auth'),
                    child: AuthPage(
                      api: api,
                      onLoggedIn: () => setState(() {}),
                    ),
                  ),

                // 3) Nach Login: Dashboard
                if (api.token != null)
                  MaterialPage(
                    key: const ValueKey('page-dash'),
                    child: DashboardPage(api: api),
                  ),
              ],
              onPopPage: (route, result) => route.didPop(result),
            ),
          );
        },
      ),
    );
  }
}
