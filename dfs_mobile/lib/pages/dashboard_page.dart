// lib/pages/dashboard_page.dart
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/customer_news_entry.dart';
import '../services/customer_news_service.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';
import 'customer_news_page.dart';
import 'knowledge_base_page.dart';
import '../widgets/pdf_view_stub.dart'
  if (dart.library.html) '../widgets/pdf_view_web.dart';

const _labCatalogLinks = [
  _CatalogLink(
    label: 'DE / EN',
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
  bool _newsLoading = false;
  String? _newsError;
  List<CustomerNewsEntry> _newsItems = const [];
  late final CustomerNewsService _newsService;

  @override
  void initState() {
    super.initState();
    _newsService = CustomerNewsService(api: widget.api);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureRepOnce();
      _initCustomerName();
    });
    _initRep();
    _refreshNewsIndicator();
    _loadDashboardNews();
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

  Future<void> _refreshNewsIndicator({bool forceRefresh = false}) async {
    if (_newsIndicatorRefreshing) return;
    _newsIndicatorRefreshing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenRaw = prefs.getString(_newsLastSeenKey);
      final lastSeen = lastSeenRaw != null ? DateTime.tryParse(lastSeenRaw) : null;

      final news = await _newsService.list(refresh: forceRefresh);
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
    } catch (e, stack) {
      debugPrint('[news] dashboard indicator failed: $e');
      debugPrint(stack.toString());
    } finally {
      _newsIndicatorRefreshing = false;
    }
  }

  Future<void> _markCustomerNewsSeen() async {
    DateTime? ts = _latestNewsTimestamp;
    if (ts == null) {
      try {
        final news = await _newsService.list(refresh: true);
        for (final entry in news) {
          if (ts == null || entry.updatedAt.isAfter(ts)) {
            ts = entry.updatedAt;
          }
        }
      } catch (e, stack) {
        debugPrint('[news] mark seen failed: $e');
        debugPrint(stack.toString());
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
      await _loadDashboardNews(refresh: true);
    }
  }

  Future<void> _loadDashboardNews({bool refresh = false}) async {
    if (!refresh && _newsLoading) return;
    setState(() {
      if (_newsItems.isEmpty || refresh) {
        _newsLoading = true;
        if (refresh) _newsError = null;
      }
    });
    try {
      final list = await _newsService.list(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _newsItems = list;
        _newsError = null;
      });
    } catch (e, stack) {
      debugPrint('[news] dashboard load failed: $e');
      debugPrint(stack.toString());
      if (!mounted) return;
      setState(() => _newsError = '$e');
    } finally {
      if (mounted) setState(() => _newsLoading = false);
    }
  }

  String _formatNewsDate(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.MMMd(locale).format(date);
  }

  Widget _buildNewsHighlightCard(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final entry = _newsItems.isNotEmpty ? _newsItems.first : null;
    final hasError = _newsError != null;
    final isLoading = _newsLoading && entry == null;
    String title = t.customerNewsTitle;
    String teaser = '';
    String? badgeLabel;
    String? dateLabel;
    String ctaLabel = t.customerNewsReadMore;
    VoidCallback? onTap;
    bool showIndicator = _hasUnreadNews;

    if (hasError) {
      teaser = 'Neuigkeiten konnten nicht geladen werden.';
      ctaLabel = t.refresh;
      onTap = () => _loadDashboardNews(refresh: true);
      showIndicator = false;
    } else if (isLoading) {
      teaser = 'Neuigkeiten werden geladen…';
      showIndicator = false;
    } else if (entry == null) {
      teaser = 'Aktuell keine Neuigkeiten.';
      ctaLabel = 'Alle Neuigkeiten';
      onTap = () async => _openCustomerNews(context);
      showIndicator = false;
    } else {
      title = entry.title.trim().isEmpty ? t.customerNewsTitle : entry.title.trim();
      teaser = entry.summary.trim().isEmpty ? t.customerNewsSubtitle : entry.summary.trim();
      badgeLabel = entry.category.trim().isEmpty
          ? t.customerNewsHeroFreshLabel
          : entry.category.trim();
      dateLabel = t.customerNewsNewSince(_formatNewsDate(context, entry.publishedAt));
      ctaLabel = entry.linkLabel?.trim().isNotEmpty == true
          ? entry.linkLabel!.trim()
          : t.customerNewsReadMore;
      onTap = () async => _openCustomerNews(context);
    }

    return NewsHighlightCard(
      title: title,
      teaser: teaser,
      badgeLabel: badgeLabel,
      dateLabel: dateLabel,
      ctaLabel: ctaLabel,
      showIndicator: showIndicator,
      isLoading: isLoading,
      isError: hasError,
      onTap: onTap,
    );
  }

  Widget _buildNewsDebugOverlay(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final theme = Theme.of(context);
    String? lastError = _newsService.lastError;
    if (lastError != null && lastError.length > 120) {
      lastError = '${lastError.substring(0, 120)}…';
    }
    final lines = <String>[
      'Status: ${_newsService.lastStatus?.toString() ?? '-'}',
      'Count: ${_newsService.lastCount?.toString() ?? '-'}',
      if (_newsService.lastUrl != null) 'Url: ${_newsService.lastUrl}',
      if (lastError != null && lastError.isNotEmpty) 'Error: $lastError',
    ];

    return Positioned(
      right: 12,
      bottom: 12 + MediaQuery.of(context).padding.bottom,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 120),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.82),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
          ),
          child: DefaultTextStyle(
            style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  height: 1.2,
                ) ??
                const TextStyle(fontSize: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'News Debug',
                  style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ) ??
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                ),
                const SizedBox(height: 4),
                for (final line in lines) Text(line, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
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

  // --- KOMPAKTE Variante (handy-optimiert, Name immer sichtbar) ---
  Widget _buildRepCardCompact(BuildContext context) {
    final theme = Theme.of(context);
    final t     = AppLocalizations.of(context)!;
    final r     = _myRep;

    // Kein Vertreter hinterlegt → Hinweis + Kontakt & Refresh
    if (r == null) {
      if (_repLoading) {
        return const SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        );
      }
      return const SizedBox.shrink();
    }

    final first  = r.firstName.trim();
    final last   = r.lastName.trim();
    final email  = r.email.trim();
    final name   = [first, last].where((s) => s.isNotEmpty).join(' ');
    final title  = name.isNotEmpty ? t.rep_banner_title(name)
                                   : t.rep_banner_title(email.isNotEmpty ? email : '—');
    final hasContact = _repForContact().email.trim().isNotEmpty;

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
                    ],
                  ),
                ),
              ],
            ),
            // Aktionen unter dem Textblock → spart Breite, nichts schneidet ab
            const SizedBox(height: 8),
            Row(
              children: [
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
    final theme  = Theme.of(context);
    final t      = AppLocalizations.of(context)!;
    final r      = _myRep;
    final cs     = theme.colorScheme;

    if (r == null) {
      if (_repLoading) {
        return const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        );
      }
      return const SizedBox.shrink();
    }
    
    final first  = r.firstName.trim();
    final last   = r.lastName.trim();
    final email  = r.email.trim();
    final name   = [first, last].where((s) => s.isNotEmpty).join(' ');
    final bannerTitle = name.isNotEmpty ? t.rep_banner_title(name)
                                        : t.rep_banner_title(email.isNotEmpty ? email : '—');
    final hasContact = _repForContact().email.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: cs.surfaceVariant.withOpacity(0.65),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withOpacity(0.15),
                  ),
                  child: Icon(Icons.handshake_outlined, color: cs.primary, size: 20),
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
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: t.refresh,
                  onPressed: _initRep,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (hasContact) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _openRepContactForm(context),
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: Text(
                    t.rep_contact_form,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- RESPONSIVE Umschalter: mobil kompakt, Desktop groß ---
  Widget? _buildRepHeaderResponsive(BuildContext context) {
    if (!_repLoading && _myRep == null) return null;

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
        label: t.knowledgeBaseTile ?? 'Knowledge base (FAQ)',
        icon: Icons.menu_book_outlined,
        colorA: const Color(0xFF1E3A8A),
        colorB: const Color(0xFF3B82F6),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => KnowledgeBasePage(api: widget.api),
            ),
          );
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

          final double iconSize = isPhone ? 26 : 36;
          final double fontSize = isPhone ? 13.0 : 14.5;
          final double aspectRatio;
          if (compressedHeight) {
            aspectRatio = isPhone ? 1.0 : 1.06;
          } else {
            aspectRatio = isPhone ? 0.9 : 0.98;
          }

          final repHeader = _buildRepHeaderResponsive(context);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Stack(
                children: [
                  CustomScrollView(
                    slivers: [
                      if (repHeader != null)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                          sliver: SliverToBoxAdapter(
                            child: repHeader,
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: _buildNewsHighlightCard(context),
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
                                    showIndicator: e.showIndicator,
                                    hovered: hovered,
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
                  _buildNewsDebugOverlay(context),
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
                label: Text(t.rep_contact_form),
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

class NewsHighlightCard extends StatelessWidget {
  final String title;
  final String teaser;
  final String? badgeLabel;
  final String? dateLabel;
  final String ctaLabel;
  final bool showIndicator;
  final bool isLoading;
  final bool isError;
  final VoidCallback? onTap;

  const NewsHighlightCard({
    required this.title,
    required this.teaser,
    this.badgeLabel,
    this.dateLabel,
    required this.ctaLabel,
    required this.showIndicator,
    required this.isLoading,
    required this.isError,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final cs = theme.colorScheme;
    final isPhone = MediaQuery.of(context).size.width < 640;
    final radius = BorderRadius.circular(18);
    final baseA = isError ? cs.errorContainer : cs.primary;
    final baseB = isError ? cs.error : cs.secondary;
    final gradientColors = [
      Color.lerp(baseA, baseB, 0.25)!.withOpacity(0.92),
      Color.lerp(baseB, cs.tertiary, 0.35)!.withOpacity(0.88),
    ];

    Widget iconContent() {
      if (isLoading) {
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.9)),
          ),
        );
      }
      return Icon(
        isError ? Icons.error_outline : Icons.campaign_outlined,
        color: Colors.white.withOpacity(0.92),
        size: 24,
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 130, maxHeight: 160),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: radius,
              border: Border.all(color: Colors.white.withOpacity(0.14)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: EdgeInsets.all(isPhone ? 14 : 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Center(child: iconContent()),
                    ),
                    if (showIndicator && !isError && !isLoading)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              color: Colors.white.withOpacity(0.96),
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            teaser,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.white.withOpacity(0.85),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (badgeLabel != null && badgeLabel!.isNotEmpty)
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                                    ),
                                    child: Text(
                                      badgeLabel!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: Colors.white.withOpacity(0.92),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              if (dateLabel != null && dateLabel!.isNotEmpty)
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.history_toggle_off_outlined,
                                        size: 14,
                                        color: Colors.white.withOpacity(0.75),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          dateLabel!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: textTheme.labelSmall?.copyWith(
                                            color: Colors.white.withOpacity(0.78),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                child: TextButton.icon(
                                  onPressed: onTap,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    textStyle: textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                                  ),
                                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                  label: Text(
                                    ctaLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
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
      String? description,
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: isPhone ? 18 : 20, color: cs.onSurface.withOpacity(0.70)),
            const SizedBox(width: 10), // war 12
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  const SizedBox(height: 2), // war 6
                  Text(link.label, style: langStyle),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
          icon: Icons.biotech_outlined,
          links: _labCatalogLinks,
        ),
        buildCard(
          title: t.catalog_dent_title,
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
  final bool hovered;

  const _FancyTile({
    required this.label,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.onTap,
    required this.iconSize,
    required this.fontSize,
    this.showIndicator = false,
    this.hovered = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(22);
    final baseGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(colorA, Colors.white, hovered ? 0.14 : 0.08)!.withOpacity(.97),
        Color.lerp(colorB, Colors.black, hovered ? 0.08 : 0.03)!.withOpacity(.93),
      ],
    );

    final haloGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colorA.withOpacity(.45),
        colorB.withOpacity(.38),
      ],
    );

    final List<BoxShadow> shadow = [
      BoxShadow(
        color: Colors.black.withOpacity(hovered ? 0.24 : 0.18),
        blurRadius: hovered ? 28 : 20,
        spreadRadius: -4,
        offset: Offset(0, hovered ? 16 : 12),
      ),
      BoxShadow(
        color: colorB.withOpacity(0.22),
        blurRadius: hovered ? 32 : 26,
        spreadRadius: -6,
        offset: const Offset(0, 8),
      ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      transform: hovered
          ? (Matrix4.identity()..translate(0.0, -2.5))
          : Matrix4.identity(),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: haloGradient,
        ),
        padding: const EdgeInsets.all(1.6),
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: baseGradient,
                border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.4),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 160;
                  final textScale = MediaQuery.textScaleFactorOf(context);
                  final paddingV = compact ? 12.0 : 16.0;
                  final paddingH = compact ? 14.0 : 16.0;
                  final spacing = compact ? 8.0 : 12.0;
                  final accentWidth = compact ? 24.0 : 32.0;
                  final resolvedFontSize = compact ? fontSize : fontSize + 1;
                  final maxFontSize = (constraints.maxHeight * 0.14).clamp(11.0, 16.0);
                  final scaledFontSize = (resolvedFontSize * textScale).clamp(11.0, maxFontSize);
                  final iconBox = (constraints.maxHeight * 0.36).clamp(44.0, 64.0);
                  final resolvedIconSize = (iconSize).clamp(20.0, iconBox * 0.55);

                  return ClipRRect(
                    borderRadius: borderRadius,
                    child: Stack(
                      children: [
                        // soft glass shine
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                stops: const [0, .36, 1],
                                colors: [
                                  Colors.white.withOpacity(.16),
                                  Colors.white.withOpacity(.04),
                                  Colors.black.withOpacity(.08),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // spotlight rings
                        Positioned(
                          top: -32,
                          right: -14,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: hovered ? 1 : .7,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withOpacity(.28),
                                    Colors.white.withOpacity(.03),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -40,
                          left: -24,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  colorB.withOpacity(.18),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Diagonal glow stripe
                        Positioned(
                          top: -70,
                          left: -10,
                          right: -40,
                          child: Transform.rotate(
                            angle: -0.35,
                            child: Container(
                              height: 120,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(.12),
                                    Colors.white.withOpacity(.02),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (showIndicator)
                          const Positioned(
                            top: 14,
                            right: 14,
                            child: _BlinkingDot(),
                          ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: iconBox,
                                  maxHeight: iconBox,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: RadialGradient(
                                      colors: [
                                        Colors.white.withOpacity(.32),
                                        Colors.white.withOpacity(.10),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(hovered ? 0.65 : 0.45),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.18),
                                        blurRadius: hovered ? 24 : 18,
                                        offset: const Offset(0, 12),
                                      ),
                                      BoxShadow(
                                        color: colorA.withOpacity(.25),
                                        blurRadius: hovered ? 26 : 18,
                                        spreadRadius: -4,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withOpacity(.28),
                                          Colors.white.withOpacity(.12),
                                        ],
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        icon,
                                        size: resolvedIconSize,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: spacing),
                              Expanded(
                                child: AutoSizeText(
                                  label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  minFontSize: 11,
                                  stepGranularity: 0.5,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: scaledFontSize,
                                    letterSpacing: .3,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: accentWidth,
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(.75),
                                      Colors.white.withOpacity(.25),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(.24),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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
        'lang'            : Localizations.localeOf(context).languageCode,
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
