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

  final ScrollController _scrollCtrl = ScrollController();

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
    _scrollCtrl.dispose();
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
        color: color.withOpacity(.08),
        border: Border.all(color: color.withOpacity(.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, letterSpacing: .2)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final filters = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.surfaceContainerHighest, cs.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Text('Feinjustierung', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Filter anwenden'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
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
                      icon: const Icon(Icons.search_rounded),
                      onPressed: _load,
                    ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    Widget buildCard(WikiArticle a) {
      return _ArticleCard(
        article: a,
        badgeBuilder: _badge,
        isNew: _isNew(a),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RepWikiDetailPage(
              api: widget.api,
              articleId: a.id,
              initialArticle: a,
            ),
          ),
        ),
      );
    }

    Widget buildList(double width) {
      final grouped = <String, List<WikiArticle>>{};
      for (final a in _articles) {
        final key = a.categoryName ?? a.categoryId ?? 'Allgemein';
        grouped.putIfAbsent(key, () => []).add(a);
      }
      final sortedCategories = grouped.keys.toList()..sort();

      if (_loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 80, height: 80, child: CircularProgressIndicator(strokeWidth: 5)),
              SizedBox(height: 16),
              Text('Wissensdatenbank wird geladen...'),
            ],
          ),
        );
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

      final crossAxisCount = width >= 1400
          ? 4
          : width >= 1150
              ? 3
              : width >= 760
                  ? 2
                  : 1;
      final aspectRatio = width >= 1400
          ? 2.4
          : width >= 1150
              ? 2.1
              : width >= 760
                  ? 1.75
                  : 1.2;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final category in sortedCategories) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.folder_special_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    category,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant.withOpacity(.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${grouped[category]!.length} Artikel',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: aspectRatio,
              ),
              itemCount: grouped[category]!.length,
              itemBuilder: (_, i) => buildCard(grouped[category]![i]),
            ),
            const SizedBox(height: 18),
          ],
        ],
      );
    }

    final header = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(.15), blurRadius: 26, offset: const Offset(0, 12))],
        border: Border.all(color: cs.primary.withOpacity(.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            child: const Icon(Icons.menu_book_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vertreter-Wiki', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Aktuelle Produkt- und Sicherheitsinfos in einem modernen, klaren Layout. Filtern Sie Inhalte blitzschnell und öffnen Sie Details mit sanften Übergängen.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 32; // account for horizontal padding below
        final slivers = <Widget>[
          SliverToBoxAdapter(child: header),
          SliverToBoxAdapter(child: filters),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ];

        Widget status(Widget child) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: child),
              ),
            );

        if (_loading) {
          slivers.add(
            status(const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 80, height: 80, child: CircularProgressIndicator(strokeWidth: 5)),
                SizedBox(height: 16),
                Text('Wissensdatenbank wird geladen...'),
              ],
            )),
          );
        } else if (_err != null) {
          slivers.add(
            status(Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_err!, style: TextStyle(color: cs.error)),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _load, child: const Text('Erneut versuchen')),
              ],
            )),
          );
        } else if (_articles.isEmpty) {
          slivers.add(status(const Text('Keine Artikel gefunden')));
        } else {
          final list = buildList(width);
          slivers.add(SliverToBoxAdapter(child: list));
        }

        return Scrollbar(
          thumbVisibility: true,
          controller: _scrollCtrl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: CustomScrollView(
              controller: _scrollCtrl,
              slivers: slivers,
            ),
          ),
        );
      },
    );
  }
}

class _ArticleCard extends StatefulWidget {
  final WikiArticle article;
  final bool isNew;
  final void Function()? onTap;
  final Widget Function(String label, Color color) badgeBuilder;

  const _ArticleCard({
    required this.article,
    required this.isNew,
    required this.badgeBuilder,
    this.onTap,
  });

  @override
  State<_ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<_ArticleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = widget.article;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..translate(0.0, _hovered ? -4 : 0.0),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(_hovered ? .18 : .10),
              blurRadius: _hovered ? 16 : 10,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.menu_book_rounded, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: .1),
                            ),
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                Icon(Icons.folder_outlined, size: 18, color: cs.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  a.categoryName ?? a.categoryId,
                                  style:
                                      Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (a.importance.toLowerCase() == 'high') widget.badgeBuilder('WICHTIG', cs.error),
                          if (a.type == 'safety') widget.badgeBuilder('SICHERHEIT', cs.primary),
                          if (widget.isNew) widget.badgeBuilder('NEU', cs.tertiary),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (a.productGroups.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ...a.productGroups.take(2).map(
                              (p) => Chip(
                                label: Text(p),
                                labelStyle: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                                backgroundColor: cs.surfaceVariant.withOpacity(.5),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                side: BorderSide(color: cs.outlineVariant.withOpacity(.7)),
                              ),
                            ),
                        if (a.productGroups.length > 2)
                          Chip(
                            label: Text('+${a.productGroups.length - 2}'),
                            labelStyle: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                            backgroundColor: cs.surfaceVariant.withOpacity(.5),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            side: BorderSide(color: cs.outlineVariant.withOpacity(.7)),
                          ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    a.teaser,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.4, color: cs.onSurfaceVariant.withOpacity(.9)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.arrow_outward_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Text('Details öffnen', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _hovered ? 1 : 0,
                        child: Icon(Icons.keyboard_arrow_right, color: cs.primary),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
