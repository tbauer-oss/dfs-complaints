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
      colors: [
        Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.35)!
            .withOpacity(isDark ? 0.7 : 1),
        colorScheme.primaryContainer.withOpacity(isDark ? 0.55 : 0.9),
      ],
    );
    final borderColor = colorScheme.outlineVariant.withOpacity(0.35);
    final textColor = theme.colorScheme.onSurface;
    final mutedText = textColor.withOpacity(0.8);
    final headerShadows = isDark
        ? null
        : [
            Shadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ];
    final highlightLabels = [t.newsCatProduct, t.newsCatApp, t.newsCatRegulatory];
    final pinnedCount = entries.where((e) => e.pinned).length;
    final recentCount = entries
        .where((e) => e.publishedAt.isAfter(DateTime.now().subtract(const Duration(days: 30))))
        .length;
    final totalCount = entries.length;

    Widget statTile({required IconData icon, required String value, required String label, required bool isCompact}) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 12,
          vertical: isCompact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(isDark ? 0.05 : 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(isDark ? 0.05 : 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(isDark ? 0.08 : 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: textColor),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    shadows: headerShadows,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget buildHeroVisual(double size, bool isCompact) {
      final accent = isDark
          ? colorScheme.primaryContainer.withOpacity(0.5)
          : Colors.white.withOpacity(0.85);
      final overlay = isDark
          ? colorScheme.onPrimary.withOpacity(0.1)
          : colorScheme.primary.withOpacity(0.1);
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [accent, overlay],
            stops: const [0.55, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.15),
              blurRadius: isCompact ? 12 : 14,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          Icons.local_fire_department_rounded,
          color: isDark ? colorScheme.onPrimaryContainer : colorScheme.primary,
          size: size * 0.42,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final double compactScale = isCompact ? 0.92 : 1.0;

        return Container(
          margin: EdgeInsets.fromLTRB(12, 10, 12, isCompact ? 6 : 10),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 18,
            vertical: isCompact ? 12 : 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
            gradient: gradient,
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.25 : 0.12),
                blurRadius: isCompact ? 12 : 18,
                offset: Offset(0, isCompact ? 8 : 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(isDark ? 0.08 : 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.campaign_outlined,
                            color: textColor,
                            size: isCompact ? 16 : 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.customerNewsSubtitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            height: 1.18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.customerNewsHeroLead,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: mutedText,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: isCompact ? 6 : 8,
                          runSpacing: 6,
                          children: highlightLabels
                              .map(
                                (label) => Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompact ? 8 : 10,
                                    vertical: isCompact ? 5 : 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    color: Colors.white.withOpacity(isDark ? 0.06 : 0.22),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(isDark ? 0.12 : 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_graph,
                                        size: 14,
                                        color: textColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        label,
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: textColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: (theme.textTheme.labelLarge?.fontSize ?? 14) *
                                              (compactScale * 0.98),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  buildHeroVisual(isCompact ? 86 : 96, isCompact),
                ],
              ),
              SizedBox(height: isCompact ? 10 : 12),
              Wrap(
                spacing: isCompact ? 8 : 10,
                runSpacing: isCompact ? 8 : 10,
                children: [
                  statTile(
                    icon: Icons.auto_awesome_motion,
                    value: '${totalCount.clamp(0, 999)}+',
                    label: t.customerNewsTitle,
                    isCompact: isCompact,
                  ),
                  statTile(
                    icon: Icons.push_pin,
                    value: '$pinnedCount',
                    label: t.customerNewsPinned,
                    isCompact: isCompact,
                  ),
                  statTile(
                    icon: Icons.flash_on,
                    value: '$recentCount',
                    label: t.customerNewsHeroFreshLabel,
                    isCompact: isCompact,
                  ),
                ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              fontSize: (theme.textTheme.labelMedium?.fontSize ?? 12) * 0.94,
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
    final listDate = DateFormat.MMMd(t.localeName).format(entry.publishedAt);
    final publishedLabel = _formatDate(t, entry.publishedAt);
    final updatedLabel = _formatDate(t, entry.updatedAt);
    final backgroundGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colorScheme.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.45 : 0.2),
        colorScheme.surface,
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: backgroundGradient,
        border: Border.all(color: accentColor.withOpacity(0.22)),
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
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              color: accentColor.withOpacity(theme.brightness == Brightness.dark ? 0.2 : 0.12),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 16,
              vertical: isCompact ? 8 : 10,
            ),
            child: Row(
              children: [
                Icon(
                  entry.pinned ? Icons.star_rounded : Icons.campaign_outlined,
                  size: isCompact ? 18 : 20,
                  color: accentColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 10 : 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: accentColor.withOpacity(0.18),
                      ),
                      child: Text(
                        t.customerNewsNewSince(listDate),
                        style: textTheme.labelLarge?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (entry.updatedAt.isAfter(
                      entry.publishedAt.add(const Duration(minutes: 1)),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildPill(
                          theme,
                          t.customerNewsUpdateLabel,
                          accentColor.withOpacity(0.9),
                          icon: Icons.bolt_rounded,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onToggle,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 14 : 16,
                isCompact ? 12 : 14,
                isCompact ? 14 : 16,
                isCompact ? 6 : 8,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withOpacity(0.22),
                          accentColor.withOpacity(0.12),
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.celebration_outlined,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: isCompact ? 6 : 8,
                          runSpacing: 4,
                          children: [
                            _buildPill(
                              theme,
                              _categoryLabel(t, entry.category),
                              accentColor,
                              icon: Icons.sell_outlined,
                            ),
                            if (entry.pinned)
                              _buildPill(
                                theme,
                                t.customerNewsPinned,
                                colorScheme.primary,
                                icon: Icons.push_pin_outlined,
                              ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 8 : 10),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 12 : 14,
                            vertical: isCompact ? 10 : 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              colors: [
                                accentColor.withOpacity(0.16),
                                accentColor.withOpacity(0.08),
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 18, color: accentColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  t.customerNewsMarketingHook,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: isCompact ? 10 : 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t.customerNewsReadMore,
                              style: textTheme.labelLarge?.copyWith(
                                color: accentColor.withOpacity(0.95),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            Icon(
                              expanded ? Icons.keyboard_arrow_up_rounded : Icons.chevron_right_rounded,
                              color: accentColor,
                            ),
                          ],
                        ),
                      ],
                    ),
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
                    Text(
                      entry.summary,
                      style: textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                    SizedBox(height: isCompact ? 12 : 16),
                    Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.event_available_rounded, size: 18, color: accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            publishedLabel,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    if (entry.updatedAt.isAfter(
                      entry.publishedAt.add(const Duration(minutes: 1)),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 18, color: accentColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                updatedLabel,
                                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (entry.linkUrl != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _openLink(entry.linkUrl!),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: Text(
                            entry.linkLabel?.isNotEmpty == true
                                ? entry.linkLabel!
                                : t.customerNewsReadMore,
                          ),
                        ),
                      ),
                    ],
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
