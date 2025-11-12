// lib/main.dart
import 'dart:math' as math;
import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'api/client.dart';
import 'l10n/app_localizations.dart';
import 'services/app_prefs.dart';
import 'services/app_prefs_scope.dart';
import 'services/push_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;

// Seiten
import 'pages/register_page.dart';
import 'pages/admin_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/rep_login_page.dart';
import 'pages/rep_dashboard_page.dart' hide ThemeAction;
import 'pages/legal_privacy_page.dart';
import 'pages/legal_imprint_page.dart';
import 'widgets/legal_footer.dart';

// Widgets
import 'widgets/lang_action.dart';
import 'widgets/theme_action.dart' as w;

// ===== THEME BRANDING ===== //
// DFS-Blau leicht heller und lebendiger (dezent medizinisch/vertrauenswürdig)
const kBrandSeed = Color(0xFF0A4FA3);

ThemeData _lightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandSeed,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    typography: Typography.material2021(),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    // <-- geändert: CardThemeData
    cardTheme: CardThemeData(
      color: scheme.surface.withOpacity(0.75),
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: scheme.primary.withOpacity(.15),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        elevation: 2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: BorderSide(color: scheme.outline),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withOpacity(.75),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.8)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // <-- geändert: DialogThemeData
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh.withOpacity(.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    // <-- geändert: MaterialStatePropertyAll
    checkboxTheme: CheckboxThemeData(fillColor: MaterialStatePropertyAll(scheme.primary)),
    radioTheme: RadioThemeData(fillColor: MaterialStatePropertyAll(scheme.primary)),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStatePropertyAll(scheme.primary),
      trackColor: MaterialStatePropertyAll(scheme.primary.withOpacity(.35)),
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
    visualDensity: VisualDensity.standard,
    typography: Typography.material2021(),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    // <-- geändert: CardThemeData
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHigh.withOpacity(.7),
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: scheme.primary.withOpacity(.18),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        elevation: 2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: scheme.onSecondaryContainer,
        backgroundColor: scheme.secondaryContainer,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh.withOpacity(.7),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.9)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // <-- geändert: DialogThemeData
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh.withOpacity(.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    // <-- geändert: MaterialStatePropertyAll
    checkboxTheme: CheckboxThemeData(fillColor: MaterialStatePropertyAll(scheme.primary)),
    radioTheme: RadioThemeData(fillColor: MaterialStatePropertyAll(scheme.primary)),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStatePropertyAll(scheme.primary),
      trackColor: MaterialStatePropertyAll(scheme.primary.withOpacity(.35)),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  if (html.window.navigator.userAgent.contains('Chrome')) {
    if (kIsWeb) {
      html.window.addEventListener('beforeinstallprompt', (event) {
        final deferredPrompt = event; // dynamic
      });
      if (kIsWeb) {
        try { html.document.title = 'DFS Complaints'; } catch (_) {}
      }
    }
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
  final push = PushNotifications.instance;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final _prefs = AppPrefs(); // zentrale Quelle für Theme & Locale

  bool _bootDone = false;
  bool _loggedIn = false; // Kundenlogin (token) steuert den Kunden-Flow

  // ---- Helpers ----
  bool get _customerLoggedIn => (api.token != null && api.token!.isNotEmpty);
  bool get _repLoggedIn => (api.repToken != null && api.repToken!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _prefs.load();        // Theme & Sprache laden (triggert Rebuild)
    _boot();              // Session-Logik
  }

  Future<void> _boot() async {
    await api.restoreSession();
    await api.ensureRepSession(); // invalides repToken nach Deploys o.ä. wegräumen
    final wasLoggedIn = _customerLoggedIn;
    setState(() {
      _loggedIn = wasLoggedIn; // Kunden-Flow bleibt unabhängig vom Vertreter-Flow
      _bootDone = true;
    });
    if (wasLoggedIn) {
      await push.setup(api, languageCode: _prefs.locale?.languageCode);
    }
  }

  Future<void> _openAdmin(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: api.adminSecret ?? '');
    final wantOpen = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.admin_area),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Admin Passwort',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.open)),
        ],
      ),
    );

    if (wantOpen != true) return;

    final secret = ctrl.text.trim();
    if (secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.required_fields)),
      );
      return;
    }

    final ok = await api.validateAdminSecret(secret);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.errorGeneric('Admin Passwort'))),
      );
      return;
    }

    api.setAdminSecret(secret);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPage(api: api)));
  }

  void _openRegister(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterPage(api: api)));
  }

  void _openRepArea(BuildContext ctx) {
    Navigator.of(ctx).pushNamed('/repLogin');
  }

  void _onLoggedIn() {
    setState(() => _loggedIn = true);   // Kundenlogin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      push.setup(api, languageCode: _prefs.locale?.languageCode);
    });
  }
  void _onLoggedOut() => setState(() => _loggedIn = false); // Kundenlogout

  @override
  Widget build(BuildContext context) {
    if (!_bootDone) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Web-Tab-Titel setzen (failsafe)
    if (kIsWeb) {
      try { html.document.title = 'DFS Complaints'; } catch (_) {}
    }

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
            supportedLocales: const [
              Locale('de'), Locale('en'), Locale('fr'), Locale('it'), Locale('es'),
            ],
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
                  for (final s in supported) {
                    if (s.languageCode.toLowerCase() == loc.languageCode.toLowerCase()) {
                      return s;
                    }
                  }
                }
              }
              return const Locale('de');
            },

            // ---- Theme ----
            themeMode: prefs.themeMode,
            theme: _lightTheme(),
            darkTheme: _darkTheme(),

            // ---- Routing ----
            initialRoute: '/',
            routes: {
              // Root / Startseite: Kunden-Flow
              '/': (_) => Builder(
                    builder: (ctx) {
                      final t = AppLocalizations.of(ctx)!;

                      // Kunde eingeloggt -> Dashboard
                      if (_loggedIn) {
                        return _ScaffoldWithAnimatedBackground(
                          appBar: AppBar(
                            title: Text(t.appTitle),
                            actions: [
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
                                      await push.deactivate(api);
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
                          body: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 0),
                              child: DashboardPage(api: api, onLoggedOut: _onLoggedOut),
                            ),
                          ),
                          footer: const SizedBox.shrink(),
                        );
                      }

                      // Kunde NICHT eingeloggt -> Startseite (Login)
                      return _LoginLanding(
                        prefs: prefs,
                        api: api,
                        onOpenRegister: () => _openRegister(ctx),
                        onOpenAdmin: () => _openAdmin(ctx),
                        onOpenRep: () => _openRepArea(ctx),
                        onLoggedIn: _onLoggedIn,
                      );
                    },
                  ),

              // Vertreter-Login
              '/repLogin': (_) => RepLoginPage(api: api),
              // Vertreter-Dashboard
              '/rep': (_) => RepDashboardPage(api: api),
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

              return null;
            },
          );
        },
      ),
    );
  }
} // <<< _MyAppState

// ------------------------
// Dekor: Animierter „Aurora“-Hintergrund mit weichen Blobs
// ------------------------
class _AuroraBackground extends StatefulWidget {
  final bool dense;
  const _AuroraBackground({this.dense = false});

  @override
  State<_AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<_AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.brightness == Brightness.dark
        ? [scheme.surface, scheme.surfaceContainerHighest]
        : [const Color(0xFFEFF4FB), Colors.white];

    final blobColorA = scheme.primary.withOpacity(.18);
    final blobColorB = scheme.tertiary.withOpacity(.12);
    final blobColorC = scheme.secondary.withOpacity(.14);

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return CustomPaint(
          painter: _GradientPainter(base: base, t: t),
          child: Stack(
            children: [
              _movingBlob(
                size: widget.dense ? 220 : 320,
                color: blobColorA,
                alignment: Alignment(
                  math.sin(t * math.pi * 2) * .7,
                  math.cos(t * math.pi * 2) * .6,
                ),
              ),
              _movingBlob(
                size: widget.dense ? 180 : 260,
                color: blobColorB,
                alignment: Alignment(
                  math.cos(t * math.pi * 2 + 1.2) * .8,
                  math.sin(t * math.pi * 2 + .8) * .7,
                ),
              ),
              _movingBlob(
                size: widget.dense ? 140 : 220,
                color: blobColorC,
                alignment: Alignment(
                  math.sin(t * math.pi * 2 + .4) * .9,
                  math.sin(t * math.pi * 2 + 1.0) * .9,
                ),
              ),
              // Leichte „Glass“-Überlagerung
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _movingBlob({
    required double size,
    required Color color,
    required Alignment alignment,
  }) {
    return AnimatedAlign(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _GradientPainter extends CustomPainter {
  final List<Color> base;
  final double t;
  _GradientPainter({required this.base, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment(0, -1 + .2 * math.sin(t * 2 * math.pi)),
      end: Alignment(0, 1),
      colors: base,
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.base != base;
  }
}

// ------------------------
// Gemeinsamer Scaffold-Wrapper mit animiertem Hintergrund
// ------------------------
class _ScaffoldWithAnimatedBackground extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget footer;

  const _ScaffoldWithAnimatedBackground({
    this.appBar,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AuroraBackground(dense: true),
          // leichter Randabstand für Inhalte
          Positioned.fill(
            child: SafeArea(
              child: body,
            ),
          ),
        ],
      ),
      bottomNavigationBar: footer,
    );
  }
}

// ------------------------
// Landing mit Login + dezentem „Hero“-Header
// ------------------------
class _LoginLanding extends StatelessWidget {
  final AppPrefs prefs;
  final ApiClient api;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenRep;
  final VoidCallback onLoggedIn;

  const _LoginLanding({
    required this.prefs,
    required this.api,
    required this.onOpenRegister,
    required this.onOpenAdmin,
    required this.onOpenRep,
    required this.onLoggedIn,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      // WICHTIG: damit bei Tastatur nichts überläuft
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(t.appTitle),
        actions: [
          LangAction(onLocaleChanged: (l) => prefs.setLang(l.languageCode)),
          w.ThemeAction(),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AuroraBackground(),
          // Scrollbare Fläche (verhindert Overflow, auch mit Tastatur)
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(22, 22, 22, 22 + bottomInset),
                    physics: const BouncingScrollPhysics(),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // (Überschrift/Claim entfernt!)
                            // Abstand oben für Luft
                            const SizedBox(height: 4),

                            // Login-Karte (Logik unverändert)
                            _LoginScreen(
                              api: api,
                              onLoggedIn: onLoggedIn,
                              onOpenRegister: onOpenRegister,
                              onOpenAdmin: onOpenAdmin,
                              onOpenRep: onOpenRep,
                            ),

                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                t.more_areas,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Buttons bleiben wie gehabt – jetzt aber sicher in der ScrollView
                            LayoutBuilder(
                              builder: (context, c) {
                                final isNarrow = c.maxWidth < 560;
                                if (isNarrow) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      FilledButton.tonalIcon(
                                        icon: const Icon(Icons.handshake),
                                        label: Text(t.rep_area ?? t.rep_area),
                                        onPressed: onOpenRep,
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: const StadiumBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.admin_panel_settings),
                                        label: Text(t.admin_area),
                                        onPressed: onOpenAdmin,
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: const StadiumBorder(),
                                        ),
                                      ),
                                    ],
                                  );
                                } else {
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          icon: const Icon(Icons.handshake),
                                          label: Text(t.rep_area ?? 'Vertreterbereich'),
                                          onPressed: onOpenRep,
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: const StadiumBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          icon: const Icon(Icons.admin_panel_settings),
                                          label: Text(t.admin_area),
                                          onPressed: onOpenAdmin,
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: const StadiumBorder(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }
                              },
                            ),

                            // etwas Extra-Platz unten
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: LegalFooter(api: api),
    );
  }
}

class _HeaderHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) {
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant.withOpacity(.6)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surface.withOpacity(.55),
                    scheme.surfaceContainerHigh.withOpacity(.65),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_moon_rounded, size: 28, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      // kurzer Claim – neutral, seriös
                      'Quality & Compliance — Dental Medical Devices',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =======================
// Interner Login-Screen (Kundenbereich) – Logik unverändert
// =======================
class _LoginScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedIn;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenRep;

  const _LoginScreen({
    required this.api,
    required this.onLoggedIn,
    required this.onOpenRegister,
    required this.onOpenAdmin,
    required this.onOpenRep,
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
      final ok = await widget.api.login(_email.text.trim(), _pw.text); // Kunden-Login
      if (!mounted) return;
      if (ok) {
        widget.onLoggedIn();
      } else {
        setState(() => _err = AppLocalizations.of(context)!.invalid);
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
      elevation: 10,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    height: 42,
                    child: FutureBuilder<bool>(
                      future: _assetExists('assets/dfs_logo.svg'),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.done && (snap.data ?? false)) {
                          return SvgPicture.asset('assets/dfs_logo.svg', height: 42);
                        }
                        return Image.asset(
                          'assets/dfs_logo.png',
                          height: 42,
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
              const SizedBox(height: 10),
              Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity(0.6)),
              const SizedBox(height: 14),

              TextField(
                controller: _email,
                decoration: InputDecoration(
                  labelText: t.email,
                ),
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pw,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.password,
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

              const SizedBox(height: 16),

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
            ],
          ),
        ),
      ),
    );
  }
}
