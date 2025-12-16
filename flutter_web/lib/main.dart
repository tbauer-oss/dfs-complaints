// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'l10n/app_localizations.dart';
import 'services/app_prefs.dart';
import 'services/app_prefs_scope.dart';
import 'dart:html' as html; // für Web-Tab-Titel
import 'utils/lang_utils.dart';

// Seiten
import 'pages/register_page.dart';
import 'pages/admin_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/help_center_page.dart';
import 'pages/rep_login_page.dart';
import 'pages/rep_dashboard_page.dart' hide ThemeAction;
import 'pages/legal_privacy_page.dart';
import 'pages/legal_imprint_page.dart';
import 'widgets/legal_footer.dart';
import 'pages/reset_password_page.dart';

// Widgets
import 'widgets/lang_action.dart';
import 'widgets/theme_action.dart' as w;
import 'widgets/password_field.dart';

// ===== THEME BRANDING ===== //
const kBrandSeed = Color(0xFF1F4C8F); // DFS-Blau – bei Bedarf anpassen

ThemeData _lightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandSeed,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: scheme.surfaceContainerHighest,
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        minimumSize: const Size(48, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 40)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: scheme.outline),
        minimumSize: const Size(48, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.8)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    checkboxTheme: CheckboxThemeData(fillColor: WidgetStatePropertyAll(scheme.primary)),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(scheme.primary)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(scheme.primary),
      trackColor: WidgetStatePropertyAll(scheme.primary.withOpacity(.35)),
    ),
  );
}

ThemeData _darkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandSeed,
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: scheme.surfaceContainerHighest,
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        minimumSize: const Size(48, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: scheme.onSecondaryContainer,
        backgroundColor: scheme.secondaryContainer,
        minimumSize: const Size(48, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        minimumSize: const Size(48, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.9)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    checkboxTheme: CheckboxThemeData(fillColor: WidgetStatePropertyAll(scheme.primary)),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(scheme.primary)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(scheme.primary),
      trackColor: WidgetStatePropertyAll(scheme.primary.withOpacity(.35)),
    ),
  );
}

void main() {
  if (html.window.navigator.userAgent.contains('Chrome')) {
    html.window.addEventListener('beforeinstallprompt', (event) {
      event.preventDefault(); // verhindert automatisches Anzeigen
      final deferredPrompt = event as html.BeforeInstallPromptEvent;
      // Beispiel-Button oder Timer:
      Future.delayed(const Duration(seconds: 5), () {
        deferredPrompt.prompt();
      });
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ---- Core ----
  final api = ApiClient();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final _prefs = AppPrefs(); // zentrale Quelle für Theme & Locale

  bool _bootDone = false;
  bool _loggedIn = false; // Kundenlogin (token) steuert den Kunden-Flow
  bool _rememberPortal = true;
  Map<String, dynamic>? _appMeta;

  // ---- Helpers ----
  bool get _customerLoggedIn => (api.token != null && api.token!.isNotEmpty);
  bool get _repLoggedIn => (api.repToken != null && api.repToken!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _prefs.load();        // Theme & Sprache laden (triggert Rebuild)
    _boot();              // deine Session-Logik wie gehabt
  }

  Future<void> _boot() async {
    await api.restoreSession();
    await api.ensureRepSession(); // invalides repToken nach Deploys o.ä. wegräumen
    Map<String, dynamic>? meta;
    try { meta = await api.getAppMeta(refresh: true); } catch (_) {}
    setState(() {
      _loggedIn = _customerLoggedIn; // Kunden-Flow bleibt unabhängig vom Vertreter-Flow
      _bootDone = true;
      _appMeta = meta;
    });
  }

  Future<void> _openAdmin(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final emailCtrl = TextEditingController(text: api.portalProfile?['email']?.toString() ?? '');
    final pwCtrl = TextEditingController();
    var remember = _rememberPortal;
    final wantOpen = await showDialog<bool>(
      context: context,
          builder: (_) => StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              title: Text(t.admin_area),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'E-Mail',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: pwCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Passwort',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                  ),
                  CheckboxListTile(
                    value: remember,
                    onChanged: (v) => setS(() => remember = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(t.stay_signed_in),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.open)),
          ],
        ),
      ),
    );

    if (wantOpen != true) return;
    _rememberPortal = remember;

    final email = emailCtrl.text.trim();
    final pw = pwCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.required_fields)),
      );
      return;
    }

    final res = await api.portalLogin(email: email, password: pw, persist: _rememberPortal);
    if (!res.ok) {
      final msg = res.message ?? t.errorGeneric('Portal Login');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPage(
          api: api,
          portalProfile: api.portalProfile,
          onMetaUpdated: (meta) => setState(() => _appMeta = meta),
        ),
      ),
    );
  }

  void _openRegister(BuildContext context) {
    api.clearGate();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterPage(api: api)));
  }

  void _openRepArea(BuildContext ctx) {
    Navigator.of(ctx).pushNamed('/repLogin');
  }

  void _openResetPassword(BuildContext ctx) {
    Navigator.of(ctx).pushNamed('/reset-password');
  }

  void _onLoggedIn() => setState(() => _loggedIn = true);   // Kundenlogin
  void _onLoggedOut() => setState(() => _loggedIn = false); // Kundenlogout

  @override
  Widget build(BuildContext context) {
    if (!_bootDone) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Web-Tab-Titel setzen (failsafe)
    try { html.document.title = 'DFS-Connect'; } catch (_) {}

    // prefs global verfügbar machen
    return AppPrefsScope(
      notifier: _prefs,
      child: Builder(
        builder: (scopeCtx) {
          final prefs = AppPrefsScope.of(scopeCtx);

          return MaterialApp(
            title: 'DFS-Connect',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navKey,

            // ---- i18n ----
            locale: prefs.locale,
            supportedLocales: supportedLangLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            localeListResolutionCallback: (locales, supported) {
              final forced = prefs.locale;
              if (forced != null) return forced;
              if (locales != null) {
                for (final loc in locales) {
                  final normalized = normalizeLangCode(loc.languageCode);
                  for (final s in supported) {
                    if (s.languageCode.toLowerCase() == normalized) {
                      return s;
                    }
                  }
                }
              }
              return localeFromLangCode(null);
            },

            // ---- Theme ----
            themeMode: prefs.themeMode,
            theme: _lightTheme(),
            darkTheme: _darkTheme(),

            builder: (ctx, child) {
              final c = child ?? const SizedBox();
              final bannerActive = _appMeta?['testMode'] == true;
              if (!bannerActive) return c;

              final testMail = (_appMeta?['testEmail'] ?? '').toString().trim();
              final pushCount = (_appMeta?['testPushTokens'] is List)
                  ? (_appMeta!['testPushTokens'] as List).length
                  : 0;

              return Column(
                children: [
                  Material(
                    color: Colors.red.shade900,
                    elevation: 3,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.white),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'TESTSYSTEM aktiv – keine produktiven Aussendungen.',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (testMail.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('Mails: $testMail', style: const TextStyle(color: Colors.white)),
                            ],
                            if (pushCount > 0) ...[
                              const SizedBox(width: 8),
                              Text('Push-Geräte: $pushCount', style: const TextStyle(color: Colors.white)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: c),
                ],
              );
            },

            // ---- Routing ----
            initialRoute: '/',
            routes: {
              // Root / Startseite: Kunden-Flow
              '/': (_) => Builder(
                    builder: (ctx) {
                      final t = AppLocalizations.of(ctx)!;

                      // Kunde eingeloggt -> Dashboard
                      if (_loggedIn) {
                        return Scaffold(
                          appBar: AppBar(
                            title: Text(t.appTitle),
                            actions: [
                              IconButton(
                                tooltip: t.help_center_title,
                                icon: const Icon(Icons.help_outline),
                                onPressed: () => _navKey.currentState?.pushNamed('/help'),
                              ),
                              LangAction(onLocaleChanged: (l) => prefs.setLang(l.languageCode)),
                              w.ThemeAction(),
                            ],
                            bottom: PreferredSize(
                              preferredSize: const Size.fromHeight(50),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: FilledButton.icon(
                                    icon: const Icon(Icons.logout),
                                    label: Text(t.logout),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                            context: ctx,
                                            builder: (dialogCtx) => AlertDialog(
                                              title: Text(t.logoutTitle),
                                              content: Text(t.logoutConfirm),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dialogCtx, false),
                                                  child: Text(t.cancel),
                                                ),
                                                FilledButton(
                                                  onPressed: () => Navigator.pop(dialogCtx, true),
                                                  child: Text(t.logout),
                                                ),
                                              ],
                                            ),
                                          ) ??
                                          false;
                                      if (!confirm) return;

                                      await api.logout(); // Kunden-Logout
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(content: Text(t.loggedOut)),
                                        );
                                      }
                                      _onLoggedOut();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          body: DashboardPage(api: api, onLoggedOut: _onLoggedOut),
                          bottomNavigationBar: LegalFooter(api: api),
                        );
                      }

                      // Kunde NICHT eingeloggt -> Startseite
                      final scheme = Theme.of(ctx).colorScheme;
                      final isDark = Theme.of(ctx).brightness == Brightness.dark;
                      return Scaffold(
                        appBar: AppBar(
                          title: Text(t.appTitle),
                          actions: [
                            IconButton(
                              tooltip: t.help_center_title,
                              icon: const Icon(Icons.help_outline),
                              onPressed: () => _navKey.currentState?.pushNamed('/help'),
                            ),
                            LangAction(onLocaleChanged: (l) => prefs.setLang(l.languageCode)),
                            w.ThemeAction(),
                          ],
                        ),
                        body: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: isDark
                                ? LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [scheme.surface, scheme.surfaceContainerHighest],
                                  )
                                : const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xFFEFF3FA), Color(0xFFFFFFFF)],
                                  ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final minHeight = constraints.maxHeight;
                              final outerPadding = constraints.maxWidth < 640 ? 16.0 : 24.0;
                              return SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: minHeight),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 1040),
                                      child: Padding(
                                        padding: EdgeInsets.all(outerPadding),
                                        child: _LoginScreen(
                                          api: api,
                                          onLoggedIn: _onLoggedIn,
                                          onOpenRegister: () => _openRegister(ctx),
                                          onOpenAdmin: () => _openAdmin(ctx),
                                          onOpenRep: () => _openRepArea(ctx),
                                          onOpenResetPassword: () => _openResetPassword(ctx),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                        ),
                        bottomNavigationBar: LegalFooter(
                          api: api,
                          trailing: const _InternalFooterButton(),
                        ),
                      );
                    },
                  ),

              // Vertreter-Login
              '/repLogin': (_) => RepLoginPage(api: api),
              // Vertreter-Dashboard
              '/rep': (_) => RepDashboardPage(api: api),
              '/help': (ctx) {
                    final args = ModalRoute.of(ctx)?.settings.arguments;
                    String? section;
                    String? topic;
                    if (args is Map<String, String>) {
                      section = args['section'];
                      topic = args['topic'];
                    }
                    return HelpCenterPage(
                      initialSectionId: section,
                      initialTopicId: topic,
                    );
                  },
              '/admin/wiki': (_) => AdminPage.wiki(
                    api: api,
                    portalProfile: api.portalProfile,
                    onMetaUpdated: (meta) => setState(() => _appMeta = meta),
                  ),
              '/admin/prrc': (ctx) => PrrcDashboardPage(
                    api: api,
                    portalProfile: api.portalProfile,
                    initialTicket: ModalRoute.of(ctx)?.settings.arguments as String?,
                  ),
              '/admin/wiki/categories': (_) => AdminPage.wikiCategories(
                    api: api,
                    portalProfile: api.portalProfile,
                    onMetaUpdated: (meta) => setState(() => _appMeta = meta),
                  ),
              '/admin/wiki/articles': (_) => AdminPage.wikiArticles(
                    api: api,
                    portalProfile: api.portalProfile,
                    onMetaUpdated: (meta) => setState(() => _appMeta = meta),
                  ),
              '/reset-password': (_) => ResetPasswordPage(api: api),
              // Datenschutz-Seite
              '/legal/privacy': (_) => const LegalPrivacyPage(),
              // Impressum-Seite
              '/legal/imprint': (_) => const LegalImprintPage(),
            },

            // Guard-Logik zentral
            onGenerateRoute: (settings) {
              final name = settings.name ?? '/';

              if (name == '/rep' && !_repLoggedIn) {
                return MaterialPageRoute(
                  builder: (_) => RepLoginPage(api: api),
                  settings: const RouteSettings(name: '/repLogin'),
                );
              }

              if (name == '/repLogin' && _repLoggedIn) {
                return MaterialPageRoute(
                  builder: (_) => RepDashboardPage(api: api),
                  settings: const RouteSettings(name: '/rep'),
                );
              }

              if (name.startsWith('/help')) {
                final uri = Uri.tryParse(name);
                final section = uri?.queryParameters['section'];
                final topic = uri?.queryParameters['topic'];
                return MaterialPageRoute(
                  builder: (_) => HelpCenterPage(
                    initialSectionId: section,
                    initialTopicId: topic,
                  ),
                  settings: settings,
                );
              }

              if (name.startsWith('/admin/audits')) {
                final uri = Uri.tryParse(name);
                final segments = uri?.pathSegments ?? const [];
                var tab = 0;
                int? reportYear;
                if (segments.length >= 3) {
                  final target = segments[2];
                  if (target == 'program') tab = 1;
                  if (target == 'matrix') tab = 2;
                  if (target == 'reports') {
                    tab = 3;
                    if (segments.length > 3) {
                      reportYear = int.tryParse(segments[3]);
                    }
                    reportYear ??= int.tryParse(uri?.queryParameters['year'] ?? '');
                  }
                }

                return MaterialPageRoute(
                  builder: (_) => AdminPage(
                    api: api,
                    portalProfile: api.portalProfile,
                    onMetaUpdated: (meta) => setState(() => _appMeta = meta),
                    initialView: AdminView.audits,
                    auditInitialTab: tab,
                    initialAuditReportYear: reportYear,
                  ),
                  settings: settings,
                );
              }

              return null;
            },
          );
        },
      ),
    );
  }
  } // <<< _MyAppState SAUBER geschlossen

class _InternalFooterButton extends StatelessWidget {
  const _InternalFooterButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Tooltip(
      message: 'DFS Internal',
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.onSurface.withOpacity(isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 16, color: scheme.onSurface.withOpacity(0.85)),
            const SizedBox(width: 6),
            Text(
              'DFS Internal',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================
// Interner Login-Screen (Kundenbereich)
// =======================
class _LoginScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenRep;
  final VoidCallback onOpenResetPassword;

  const _LoginScreen({
    required this.api,
    required this.onLoggedIn,
    required this.onOpenRegister,
    required this.onOpenAdmin,
    required this.onOpenRep,
    required this.onOpenResetPassword,
  });

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _email = TextEditingController();
  final _pw    = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _doLogin() async {
    setState(() { _busy = true; _err = null; });
    try {
      final result = await widget.api.login(_email.text.trim(), _pw.text); // Kunden-Login
      if (!mounted) return;
      if (result.ok) {
        widget.onLoggedIn();
      } else {
        final t = AppLocalizations.of(context)!;
        final err = result.revoked
            ? t.account_blocked
            : (result.statusCode == 401
                ? t.login_failed_check_credentials
                : (result.message?.isNotEmpty == true
                    ? result.message!
                    : t.invalid));
        setState(() => _err = err);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final canLogin = !_busy && _email.text.trim().isNotEmpty && _pw.text.isNotEmpty;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    InputDecoration _fieldDecoration(String label, {IconData? icon}) {
      return InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
        filled: true,
        fillColor: scheme.surfaceVariant.withOpacity(0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
    }

    Widget _hero() {
      return Column(
        children: [
          Opacity(
            opacity: 0.75,
            child: Image.asset(
              'assets/dfs_logo.png',
              height: 32,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.appTitle,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurface.withOpacity(0.7),
              letterSpacing: 0.2,
            ),
          ),
        ],
      );
    }

    Widget _loginCard() {
      return Card(
        elevation: 6,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset('assets/DFS_Connect.png', height: 52, fit: BoxFit.contain),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DFS Connect',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.customer_login,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withOpacity(0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _email,
                decoration: _fieldDecoration(t.email, icon: Icons.mail_outline),
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _pw,
                decoration: _fieldDecoration(t.password, icon: Icons.lock_outline),
                onSubmitted: (_) => canLogin ? _doLogin() : null,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              if (_err != null) ...[
                const SizedBox(height: 12),
                Text(_err!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: canLogin ? _doLogin : null,
                  icon: _busy
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(t.login),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_alt),
                  onPressed: _busy ? null : widget.onOpenRegister,
                  label: Text(t.register),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant.withOpacity(.3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant.withOpacity(.55)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_reset, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.forgot_password_button,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.forgot_password_instructions,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: _busy ? null : widget.onOpenResetPassword,
                            icon: const Icon(Icons.mail_outline),
                            label: Text(t.reset_password_request_action),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget _internalTiles() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final isTwoColumn = constraints.maxWidth >= 820;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.quick_access_title,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                t.quick_access_subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Flex(
                direction: isTwoColumn ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _InternalTile(
                      title: 'DFS Connect+',
                      subtitle: 'Mitarbeiterbereich mit allen internen Tools.',
                      logoPath: 'assets/DFS_Connect+.png',
                      badgeLabel: 'Intern',
                      buttonLabel: 'Zum Mitarbeiter-Login',
                      icon: Icons.lock_outline,
                      primary: true,
                      onPressed: widget.onOpenAdmin,
                    ),
                  ),
                  SizedBox(width: isTwoColumn ? 16 : 0, height: isTwoColumn ? 0 : 12),
                  Expanded(
                    child: _InternalTile(
                      title: t.rep_area ?? 'Vertreterbereich',
                      subtitle: 'Direkter Zugang zum Vertreter-Portal.',
                      icon: Icons.work_outline,
                      buttonLabel: 'Zum Vertreter-Login',
                      primary: false,
                      onPressed: widget.onOpenRep,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(),
        const SizedBox(height: 32),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: _loginCard(),
        ),
        const SizedBox(height: 32),
        _internalTiles(),
      ],
    );
  }
}

class _InternalTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? logoPath;
  final String? badgeLabel;
  final String buttonLabel;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  const _InternalTile({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.icon,
    required this.primary,
    required this.onPressed,
    this.logoPath,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (logoPath != null)
                Image.asset(logoPath!, height: 48, fit: BoxFit.contain)
              else
                Icon(icon, size: 26, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (badgeLabel != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          badgeLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: primary
                ? FilledButton.icon(
                    onPressed: onPressed,
                    icon: Icon(icon),
                    label: Text(buttonLabel),
                  )
                : OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: Icon(icon),
                    label: Text(buttonLabel),
                  ),
          ),
        ],
      ),
    );
  }
}
