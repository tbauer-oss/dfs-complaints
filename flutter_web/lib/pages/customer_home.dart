// lib/pages/customer_home_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

// Bedingter Web-Compat-Import statt 'dart:html', damit Android/iOS Builds nicht brechen
import 'package:flutter_web/web_compat/html_stub.dart'
  if (dart.library.html) 'package:flutter_web/web_compat/html_web.dart' as html;

import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';
import 'customer_news_page.dart';
import 'knowledge_base_page.dart';

/// Dezenter, Web-only PWA-Install-Button (zeigt sich nur, wenn möglich).
class InstallPwaButton extends StatefulWidget {
  const InstallPwaButton({super.key});
  @override
  State<InstallPwaButton> createState() => _InstallPwaButtonState();
}

class _InstallPwaButtonState extends State<InstallPwaButton> {
  bool _canInstall = false;

  @override
  void initState() {
    super.initState();
    try {
      _canInstall = (html.window as dynamic).__pwaCanInstall == true;
      html.window.addEventListener('pwa-can-install', (_) {
        if (mounted) setState(() => _canInstall = true);
      });
    } catch (_) {
      // auf Nicht-Web (oder ohne Event) ruhig ignorieren
      _canInstall = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canInstall) return const SizedBox.shrink();

    return FilledButton.icon(
      icon: const Icon(Icons.download),
      label: Flexible(
        child: Text(
          t?.installApp ?? 'App installieren',
          textAlign: TextAlign.center,
        ),
      ),
      onPressed: () async {
        try {
          final accepted =
              await (html.window as dynamic).showInstallPrompt() as bool? ?? false;
          if (!accepted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t?.installCanceled ?? 'Installation abgebrochen.')),
            );
          }
        } catch (_) {
          // still, no-op
        }
      },
    );
  }
}

class CustomerHomePage extends StatelessWidget {
  final ApiClient api;
  const CustomerHomePage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    // DFS-Blau (#0865A2) dezent einmischen (ohne CI zu überfahren)
    final dfsBlue = const Color(0xFF0865A2);

    final buttonStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(0, 56),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    );

    Widget buildAction({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      String? semantics,
    }) {
      final btn = ElevatedButton.icon(
        style: buttonStyle,
        onPressed: onTap,
        icon: Icon(icon),
        label: Flexible(
          child: Text(label, textAlign: TextAlign.center),
        ),
      );
      return Semantics(
        button: true,
        label: semantics ?? label,
        child: btn,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.customer_area),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final isWide = maxW >= 900;
          final contentWidth = math.min(maxW, 1100.0);

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: contentWidth),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _HeaderHero(
                      title: t.customer_area,
                      subtitle: t.customer_area_subtitle ??
                          'Schnell, sicher und konform: Reklamation melden, Vorgänge im Blick behalten und Support erhalten.',
                      dfsBlue: dfsBlue,
                    ),
                  ),

                  // Abstand
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // Kachelbereich (Card) – klar, ruhig, hochwertig
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        color: theme.brightness == Brightness.light
                            ? color.surface
                            : color.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // dezente Sektion-Überschrift
                              Row(
                                children: [
                                  Icon(Icons.dashboard_customize,
                                      color: dfsBlue.withOpacity(0.9)),
                                  const SizedBox(width: 10),
                                  Text(
                                    t.quick_actions ??
                                        'Schnellzugriff',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  const InstallPwaButton(), // zeigt sich nur, wenn möglich
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Responsive Wrap der Buttons
                              LayoutBuilder(
                                builder: (context, c) {
                                  final w = c.maxWidth;
                                  final targetWidth = w >= 700 ? 320.0 : 280.0;

                                  return Center(
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 16,
                                      runSpacing: 16,
                                      children: [
                                        SizedBox(
                                          width: targetWidth,
                                          child: buildAction(
                                            icon: Icons.add_circle_outline,
                                            label: t.reportComplaint,
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ComplaintFormPage(api: api),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: targetWidth,
                                          child: buildAction(
                                            icon: Icons.list_alt,
                                            label: t.myComplaints,
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      MyComplaintsPage(api: api),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: targetWidth,
                                          child: buildAction(
                                            icon: Icons.person,
                                            label: t.myAccount,
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      AccountPage(api: api),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: targetWidth,
                                          child: buildAction(
                                            icon: Icons.support_agent,
                                            label: t.supportTitle,
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      SupportPage(api: api),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: targetWidth,
                                          child: buildAction(
                                            icon: Icons.menu_book_outlined,
                                            label: t.knowledgeBaseTile ??
                                                'Knowledge base (FAQ)',
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      KnowledgeBasePage(api: api),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: targetWidth,
                                          child: buildAction(
                                            icon: Icons.campaign_outlined,
                                            label: t.customerNewsTile ?? 'Neuigkeiten & Updates',
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      CustomerNewsPage(api: api),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              // dezente Fußzeile im Card – Vertrauen/Compliance, nicht aufdringlich
                              _ComplianceFooter(dfsBlue: dfsBlue),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Header mit sehr zurückhaltendem, hochwertigen Verlauf und leichtem „Dental“-Akzent.
/// Kein Bild nötig – wirkt in Hell & Dunkel sauber.
class _HeaderHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color dfsBlue;

  const _HeaderHero({
    required this.title,
    required this.subtitle,
    required this.dfsBlue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              (theme.brightness == Brightness.light
                      ? dfsBlue
                      : dfsBlue.withOpacity(0.9))
                  .withOpacity(0.08),
              cs.surfaceContainerHighest.withOpacity(0.0),
            ],
          ),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Row(
            children: [
              // Icon-Kreis als dezentes Markenzeichen
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dfsBlue.withOpacity(0.12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.health_and_safety,
                  color: dfsBlue.withOpacity(0.9),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              // Texte
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        color: theme.textTheme.bodyMedium?.color
                            ?.withOpacity(0.85),
                      ),
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

/// Kleiner, seriöser Compliance-Hinweis in der Karte – unaufdringlich.
class _ComplianceFooter extends StatelessWidget {
  final Color dfsBlue;
  const _ComplianceFooter({required this.dfsBlue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
    );

    return Row(
      children: [
        Icon(Icons.verified_user, size: 18, color: dfsBlue.withOpacity(0.9)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            // bewusst generisch gehalten, damit in allen Sprachen nutzbar –
            // kann über ARB noch weiter lokalisiert werden
            'Datenschutz & Konformität nach geltenden Regularien. '
            'Sichere Übertragung und verantwortungsvoller Umgang mit Informationen.',
            style: muted,
          ),
        ),
      ],
    );
  }
}
