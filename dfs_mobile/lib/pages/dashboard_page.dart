// lib/pages/dashboard_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;
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

/// =====================
/// Brand & UI constants
/// =====================

const _dfsBlue = Color(0xFF0865A2); // DFS-Blau (RGB 8,101,162)
const _dfsBlueDark = Color(0xFF074E7E);
const _tileRadius = 16.0;
const _cardRadius = 14.0;

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
    label: 'DE / EN / IT',
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
  bool _repLoading = false;
  bool _repRequested = false; // verhindert mehrfaches Nachladen
  int _hoverIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureRepOnce());
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
      if (widget.api.token == null || widget.api.token!.isEmpty) {
        await widget.api.restoreSession();
      }
      final rep = await widget.api.getMyRep(); // Backend: /api/rep/my (JWT)
      if (!mounted) return;
      setState(() => _myRep = rep);
    } catch (_) {
      // still
    } finally {
      if (mounted) setState(() => _repLoading = false);
    }
  }

  void _ensureRepOnce() {
    if (_myRep == null && !_repRequested) {
      _repRequested = true;
      _initRep();
    }
  }

  // --- mailto an Vertreter öffnen (mit Betreff + Body aus i18n) ---
  void _mailToRep(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final r = _myRep;
    if (r == null || (r.email).trim().isEmpty) return;

    final first = r.firstName.trim();
    final last  = r.lastName.trim();
    final name  = [first, last].where((s) => s.isNotEmpty).join(' ');

    final subject = Uri.encodeComponent(t.mail_subject_rep);
    final body    = Uri.encodeComponent(t.mail_body_rep(name));
    final mailto  = 'mailto:${r.email}?subject=$subject&body=$body';

    if (kIsWeb) {
      html.window.open(mailto, '_self');
    } else {
      // fallback: kurze Info (Launcher kann optional später ergänzt werden)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.rep_email_tooltip)),
      );
    }
  }

  Future<void> _openMail(String email, String subject, String body) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': subject, 'body': body},
    );
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  // ------------------ VISUELLE KOMPONENTEN ------------------

  // Dezente Infokarte (Kompakt) – mobil & schmale Layouts
  Widget _buildRepCardCompact(BuildContext context) {
    final theme  = Theme.of(context);
    final t      = AppLocalizations.of(context)!;
    final r      = _myRep;
    final name   = (r == null) ? '' : [r.firstName.trim(), r.lastName.trim()].where((s) => s.isNotEmpty).join(' ');
    final email  = (r?.email ?? '').trim();
    final region = (r?.region ?? '').trim();

    if (r == null) {
      return _InfoHintCard(
        icon: Icons.person_search_outlined,
        text: t.rep_not_assigned,
        trailing: IconButton(
          tooltip: t.refresh,
          onPressed: _initRep,
          icon: const Icon(Icons.refresh),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardRadius)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        leading: _MonoBadge(icon: Icons.handshake_outlined),
        title: Text(
          t.rep_banner_title(name.isNotEmpty ? name : email),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [if (email.isNotEmpty) email, if (region.isNotEmpty) region].join(' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (email.isNotEmpty)
              IconButton(
                tooltip: t.rep_email_tooltip,
                icon: const Icon(Icons.mail_outline),
                onPressed: () => _mailToRep(context),
              ),
            IconButton(
              tooltip: t.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: _initRep,
            ),
          ],
        ),
      ),
    );
  }

  // Größere Infokarte – Desktop & breite Layouts
  Widget _buildRepCardLarge(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final r = _myRep;

    if (r == null) {
      return _InfoHintCard(
        icon: Icons.person_search_outlined,
        text: t.rep_not_assigned,
        trailing: IconButton(
          tooltip: t.refresh,
          onPressed: _initRep,
          icon: const Icon(Icons.refresh),
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: _dfsBlue.withOpacity(.06),
        border: Border.all(color: _dfsBlue.withOpacity(.25)),
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          _MonoBadge(color: _dfsBlue, icon: Icons.handshake_outlined),
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
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
              ],
            ),
          ),
          if (email.isNotEmpty)
            Tooltip(
              message: t.rep_email_tooltip,
              child: TextButton.icon(
                onPressed: () => _mailToRep(context),
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
    );
  }

  // Responsive Umschalter
  Widget _buildRepHeaderResponsive(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return isWide ? _buildRepCardLarge(context)
                  : _buildRepCardCompact(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    // Haupt-Aktionen (ohne Logikänderung)
    final tiles = <_Entry>[
      _Entry(
        label: t.reportComplaint,
        icon: Icons.add_circle,
        colorA: _dfsBlue,
        colorB: _dfsBlueDark,
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
        colorB: const Color(0xFF1E5B23),
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
        colorB: const Color(0xFF53207B),
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
        colorB: const Color(0xFF7C0F3F),
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
              ? (isPortrait ? 150 : 190)
              : (size.width < 1024 ? 230 : 250);

          final double iconSize = isPhone ? 26 : 36;
          final double fontSize = isPhone ? 13.0 : 14.0;
          final double aspectRatio = compressedHeight
              ? (isPhone ? 1.14 : 1.12)
              : (isPhone ? 1.06 : 1.1);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: CustomScrollView(
                slivers: [
                  // Vertreter / Info
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    sliver: SliverToBoxAdapter(
                      child: _buildRepHeaderResponsive(context),
                    ),
                  ),

                  // Aktionskacheln – ruhigeres Design
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
                            child: _ActionTile(
                              label: e.label,
                              icon: e.icon,
                              colorA: e.colorA,
                              colorB: e.colorB,
                              iconSize: iconSize,
                              fontSize: fontSize,
                              hovered: hovered,
                              onTap: e.onTap,
                            ),
                          );
                        },
                        childCount: tiles.length,
                      ),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: aspectRatio,
                      ),
                    ),
                  ),

                  // Kataloge – dezent, besonders mobil
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      16 + MediaQuery.of(ctx).padding.bottom,
                    ),
                    sliver: const SliverToBoxAdapter(
                      child: _CatalogPanel(),
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

/// =====================
/// Sub-Widgets
/// =====================

class _InfoHintCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? trailing;

  const _InfoHintCard({
    required this.icon,
    required this.text,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.16),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurface.withOpacity(.8)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _MonoBadge extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _MonoBadge({
    this.color = _dfsBlue,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

/// Dezent gestaltetes Katalog-Panel (Mobile noch zurückhaltender)
class _CatalogPanel extends StatelessWidget {
  const _CatalogPanel();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPhone = MediaQuery.of(context).size.width < 600;
    final localeCode = Localizations.localeOf(context).languageCode.toLowerCase();

    Widget buildCard({
      required String title,
      required String description,
      required IconData icon,
      required List<_CatalogLink> links,
    }) {
      final link = _catalogLinkForLocale(links, localeCode);

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: EdgeInsets.fromLTRB(isPhone ? 12 : 16, isPhone ? 10 : 14, isPhone ? 12 : 16, isPhone ? 12 : 16),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(.6),
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: cs.outlineVariant.withOpacity(.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kopfzeile
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: isPhone ? 20 : 22, color: _dfsBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Beschreibung
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(.75),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            // Sprachhinweis
            Row(
              children: [
                const Icon(Icons.language, size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                Text(
                  link.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black87,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Button – dezent (Outlined), keine Dominanz über den Tiles
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PdfInAppPage(url: link.url, title: title),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _dfsBlue,
                  side: BorderSide(color: _dfsBlue.withOpacity(.5)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.symmetric(horizontal: isPhone ? 10 : 12, vertical: 8),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(t.catalog_open),
              ),
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
          description: t.catalog_lab_desc,
          icon: Icons.biotech_outlined,
          links: _labCatalogLinks,
        ),
        buildCard(
          title: t.catalog_dent_title,
          description: t.catalog_dent_desc,
          icon: Icons.medical_services_outlined,
          links: _dentCatalogLinks,
        ),
      ],
    );
  }
}

/// Handlungs-Tiles: sachlich, mit solider Fläche statt kräftiger Gradients
class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color colorA; // Primärfarbe (Rand/Badge)
  final Color colorB; // Dunklere Schattierung für Hover/Focus Border
  final VoidCallback onTap;
  final double iconSize;
  final double fontSize;
  final bool hovered;

  const _ActionTile({
    required this.label,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.onTap,
    required this.iconSize,
    required this.fontSize,
    required this.hovered,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final baseBorder = BorderSide(color: colorA.withOpacity(.35));
    final hoverBorder = BorderSide(color: colorB.withOpacity(.55), width: 1.1);

    return AnimatedScale(
      duration: const Duration(milliseconds: 130),
      scale: hovered ? 1.01 : 1.0,
      child: Material(
        elevation: hovered ? 6 : 3,
        shadowColor: Colors.black.withOpacity(0.10),
        color: Colors.white,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_tileRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_tileRadius),
              border: Border.all(color: hovered ? hoverBorder.color : baseBorder.color, width: hovered ? hoverBorder.width : baseBorder.width),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // dezenter Icon-Hintergrund
                Container(
                  width: iconSize + 18,
                  height: iconSize + 18,
                  decoration: BoxDecoration(
                    color: colorA.withOpacity(.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: colorA.withOpacity(.25)),
                  ),
                  child: Icon(icon, size: iconSize, color: colorA),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: fontSize,
                    height: 1.15,
                    letterSpacing: .2,
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

// ---------------- (Optional weiterhin vorhanden – falls anderswo genutzt) ----------
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
          borderRadius: BorderRadius.circular(_cardRadius),
          color: _dfsBlue.withOpacity(.06),
          border: Border.all(color: _dfsBlue.withOpacity(.35)),
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
      return _InfoHintCard(
        icon: Icons.person_search_outlined,
        text: t.rep_not_assigned,
        trailing: IconButton(
          tooltip: t.refresh,
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
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
        color: _dfsBlue.withOpacity(.06),
        border: Border.all(color: _dfsBlue.withOpacity(.35)),
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Row(
        children: [
          _MonoBadge(icon: Icons.handshake_outlined),
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
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
              ],
            ),
          ),
          if (email.isNotEmpty)
            Tooltip(
              message: t.rep_email_tooltip,
              child: TextButton.icon(
                onPressed: () => onEmailTap(email, name),
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

// =====================
// Models & Helpers
// =====================

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
