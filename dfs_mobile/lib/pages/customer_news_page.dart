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
        colorScheme.primary.withOpacity(isDark ? 0.65 : 0.78),
        Color.lerp(colorScheme.secondary, colorScheme.tertiary, 0.4)!
            .withOpacity(isDark ? 0.36 : 0.52),
      ],
    );
    final textColor = colorScheme.onPrimaryContainer;
    final mutedText = textColor.withOpacity(0.82);
    final highlightLabels = [
      t.newsCatProduct,
      t.newsCatApp,
      t.newsCatRegulatory,
    ];
    final pinnedCount = entries.where((e) => e.pinned).length;
    final recentCount = entries
        .where((e) => e.publishedAt.isAfter(DateTime.now().subtract(const Duration(days: 30))))
        .length;
    final totalCount = entries.length;

    Widget statTile({
      required IconData icon,
      required String value,
      required String label,
      required bool isCompact,
    }) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 12,
          vertical: isCompact ? 7 : 9,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(isDark ? 0.12 : 0.18),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isCompact ? 14 : 16, color: textColor),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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

    Widget buildHeroVisual(double size, bool isCompact) {
      final accent = isDark
          ? colorScheme.primaryContainer.withOpacity(0.6)
          : Colors.white.withOpacity(0.9);
      final overlay = colorScheme.onPrimaryContainer.withOpacity(0.15);
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.94, end: 1.0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        builder: (context, value, _) {
          final effectiveSize = size * value;
          return Container(
            width: effectiveSize,
            height: effectiveSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [accent, overlay],
                stops: const [0.6, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.12),
                  blurRadius: isCompact ? 8 : 12,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: isDark ? colorScheme.onPrimary : colorScheme.primary,
              size: effectiveSize * 0.36,
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final isTight = constraints.maxWidth < 360;
        final heroSize = isCompact ? 64.0 : 76.0;

        return Container(
          margin: EdgeInsets.fromLTRB(12, 8, 12, isCompact ? 6 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
            gradient: gradient,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.22 : 0.14),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -14,
                child: Container(
                  width: heroSize * 1.4,
                  height: heroSize * 1.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(isDark ? 0.08 : 0.14),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 10,
                child: Row(
                  children: List.generate(
                    4,
                    (i) => Padding(
                      padding: EdgeInsets.only(right: isCompact ? 6 : 8),
                      child: Icon(
                        Icons.auto_awesome,
                        color: Colors.white.withOpacity(0.35 - (i * 0.05)),
                        size: isCompact ? 14 : 16,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 12 : 14,
                  vertical: isCompact ? 10 : 12,
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
                                  horizontal: isCompact ? 9 : 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.white.withOpacity(isDark ? 0.16 : 0.22),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.28),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.campaign_rounded, size: 16, color: textColor),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w900,
                                  height: 1.2,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.customerNewsHeroLead,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: mutedText,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: isCompact ? 30 : 32,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: highlightLabels.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final label = highlightLabels[index];
                                    return Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isCompact ? 9 : 11,
                                        vertical: isCompact ? 6 : 7,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: Colors.white.withOpacity(isDark ? 0.12 : 0.2),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.26),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.local_fire_department, size: 14, color: textColor),
                                          const SizedBox(width: 6),
                                          Text(
                                            label,
                                            style: theme.textTheme.labelMedium?.copyWith(
                                              color: textColor,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isTight) ...[
                          const SizedBox(width: 10),
                          buildHeroVisual(heroSize, isCompact),
                        ],
                      ],
                    ),
                    if (isTight) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.center,
                        child: buildHeroVisual(heroSize * 0.9, isCompact),
                      ),
                    ],
                    SizedBox(height: isCompact ? 10 : 12),
                    Wrap(
                      spacing: isCompact ? 8 : 10,
                      runSpacing: isCompact ? 8 : 10,
                      children: [
                        statTile(
                          icon: Icons.auto_awesome_motion,
                          value: '${totalCount.clamp(0, 999)}+',
                          label: t.customerNewsHeroFreshLabel,
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
                          label: t.customerNewsTitle,
                          isCompact: isCompact,
                        ),
                      ],
                    ),
                    SizedBox(height: isCompact ? 10 : 12),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: Size(isCompact ? double.infinity : 0, 44),
                        backgroundColor: Colors.white.withOpacity(isDark ? 0.14 : 0.2),
                        foregroundColor: textColor,
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 12 : 16,
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
        colorScheme.surfaceBright.withOpacity(theme.brightness == Brightness.dark ? 0.32 : 0.14),
        colorScheme.surface,
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
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
              color: accentColor.withOpacity(theme.brightness == Brightness.dark ? 0.2 : 0.12),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 16,
              vertical: isCompact ? 8 : 10,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isCompact ? 8 : 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withOpacity(theme.brightness == Brightness.dark ? 0.26 : 0.18),
                  ),
                  child: Icon(
                    entry.pinned ? Icons.star_rounded : Icons.campaign_outlined,
                    size: isCompact ? 18 : 20,
                    color: colorScheme.onPrimaryContainer,
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
                          fontWeight: FontWeight.w800,
                          height: 1.18,
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
