import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/wiki_article.dart';
import '../models/wiki_category.dart';

class AdminWikiArticlesPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback? onBack;
  const AdminWikiArticlesPage({super.key, required this.api, this.onBack});

  @override
  State<AdminWikiArticlesPage> createState() => _AdminWikiArticlesPageState();
}

class _AdminWikiArticlesPageState extends State<AdminWikiArticlesPage> {
  bool _loading = true;
  String? _err;
  List<WikiArticle> _articles = const [];
  List<WikiCategory> _categories = const [];
  final Set<String> _deletingIds = {};
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  double _horizontalOffset = 0;
  late final VoidCallback _horizontalOffsetListener;
  static const double _headerHeight = 56;
  Map<String, double> _columnWidths = const {
    'title': 200,
    'category': 150,
    'productGroups': 170,
    'type': 110,
    'importance': 120,
    'status': 120,
    'updated': 180,
    'actions': 140,
  };

  String? _categoryFilter;
  String? _productGroupFilter;
  String? _typeFilter;
  String? _statusFilter;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _restoreColumnWidths();
    _horizontalOffsetListener = () {
      if (!mounted) return;
      setState(() => _horizontalOffset = _horizontalController.offset);
    };
    _horizontalController.addListener(_horizontalOffsetListener);
  }

  @override
  void dispose() {
    _horizontalController.removeListener(_horizontalOffsetListener);
    _horizontalController.dispose();
    _verticalController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _restoreColumnWidths() {
    final raw = html.window.localStorage['adminWikiTableColumnWidths'];
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final restored = <String, double>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is num) restored[entry.key] = value.toDouble();
      }
      setState(() {
        _columnWidths = {
          ..._columnWidths,
          ...restored,
        };
      });
    } catch (_) {}
  }

  void _persistColumnWidths() {
    html.window.localStorage['adminWikiTableColumnWidths'] = jsonEncode(_columnWidths);
  }

  Future<void> _openColumnWidthDialog() async {
    final temp = Map<String, double>.from(_columnWidths);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Spaltenbreiten anpassen'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WidthSlider(
                  label: 'Titel',
                  value: temp['title']!,
                  min: 160,
                  max: 260,
                  onChanged: (v) => setDialogState(() => temp['title'] = v),
                ),
                _WidthSlider(
                  label: 'Kategorie',
                  value: temp['category']!,
                  min: 130,
                  max: 220,
                  onChanged: (v) => setDialogState(() => temp['category'] = v),
                ),
                _WidthSlider(
                  label: 'Produktgruppen',
                  value: temp['productGroups']!,
                  min: 140,
                  max: 240,
                  onChanged: (v) => setDialogState(() => temp['productGroups'] = v),
                ),
                _WidthSlider(
                  label: 'Typ',
                  value: temp['type']!,
                  min: 100,
                  max: 180,
                  onChanged: (v) => setDialogState(() => temp['type'] = v),
                ),
                _WidthSlider(
                  label: 'Wichtigkeit',
                  value: temp['importance']!,
                  min: 110,
                  max: 180,
                  onChanged: (v) => setDialogState(() => temp['importance'] = v),
                ),
                _WidthSlider(
                  label: 'Status',
                  value: temp['status']!,
                  min: 110,
                  max: 180,
                  onChanged: (v) => setDialogState(() => temp['status'] = v),
                ),
                _WidthSlider(
                  label: 'Geändert',
                  value: temp['updated']!,
                  min: 150,
                  max: 240,
                  onChanged: (v) => setDialogState(() => temp['updated'] = v),
                ),
                _WidthSlider(
                  label: 'Aktionen',
                  value: temp['actions']!,
                  min: 120,
                  max: 200,
                  onChanged: (v) => setDialogState(() => temp['actions'] = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _columnWidths = temp;
                });
                _persistColumnWidths();
                Navigator.pop(ctx);
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
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

  void _handlePanDrag(DragUpdateDetails details) {
    if (_horizontalController.hasClients) {
      final maxH = _horizontalController.position.maxScrollExtent;
      final newH = (_horizontalController.offset - details.delta.dx).clamp(0.0, maxH);
      _horizontalController.jumpTo(newH);
    }
    if (_verticalController.hasClients) {
      final maxV = _verticalController.position.maxScrollExtent;
      final newV = (_verticalController.offset - details.delta.dy).clamp(0.0, maxV);
      _verticalController.jumpTo(newV);
    }
  }

  Map<String, double> _resolvedWidths() {
    return {
      'title': _widthFor('title', min: 160, max: 260),
      'category': _widthFor('category', min: 130, max: 220),
      'productGroups': _widthFor('productGroups', min: 140, max: 240),
      'type': _widthFor('type', min: 100, max: 180),
      'importance': _widthFor('importance', min: 110, max: 180),
      'status': _widthFor('status', min: 110, max: 180),
      'updated': _widthFor('updated', min: 150, max: 240),
      'actions': _widthFor('actions', min: 120, max: 200),
    };
  }

  double _widthFor(String key, {required double min, required double max}) {
    final value = _columnWidths[key] ?? min;
    return value.clamp(min, max).toDouble();
  }

  double _tableWidth() {
    const double columnSpacing = 12;
    const double horizontalMargin = 12;
    final widths = _resolvedWidths();
    final double baseWidth = widths.values.fold(0, (sum, v) => sum + v);
    return baseWidth + columnSpacing * (widths.length - 1) + horizontalMargin * 2;
  }

  Widget _buildStickyHeader(ColorScheme cs, TextTheme textTheme) {
    const double columnSpacing = 12;
    const double horizontalMargin = 12;
    final widths = _resolvedWidths();
    final tableWidth = _tableWidth();

    Widget buildCell(String label, double width) {
      return SizedBox(
        width: width,
        child: Text(label, style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: .2)),
      );
    }

    return ClipRect(
      child: Transform.translate(
        offset: Offset(-_horizontalOffset, 0),
        child: Container(
          width: tableWidth,
          height: _headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              buildCell('Titel', widths['title']!),
              const SizedBox(width: columnSpacing),
              buildCell('Kategorie', widths['category']!),
              const SizedBox(width: columnSpacing),
              buildCell('Produktgruppen', widths['productGroups']!),
              const SizedBox(width: columnSpacing),
              buildCell('Typ', widths['type']!),
              const SizedBox(width: columnSpacing),
              buildCell('Wichtigkeit', widths['importance']!),
              const SizedBox(width: columnSpacing),
              buildCell('Status', widths['status']!),
              const SizedBox(width: columnSpacing),
              buildCell('Geändert', widths['updated']!),
              const SizedBox(width: columnSpacing),
              buildCell('Aktionen', widths['actions']!),
            ],
          ),
        ),
      ),
    );
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
        title: const Text('Artikel endgültig löschen?'),
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 32),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${article.title}" wird unwiderruflich entfernt.'),
            const SizedBox(height: 8),
            const Text('Diese Aktion kann nicht rückgängig gemacht werden.',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Jetzt löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deletingIds.add(article.id));
    try {
      await widget.api.adminDeleteWikiArticle(article.id);
      if (!mounted) return;
      setState(() {
        _articles = _articles.where((a) => a.id != article.id).toList();
        _deletingIds.remove(article.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Artikel "${article.title}" gelöscht')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingIds.remove(article.id));
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
            content: Scrollbar(
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 900),
                  child: SizedBox(
                    width: 900,
                    child: Scrollbar(
                      thumbVisibility: true,
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
                  ),
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
    final t = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, cons) {
        final isCompact = cons.maxWidth < 1000;
        return Card(
          elevation: 4,
          shadowColor: cs.shadow.withOpacity(.12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primaryContainer, cs.surface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.primary.withOpacity(.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            child: const Icon(Icons.menu_book_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.adminWikiBannerTitle,
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(t.adminWikiBannerSubtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (widget.onBack != null)
                              OutlinedButton.icon(
                                onPressed: widget.onBack,
                                icon: const Icon(Icons.arrow_back),
                                label: Text(t.adminWikiBannerBack),
                              ),
                            FilledButton.icon(
                              onPressed: _loading ? null : () => _openForm(),
                              icon: const Icon(Icons.add),
                              label: Text(t.adminWikiBannerNew),
                            ),
                          ],
                        ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(t.adminWikiFiltersTitle,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      SizedBox(
                        width: isCompact ? 210 : 240,
                        child: DropdownButtonFormField<String?>(
                          value: _categoryFilter,
                          decoration: InputDecoration(labelText: t.adminWikiFilterCategoryLabel),
                          onChanged: (v) {
                            setState(() => _categoryFilter = v);
                            _load();
                          },
                          items: <DropdownMenuItem<String?>>[
                            DropdownMenuItem<String?>(value: null, child: Text(t.adminWikiFilterCategoryAll)),
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
                          decoration: InputDecoration(labelText: t.adminWikiFilterProductGroupLabel),
                          onChanged: (v) {
                            setState(() => _productGroupFilter = v);
                            _load();
                          },
                          items: <DropdownMenuItem<String?>>[
                            DropdownMenuItem<String?>(value: null, child: Text(t.adminWikiFilterProductGroupAll)),
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
                          decoration: InputDecoration(labelText: t.adminWikiFilterTypeLabel),
                          onChanged: (v) {
                            setState(() => _typeFilter = v);
                            _load();
                          },
                          items: [
                            DropdownMenuItem(value: null, child: Text(t.adminWikiFilterTypeAll)),
                            DropdownMenuItem(value: 'faq', child: Text(t.adminWikiFilterTypeFaq)),
                            DropdownMenuItem(value: 'safety', child: Text(t.adminWikiFilterTypeSafety)),
                            DropdownMenuItem(value: 'error', child: Text(t.adminWikiFilterTypeError)),
                            DropdownMenuItem(value: 'prevention', child: Text(t.adminWikiFilterTypePrevention)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: isCompact ? 180 : 200,
                        child: DropdownButtonFormField<String?>(
                          value: _statusFilter,
                          decoration: InputDecoration(labelText: t.adminWikiFilterStatusLabel),
                          onChanged: (v) {
                            setState(() => _statusFilter = v);
                            _load();
                          },
                          items: [
                            DropdownMenuItem(value: null, child: Text(t.adminWikiFilterStatusAll)),
                            DropdownMenuItem(value: 'active', child: Text(t.adminWikiFilterStatusActive)),
                            DropdownMenuItem(value: 'inactive', child: Text(t.adminWikiFilterStatusInactive)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: isCompact ? 220 : 260,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(labelText: t.adminWikiFilterSearchLabel),
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                      IconButton(
                        tooltip: t.adminWikiFilterTooltip,
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _openColumnWidthDialog,
                        icon: const Icon(Icons.view_column_rounded),
                        label: Text(t.adminWikiFilterColumnsWidth),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(minHeight: 3),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_err!, style: TextStyle(color: cs.error)),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tableWidth = _tableWidth();
                      final widths = _resolvedWidths();
                      final double bodyHeight = constraints.maxHeight > _headerHeight
                          ? constraints.maxHeight - _headerHeight
                          : 0;
                      return ScrollConfiguration(
                        behavior: _TableDragScrollBehavior(),
                        child: GestureDetector(
                          onPanUpdate: _handlePanDrag,
                          child: Stack(
                            children: [
                              _buildStickyHeader(cs, theme.textTheme),
                              Padding(
                                padding: EdgeInsets.only(top: _headerHeight),
                                child: Scrollbar(
                                  controller: _verticalController,
                                  thumbVisibility: true,
                                  trackVisibility: true,
                                  notificationPredicate: (notification) =>
                                      notification.metrics.axis == Axis.vertical,
                                  scrollbarOrientation: ScrollbarOrientation.right,
                                  child: SingleChildScrollView(
                                    controller: _verticalController,
                                    child: Scrollbar(
                                      controller: _horizontalController,
                                      thumbVisibility: true,
                                      trackVisibility: true,
                                      notificationPredicate: (notification) =>
                                          notification.metrics.axis == Axis.horizontal,
                                      scrollbarOrientation: ScrollbarOrientation.bottom,
                                      child: SingleChildScrollView(
                                        controller: _horizontalController,
                                        scrollDirection: Axis.horizontal,
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minWidth: tableWidth,
                                            maxWidth: tableWidth,
                                            minHeight: bodyHeight,
                                          ),
                                          child: DataTableTheme(
                                            data: DataTableThemeData(
                                              dataRowColor: WidgetStateProperty.resolveWith(
                                                (states) => states.contains(WidgetState.hovered)
                                                    ? cs.surfaceContainerHighest
                                                    : cs.surface,
                                              ),
                                              dividerThickness: 0.5,
                                              horizontalMargin: 10,
                                              columnSpacing: 12,
                                              dataRowMinHeight: 52,
                                              dataRowMaxHeight: 160,
                                              headingRowHeight: 0,
                                            ),
                                            child: DataTable(
                                              columns: const [
                                                DataColumn(label: SizedBox.shrink()),
                                                DataColumn(label: SizedBox.shrink()),
                                                DataColumn(label: SizedBox.shrink()),
                                                DataColumn(label: SizedBox.shrink()),
                                                DataColumn(label: SizedBox.shrink()),
                                                DataColumn(label: SizedBox.shrink()),
                                                DataColumn(label: SizedBox.shrink()),
                                                DataColumn(label: SizedBox.shrink()),
                                              ],
                                              rows: _articles
                                                  .map(
                                                    (a) => DataRow(cells: [
                                                      DataCell(
                                                        SizedBox(
                                                          width: widths['title'],
                                                          child: Text(
                                                            a.title,
                                                            softWrap: true,
                                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        SizedBox(
                                                          width: widths['category'],
                                                          child: Text(
                                                            _categoryLabel(a.categoryId),
                                                            softWrap: true,
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        SizedBox(
                                                          width: widths['productGroups'],
                                                          child: Text(
                                                            a.productGroups.join(', '),
                                                            softWrap: true,
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        SizedBox(
                                                          width: widths['type'],
                                                          child: Text(
                                                            a.type,
                                                            softWrap: true,
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        SizedBox(
                                                          width: widths['importance'],
                                                          child: Text(
                                                            a.importance,
                                                            softWrap: true,
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        SizedBox(
                                                          width: widths['status'],
                                                          child: Chip(
                                                            label: Text(a.isActive ? 'Aktiv' : 'Inaktiv'),
                                                            backgroundColor:
                                                                a.isActive ? cs.primaryContainer : cs.surfaceVariant,
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        SizedBox(
                                                          width: widths['updated'],
                                                          child: Text(
                                                            a.updatedAt.toLocal().toString().split('.').first,
                                                            softWrap: true,
                                                          ),
                                                        ),
                                                      ),
                                                      DataCell(
                                                        SizedBox(
                                                          width: widths['actions'],
                                                          child: Row(
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
                                                                onPressed: _deletingIds.contains(a.id)
                                                                    ? null
                                                                    : () => _delete(a),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ]),
                                                  )
                                                  .toList(),
                                            ),
                                          ),
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

class _WidthSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _WidthSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text('${value.toStringAsFixed(0)} px', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _TableDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
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
