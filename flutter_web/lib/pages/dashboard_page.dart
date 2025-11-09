// lib/pages/dashboard_page.dart
import 'dart:html' as html; // für mailto
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';

const _pdfLabUrl  = 'https://dfs-diamon.de/sites/default/public/instructions/pdfs/DFS-Labor-DE-US-2025-26_1.pdf';
const _pdfDentUrl = 'https://dfs-diamon.de/sites/default/public/instructions/pdfs/DFS-Praxis-DE-US-2025-2026_1.pdf';

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

class _DashboardPageState extends State<DashboardPage> {
  MyRep? _myRep;
  Future<MyRep?>? _repFuture; // stabiler Future-Loader für Banner
  int _hoverIndex = -1;

  @override
  void initState() {
    super.initState();
    _repFuture = _ensureSessionThenGetRep();
  }

  Future<MyRep?> _ensureSessionThenGetRep() async {
    if (widget.api.token == null || widget.api.token!.isEmpty) {
      await widget.api.restoreSession();
    }
    try {
      final rep = await widget.api.getMyRep(); // null, wenn keiner zugewiesen
      _myRep = rep;
      return rep;
    } catch (_) {
      return null;
    }
  }

  Future<void> _reloadRep() async {
    setState(() => _repFuture = _ensureSessionThenGetRep());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final tiles = <_Entry>[
      _Entry(
        label: t.reportComplaint,
        icon: Icons.add_circle,
        colorA: const Color(0xFF1976D2), // DFS-Blau nah
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
          final isPortrait = MediaQuery.of(ctx).orientation == Orientation.portrait;
          final isPhone = size.width < 600;

          final double maxExtent = isPhone
              ? (isPortrait ? 160 : 200)
              : (size.width < 1024 ? 240 : 260);

          final double iconSize = isPhone ? 28 : 40;
          final double fontSize = isPhone ? 13.0 : 14.5;

          // --- Vertreter-Banner als hübsche Card (immer oben, über den Kacheln) ---
          final repBanner = FutureBuilder<MyRep?>(
            future: _repFuture,
            builder: (context, snap) {
              final rep = snap.data ?? _myRep;
              if (rep == null) {
                // Loader-Placeholder, aber nur wenn gerade wirklich geladen wird
                if (snap.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Container(
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.blue.withOpacity(0.28), width: 1),
                      ),
                      child: const Center(
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }

              final first = rep.firstName.trim();
              final last  = rep.lastName.trim();
              final email = rep.email.trim();
              final region = rep.region.trim();
              final name = [first, last].where((s) => s.isNotEmpty).join(' ');
              final bannerTitle = (name.isNotEmpty)
                  ? t.rep_banner_title(name)
                  : t.rep_banner_title(email.isNotEmpty ? email : '—');

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1976D2).withOpacity(0.14),
                          const Color(0xFF42A5F5).withOpacity(0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.45), width: 1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF1976D2),
                          ),
                          child: const Icon(Icons.handshake_outlined, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bannerTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (email.isNotEmpty || region.isNotEmpty)
                                Text(
                                  [
                                    if (email.isNotEmpty) email,
                                    if (region.isNotEmpty) region,
                                  ].join(' • '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 13.2,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Primärer Kontakt-Button
                        Tooltip(
                          message: t.rep_email_tooltip,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              foregroundColor: Colors.white,
                              backgroundColor: const Color(0xFF1976D2),
                            ),
                            onPressed: email.isEmpty
                                ? null
                                : () {
                                    final subject = Uri.encodeComponent(t.mail_subject_rep);
                                    final body = Uri.encodeComponent(t.mail_body_rep(name.isNotEmpty ? name : ''));
                                    final mailto = 'mailto:$email?subject=$subject&body=$body';
                                    html.window.open(mailto, '_self');
                                  },
                            icon: const Icon(Icons.email_outlined, size: 18),
                            label: Text(t.rep_email_button),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Leichter Refresh rechts
                        IconButton(
                          tooltip: t.refresh,
                          onPressed: _reloadRep,
                          splashRadius: 20,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                children: [
                  // 1) Vertreter-Banner (bleibt oben)
                  repBanner,

                  const SizedBox(height: 8),

                  // 2) Kachel-Grid (Hauptfokus)
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: isPhone ? 1.06 : 1.1,
                      ),
                      itemCount: tiles.length,
                      itemBuilder: (context, i) {
                        final e = tiles[i];
                        final hovered = _hoverIndex == i;
                        return MouseRegion(
                          onEnter: (_) => setState(() => _hoverIndex = i),
                          onExit:  (_) => setState(() => _hoverIndex = -1),
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
                    ),
                  ),

                  // 3) Dezente Katalog-Card (unter den Kacheln)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _buildCatalogsCard(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCatalogsCard(BuildContext context) {
    final t  = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    Widget tile({
      required String title,
      required String desc,
      required String url,
      required IconData icon,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => html.window.open(url, '_blank'),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
            color: cs.surface, // dezent, ohne Verlauf
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                // kleine runde Iconfläche
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 22, color: cs.primary),
                ),
                const SizedBox(width: 12),

                // Titel + Beschreibung
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurface.withOpacity(.65), fontSize: 13.0),
                      ),
                    ],
                  ),
                ),
  
                const SizedBox(width: 8),

                // schlanker „Ansehen“-Button
                TextButton.icon(
                  onPressed: () => html.window.open(url, '_blank'),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(t.catalog_open),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    foregroundColor: cs.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 0, // dezent
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Theme.of(context).colorScheme.surface, // ruhig
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.menu_book_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                t.catalogs_title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5),
              ),
            ]),
            const SizedBox(height: 10),

            LayoutBuilder(
              builder: (_, cons) {
                final isNarrow = cons.maxWidth < 560;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isNarrow ? 1 : 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: isNarrow ? 3.6 : 3.8, // flacher, unaufdringlich
                  children: [
                    tile(
                      title: t.catalog_lab_title,
                      desc:  t.catalog_lab_desc,
                      url:   _pdfLabUrl,
                      icon:  Icons.biotech_outlined,
                    ),
                    tile(
                      title: t.catalog_dent_title,
                      desc:  t.catalog_dent_desc,
                      url:   _pdfDentUrl,
                      icon:  Icons.medical_services_outlined,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
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

/// Schicke Kachel im Admin-Stil (Gradient, Shadow, runde Ecken, Hover-Lift)
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
                  top: 0,
                  right: 0,
                  left: 0,
                  height: 46,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.18),
                            Colors.white.withOpacity(0.00),
                          ],
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
                        width: iconSize + 20,
                        height: iconSize + 20,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: fontSize,
                          height: 1.15,
                          letterSpacing: 0.2,
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
