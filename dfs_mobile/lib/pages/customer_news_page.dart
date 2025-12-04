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
    final baseGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colorScheme.primary.withOpacity(isDark ? 0.55 : 0.72),
        colorScheme.secondary.withOpacity(isDark ? 0.38 : 0.54),
      ],
    );
    final accentGlow = colorScheme.tertiary.withOpacity(isDark ? 0.22 : 0.26);
    final textColor = colorScheme.onPrimary;
    final mutedText = textColor.withOpacity(0.84);
    final pinnedCount = entries.where((e) => e.pinned).length;
    final recentCount = entries
        .where((e) => e.publishedAt.isAfter(DateTime.now().subtract(const Duration(days: 30))))
        .length;
    final totalCount = entries.length;

    Widget statPill({
      required IconData icon,
      required String label,
      required String value,
      required bool compact,
    }) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 9,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(isDark ? 0.12 : 0.2),
          border: Border.all(color: Colors.white.withOpacity(0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.18 : 0.08),
              blurRadius: compact ? 8 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 16 : 18, color: textColor),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final tight = constraints.maxWidth < 360;
        // Provide a taller hero on compact widths to avoid overflow from
        // localized text wrapping across multiple lines.
        final heroHeight = tight
            ? 204.0
            : compact
                ? 188.0
                : 200.0;

        return Container(
          margin: EdgeInsets.fromLTRB(12, 10, 12, compact ? 6 : 10),
          constraints: BoxConstraints(minHeight: heroHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            gradient: baseGradient,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.24 : 0.14),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -36,
                child: Container(
                  width: heroHeight * 0.9,
                  height: heroHeight * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentGlow,
                    boxShadow: [
                      BoxShadow(
                        color: accentGlow.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: -14,
                bottom: -20,
                child: Container(
                  width: heroHeight * 0.7,
                  height: heroHeight * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(isDark ? 0.08 : 0.15),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 18,
                  vertical: compact ? 12 : 16,
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
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 9 : 11,
                                  vertical: compact ? 6 : 7,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.white.withOpacity(isDark ? 0.14 : 0.2),
                                  border: Border.all(color: Colors.white.withOpacity(0.28)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.campaign_rounded, size: 16, color: Colors.white),
                                    const SizedBox(width: 6),
                                    Text(
                                      t.customerNewsTitle,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                t.customerNewsSubtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w900,
                                  height: 1.25,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                t.customerNewsHeroLead,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: mutedText,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!tight) ...[
                          const SizedBox(width: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(isDark ? 0.12 : 0.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(isDark ? 0.18 : 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: textColor,
                              size: compact ? 28 : 32,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          statPill(
                            icon: Icons.auto_awesome_motion,
                            label: t.customerNewsHeroFreshLabel,
                            value: '${totalCount.clamp(0, 999)}+',
                            compact: compact,
                          ),
                          const SizedBox(width: 8),
                          statPill(
                            icon: Icons.push_pin_outlined,
                            label: t.customerNewsPinned,
                            value: '$pinnedCount',
                            compact: compact,
                          ),
                          const SizedBox(width: 8),
                          statPill(
                            icon: Icons.new_releases_outlined,
                            label: t.customerNewsHeroNewLabel,
                            value: '$recentCount',
                            compact: compact,
                          ),
                          const SizedBox(width: 8),
                          statPill(
                            icon: Icons.history_toggle_off_outlined,
                            label: t.customerNewsHeroDateLabel,
                            value: DateFormat.MMMd().format(DateTime.now()),
                            compact: compact,
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              foregroundColor: textColor,
                              backgroundColor: Colors.white.withOpacity(isDark ? 0.16 : 0.26),
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 12 : 14,
                                vertical: compact ? 8 : 9,
                              ),
                            ),
                            onPressed: () => _load(refresh: true),
                            icon: const Icon(Icons.refresh),
                            label: Text(t.refresh),
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
    );
  }
  Widget _buildPill(
    ThemeData theme,
    String label,
    Color color, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: color.withOpacity(0.16),
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
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              fontSize: (theme.textTheme.labelMedium?.fontSize ?? 12) * 0.9,
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
    final publishedLabel = _formatDate(t, entry.publishedAt);
    final updatedLabel = _formatDate(t, entry.updatedAt);
    final backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colorScheme.surfaceBright
            .withOpacity(theme.brightness == Brightness.dark ? 0.28 : 0.12),
        colorScheme.surface,
        colorScheme.surfaceVariant
            .withOpacity(theme.brightness == Brightness.dark ? 0.16 : 0.1),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: backgroundGradient,
        border: Border.all(color: accentColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(theme.brightness == Brightness.dark ? 0.28 : 0.1),
            blurRadius: isCompact ? 10 : 16,
            offset: Offset(0, isCompact ? 8 : 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  accentColor.withOpacity(theme.brightness == Brightness.dark ? 0.26 : 0.2),
                  accentColor.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.12),
                ],
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 16,
              vertical: isCompact ? 10 : 12,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isCompact ? 8 : 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white
                        .withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.22),
                  ),
                  child: Icon(
                    entry.pinned ? Icons.star_rounded : Icons.campaign_outlined,
                    size: isCompact ? 18 : 20,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
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
                          if (entry.updatedAt.isAfter(
                            entry.publishedAt.add(const Duration(minutes: 1)),
                          ))
                            _buildPill(
                              theme,
                              t.customerNewsUpdateLabel,
                              accentColor.withOpacity(0.92),
                              icon: Icons.bolt_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
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
                    width: isCompact ? 40 : 44,
                    height: isCompact ? 40 : 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: accentColor.withOpacity(theme.brightness == Brightness.dark ? 0.22 : 0.14),
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
                        Text(
                          t.customerNewsMarketingHook,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.24,
                          ),
                        ),
                        SizedBox(height: isCompact ? 10 : 12),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                t.customerNewsReadMore,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelLarge?.copyWith(
                                  color: accentColor.withOpacity(0.95),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
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
                            entry.updatedAt.isAfter(
                              entry.publishedAt.add(const Duration(minutes: 1)),
                            )
                                ? '${t.customerNewsUpdateLabel}: $updatedLabel'
                                : publishedLabel,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      ],
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
