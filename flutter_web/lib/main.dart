// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show rootBundle;

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
  bool _showInternal = false;
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
    try { html.document.title = 'DFS Complaints'; } catch (_) {}

    // prefs global verfügbar machen
    return AppPrefsScope(
      notifier: _prefs,
      child: Builder(
        builder: (scopeCtx) {
          final prefs = AppPrefsScope.of(scopeCtx);

          return MaterialApp(
            title: 'DFS Complaints',
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
                              return SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: minHeight),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 920),
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _LoginScreen(
                                              api: api,
                                              onLoggedIn: _onLoggedIn,
                                              onOpenRegister: () => _openRegister(ctx),
                                              onOpenAdmin: () => _openAdmin(ctx),
                                              onOpenRep: () => _openRepArea(ctx), // -> /repLogin
                                              onOpenResetPassword: () => _openResetPassword(ctx),
                                            ),
                                            const SizedBox(height: 18),
                                            Align(
                                              alignment: Alignment.center,
                                              child: TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: scheme.onSurfaceVariant,
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                ),
                                                onPressed: () => setState(() => _showInternal = !_showInternal),
                                                icon: Icon(
                                                  _showInternal
                                                      ? Icons.keyboard_arrow_up_rounded
                                                      : Icons.keyboard_arrow_down_rounded,
                                                  size: 22,
                                                ),
                                                label: Text(
                                                  _showInternal ? 'DFS intern ausblenden' : 'DFS intern anzeigen',
                                                  style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            AnimatedSize(
                                              duration: const Duration(milliseconds: 220),
                                              curve: Curves.easeInOut,
                                              child: _showInternal
                                                  ? Container(
                                                      width: double.infinity,
                                                      padding: const EdgeInsets.all(22),
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment.topLeft,
                                                          end: Alignment.bottomRight,
                                                          colors: [
                                                            scheme.primary.withOpacity(isDark ? 0.18 : 0.22),
                                                            scheme.surfaceVariant.withOpacity(isDark ? 0.45 : 0.35),
                                                          ],
                                                        ),
                                                        borderRadius: BorderRadius.circular(20),
                                                        border: Border.all(
                                                          color: scheme.outlineVariant.withOpacity(isDark ? 0.7 : 0.9),
                                                        ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
                                                            blurRadius: 20,
                                                            offset: const Offset(0, 12),
                                                          ),
                                                        ],
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.center,
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                                                            decoration: BoxDecoration(
                                                              color: scheme.surface.withOpacity(0.7),
                                                              borderRadius: BorderRadius.circular(30),
                                                              border: Border.all(color: scheme.primary.withOpacity(0.4)),
                                                            ),
                                                            child: Text(
                                                              'DFS',
                                                              style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                                                                    letterSpacing: 0.8,
                                                                    fontWeight: FontWeight.w700,
                                                                    color: scheme.primary,
                                                                  ),
                                                            ),
                                                          ),
                                                          const SizedBox(height: 12),
                                                          Text(
                                                            t.quick_access_title,
                                                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                                                  fontWeight: FontWeight.w800,
                                                                  color: scheme.onSurface,
                                                                ),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                          const SizedBox(height: 8),
                                                          Text(
                                                            t.quick_access_subtitle,
                                                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                                                  color: scheme.onSurfaceVariant,
                                                                ),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                          const SizedBox(height: 18),
                                                          Wrap(
                                                            spacing: 12,
                                                            runSpacing: 12,
                                                            alignment: WrapAlignment.center,
                                                            children: [
                                                              FilledButton(
                                                                onPressed: () => _openRepArea(ctx),
                                                                style: FilledButton.styleFrom(
                                                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                                                  shape: const StadiumBorder(),
                                                                  backgroundColor: scheme.primary,
                                                                  foregroundColor: scheme.onPrimary,
                                                                  elevation: 0,
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    Text(t.rep_area ?? 'Vertreterbereich'),
                                                                    const SizedBox(width: 8),
                                                                    const Icon(Icons.chevron_right_rounded, size: 20),
                                                                  ],
                                                                ),
                                                              ),
                                                              OutlinedButton(
                                                                onPressed: () => _openAdmin(ctx),
                                                                style: OutlinedButton.styleFrom(
                                                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                                                  shape: const StadiumBorder(),
                                                                  side: BorderSide(color: scheme.outlineVariant.withOpacity(0.9)),
                                                                  foregroundColor: scheme.onSurface,
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    Text(t.admin_area ?? 'DFS Portal'),
                                                                    const SizedBox(width: 8),
                                                                    Icon(Icons.arrow_outward_rounded, color: scheme.primary, size: 20),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomNavigationBar: LegalFooter(api: api),
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

              return null;
            },
          );
        },
      ),
    );
  }
} // <<< _MyAppState SAUBER geschlossen

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

  // robustes Asset-Checking (SVG → PNG → Text)
  Future<bool> _assetExists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }

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

    return Card(
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    height: 40,
                    child: FutureBuilder<bool>(
                      future: _assetExists('assets/dfs_logo.svg'),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.done && (snap.data ?? false)) {
                          return SvgPicture.asset('assets/dfs_logo.svg', height: 40);
                        }
                        return Image.asset(
                          'assets/dfs_logo.png',
                          height: 40,
                          filterQuality: FilterQuality.high,
                          isAntiAlias: true,
                          errorBuilder: (_, __, ___) => const Text('DFS'),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      t.customer_login,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity(0.6)),
              const SizedBox(height: 14),

              TextField(
                controller: _email,
                decoration: InputDecoration(
                  labelText: t.email,
                  border: const OutlineInputBorder(),
                ),
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _pw,
                decoration: InputDecoration(
                  labelText: t.password,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => canLogin ? _doLogin() : null,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),

              if (_err != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_err!, style: const TextStyle(color: Colors.red)),
                ),
              ],

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canLogin ? _doLogin : null,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.login),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_alt),
                  onPressed: _busy ? null : widget.onOpenRegister,
                  label: Text(t.register),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withOpacity(.6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_reset, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.forgot_password_button,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.forgot_password_instructions,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy ? null : widget.onOpenResetPassword,
                      icon: const Icon(Icons.mail_outline),
                      label: Text(t.reset_password_request_action),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
