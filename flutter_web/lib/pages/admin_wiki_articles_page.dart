import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../api/client.dart';
import '../models/wiki_article.dart';
import '../models/wiki_category.dart';

class AdminWikiArticlesPage extends StatefulWidget {
  final ApiClient api;
  const AdminWikiArticlesPage({super.key, required this.api});

  @override
  State<AdminWikiArticlesPage> createState() => _AdminWikiArticlesPageState();
}

class _AdminWikiArticlesPageState extends State<AdminWikiArticlesPage> {
  bool _loading = true;
  String? _err;
  List<WikiArticle> _articles = const [];
  List<WikiCategory> _categories = const [];

  String? _categoryFilter;
  String? _productGroupFilter;
  String? _typeFilter;
  String? _statusFilter;
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
      final cats = await widget.api.adminFetchWikiCategories();
      final arts = await widget.api.adminFetchWikiArticles(
        category: _categoryFilter,
        productGroup: _productGroupFilter,
        type: _typeFilter,
        status: _statusFilter,
        search: _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _articles = arts;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  String _categoryLabel(String id) {
    final cat = _categories.firstWhere((c) => c.id == id, orElse: () => WikiCategory(
          id: id,
          name: id,
          description: '',
          icon: 'info',
          sortOrder: 0,
          isActive: true,
        ));
    return cat.name;
  }

  Future<void> _openPreview(WikiArticle article) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Artikel-Vorschau', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Mobile Ansicht'),
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: _ArticlePreview(article: article, maxWidth: 420),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Web Ansicht'),
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: _ArticlePreview(article: article, maxWidth: 900),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(WikiArticle article) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Artikel löschen?'),
        content: Text('Soll "${article.title}" gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.adminDeleteWikiArticle(article.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Artikel "${article.title}" gelöscht')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  Future<void> _openForm({WikiArticle? article}) async {
    final titleCtrl = TextEditingController(text: article?.title ?? '');
    final teaserCtrl = TextEditingController(text: article?.teaser ?? '');
    final contentCtrl = TextEditingController(text: article?.contentMarkdown ?? '');
    final productCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    List<String> productGroups = List.from(article?.productGroups ?? const []);
    List<String> tags = List.from(article?.tags ?? const []);
    String? categoryId = article?.categoryId ?? (_categories.isNotEmpty ? _categories.first.id : null);
    String type = article?.type ?? 'faq';
    String importance = article?.importance ?? 'normal';
    bool isActive = article?.isActive ?? true;

    Future<void> addProductGroup(String v) async {
      final value = v.trim();
      if (value.isEmpty) return;
      setState(() => productGroups = {...productGroups, value}.toList());
      productCtrl.clear();
    }

    Future<void> addTag(String v) async {
      final value = v.trim();
      if (value.isEmpty) return;
      setState(() => tags = {...tags, value}.toList());
      tagsCtrl.clear();
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void updateContent(String prefix) {
            final text = contentCtrl.text;
            final selection = contentCtrl.selection;
            final insertion = '$prefix ';
            final newText = text.replaceRange(selection.start, selection.end, insertion);
            contentCtrl.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: (selection.start + insertion.length)),
            );
          }

          return AlertDialog(
            title: Text(article == null ? 'Artikel anlegen' : 'Artikel bearbeiten'),
            content: SizedBox(
              width: 900,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: categoryId,
                      decoration: const InputDecoration(labelText: 'Kategorie *'),
                      items: _categories
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setModalState(() => categoryId = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Titel *'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: teaserCtrl,
                      decoration: const InputDecoration(labelText: 'Teaser'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: type,
                            decoration: const InputDecoration(labelText: 'Typ'),
                            items: const [
                              DropdownMenuItem(value: 'faq', child: Text('FAQ')),
                              DropdownMenuItem(value: 'safety', child: Text('Sicherheit')),
                              DropdownMenuItem(value: 'error', child: Text('Fehler')),
                              DropdownMenuItem(value: 'prevention', child: Text('Vermeidung')),
                            ],
                            onChanged: (v) => setModalState(() => type = v ?? 'faq'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: importance,
                            decoration: const InputDecoration(labelText: 'Wichtigkeit'),
                            items: const [
                              DropdownMenuItem(value: 'normal', child: Text('Normal')),
                              DropdownMenuItem(value: 'high', child: Text('Wichtig')),
                              DropdownMenuItem(value: 'critical', child: Text('Kritisch')),
                            ],
                            onChanged: (v) => setModalState(() => importance = v ?? 'normal'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              const Text('Produktgruppen:'),
                              ...productGroups
                                  .map(
                                    (pg) => Chip(
                                      label: Text(pg),
                                      onDeleted: () => setModalState(() => productGroups.remove(pg)),
                                    ),
                                  )
                                  .toList(),
                              SizedBox(
                                width: 180,
                                child: TextField(
                                  controller: productCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'hinzufügen',
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: () => setModalState(() => addProductGroup(productCtrl.text)),
                                    ),
                                  ),
                                  onSubmitted: (v) => setModalState(() => addProductGroup(v)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Tags'),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ...tags
                                      .map((t) => Chip(
                                            label: Text(t),
                                            onDeleted: () => setModalState(() => tags.remove(t)),
                                          ))
                                      .toList(),
                                  SizedBox(
                                    width: 180,
                                    child: TextField(
                                      controller: tagsCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Tag hinzufügen',
                                        suffixIcon: IconButton(
                                          icon: const Icon(Icons.add),
                                          onPressed: () => setModalState(() => addTag(tagsCtrl.text)),
                                        ),
                                      ),
                                      onSubmitted: (v) => setModalState(() => addTag(v)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Switch(value: isActive, onChanged: (v) => setModalState(() => isActive = v)),
                        const SizedBox(width: 6),
                        const Text('Aktiv')
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Markdown-Inhalt'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => updateContent('**Fett**'),
                          icon: const Icon(Icons.format_bold),
                          label: const Text('Bold'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('_Kursiv_'),
                          icon: const Icon(Icons.format_italic),
                          label: const Text('Italic'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('# H1'),
                          icon: const Icon(Icons.title),
                          label: const Text('H1'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('## H2'),
                          icon: const Icon(Icons.title_outlined),
                          label: const Text('H2'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('### H3'),
                          icon: const Icon(Icons.subtitles_outlined),
                          label: const Text('H3'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('- Punkt'),
                          icon: const Icon(Icons.format_list_bulleted),
                          label: const Text('Liste'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('1. Punkt'),
                          icon: const Icon(Icons.format_list_numbered),
                          label: const Text('Nummeriert'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('> INFO: Hinweis...'),
                          icon: const Icon(Icons.info_outline),
                          label: const Text('Info-Box'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('> WARNUNG: Achtung...'),
                          icon: const Icon(Icons.warning_amber_outlined),
                          label: const Text('Warn-Box'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => updateContent('[Linktext](https://example.com)'),
                          icon: const Icon(Icons.link),
                          label: const Text('Link'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: contentCtrl,
                      minLines: 10,
                      maxLines: 18,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    if (article != null)
                      Text('Erstellt: ${article.createdAt.toLocal()} | Geändert: ${article.updatedAt.toLocal()}'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
              FilledButton(
                onPressed: () async {
                  if (categoryId == null || titleCtrl.text.trim().isEmpty) return;
                  try {
                    await widget.api.adminSaveWikiArticle({
                      'categoryId': categoryId,
                      'productGroups': productGroups,
                      'type': type,
                      'title': titleCtrl.text.trim(),
                      'teaser': teaserCtrl.text.trim(),
                      'importance': importance,
                      'contentMarkdown': contentCtrl.text,
                      'tags': tags,
                      'isActive': isActive,
                    }, id: article?.id);
                    if (!mounted) return;
                    Navigator.pop(ctx, true);
                  } catch (e) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Fehler: $e')),
                    );
                  }
                },
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      _load();
    }

    titleCtrl.dispose();
    teaserCtrl.dispose();
    contentCtrl.dispose();
    productCtrl.dispose();
    tagsCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, cons) {
        final isCompact = cons.maxWidth < 1000;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_outlined),
                        const SizedBox(width: 8),
                        Text('Artikel verwalten', style: theme.textTheme.titleLarge),
                      ],
                    ),
                    SizedBox(
                      width: isCompact ? 210 : 240,
                      child: DropdownButtonFormField<String?>(
                        value: _categoryFilter,
                        decoration: const InputDecoration(labelText: 'Kategorie'),
                        onChanged: (v) {
                          setState(() => _categoryFilter = v);
                          _load();
                        },
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(value: null, child: Text('Alle Kategorien')),
                        ]
                            .followedBy(
                              _categories.map(
                                (c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    SizedBox(
                      width: isCompact ? 190 : 220,
                      child: DropdownButtonFormField<String?>(
                        value: _productGroupFilter,
                        decoration: const InputDecoration(labelText: 'Produktgruppe'),
                        onChanged: (v) {
                          setState(() => _productGroupFilter = v);
                          _load();
                        },
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(value: null, child: Text('Alle')),
                        ]
                            .followedBy(
                              _productGroupOptions().map(
                                (p) => DropdownMenuItem<String?>(value: p, child: Text(p)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    SizedBox(
                      width: isCompact ? 180 : 200,
                      child: DropdownButtonFormField<String?>(
                        value: _typeFilter,
                        decoration: const InputDecoration(labelText: 'Typ'),
                        onChanged: (v) {
                          setState(() => _typeFilter = v);
                          _load();
                        },
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Alle Typen')),
                          DropdownMenuItem(value: 'faq', child: Text('FAQ')),
                          DropdownMenuItem(value: 'safety', child: Text('Sicherheit')),
                          DropdownMenuItem(value: 'error', child: Text('Fehler')),
                          DropdownMenuItem(value: 'prevention', child: Text('Vermeidung')),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: isCompact ? 180 : 200,
                      child: DropdownButtonFormField<String?>(
                        value: _statusFilter,
                        decoration: const InputDecoration(labelText: 'Status'),
                        onChanged: (v) {
                          setState(() => _statusFilter = v);
                          _load();
                        },
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Alle')),
                          DropdownMenuItem(value: 'active', child: Text('Aktiv')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: isCompact ? 220 : 260,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(labelText: 'Suche Titel/Teaser/Tags'),
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Filtern',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                    FilledButton.icon(
                      onPressed: _loading ? null : () => _openForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('Neu'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_err!, style: TextStyle(color: cs.error)),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: cons.maxWidth - 32),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Titel')),
                              DataColumn(label: Text('Kategorie')),
                              DataColumn(label: Text('Produktgruppen')),
                              DataColumn(label: Text('Typ')),
                              DataColumn(label: Text('Wichtigkeit')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Geändert')),
                              DataColumn(label: Text('Aktionen')),
                            ],
                            rows: _articles
                                .map(
                                  (a) => DataRow(cells: [
                                    DataCell(Text(a.title)),
                                    DataCell(Text(_categoryLabel(a.categoryId))),
                                    DataCell(Text(a.productGroups.join(', '))),
                                    DataCell(Text(a.type)),
                                    DataCell(Text(a.importance)),
                                    DataCell(Chip(
                                      label: Text(a.isActive ? 'Aktiv' : 'Inaktiv'),
                                      backgroundColor: a.isActive ? cs.primaryContainer : cs.surfaceVariant,
                                    )),
                                    DataCell(Text(a.updatedAt.toLocal().toString().split('.').first)),
                                    DataCell(Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Vorschau',
                                          icon: const Icon(Icons.visibility_outlined),
                                          onPressed: () => _openPreview(a),
                                        ),
                                        IconButton(
                                          tooltip: 'Bearbeiten',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () => _openForm(article: a),
                                        ),
                                        IconButton(
                                          tooltip: 'Löschen',
                                          icon: const Icon(Icons.delete_outline),
                                          onPressed: () => _delete(a),
                                        ),
                                      ],
                                    )),
                                  ]),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArticlePreview extends StatelessWidget {
  final WikiArticle article;
  final double maxWidth;
  const _ArticlePreview({required this.article, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(article.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text(article.categoryName ?? article.categoryId)),
              if (article.productGroups.isNotEmpty)
                Chip(label: Text(article.productGroups.join(', '))),
              Chip(label: Text(article.type.toUpperCase())),
              Chip(label: Text(article.importance.toUpperCase())),
            ],
          ),
          const Divider(height: 20),
          MarkdownBody(
            data: article.contentMarkdown,
            styleSheet: MarkdownStyleSheet(
              h1: theme.textTheme.headlineSmall,
              h2: theme.textTheme.titleLarge,
              h3: theme.textTheme.titleMedium,
              blockquoteDecoration: BoxDecoration(
                color: cs.tertiaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border(left: BorderSide(color: cs.primary, width: 4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
