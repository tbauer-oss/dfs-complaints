// lib/pages/dashboard_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';
import '../widgets/pdf_view_stub.dart'
  if (dart.library.html) '../widgets/pdf_view_web.dart';

const _labCatalogLinks = [
  _CatalogLink(
    label: 'DE / EN / IT',
    url: 'https://dfs-diamon.de/sites/default/public/instructions/pdfs/DFS-Labor-DE-US-2025-26_1.pdf',
    locales: {'de', 'en', 'it'},
  ),
  _CatalogLink(
    label: 'ES / FR',
    url: 'https://dfs-diamon.de/sites/default/public/instructions/pdfs/DFS-LaborES-FR-2025-26_0.pdf',
    locales: {'es', 'fr'},
  ),
];

const _dentCatalogLinks = [
  _CatalogLink(
    label: 'DE / EN',
    url: 'https://dfs-diamon.de/sites/default/public/instructions/pdfs/DFS-Praxis-DE-US-2025-2026_1.pdf',
    locales: {'de', 'en', 'it'},
  ),
  _CatalogLink(
    label: 'ES / FR',
    url: 'https://dfs-diamon.de/sites/default/public/instructions/pdfs/DFS-Praxis-ES-FR-2025-2026_1.pdf',
    locales: {'es', 'fr'},
  ),
];

_CatalogLink _catalogLinkForLocale(List<_CatalogLink> links, String localeCode) {
  final normalized = localeCode.toLowerCase();
  return links.firstWhere(
    (link) => link.matches(normalized),
    orElse: () => links.first,
  );
}

class DashboardPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLoggedOut;

  const DashboardPage({
    super.key,
    required this.api,
    required this.onLoggedOut,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
  MyRep? _myRep;
  String? _customerName;
  String? _customerEmail;
  bool _repLoading = false;
  bool _repRequested = false;
  int _hoverIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureRepOnce();
      _initCustomerName();
    });
    _initRep();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Falls Session erst nach Build restauriert wurde
    _ensureRepOnce();
  }

  Future<void> _initRep() async {
    if (_repLoading) return;
    setState(() => _repLoading = true);
    try {
      // Session ggf. herstellen
      if (widget.api.token == null || widget.api.token!.isEmpty) {
        await widget.api.restoreSession();
      }
      // Vertreter laden
      final rep = await widget.api.getMyRep(); // Backend: /api/rep/my (JWT)
      if (!mounted) return;
      setState(() => _myRep = rep);
    } catch (_) {
      // still
    } finally {
      if (mounted) setState(() => _repLoading = false);
    }
  }

  Future<void> _initCustomerName() async {
    Map<String, dynamic>? profile;

    try {
      // sicherstellen, dass eine Session existiert (Token aus LocalStorage holen)
      if (widget.api.token == null || widget.api.token!.isEmpty) {
        await widget.api.restoreSession();
      }

      // sauber über deine ApiClient-Methode
      profile = await widget.api.accountGet();
    } catch (_) {
      profile = null; // im Fehlerfall einfach leer lassen → Fallback greift
    }

    String? company;
    String? email;

    if (profile != null) {
      // typische Firmenschlüssel
      const companyKeys = [
        'company',
        'companyName',
        'firm',
        'firma',
        'organization',
        'organisation',
        'org',
        'customerCompany',
        'customer_name',
        'customer',
        'accountCompany',
      ];

      for (final k in companyKeys) {
        final v = profile[k];
        if (v is String) {
          final s = v.trim();
          if (s.isNotEmpty) {
            company = s;
            break;
          }
        }
      }

      // typische E-Mail-Schlüssel
      const emailKeys = [
        'email',
        'mail',
        'emailAddress',
        'email_address',
        'contactEmail',
        'customer_email',
      ];

      for (final k in emailKeys) {
        final v = profile[k];
        if (v is String) {
          final s = v.trim();
          if (s.isNotEmpty) {
            email = s;
            break;
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _customerName  = company;
        _customerEmail = email;
      });
    }
  }

  void _ensureRepOnce() {
    if (_myRep == null && !_repRequested) {
      _repRequested = true;
      _initRep();
    }
  }

  Future<void> _openMail(String email, String subject, String body) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': subject, 'body': body},
    );
    if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      // Fallback
    }
  }

  void _openRepContactForm(BuildContext context) {
    final rep = _myRep;
    if (rep == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RepContactPage(
          api: widget.api,
          rep: rep,
          customerCompany: _customerName,
          customerEmail: _customerEmail,
        ),
      ),
    );
  }

  // --- KOMPAKTE Variante (handy-optimiert, Name immer sichtbar) ---
  Widget _buildRepCardCompact(BuildContext context) {
    final theme = Theme.of(context);
    final t     = AppLocalizations.of(context)!;
    final r     = _myRep;
    final cs    = theme.colorScheme;
    final company = (_customerName ?? '').trim();

    // Kein Vertreter hinterlegt → dezenter Hinweis + Refresh
    if (r == null) {
      return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.withOpacity(.35)),
            color: Colors.grey.withOpacity(.07),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.business_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Zeige den Kundennamen (statt "DFS-Diamon GmbH")
                    Text(
                      company.isNotEmpty ? company : t.yourCompany,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // dezenter Hinweis, dass kein Vertreter zugewiesen ist
                    Text(
                      AppLocalizations.of(context)!.rep_not_assigned,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(.70),
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.refresh,
                onPressed: () {
                  _initRep();
                  _initCustomerName(); // falls sich was ändert
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        );
      }

    final first  = r.firstName.trim();
    final last   = r.lastName.trim();
    final email  = r.email.trim();
    final region = r.region.trim();
    final name   = [first, last].where((s) => s.isNotEmpty).join(' ');
    final title  = name.isNotEmpty ? t.rep_banner_title(name)
                                   : t.rep_banner_title(email.isNotEmpty ? email : '—');

    // Handy-optimiertes Layout: 1) Avatar + Textblock, 2) Aktionszeile darunter
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // kompakter Avatar
                const CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.handshake_outlined, size: 18),
                ),
                const SizedBox(width: 10),
                // Textblock darf platz fressen: 2 Zeilen Titel, 1 Zeile Sub
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Titel mit 2 Zeilen und Ellipsis
                      Text(
                        title,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.1, // engere Zeilenhöhe
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (email.isNotEmpty || region.isNotEmpty)
                        Text(
                          [if (email.isNotEmpty) email, if (region.isNotEmpty) region].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(.75),
                            height: 1.15,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // Aktionen unter dem Textblock → spart Breite, nichts schneidet ab
            const SizedBox(height: 8),
            Row(
              children: [
                if (email.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () => _openRepContactForm(context),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: Text(
                      t.rep_email_button,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: t.refresh,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: _initRep,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- GROSSE Variante (wie früher, optisch präsenter) ---
  Widget _buildRepCardLarge(BuildContext context) {
    final t      = AppLocalizations.of(context)!;
    final r      = _myRep;
    final cs = Theme.of(context).colorScheme;
    final company = (_customerName ?? '').trim();

    if (r == null) {
      // wie oben: Null-Hinweis
      return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF1976D2).withOpacity(0.14), const Color(0xFF42A5F5).withOpacity(0.10)],
            ),
            border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.5), width: 1),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1976D2)),
                child: const Icon(Icons.business_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.isNotEmpty ? company : t.yourCompany,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.rep_not_assigned,
                      style: TextStyle(color: cs.onSurface.withOpacity(.75), fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t.refresh,
                onPressed: () {
                  _initRep();
                  _initCustomerName();
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        );
      }
    
    final first  = r.firstName.trim();
    final last   = r.lastName.trim();
    final email  = r.email.trim();
    final region = r.region.trim();
    final name   = [first, last].where((s) => s.isNotEmpty).join(' ');
    final bannerTitle = name.isNotEmpty ? t.rep_banner_title(name)
                                        : t.rep_banner_title(email.isNotEmpty ? email : '—');

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1976D2).withOpacity(0.14),
              const Color(0xFF42A5F5).withOpacity(0.10),
            ],
          ),
          border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.5), width: 1),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1976D2)),
              child: const Icon(Icons.handshake_outlined, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bannerTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  if (email.isNotEmpty || region.isNotEmpty)
                    Text(
                      [if (email.isNotEmpty) email, if (region.isNotEmpty) region].join(' • '),
                      style: TextStyle(color: Colors.grey[800], fontSize: 13),
                    ),
                ],
              ),
            ),
            if (email.isNotEmpty)
              Tooltip(
                message: t.rep_email_tooltip,
                child: TextButton.icon(
                  onPressed: () => _openRepContactForm(context),
                  icon: const Icon(Icons.email_outlined),
                  label: Text(t.rep_email_button),
                ),
              ),
            IconButton(
              tooltip: t.refresh,
              onPressed: _initRep,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  // --- RESPONSIVE Umschalter: mobil kompakt, Desktop groß ---
  Widget _buildRepHeaderResponsive(BuildContext context) {
    // Breakpoint beliebig – 900px ist ein guter Desktop-Schwellenwert
    final isWide = MediaQuery.of(context).size.width >= 900;
    return isWide ? _buildRepCardLarge(context)
                  : _buildRepCardCompact(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final tiles = <_Entry>[
      _Entry(
        label: t.reportComplaint,
        icon: Icons.add_circle,
        colorA: const Color(0xFF1976D2),
        colorB: const Color(0xFF42A5F5),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ComplaintFormPage(api: widget.api),
          ));
        },
      ),
      _Entry(
        label: t.myComplaints,
        icon: Icons.list_alt,
        colorA: const Color(0xFF2E7D32),
        colorB: const Color(0xFF66BB6A),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MyComplaintsPage(api: widget.api),
          ));
        },
      ),
      _Entry(
        label: t.myAccount,
        icon: Icons.person,
        colorA: const Color(0xFF6A1B9A),
        colorB: const Color(0xFFAB47BC),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AccountPage(api: widget.api),
          ));
        },
      ),
      _Entry(
        label: t.supportTitle,
        icon: Icons.support_agent,
        colorA: const Color(0xFFAD1457),
        colorB: const Color(0xFFEC407A),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SupportPage(api: widget.api),
          ));
        },
      ),
    ];

    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final size = MediaQuery.of(ctx).size;
          final orientation = MediaQuery.of(ctx).orientation;
          final isPortrait = orientation == Orientation.portrait;
          final isPhone = size.width < 600;
          final bool compressedHeight = constraints.maxHeight < (isPhone ? 620 : 540);

          final double maxExtent = isPhone
              ? (isPortrait ? 160 : 200)
              : (size.width < 1024 ? 240 : 260);

          final double iconSize = isPhone ? 28 : 40;
          final double fontSize = isPhone ? 13.0 : 14.5;
          final double aspectRatio;
          if (compressedHeight) {
            aspectRatio = isPhone ? 1.18 : 1.15;
          } else {
            aspectRatio = isPhone ? 1.06 : 1.1;
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    sliver: SliverToBoxAdapter(
                      child: _buildRepHeaderResponsive(context),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final e = tiles[i];
                          final hovered = _hoverIndex == i;
                          return MouseRegion(
                            onEnter: (_) => setState(() => _hoverIndex = i),
                            onExit: (_) => setState(() => _hoverIndex = -1),
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 140),
                              scale: hovered ? 1.02 : 1.0,
                              child: _FancyTile(
                                label: e.label,
                                icon: e.icon,
                                colorA: e.colorA,
                                colorB: e.colorB,
                                iconSize: iconSize,
                                fontSize: fontSize,
                                onTap: e.onTap,
                              ),
                            ),
                          );
                        },
                        childCount: tiles.length,
                      ),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: aspectRatio,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      16 + MediaQuery.of(ctx).padding.bottom,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: const _CatalogButtons(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------- Komponenten ----------------

// (Optional weiterhin vorhanden – falls du sie anderswo nutzt.
// In dieser Datei wird _RepBanner jetzt nicht mehr verwendet.)
class _RepBanner extends StatelessWidget {
  final MyRep? rep;
  final bool loading;
  final VoidCallback onRefresh;
  final void Function(String email, String name) onEmailTap;

  const _RepBanner({
    required this.rep,
    required this.loading,
    required this.onRefresh,
    required this.onEmailTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (loading) {
      return Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.blue.withOpacity(.06),
          border: Border.all(color: const Color(0xFF1976D2).withOpacity(.35)),
        ),
        child: Row(
          children: const [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('…'),
          ],
        ),
      );
    }

    if (rep == null) {
      // Kein Vertreter hinterlegt → dezenter Hinweis + Refresh
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withOpacity(.35)),
          color: Colors.grey.withOpacity(.07),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_search_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(t.rep_not_assigned)),
            IconButton(
              tooltip: t.refresh,
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      );
    }

    final first = (rep!.firstName).trim();
    final last  = (rep!.lastName).trim();
    final email = (rep!.email).trim();
    final region = (rep!.region).trim();

    final name = [first, last].where((s) => s.isNotEmpty).join(' ');
    final bannerTitle = (name.isNotEmpty) ? t.rep_banner_title(name)
                                          : t.rep_banner_title(email.isNotEmpty ? email : '—');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1976D2).withOpacity(0.14),
            const Color(0xFF42A5F5).withOpacity(0.10),
          ],
        ),
        border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1976D2)),
            child: const Icon(Icons.handshake_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bannerTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                const SizedBox(height: 2),
                if (email.isNotEmpty || region.isNotEmpty)
                  Text(
                    [if (email.isNotEmpty) email, if (region.isNotEmpty) region].join(' • '),
                    style: TextStyle(color: Colors.grey[800], fontSize: 13),
                  ),
              ],
            ),
          ),
          if (email.isNotEmpty)
            Tooltip(
              message: t.rep_email_tooltip,
              child: TextButton.icon(
                onPressed: () {
                  final subject = Uri.encodeComponent(t.mail_subject_rep);
                  final body    = Uri.encodeComponent(t.mail_body_rep(name));
                  final mailto  = 'mailto:$email?subject=$subject&body=$body';
                  if (kIsWeb) {
                    html.window.open(mailto, '_self');
                   } else {
                    // Vorläufig: nichts tun oder Snackbar anzeigen
                    // Besser: url_launcher benutzen (siehe unten)
                  }
                },
                icon: const Icon(Icons.email_outlined),
                label: Text(t.rep_email_button),
              ),
            ),
          IconButton(
            tooltip: t.refresh,
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

// Dezente Katalog-Leiste: kompakte Darstellung mit nur einer passenden Sprache
// Dezente Katalog-Leiste: kompaktere Abstände & geringere Zeilenhöhe
class _CatalogButtons extends StatelessWidget {
  const _CatalogButtons();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPhone = MediaQuery.of(context).size.width < 600;
    final localeCode = Localizations.localeOf(context).languageCode.toLowerCase();

    Widget buildCard({
      required String title,
      required IconData icon,
      required String description,
      required List<_CatalogLink> links,
    }) {
      final link = _catalogLinkForLocale(links, localeCode);

      // etwas straffer gepolstert
      final padding = EdgeInsets.fromLTRB(
        isPhone ? 12 : 14,
        isPhone ? 8 : 10,
        isPhone ? 12 : 14,
        isPhone ? 10 : 12,
      );

      // engere Zeilenhöhen
      final titleStyle = theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: .2,
        height: 1.05, // straffer
      );
      final descStyle = theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurface.withOpacity(.75),
        height: 1.15, // weniger Zeilenabstand
      );
      final langStyle = theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurface.withOpacity(.6),
        fontStyle: FontStyle.italic,
        height: 1.10, // dezent
      );

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4), // war 6
        padding: padding,
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: isPhone ? 18 : 20, color: cs.onSurface.withOpacity(0.70)),
                const SizedBox(width: 10), // war 12
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: titleStyle),
                      const SizedBox(height: 2), // war 4
                      Text(description, style: descStyle),
                      const SizedBox(height: 2), // war 6
                      Text(link.label, style: langStyle),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6), // war 10
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PdfInAppPage(url: link.url, title: title),
                  ),
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: isPhone ? 10 : 12, // etwas kompakter
                  vertical: 6, // war 8
                ),
                textStyle: theme.textTheme.labelMedium,
                visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(t.catalog_open),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildCard(
          title: t.catalog_lab_title,
          description: '',
          icon: Icons.biotech_outlined,
          links: _labCatalogLinks,
        ),
        buildCard(
          title: t.catalog_dent_title,
          description: '',
          icon: Icons.medical_services_outlined,
          links: _dentCatalogLinks,
        ),
      ],
    );
  }
}

class _CatalogLink {
  final String label;
  final String url;
  final Set<String> locales;

  const _CatalogLink({
    required this.label,
    required this.url,
    required this.locales,
  });

  bool matches(String localeCode) => locales.contains(localeCode);
}

class _Entry {
  final String label;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final VoidCallback onTap;
  _Entry({
    required this.label,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.onTap,
  });
}

class _FancyTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final VoidCallback onTap;
  final double iconSize;
  final double fontSize;

  const _FancyTile({
    required this.label,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.onTap,
    required this.iconSize,
    required this.fontSize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colorA.withOpacity(0.92), colorB.withOpacity(0.92)],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            child: Stack(
              children: [
                Positioned(
                  top: 0, right: 0, left: 0, height: 46,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.00)],
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: iconSize + 20, height: iconSize + 20,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.28), width: 1),
                        ),
                        child: Icon(icon, size: iconSize, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: fontSize,
                          height: 1.15, letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RepContactPage extends StatefulWidget {
  final ApiClient api;
  final MyRep rep;
  final String? customerCompany;
  final String? customerEmail;

  const RepContactPage({
    super.key,
    required this.api,
    required this.rep,
    this.customerCompany,
    this.customerEmail,
  });

  @override
  State<RepContactPage> createState() => _RepContactPageState();
}

class _RepContactPageState extends State<RepContactPage> {
  final _firstName = TextEditingController();
  final _lastName  = TextEditingController();
  final _subject   = TextEditingController();
  final _message   = TextEditingController();

  bool _sending = false;
  bool _dirty   = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_firstName, _lastName, _subject, _message]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!_dirty &&
        (_firstName.text.isNotEmpty ||
         _lastName.text.isNotEmpty ||
         _subject.text.isNotEmpty ||
         _message.text.isNotEmpty)) {
      setState(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _subject, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_dirty) return true;
    final t = AppLocalizations.of(context)!;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.rep_contact_discard_title),
        content: Text(t.rep_contact_discard_text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.yes),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _handleCancel() async {
    final ok = await _confirmLeaveIfDirty();
    if (ok && mounted) {
      Navigator.of(context).pop(); // zurück zum Dashboard
    }
  }

  Future<void> _handleSend() async {
    final t = AppLocalizations.of(context)!;
    final subject = _subject.text.trim();
    final msg     = _message.text.trim();

    if (subject.isEmpty || msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_validation)),
      );
      return;
    }

    final repEmail = widget.rep.email.trim();
    if (repEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_no_rep_email)),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final company      = (widget.customerCompany ?? '').trim();
      final companyEmail = (widget.customerEmail ?? '').trim();

      final payload = <String, dynamic>{
        'repEmail'        : repEmail,
        'repFirstName'    : widget.rep.firstName,
        'repLastName'     : widget.rep.lastName,
        'company'         : company,
        'companyEmail'    : companyEmail,
        'contactFirstName': _firstName.text.trim(),
        'contactLastName' : _lastName.text.trim(),
        'subject'         : subject,
        'message'         : msg,
      };

      // 🔴 Jetzt: Versand über dein Backend mit Kunden-Bearer-Token
      await widget.api.sendRepContact(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_sent)),
      );
      Navigator.of(context).pop(); // zurück zum Dashboard
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.rep_contact_error} (${e.message})')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_contact_error)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t     = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    final company      = (widget.customerCompany ?? '').trim();
    final companyEmail = (widget.customerEmail ?? '').trim();
    final firstRep     = widget.rep.firstName.trim();
    final lastRep      = widget.rep.lastName.trim();

    return WillPopScope(
      onWillPop: _confirmLeaveIfDirty,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.rep_contact_title),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.rep_contact_intro(firstRep, lastRep),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(.8),
                ),
              ),
              const SizedBox(height: 16),
              // Firmenname (read-only)
              TextFormField(
                initialValue: company.isNotEmpty ? company : t.yourCompany,
                enabled: false,
                decoration: InputDecoration(
                  labelText: t.rep_contact_company_label,
                  prefixIcon: const Icon(Icons.business),
                ),
              ),
              const SizedBox(height: 12),
              // Firmen-E-Mail (read-only)
              TextFormField(
                initialValue: companyEmail,
                enabled: false,
                decoration: InputDecoration(
                  labelText: t.rep_contact_company_email_label,
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _firstName,
                      decoration: InputDecoration(
                        labelText: t.firstName,
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lastName,
                      decoration: InputDecoration(
                        labelText: t.lastName,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subject,
                decoration: InputDecoration(
                  labelText: t.rep_contact_subject_label,
                  prefixIcon: const Icon(Icons.subject),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: t.rep_contact_message_label,
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.message_outlined),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sending ? null : _handleCancel,
                      child: Text(t.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _handleSend,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(t.send),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
