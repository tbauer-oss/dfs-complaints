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

  Widget _buildHeader(AppLocalizations t, ThemeData theme) {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        theme.colorScheme.primary.withOpacity(theme.brightness == Brightness.dark ? 0.2 : 0.1),
        theme.colorScheme.surfaceVariant.withOpacity(0.05),
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: gradient,
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withOpacity(0.15),
                ),
                child: const Icon(Icons.campaign_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.customerNewsTitle,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.customerNewsSubtitle,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(AppLocalizations t, ThemeData theme, CustomerNewsEntry entry) {
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final chips = <Widget>[
      Chip(
        label: Text(_categoryLabel(t, entry.category)),
        backgroundColor: colorScheme.secondaryContainer,
      ),
      if (entry.pinned)
        Chip(
          label: Text(t.customerNewsPinned),
          backgroundColor: colorScheme.primaryContainer,
        ),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: chips,
            ),
            const SizedBox(height: 12),
            Text(
              entry.title,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              entry.summary,
              style: textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  _formatDate(t, entry.publishedAt),
                  style: textTheme.bodySmall,
                ),
                const Spacer(),
                if (entry.linkUrl != null)
                  TextButton.icon(
                    onPressed: () => _openLink(entry.linkUrl!),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(entry.linkLabel?.isNotEmpty == true
                        ? entry.linkLabel!
                        : t.customerNewsReadMore),
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
            SliverToBoxAdapter(child: _buildHeader(t, theme)),
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
