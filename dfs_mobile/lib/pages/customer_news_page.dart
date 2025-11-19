// lib/pages/customer_news_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/customer_news_entry.dart';

class CustomerNewsPage extends StatefulWidget {
  final ApiClient api;
  const CustomerNewsPage({super.key, required this.api});

  @override
  State<CustomerNewsPage> createState() => _CustomerNewsPageState();
}

class _CustomerNewsPageState extends State<CustomerNewsPage> {
  bool _loading = true;
  String? _error;
  List<CustomerNewsEntry> _items = const [];
  final Set<String> _expandedEntries = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      if (_items.isEmpty || refresh) {
        _loading = true;
        if (refresh) _error = null;
      }
    });
    try {
      final list = await widget.api.fetchCustomerNews(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _categoryLabel(AppLocalizations t, String raw) {
    switch (raw) {
      case 'catalogs':
        return t.newsCatCatalogs;
      case 'technical':
        return t.newsCatTechnical;
      case 'regulatory':
        return t.newsCatRegulatory;
      case 'product':
        return t.newsCatProduct;
      case 'shortage':
        return t.newsCatShortage;
      case 'app':
        return t.newsCatApp;
      default:
        return t.newsCatGeneral;
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatDate(AppLocalizations t, DateTime dt) {
    final locale = t.localeName;
    final dateFmt = DateFormat.yMMMMd(locale).add_Hm();
    return dateFmt.format(dt);
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations t,
    ThemeData theme,
    List<CustomerNewsEntry> entries,
  ) {
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              colorScheme.surface,
              colorScheme.surfaceVariant.withOpacity(0.9),
            ]
          : [
              Color.lerp(colorScheme.primary, Colors.black, 0.25)!,
              colorScheme.primary,
            ],
    );
    final borderColor = isDark
        ? colorScheme.outline.withOpacity(0.35)
        : Colors.white.withOpacity(0.35);
    final textColor = isDark ? colorScheme.onSurface : Colors.white;
    final secondaryTextColor =
        isDark ? colorScheme.onSurfaceVariant : Colors.white.withOpacity(0.92);
    final headerShadows = !isDark
        ? [
            Shadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ]
        : null;
    final highlightLabels = [t.newsCatProduct, t.newsCatApp, t.newsCatRegulatory];
    final pinnedCount = entries.where((e) => e.pinned).length;
    final recentCount = entries
        .where((e) => e.publishedAt.isAfter(DateTime.now().subtract(const Duration(days: 30))))
        .length;
    final totalCount = entries.length;

    Widget statTile(String value, String label) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w800,
              shadows: headerShadows,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withOpacity(0.95),
              shadows: headerShadows,
            ),
          ),
        ],
      );
    }

    Widget buildHeroVisual(double height) {
      final accent = isDark
          ? colorScheme.primary.withOpacity(0.25)
          : Colors.white.withOpacity(0.25);
      final largeCircle = height * 0.75;
      final mediumCircle = height * 0.6;
      final smallCircle = height * 0.45;
      return SizedBox(
        height: height,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: largeCircle,
                height: largeCircle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: mediumCircle,
                height: mediumCircle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.6),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: smallCircle,
                height: smallCircle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: textColor.withOpacity(0.35), width: 2),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Icon(Icons.auto_awesome, color: textColor, size: 48),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final double compactScale = isCompact ? 0.88 : 0.95;

        return Container(
          margin: EdgeInsets.fromLTRB(10, 10, 10, isCompact ? 6 : 10),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 18,
            vertical: isDark
                ? (isCompact ? 10 : 14)
                : (isCompact ? 12 : 16),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isCompact ? 14 : 18),
            gradient: gradient,
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                blurRadius: isCompact ? 10 : 16,
                offset: Offset(0, isCompact ? 6 : 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isCompact
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? textColor.withOpacity(0.12)
                                      : Colors.black.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.campaign_outlined,
                                  color: textColor,
                                  size: 18,
                                  shadows: headerShadows,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                t.customerNewsTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w800,
                                  height: 1.05,
                                  fontSize:
                                      (theme.textTheme.titleMedium?.fontSize ?? 20) * compactScale,
                                  shadows: headerShadows,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.customerNewsSubtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: secondaryTextColor,
                                  height: 1.25,
                                  fontSize:
                                      (theme.textTheme.bodyMedium?.fontSize ?? 14) * compactScale,
                                  shadows: headerShadows,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.customerNewsHeroLead,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: secondaryTextColor,
                                  height: 1.3,
                                  fontSize:
                                      (theme.textTheme.bodySmall?.fontSize ?? 12) * compactScale,
                                  shadows: headerShadows,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        buildHeroVisual(68),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? textColor.withOpacity(0.12)
                                      : Colors.black.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.campaign_outlined,
                                  color: textColor,
                                  size: 22,
                                  shadows: headerShadows,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t.customerNewsTitle,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize:
                                      (theme.textTheme.titleLarge?.fontSize ?? 22) * 0.95,
                                  shadows: headerShadows,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.customerNewsSubtitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: secondaryTextColor,
                                  fontSize:
                                      (theme.textTheme.titleMedium?.fontSize ?? 18) * 0.94,
                                  shadows: headerShadows,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.customerNewsHeroLead,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: secondaryTextColor,
                                  height: 1.35,
                                  fontSize:
                                      (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.94,
                                  shadows: headerShadows,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        buildHeroVisual(86),
                      ],
                    ),
              SizedBox(height: isCompact ? 10 : 12),
              Wrap(
                spacing: isCompact ? 8 : 10,
                runSpacing: 8,
                children: highlightLabels
                    .map(
                      (label) => Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 10 : 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: isDark
                              ? colorScheme.surfaceVariant.withOpacity(0.5)
                              : Colors.white.withOpacity(0.2),
                          border: Border.all(
                            color: isDark
                                ? textColor.withOpacity(0.2)
                                : Colors.white.withOpacity(0.65),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_graph,
                              size: 14,
                              color: textColor.withOpacity(0.95),
                              shadows: headerShadows,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                                shadows: headerShadows,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              SizedBox(height: isCompact ? 10 : 14),
              LayoutBuilder(
                builder: (context, innerConstraints) {
                  final stats = [
                    statTile('${totalCount.clamp(0, 999)}+', t.customerNewsTitle),
                    statTile('$pinnedCount', t.customerNewsPinned),
                    statTile('$recentCount', t.customerNewsHeroFreshLabel),
                  ];

                  if (innerConstraints.maxWidth < 360) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final stat in stats) ...[stat, const SizedBox(height: 10)],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      for (final stat in stats) ...[
                        Expanded(child: stat),
                        if (stat != stats.last) SizedBox(width: isCompact ? 8 : 12),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPill(
    ThemeData theme,
    String label,
    Color color, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withOpacity(0.15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(
    BuildContext context,
    AppLocalizations t,
    ThemeData theme,
    CustomerNewsEntry entry,
    bool expanded,
    VoidCallback onToggle,
  ) {
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final isCompact = MediaQuery.of(context).size.width < 420;
    final accentColor = entry.pinned ? colorScheme.primary : colorScheme.secondary;
    final backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        accentColor.withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.1),
        colorScheme.surface,
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: backgroundGradient,
        border: Border.all(color: accentColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.08),
            blurRadius: isCompact ? 12 : 18,
            offset: Offset(0, isCompact ? 10 : 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onToggle,
            child: Padding(
              padding: EdgeInsets.all(isCompact ? 14 : 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(isCompact ? 8 : 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withOpacity(0.18),
                    ),
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      color: accentColor,
                      size: isCompact ? 18 : 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: accentColor,
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedCrossFade(
              crossFadeState:
                  expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: EdgeInsets.fromLTRB(
                    isCompact ? 16 : 20, 0, isCompact ? 16 : 20, isCompact ? 16 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: isCompact ? 6 : 8,
                      runSpacing: 6,
                      children: [
                        _buildPill(theme, _categoryLabel(t, entry.category), accentColor,
                            icon: Icons.sell_outlined),
                        if (entry.pinned)
                          _buildPill(theme, t.customerNewsPinned, colorScheme.primary,
                              icon: Icons.push_pin_outlined),
                      ],
                    ),
                    SizedBox(height: isCompact ? 10 : 12),
                    Text(
                      entry.summary,
                      style: textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                    SizedBox(height: isCompact ? 10 : 14),
                    const Divider(height: 1, thickness: 1),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final dateRow = Row(
                          children: [
                            Icon(Icons.calendar_today, size: 16, color: accentColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _formatDate(t, entry.publishedAt),
                                style:
                                    textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        );

                        final linkButton = entry.linkUrl != null
                            ? TextButton.icon(
                                onPressed: () => _openLink(entry.linkUrl!),
                                icon: const Icon(Icons.arrow_forward),
                                label: Text(
                                  entry.linkLabel?.isNotEmpty == true
                                      ? entry.linkLabel!
                                      : t.customerNewsReadMore,
                                ),
                              )
                            : null;

                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              dateRow,
                              if (linkButton != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: linkButton,
                                ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: dateRow),
                            if (linkButton != null) linkButton,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget bodyContent;
    if (_loading && _items.isEmpty) {
      bodyContent = const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null && _items.isEmpty) {
      bodyContent = SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.errorGeneric(_error!), textAlign: TextAlign.center),
          ),
        ),
      );
    } else if (_items.isEmpty) {
      bodyContent = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t.customerNewsEmpty,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    } else {
      bodyContent = SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = _items[index];
            final expanded = _expandedEntries.contains(entry.id);
            return _buildNewsCard(
              context,
              t,
              theme,
              entry,
              expanded,
              () {
                setState(() {
                  if (expanded) {
                    _expandedEntries.remove(entry.id);
                  } else {
                    _expandedEntries.add(entry.id);
                  }
                });
              },
            );
          },
          childCount: _items.length,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.customerNewsTitle),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context, t, theme, _items)),
            if (_error != null && _items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    t.customerNewsError(_error!),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            bodyContent,
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
