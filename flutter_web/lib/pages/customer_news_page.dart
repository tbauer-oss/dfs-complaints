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

  Widget _buildHeader(AppLocalizations t, ThemeData theme, List<CustomerNewsEntry> entries) {
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              colorScheme.surfaceVariant.withOpacity(0.9),
              colorScheme.primary.withOpacity(0.35),
            ]
          : [
              colorScheme.primaryContainer,
              colorScheme.primary,
            ],
    );
    final textColor = isDark ? colorScheme.onSurface : colorScheme.onPrimary;
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
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withOpacity(0.9),
              letterSpacing: 0.3,
            ),
          ),
        ],
      );
    }

    Widget buildHeroVisual() {
      final accent = textColor.withOpacity(isDark ? 0.2 : 0.15);
      return SizedBox(
        height: 160,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.6),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: textColor.withOpacity(0.4), width: 2),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome,
                color: textColor,
                size: 64,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
            blurRadius: 30,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: textColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.campaign_outlined, color: textColor, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                t.customerNewsTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.customerNewsSubtitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: textColor.withOpacity(0.95),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.customerNewsHeroLead,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor.withOpacity(0.9),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: highlightLabels
                    .map(
                      (label) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: textColor.withOpacity(isDark ? 0.08 : 0.18),
                          border: Border.all(color: textColor.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_graph, size: 16, color: textColor),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: statTile('${totalCount.clamp(0, 999)}+', t.customerNewsTitle)),
                  const SizedBox(width: 12),
                  Expanded(child: statTile('$pinnedCount', t.customerNewsPinned)),
                  const SizedBox(width: 12),
                  Expanded(child: statTile('$recentCount', t.customerNewsHeroFreshLabel)),
                ],
              ),
            ],
          );

          if (constraints.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 24),
                buildHeroVisual(),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 32),
              Expanded(child: buildHeroVisual()),
            ],
          );
        },
      ),
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

  Widget _buildNewsCard(AppLocalizations t, ThemeData theme, CustomerNewsEntry entry) {
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final accentColor = entry.pinned ? colorScheme.primary : colorScheme.secondary;
    final backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        accentColor.withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.12),
        colorScheme.surface,
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: backgroundGradient,
        border: Border.all(color: accentColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.4 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _buildPill(theme, _categoryLabel(t, entry.category), accentColor, icon: Icons.sell_outlined),
                if (entry.pinned)
                  _buildPill(theme, t.customerNewsPinned, colorScheme.primary, icon: Icons.push_pin_outlined),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withOpacity(0.18),
                  ),
                  child: Icon(Icons.auto_awesome_outlined, color: accentColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.summary,
                        style: textTheme.bodyMedium?.copyWith(height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  _formatDate(t, entry.publishedAt),
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (entry.linkUrl != null)
                  TextButton.icon(
                    onPressed: () => _openLink(entry.linkUrl!),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(
                      entry.linkLabel?.isNotEmpty == true ? entry.linkLabel! : t.customerNewsReadMore,
                    ),
                  ),
              ],
            ),
          ],
        ),
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
          (context, index) => _buildNewsCard(t, theme, _items[index]),
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
            SliverToBoxAdapter(child: _buildHeader(t, theme, _items)),
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
