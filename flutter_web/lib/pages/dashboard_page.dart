// lib/pages/dashboard_page.dart
import 'dart:html' as html; // für mailto
import 'dart:ui' as ui show platformViewRegistry; // nur für Web
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';
import 'rep_contact_page.dart';
import 'customer_news_page.dart';

// const _pdfLabUrl  = 'pdfs/DFS-Labor-DE-US-2025-26_1.pdf';
// const _pdfDentUrl = 'pdfs/DFS-Praxis-DE-US-2025-2026_1.pdf';

// Sprachabhängige Pfadwahl (relativ zum Web-Root, ohne führenden Slash!)
String _pdfLabFor(BuildContext context) {
  final lc = Localizations.localeOf(context).languageCode.toLowerCase();
  final esFr = lc == 'es' || lc == 'fr';

  // Dateien liegen unter flutter_web/web/pdfs
  return esFr
      ? 'pdfs/DFS-Labor-ES-FR-2025-26_1.pdf'
      : 'pdfs/DFS-Labor-DE-US-2025-26_1.pdf';
}

String _pdfDentFor(BuildContext context) {
  final lc = Localizations.localeOf(context).languageCode.toLowerCase();
  final esFr = lc == 'es' || lc == 'fr';

  return esFr
      ? 'pdfs/DFS-Praxis-ES-FR-2025-2026_1.pdf'
      : 'pdfs/DFS-Praxis-DE-US-2025-2026_1.pdf';
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
  static const _newsLastSeenKey = 'customer_news_last_seen';
  static const _fallbackRep = MyRep(
    firstName: 'DFS-Diamon',
    lastName: 'GmbH',
    email: 'complaint@dfs-diamon.de',
    region: '',
  );

  MyRep? _myRep;
  String? _customerName;
  String? _customerEmail;
  bool _repLoading = false;
  bool _repRequested = false;
  int _hoverIndex = -1;
  bool _hasUnreadNews = false;
  bool _newsIndicatorRefreshing = false;
  DateTime? _latestNewsTimestamp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureRepOnce();
      _initCustomerName();
    });
    _initRep();
    _refreshNewsIndicator();
  }

  bool _isStandaloneWebApp() {
    if (!kIsWeb) return false;
    try {
      // Chrome/Edge: display-mode
      final mm = html.window.matchMedia('(display-mode: standalone)');
      if (mm != null && mm.matches) return true;
    } catch (_) {}
    try {
      // iOS Safari PWA
      final nav = (html.window.navigator as dynamic);
      if (nav != null && nav.standalone == true) return true;
    } catch (_) {}
    try {
      // TWA / Spezialfälle
      if (html.document.referrer.contains('android-app://')) return true;
    } catch (_) {}
    return false;
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
    // Wir versuchen mehrere Quellen, ohne harte Abhängigkeit von bestimmten ApiClient-Methoden.
    Map<String, dynamic>? profile;

    try {
      final dyn = widget.api as dynamic; // dynamisch, damit kein Compile-Error, falls Methode fehlt

      // 1) Häufige Varianten
      try { if (dyn.getMyAccount != null) profile = await dyn.getMyAccount(); } catch (_) {}
      try { if (profile == null && dyn.getMe != null) profile = await dyn.getMe(); } catch (_) {}

      // 2) Direkt-Caches, falls vorhanden
      if (profile == null) {
        try { final p = dyn.currentUser; if (p is Map) profile = Map<String, dynamic>.from(p); } catch (_) {}
      }

      // 3) JWT-Claims, falls verfügbar
      if (profile == null) {
        try { final c = dyn.jwtClaims; if (c is Map) profile = Map<String, dynamic>.from(c); } catch (_) {}
      }
    } catch (_) {
      // still
    }

    final name = _pickCompany(profile);
    final email = _pickEmail(profile);
    if (mounted) {
      setState(() {
        _customerName = name;
        _customerEmail = email;
      });
    }
  }

  String? _pickCompany(Map<String, dynamic>? m) {
    if (m == null) return null;
    // typ. Schlüssel, die in deinen Projekten vorkommen könnten
    const keys = [
      'company', 'companyName', 'firm', 'firma', 'organization', 'organisation',
      'org', 'customerCompany', 'customer_name', 'customer', 'accountCompany'
    ];
    for (final k in keys) {
      final v = m[k];
      if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  String? _pickEmail(Map<String, dynamic>? m) {
    if (m == null) return null;
    const keys = [
      'email', 'mail', 'emailAddress', 'email_address',
      'contactEmail', 'customer_email', 'companyEmail',
    ];
    for (final k in keys) {
      final v = m[k];
      if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  void _ensureRepOnce() {
    if (_myRep == null && !_repRequested) {
      _repRequested = true;
      _initRep();
    }
  }

  Future<void> _refreshNewsIndicator({bool forceRefresh = false}) async {
    if (_newsIndicatorRefreshing) return;
    _newsIndicatorRefreshing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenRaw = prefs.getString(_newsLastSeenKey);
      final lastSeen = lastSeenRaw != null ? DateTime.tryParse(lastSeenRaw) : null;

      final news = await widget.api.fetchCustomerNews(refresh: forceRefresh);
      DateTime? latest;
      for (final entry in news) {
        if (latest == null || entry.updatedAt.isAfter(latest)) {
          latest = entry.updatedAt;
        }
      }

      final hasUnread = latest != null && (lastSeen == null || latest.isAfter(lastSeen));
      if (mounted) {
        setState(() {
          _hasUnreadNews = hasUnread;
          _latestNewsTimestamp = latest;
        });
      } else {
        _hasUnreadNews = hasUnread;
        _latestNewsTimestamp = latest;
      }
    } catch (_) {
      // Indicator silently stays as-is when loading fails
    } finally {
      _newsIndicatorRefreshing = false;
    }
  }

  Future<void> _markCustomerNewsSeen() async {
    DateTime? ts = _latestNewsTimestamp;
    if (ts == null) {
      try {
        final news = await widget.api.fetchCustomerNews(refresh: true);
        for (final entry in news) {
          if (ts == null || entry.updatedAt.isAfter(ts)) {
            ts = entry.updatedAt;
          }
        }
      } catch (_) {
        // ignore
      }
    }
    ts ??= DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_newsLastSeenKey, ts.toIso8601String());
    if (!mounted) return;
    setState(() {
      _hasUnreadNews = false;
      _latestNewsTimestamp = ts;
    });
  }

  Future<void> _openCustomerNews(BuildContext context) async {
    await _markCustomerNewsSeen();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CustomerNewsPage(api: widget.api),
    ));
    if (mounted) {
      await _refreshNewsIndicator(forceRefresh: true);
    }
  }

  // --- HILFSFUNKTION: mailto an Vertreter öffnen (mit Betreff + Body aus i18n) ---
  MyRep _repForContact() {
    final rep = _myRep;
    if (rep == null || rep.email.trim().isEmpty) {
      return _fallbackRep;
    }
    return rep;
  }

  void _openRepContactForm(BuildContext context) {
    final rep = _repForContact();

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

  // --- KOMPAKTE Variante (eingeklappbar) ---
  Widget _buildRepCardCompact(BuildContext context) {
    final theme  = Theme.of(context);
    final t      = AppLocalizations.of(context)!;
    final r      = _myRep;
    final name   = (r == null) ? '' : [r.firstName.trim(), r.lastName.trim()].where((s) => s.isNotEmpty).join(' ');
    final email  = (r?.email ?? '').trim();
    final region = (r?.region ?? '').trim();
    final cs = theme.colorScheme;
    final company = (_customerName ?? '').trim();
    final hasContact = _repForContact().email.trim().isNotEmpty;

    // Kein Vertreter hinterlegt → Hinweis + Kontakt & Refresh
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
                      company.isNotEmpty ? company : t.we_are_here_for_you,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Hinweis + Kontaktmöglichkeit
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.rep_not_assigned,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(.70),
                            height: 1.15,
                          ),
                        ),
                        if (hasContact)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () => _openRepContactForm(context),
                            icon: const Icon(Icons.mail_outline, size: 18),
                            label: Text(
                              t.rep_contact_form,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                      ],
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

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: const CircleAvatar(child: Icon(Icons.handshake_outlined)),
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
        trailing: Wrap(
          spacing: 4,
          children: [
            if (hasContact)
              IconButton(
                tooltip: t.rep_contact_form,
                icon: const Icon(Icons.mail_outline),
                onPressed: () => _openRepContactForm(context),
              ),
            IconButton(
              tooltip: t.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: _initRep,
            ),
          ],
        ),
        // Optional: Details im aufgeklappten Bereich
        children: [
          if (region.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(region, style: theme.textTheme.bodySmall),
              ),
            ),
        ],
      ),
    );
  }

  // --- GROSSE Variante (wie früher, optisch präsenter) ---
  Widget _buildRepCardLarge(BuildContext context) {
    final t      = AppLocalizations.of(context)!;
    final r      = _myRep;
    final cs = Theme.of(context).colorScheme;
    final company = (_customerName ?? '').trim();
    final hasContact = _repForContact().email.trim().isNotEmpty;

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
                      company.isNotEmpty ? company : t.we_are_here_for_you,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          t.rep_not_assigned,
                          style: TextStyle(color: cs.onSurface.withOpacity(.75), fontSize: 13),
                        ),
                        if (hasContact)
                          TextButton.icon(
                            onPressed: () => _openRepContactForm(context),
                            icon: const Icon(Icons.mail_outline),
                            label: Text(t.rep_contact_form),
                          ),
                      ],
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
            if (hasContact)
              Tooltip(
                message: t.rep_contact_form,
                child: TextButton.icon(
                  onPressed: () => _openRepContactForm(context),
                  icon: const Icon(Icons.email_outlined),
                  label: Text(t.rep_contact_form),
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
      _Entry(
        label: t.customerNewsTile,
        icon: Icons.campaign_outlined,
        colorA: const Color(0xFF5D4037),
        colorB: const Color(0xFF8D6E63),
        showIndicator: _hasUnreadNews,
        onTap: () async {
          await _openCustomerNews(context);
        },
      ),
    ];

    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final size = MediaQuery.of(ctx).size;
          final isPortrait = MediaQuery.of(ctx).orientation == Orientation.portrait;
          final isPhone = size.width < 600;
          final isAppView = _isStandaloneWebApp(); // PWA installiert = true

          final double maxExtent = isPhone
              ? (isPortrait ? (isAppView ? 150 : 180) : (isAppView ? 170 : 200))
              : (size.width < 1024 ? (isAppView ? 220 : 240) : (isAppView ? 240 : 260));

          final double iconSize = isPhone
              ? (isAppView ? 26 : 32)
              : (isAppView ? 36 : 40);

          final double fontSize = isPhone
              ? (isAppView ? 12.5 : 14.0)
              : (isAppView ? 14.0 : 14.5);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                children: [
                  // ---------- Vertreter-Header (responsiv) ----------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: _buildRepHeaderResponsive(context),
                  ),

                  // ---------- Kacheln ----------
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: isAppView
                            ? (isPhone ? 1.12 : 1.15)   // dezenter in App
                            : (isPhone ? 1.06 : 1.10),  // wie vorher im Web
                      ),
                      itemCount: tiles.length,
                      itemBuilder: (context, i) {
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
                              showIndicator: e.showIndicator,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // ---------- Dezente Kataloge (unter den Kacheln) ----------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: isAppView
                        ? const _CatalogChips()  // dezent in PWA (Appansicht)
                        : _CatalogStrip(),       // wie zuvor im Browser/Web
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
                  html.window.open(mailto, '_self');
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

class _CatalogStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPhone = MediaQuery.of(context).size.width < 700;
    final labUrl  = _pdfLabFor(context);
    final dentUrl = _pdfDentFor(context);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 18, color: cs.onSurface.withOpacity(0.7)),
              const SizedBox(width: 8),
              Text(
                t.catalogs_title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurface.withOpacity(0.8),
                  letterSpacing: .2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: isPhone ? WrapAlignment.center : WrapAlignment.start,
            children: [
              _CatalogTile(
                title: t.catalog_lab_title,
                subtitle: t.catalog_lab_desc,
                icon: Icons.biotech_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PdfInAppPage(url: labUrl,  title: t.catalog_lab_title),
                    ),
                  );
                },
              ),
              _CatalogTile(
                title: t.catalog_dent_title,
                subtitle: t.catalog_dent_desc,
                icon: Icons.medical_services_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PdfInAppPage(url: dentUrl, title: t.catalog_dent_title),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CatalogChips extends StatelessWidget {
  const _CatalogChips();

  @override
  Widget build(BuildContext context) {
    final t  = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isPhone = MediaQuery.of(context).size.width < 700;
    final labUrl  = _pdfLabFor(context);
    final dentUrl = _pdfDentFor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // winzige, sehr zurückhaltende Überschrift
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 16, color: cs.onSurface.withOpacity(.65)),
            const SizedBox(width: 6),
            Text(
              t.catalogs_title, // "Kataloge"
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurface.withOpacity(.75),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // zwei „Chip“-Links nebeneinander, umbrechend
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: isPhone ? WrapAlignment.center : WrapAlignment.start,
          children: [
            _ChipLink(
              icon: Icons.science_outlined,
              label: t.catalog_lab_title, // „Dentallabor Katalog“
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PdfInAppPage(url: labUrl,  title: t.catalog_lab_title),
                  ),
                );
              },
            ),
            _ChipLink(
              icon: Icons.medical_information_outlined,
              label: t.catalog_dent_title, // „Zahnmedizin Katalog“
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PdfInAppPage(url: dentUrl, title: t.catalog_dent_title),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ChipLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ChipLink({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.primary,
        side: BorderSide(color: cs.outlineVariant),
        backgroundColor: Colors.transparent,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _CatalogTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _CatalogTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_CatalogTile> createState() => _CatalogTileState();
}

class _CatalogTileState extends State<_CatalogTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isNarrow = MediaQuery.of(context).size.width < 700;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        width: isNarrow ? 360 : 400,
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hover ? cs.primary.withOpacity(.45) : cs.outlineVariant),
          boxShadow: _hover
              ? [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 10, offset: const Offset(0, 4))]
              : const [],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.25)),
                ),
                child: Icon(widget.icon, size: 24, color: cs.primary.withOpacity(0.90)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(.7),
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: widget.onTap,
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  AppLocalizations.of(context)!.catalog_open,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
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
  final bool showIndicator;
  _Entry({
    required this.label,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.onTap,
    this.showIndicator = false,
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
  final bool showIndicator;

  const _FancyTile({
    required this.label,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.onTap,
    required this.iconSize,
    required this.fontSize,
    this.showIndicator = false,
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
                if (showIndicator)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: _BlinkingDot(),
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

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot({super.key});

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFFFFEB3B),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withOpacity(0.6),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- In-App PDF Viewer (pdf.js) ----------------
class PdfInAppPage extends StatefulWidget {
  final String url;
  final String title;
  const PdfInAppPage({super.key, required this.url, required this.title});

  @override
  State<PdfInAppPage> createState() => _PdfInAppPageState();
}

class _PdfInAppPageState extends State<PdfInAppPage> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();

    // 1) PDF-URL relativ zum aktuellen Base-Pfad auflösen
    final pdfUrl = Uri.base.resolve(widget.url).toString();

    // 2) Lokalen pdf.js-Viewer RELATIV aufrufen (kein führender Slash!)
    final viewerPath = 'pdfjs/web/viewer.html'
        '?file=${Uri.encodeComponent(pdfUrl)}#zoom=page-width&pagemode=none';

    // 3) Auch den Viewer relativ auflösen (deckt Unterpfade ab)
    final viewerUrl = Uri.base.resolve(viewerPath).toString();

    _viewType = 'pdfjs-${DateTime.now().millisecondsSinceEpoch}';

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = html.IFrameElement()
        ..src = viewerUrl
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: SizedBox.expand(
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
