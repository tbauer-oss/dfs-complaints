import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'l10n/app_localizations.dart';

import 'pages/login_page.dart';
import 'pages/register_page.dart';
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

  Locale? _locale;           // globale Sprachwahl
  bool _restored = false;    // Session wiederhergestellt?

  @override
  void initState() {
    super.initState();
    api.restoreSession().whenComplete(() {
      setState(() => _restored = true);
    });
  }

  void _setLocale(Locale? loc) {
    setState(() => _locale = loc);
  }

  void _goToLogin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _buildLogin()),
      (r) => false,
    );
  }

  Widget _buildLogin() {
    return LoginPage(
      api: api,
      onLoggedIn: () {
        // Nach erfolgreichem Login → Dashboard
        // (pushReplacement, damit der Login aus dem Stack ist)
        // Hier brauchen wir den BuildContext der aufrufenden Stelle; wir lösen das im Navigator unten.
      },
      onOpenRegister: () {
        // RegisterPage (mit Gate-Abfrage in der Seite selbst)
        Navigator.of(_navKey.currentContext!).push(
          MaterialPageRoute(
            builder: (_) => RegisterPage(api: api),
          ),
        );
      },
      onOpenAdmin: () {
        Navigator.of(_navKey.currentContext!).push(
          MaterialPageRoute(builder: (_) => const AdminPage()),
        );
      },
    );
  }

  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // Wrapper, um von überall die Sprache ändern zu können (LangAction ruft DFSApp.of(context)?.setLocale(...) auf)
    return _AppLocale(
      locale: _locale,
      setLocale: _setLocale,
      child: MaterialApp(
        navigatorKey: _navKey,
        debugShowCheckedModeBanner: false,
        title: 'DFS Customer Complaint',
        locale: _locale,
        supportedLocales: const [
          Locale('de'),
          Locale('en'),
          Locale('fr'),
          Locale('it'),
          Locale('es'),
        ],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: _restored
            ? Builder(
                builder: (ctx) {
                  // Wenn bereits eingeloggt → Dashboard, sonst Login
                  if (api.token != null && api.token!.isNotEmpty) {
                    return DashboardPage(
                      api: api,
                      onLoggedOut: () => _goToLogin(ctx),
                    );
                  }
                  return _LoginWithNavigation(
                    login: _buildLogin,
                    onLoggedIn: () {
                      Navigator.of(ctx).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => DashboardPage(
                            api: api,
                            onLoggedOut: () => _goToLogin(ctx),
                          ),
                        ),
                      );
                    },
                  );
                },
              )
            : const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

/// Kleiner Helper, damit wir `onLoggedIn` sauber in LoginPage verdrahten können.
class _LoginWithNavigation extends StatelessWidget {
  final Widget Function() login;
  final VoidCallback onLoggedIn;
  const _LoginWithNavigation({required this.login, required this.onLoggedIn});

  @override
  Widget build(BuildContext context) {
    final w = login();
    if (w is LoginPage) {
      return LoginPage(
        api: w.api,
        onLoggedIn: onLoggedIn,               // <- HIER callback rein
        onOpenRegister: w.onOpenRegister,
        onOpenAdmin: w.onOpenAdmin,
      );
    }
    return w;
  }
}

/// InheritedWidget, damit LangAction die App-Sprache setzen kann.
class _AppLocale extends InheritedWidget {
  final Locale? locale;
  final void Function(Locale?) setLocale;
  const _AppLocale({
    required this.locale,
    required this.setLocale,
    required super.child,
  });

  static _AppLocale? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_AppLocale>();
  }

  @override
  bool updateShouldNotify(covariant _AppLocale oldWidget) {
    return oldWidget.locale != locale;
  }
}
