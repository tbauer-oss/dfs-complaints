// lib/pages/dashboard_page.dart
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../services/customer_news_service.dart';
import '../services/news_badge_store.dart';
import '../models/customer_news_entry.dart';

import 'complaint_form_page.dart';
import 'my_complaints_page.dart';
import 'account_page.dart';
import 'support_page.dart';
import 'customer_news_page.dart';
import 'knowledge_base_page.dart';
import '../widgets/pdf_view_stub.dart'
  if (dart.library.html) '../widgets/pdf_view_web.dart';

// Variante A styling: use theme tokens so dark mode updates the entire UI.
Color _chipFill(ColorScheme scheme) {
  final opacity = scheme.brightness == Brightness.dark ? 0.18 : 0.12;
  return scheme.primary.withOpacity(opacity);
}

Color _subtitleColor(ColorScheme scheme) => scheme.onSurface.withOpacity(0.7);

Color _shadowColor(ThemeData theme) {
  final opacity = theme.brightness == Brightness.dark ? 0.18 : 0.08;
  return theme.colorScheme.shadow.withOpacity(opacity);
}

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

  const DashboardPage({
    super.key,
    required this.api,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
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
  bool _hasUnreadNews = false;
  bool _newsIndicatorRefreshing = false;
  DateTime? _latestNewsTimestamp;
  late Future<List<CustomerNewsEntry>> _newsPreviewFuture;
  late final CustomerNewsService _newsService;
  late final NewsBadgeStore _newsBadgeStore;

  @override
  void initState() {
    super.initState();
    _newsService = CustomerNewsService(api: widget.api);
    _newsBadgeStore = NewsBadgeStore();
    _newsPreviewFuture = _newsService.list();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureRepOnce();
      _initCustomerName();
    });
    _initRep();
    _refreshNewsIndicator();
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
      final latest = await _fetchLatestNewsTimestamp(forceRefresh: forceRefresh);
      final lastSeen = await _newsBadgeStore.loadLastSeen();
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
      if (kDebugMode) {
        debugPrint('[news] dashboard indicator failed: $e');
        debugPrint(stack.toString());
      }
    } finally {
      _newsIndicatorRefreshing = false;
    }
  }

  Future<DateTime?> _fetchLatestNewsTimestamp({required bool forceRefresh}) async {
    final news = await _newsService.list(refresh: forceRefresh);
    DateTime? latest;
    for (final entry in news) {
      if (latest == null || entry.updatedAt.isAfter(latest)) {
        latest = entry.updatedAt;
      }
    }
    return latest;
  }

  Future<void> _markCustomerNewsSeen() async {
    DateTime? ts = _latestNewsTimestamp;
    if (ts == null) {
      try {
        ts = await _fetchLatestNewsTimestamp(forceRefresh: true);
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint('[news] mark seen failed: $e');
          debugPrint(stack.toString());
        }
      }
    }
    ts ??= DateTime.now();

    await _newsBadgeStore.saveLastSeen(ts);
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

  Widget _buildNewsSection(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return FutureBuilder<List<CustomerNewsEntry>>(
      future: _newsPreviewFuture,
      builder: (context, snapshot) {
        final hasError = snapshot.hasError;
        final data = snapshot.data;
        final hasNews = data != null && data.isNotEmpty;
        final state = hasError
            ? NewsCardState.error
            : snapshot.connectionState == ConnectionState.waiting
                ? NewsCardState.loading
                : hasNews
                    ? NewsCardState.ready
                    : NewsCardState.empty;
        return NewsCard(
          title: t.customerNewsTitle,
          subtitle: t.customerNewsSubtitle,
          ctaLabel: t.customerNewsReadMore,
          showIndicator: _hasUnreadNews,
          state: state,
          onTap: () async => _openCustomerNews(context),
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final backgroundTop = Color.lerp(
      scheme.primary,
      scheme.background,
      isDark ? 0.88 : 0.92,
    )!;
    final backgroundBottom = Color.lerp(
      scheme.primary,
      scheme.background,
      isDark ? 0.82 : 0.88,
    )!;

    final tiles = <_Entry>[
      _Entry(
        label: t.reportComplaint,
        icon: Icons.add_circle_outline,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ComplaintFormPage(api: widget.api),
          ));
        },
      ),
      _Entry(
        label: t.myComplaints,
        icon: Icons.list_alt,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MyComplaintsPage(api: widget.api),
          ));
        },
      ),
      _Entry(
        label: t.supportTitle,
        icon: Icons.support_agent,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SupportPage(api: widget.api),
          ));
        },
      ),
      _Entry(
        label: t.knowledgeBaseTile ?? 'Knowledge base (FAQ)',
        icon: Icons.menu_book_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => KnowledgeBasePage(api: widget.api),
            ),
          );
        },
      ),
      _Entry(
        label: t.myAccount,
        icon: Icons.person_outline,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AccountPage(api: widget.api),
          ));
        },
      ),
    ];

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Theme tokens replace hardcoded colors so Dark Mode flips the whole surface.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundTop, backgroundBottom],
          ),
        ),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final theme = Theme.of(ctx);
            final textTheme = theme.textTheme;
            final scheme = theme.colorScheme;
            final rep = _myRep;
            final repTitle = _repTitle(context, rep);
            final hasContact = _repForContact().email.trim().isNotEmpty;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // UX: ruhiger Startbereich mit klaren Abständen.
                                if (_repLoading || rep != null)
                                  RepresentativeStrip(
                                    title: repTitle,
                                    loading: _repLoading,
                                    onRefreshTap: _initRep,
                                    onMailTap: hasContact ? () => _openRepContactForm(context) : null,
                                  ),
                                const SizedBox(height: 12),
                                _buildNewsSection(context),
                                const SizedBox(height: 16),
                                Text(
                                  t.quick_access_title,
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 22,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                GridView.count(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 1.1,
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  children: [
                                    for (final entry in tiles)
                                      DashboardTile(
                                        label: entry.label,
                                        icon: entry.icon,
                                        onTap: entry.onTap,
                                        showIndicator: entry.showIndicator,
                                        accentColor: scheme.primary,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  t.catalogs_title,
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 22,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _CatalogList(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _repTitle(BuildContext context, MyRep? rep) {
    final t = AppLocalizations.of(context)!;
    if (rep == null) return '—';
    final first = rep.firstName.trim();
    final last = rep.lastName.trim();
    final name = [first, last].where((s) => s.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : '—';
  }
}

// ---------------- Komponenten ----------------

class RepresentativeStrip extends StatelessWidget {
  final String title;
  final bool loading;
  final VoidCallback onRefreshTap;
  final VoidCallback? onMailTap;

  const RepresentativeStrip({
    super.key,
    required this.title,
    required this.loading,
    required this.onRefreshTap,
    this.onMailTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceOpacity = isDark ? 0.4 : 0.93;
    final radius = BorderRadius.circular(15);

    if (loading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(surfaceOpacity),
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52, maxHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _chipFill(scheme),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.handshake_outlined, color: scheme.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.contact_person_label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.15,
                        color: scheme.onSurface.withOpacity(0.75),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.15,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t.rep_contact_form,
                onPressed: onMailTap,
                icon: const Icon(Icons.mail_outline, size: 20),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                tooltip: t.refresh,
                onPressed: onRefreshTap,
                icon: const Icon(Icons.refresh, size: 20),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum NewsCardState { loading, ready, empty, error }

class NewsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String ctaLabel;
  final bool showIndicator;
  final NewsCardState state;
  final VoidCallback? onTap;

  const NewsCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.showIndicator,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final radius = BorderRadius.circular(20);

    // UX: kompakte News-Card mit Lade-/Fehlerzustand statt leerem Widget.
    String stateText;
    switch (state) {
      case NewsCardState.loading:
        stateText = AppLocalizations.of(context)!.loading;
        break;
      case NewsCardState.error:
        stateText = AppLocalizations.of(context)!.network_error_generic;
        break;
      case NewsCardState.empty:
        stateText = AppLocalizations.of(context)!.customerNewsEmpty;
        break;
      case NewsCardState.ready:
        stateText = subtitle;
        break;
    }

    return Semantics(
      button: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Variante A styling: white surface with soft shadow and border.
          color: scheme.surface,
          borderRadius: radius,
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: _shadowColor(theme),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _chipFill(scheme),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.campaign_outlined,
                              color: scheme.primary,
                              size: 22,
                            ),
                          ),
                          if (showIndicator)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: SizedBox(width: 10, height: 10),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              stateText,
                              maxLines: state == NewsCardState.ready ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: _subtitleColor(scheme),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onTap,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(ctaLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool showIndicator;
  final Color accentColor;

  const DashboardTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.accentColor,
    this.showIndicator = false,
  });

  @override
  State<DashboardTile> createState() => _DashboardTileState();
}

class _DashboardTileState extends State<DashboardTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    const radius = BorderRadius.all(Radius.circular(18));
    final baseFill = scheme.surface.withOpacity(isDark ? 0.88 : 0.96);
    final gradient = isDark
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface.withOpacity(0.92),
              scheme.surface.withOpacity(0.78),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              baseFill,
              scheme.surface.withOpacity(0.90),
            ],
          );
    final shadows = _pressed
        ? (isDark
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: scheme.primary.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: scheme.primary.withOpacity(0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ])
        : (isDark
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.55),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: scheme.primary.withOpacity(0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 14),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 26,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: scheme.primary.withOpacity(0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]);

    return Semantics(
      button: true,
      label: widget.label,
      child: ClipRRect(
        borderRadius: radius,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              // Unified tile widget + fixed accent bar alignment
              gradient: gradient,
              borderRadius: radius,
              border: Border.all(
                color: scheme.outlineVariant.withOpacity(isDark ? 0.35 : 0.65),
                width: 1.2,
              ),
              boxShadow: shadows,
            ),
            child: Stack(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onTap,
                    onTapDown: (_) => _setPressed(true),
                    onTapUp: (_) => _setPressed(false),
                    onTapCancel: () => _setPressed(false),
                    borderRadius: radius,
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Container(
                          height: 6,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.accentColor.withOpacity(0.95),
                                widget.accentColor.withOpacity(0.55),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withOpacity(isDark ? 0.20 : 0.12),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: isDark
                                                ? scheme.primary.withOpacity(0.18)
                                                : Colors.black.withOpacity(0.06),
                                            blurRadius: isDark ? 14 : 12,
                                            offset: Offset(0, isDark ? 8 : 6),
                                          ),
                                        ],
                                      ),
                                      child: Icon(widget.icon, color: scheme.primary, size: 26),
                                    ),
                                    if (widget.showIndicator)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: scheme.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SizedBox(width: 8, height: 8),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: scheme.onSurface,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Positioned.fill(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: 1.2,
                        color: Colors.white.withOpacity(isDark ? 0.06 : 0.35),
                      ),
                    ),
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

class CatalogListItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const CatalogListItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = AppLocalizations.of(context)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        // Variante A styling: white surface with soft shadow and border.
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: _shadowColor(theme),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: _subtitleColor(scheme)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: _subtitleColor(scheme)),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(t.catalog_open),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final localeCode = Localizations.localeOf(context).languageCode.toLowerCase();

    final labLink = _catalogLinkForLocale(_labCatalogLinks, localeCode);
    final dentLink = _catalogLinkForLocale(_dentCatalogLinks, localeCode);

    return Column(
      children: [
        CatalogListItem(
          title: t.catalog_lab_title,
          subtitle: labLink.label,
          icon: Icons.biotech_outlined,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PdfInAppPage(url: labLink.url, title: t.catalog_lab_title),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        CatalogListItem(
          title: t.catalog_dent_title,
          subtitle: dentLink.label,
          icon: Icons.medical_services_outlined,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PdfInAppPage(url: dentLink.url, title: t.catalog_dent_title),
              ),
            );
          },
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
  final VoidCallback onTap;
  final bool showIndicator;
  _Entry({
    required this.label,
    required this.icon,
    required this.onTap,
    this.showIndicator = false,
  });
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
