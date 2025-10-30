import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart'; // wird von gen-l10n erzeugt

import 'api/client.dart';
import 'pages/gate_page.dart';
import 'pages/auth_page.dart';
import 'pages/dashboard_page.dart';

void main() {
  runApp(const AppRoot());
}

class DFSApp extends StatefulWidget {
  const DFSApp({super.key});
  @override State<DFSApp> createState() => _DFSAppState();
}

class _DFSAppState extends State<DFSApp> {
  final api = ApiClient();
  Locale _locale = const Locale('de');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
                    onChanged: (v){ if (v!=null) setState(()=>_locale=v); },
                  ),
                ),
              ],
            ),
            body: Navigator(
              pages: [
                MaterialPage(child: GatePage(api: api, onUnlocked: ()=>setState((){}))),
                if (api.gate != null) MaterialPage(child: AuthPage(api: api, onLoggedIn: ()=>setState((){}))),
                if (api.token != null) MaterialPage(child: DashboardPage(api: api)),
              ],
              onPopPage: (route, result) => route.didPop(result),
            ),
          );
        }
      ),
    );
  }
}
