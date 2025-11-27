import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/wiki_article.dart';
import '../utils/lang_utils.dart';
import 'rep_wiki_detail_page.dart';

class RepWikiListPage extends StatefulWidget {
  final ApiClient api;
  const RepWikiListPage({super.key, required this.api});

  @override
  State<RepWikiListPage> createState() => _RepWikiListPageState();
}

class _RepWikiListPageState extends State<RepWikiListPage> {
  bool _loading = true;
  String? _err;
  List<WikiArticle> _articles = const [];

  String? _category;
  String? _productGroup;
  String? _type;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
      final items = await widget.api.fetchWikiArticles(
        category: _category,
        productGroup: _productGroup,
        type: _type,
        search: _searchCtrl.text.trim(),
        lang: lang,
      );
      if (!mounted) return;
      setState(() => _articles = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _categoryOptions() {
    final set = <String>{};
    for (final a in _articles) {
      set.add(a.categoryName ?? a.categoryId);
    }
    final list = set.toList();
    list.sort();
    return list;
  }

  List<String> _productGroupOptions() {
    final set = <String>{};
    for (final a in _articles) {
      set.addAll(a.productGroups);
    }
    final list = set.toList();
    list.sort();
    return list;
  }

  bool _isNew(WikiArticle a) {
    final now = DateTime.now();
    final diff = now.difference(a.updatedAt.isAfter(a.createdAt) ? a.updatedAt : a.createdAt);
    return diff.inDays <= 14;
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final filters = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kategorie'),
            value: _category,
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(value: null, child: Text('Alle Kategorien')),
            ]
                .followedBy(_categoryOptions().map(
                  (c) => DropdownMenuItem<String?>(value: c, child: Text(c)),
                ))
                .toList(),
            onChanged: (v) {
              setState(() => _category = v);
              _load();
            },
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Produktgruppe'),
            value: _productGroup,
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(value: null, child: Text('Alle')),
            ]
                .followedBy(_productGroupOptions().map(
                  (p) => DropdownMenuItem<String?>(value: p, child: Text(p)),
                ))
                .toList(),
            onChanged: (v) {
              setState(() => _productGroup = v);
              _load();
            },
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Typ'),
            value: _type,
            items: const <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(value: null, child: Text('Alle Typen')),
              DropdownMenuItem<String?>(value: 'faq', child: Text('FAQ')),
              DropdownMenuItem<String?>(value: 'safety', child: Text('Sicherheit')),
              DropdownMenuItem<String?>(value: 'error', child: Text('Fehler')),
              DropdownMenuItem<String?>(value: 'prevention', child: Text('Vermeidung')),
            ],
            onChanged: (v) {
              setState(() => _type = v);
              _load();
            },
          ),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              labelText: 'Suche (Titel, Teaser, Inhalt)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _load,
              ),
            ),
            onSubmitted: (_) => _load(),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
    );

    Widget buildCard(WikiArticle a) {
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RepWikiDetailPage(
              api: widget.api,
              articleId: a.id,
              initialArticle: a,
            ),
          ),
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                          Text(a.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(a.categoryName ?? a.categoryId, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (a.importance.toLowerCase() == 'high') _badge('WICHTIG', cs.error),
                        if (a.type == 'safety') _badge('SICHERHEIT', cs.primary),
                        if (_isNew(a)) _badge('NEU', cs.tertiary),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (a.productGroups.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: a.productGroups
                        .map((p) => Chip(
                              label: Text(p),
                              backgroundColor: cs.surfaceVariant,
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                Text(a.teaser, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildList() {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_err != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_err!, style: TextStyle(color: cs.error)),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _load, child: const Text('Erneut versuchen')),
            ],
          ),
        );
      }
      if (_articles.isEmpty) {
        return const Center(child: Text('Keine Artikel gefunden'));
      }

      return LayoutBuilder(
        builder: (_, cons) {
          final width = cons.maxWidth;
          if (width < 720) {
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (_, i) => buildCard(_articles[i]),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: _articles.length,
            );
          }
          final crossAxisCount = width > 1100 ? 3 : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
            ),
            itemCount: _articles.length,
            itemBuilder: (_, i) => buildCard(_articles[i]),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kundenwissen & Produktinfos', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        filters,
        const SizedBox(height: 12),
        buildList(),
      ],
    );
  }
}
