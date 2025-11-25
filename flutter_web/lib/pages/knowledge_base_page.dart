import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../api/client.dart';
import '../data/knowledge_base_data.dart';
import '../l10n/app_localizations.dart';
import '../models/faq.dart';
import '../utils/lang_utils.dart';

class KnowledgeBasePage extends StatefulWidget {
  final ApiClient api;
  const KnowledgeBasePage({super.key, required this.api});

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String? _selectedCategory;
  bool _loading = true;
  String? _error;
  bool _usingLegacyFallback = false;
  List<FaqCategory> _categories = const [];
  List<FaqEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFaq());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  KnowledgeCategory? _legacyCategoryForId(String categoryId) {
    final normalized = categoryId.replaceFirst(RegExp(r'^legacy_'), '');
    for (final cat in KnowledgeCategory.values) {
      if (knowledgeCategoryCode(cat) == normalized) return cat;
    }
    return null;
  }

  IconData _categoryIcon(String categoryId) {
    final legacy = _legacyCategoryForId(categoryId);
    switch (legacy) {
      case KnowledgeCategory.aGeneral:
        return Icons.info_outline;
      case KnowledgeCategory.bDiamond:
        return Icons.diamond_outlined;
      case KnowledgeCategory.cCarbide:
        return Icons.construction_outlined;
      case KnowledgeCategory.dCeramic:
        return Icons.blur_on_outlined;
      case KnowledgeCategory.ePolishers:
        return Icons.brush_outlined;
      case KnowledgeCategory.fReprocessing:
        return Icons.autorenew_outlined;
      case KnowledgeCategory.gApp:
        return Icons.app_shortcut_outlined;
      case KnowledgeCategory.hAnalysis:
        return Icons.analytics_outlined;
      case KnowledgeCategory.iPhotos:
        return Icons.photo_camera_outlined;
      case KnowledgeCategory.jMisconceptions:
        return Icons.help_outline;
      default:
        return Icons.psychology_outlined;
    }
  }

  Future<void> _loadFaq({bool refresh = false}) async {
    setState(() {
      _loading = true;
      if (!refresh) _error = null;
      _usingLegacyFallback = false;
    });

    try {
      final data = await widget.api.fetchFaq(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _categories = data.categories;
        _entries = data.entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      final fallback = t == null ? null : _legacyData(t);
      setState(() {
        _error = e.toString();
        if (fallback != null) {
          _categories = fallback.categories;
          _entries = fallback.entries;
          _usingLegacyFallback = true;
        }
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  FaqData _legacyData(AppLocalizations t) {
    final cats = KnowledgeCategory.values
        .map(
          (cat) => FaqCategory(
            id: knowledgeCategoryCode(cat),
            title: knowledgeCategoryLabel(cat, t),
            order: KnowledgeCategory.values.indexOf(cat),
            active: true,
          ),
        )
        .toList();

    final entries = knowledgeItems
        .map(
          (item) => FaqEntry(
            id: 'legacy_${item.id}',
            categoryId: knowledgeCategoryCode(item.category),
            question: item.question(t),
            answer: item.answer(t),
            audience: 'both',
            order: item.id,
            active: true,
          ),
        )
        .toList();

    return FaqData(categories: cats, entries: entries, audience: 'customer');
  }

  List<String> _splitAnswer(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.replaceFirst(RegExp(r'^[•\-\u2022]\s*'), ''))
        .toList();
  }

  List<_FaqItemView> _filteredItems() {
    final query = _searchQuery.trim().toLowerCase();
    final lang = normalizeLangCode(Localizations.localeOf(context).languageCode);
    final catById = {for (final cat in _categories) cat.id: cat};

    final List<_FaqItemView> filtered = [];
    for (final entry in _entries) {
      final cat = catById[entry.categoryId];
      if (cat == null) continue;
      if (_selectedCategory != null && entry.categoryId != _selectedCategory) {
        continue;
      }

      final question = entry.localizedQuestion(lang);
      final answer = entry.localizedAnswer(lang);

      if (query.isNotEmpty) {
        final q = question.toLowerCase();
        final a = answer.toLowerCase();
        if (!q.contains(query) && !a.contains(query)) continue;
      }

      filtered.add(_FaqItemView(entry: entry, category: cat, question: question, answer: answer));
    }

    filtered.sort((a, b) {
      final catOrder = a.category.order.compareTo(b.category.order);
      if (catOrder != 0) return catOrder;
      final entryOrder = a.entry.order.compareTo(b.entry.order);
      if (entryOrder != 0) return entryOrder;
      return a.question.compareTo(b.question);
    });

    return filtered;
  }

  Widget _buildQuestionCard({
    required BuildContext context,
    required String question,
    required List<String> answers,
    required String categoryId,
    required Color primary,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashFactory: InkRipple.splashFactory,
        ),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          leading: Icon(
            _categoryIcon(categoryId),
            color: primary,
          ),
          title: Text(
            question,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          iconColor: primary,
          collapsedIconColor: primary,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: answers
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              width: 12,
                              height: 3,
                              decoration: BoxDecoration(
                                color: primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MarkdownBody(
                              data: a,
                              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                                p: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                                strong: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                                em: theme.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  height: 1.4,
                                ),
                                pPadding: EdgeInsets.zero,
                                textScaleFactor:
                                    MediaQuery.of(context).textScaler.scale(1.0),
                              ),
                              builders: {
                                'mark': _HighlightBuilder(
                                  baseStyle: theme.textTheme.bodyMedium,
                                  highlightColor: primary,
                                ),
                                'u': _UnderlineBuilder(
                                  baseStyle: theme.textTheme.bodyMedium,
                                ),
                              },
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? colorScheme.secondary : const Color(0xFF0865A2);
    final gradient = LinearGradient(
      colors: isDark
          ? const [Color(0xFF0B1525), Color(0xFF111C2E)]
          : const [Color(0xFFE7F3FB), Colors.white],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    final items = _filteredItems();
    final sortedCategories = [..._categories]
      ..sort((a, b) => a.order.compareTo(b.order));

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: Text(t.knowledgeBaseTile ?? 'Knowledge base (FAQ)'),
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header / Hero
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  color: theme.cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                primary,
                                primary.withOpacity(0.7),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.psychology_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.kb_title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.kb_intro,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.8),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Suchfeld
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: t.kb_search_hint,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: theme.cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide:
                          BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withOpacity(0.6),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: primary, width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Kategorie-Filter (Chips)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(t.kb_filter_all),
                      selected: _selectedCategory == null,
                      onSelected: (_) {
                        setState(() => _selectedCategory = null);
                      },
                    ),
                    ...sortedCategories.map((cat) {
                      return ChoiceChip(
                        label: Text(cat.title),
                        selected: _selectedCategory == cat.id,
                        onSelected: (sel) {
                          setState(() {
                            _selectedCategory = sel ? cat.id : null;
                          });
                        },
                      );
                    }),
                  ],
                ),

                const SizedBox(height: 10),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      color: colorScheme.errorContainer,
                      child: ListTile(
                        leading: Icon(Icons.warning_amber_rounded,
                            color: colorScheme.onErrorContainer),
                        title: Text(
                          _usingLegacyFallback
                              ? 'Aktuelle FAQ konnten nicht geladen werden. Zeige Offline-Version.'
                              : 'Aktuelle FAQ konnten nicht geladen werden.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh),
                          color: colorScheme.onErrorContainer,
                          onPressed: () => _loadFaq(refresh: true),
                        ),
                      ),
                    ),
                  ),

                // Liste der Einträge
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                          ? Center(
                              child: Text(
                                t.kb_empty_message,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () => _loadFaq(refresh: true),
                                  child: ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  final question = item.question;
                                  final answerLines =
                                      _splitAnswer(item.answer);

                                  final bool showCategoryHeader;
                                  if (index == 0) {
                                    showCategoryHeader = true;
                                  } else {
                                    showCategoryHeader =
                                        items[index - 1].category.id !=
                                            item.category.id;
                                  }

                                  final widgets = <Widget>[];

                                  if (showCategoryHeader) {
                                    widgets.add(
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            top: 16, bottom: 4),
                                        child: Text(
                                          item.category.title,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  widgets.add(
                                    _buildQuestionCard(
                                      context: context,
                                      question: question,
                                      answers: answerLines,
                                      categoryId: item.category.id,
                                      primary: primary,
                                    ),
                                  );

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: widgets,
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FaqItemView {
  final FaqEntry entry;
  final FaqCategory category;
  final String question;
  final String answer;

  const _FaqItemView({
    required this.entry,
    required this.category,
    required this.question,
    required this.answer,
  });
}

class _UnderlineBuilder extends MarkdownElementBuilder {
  _UnderlineBuilder({required this.baseStyle});

  final TextStyle? baseStyle;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final style = (baseStyle ?? const TextStyle())
        .merge(preferredStyle)
        .copyWith(decoration: TextDecoration.underline);
    return Text.rich(TextSpan(text: element.textContent, style: style));
  }
}

class _HighlightBuilder extends MarkdownElementBuilder {
  _HighlightBuilder({required this.baseStyle, required this.highlightColor});

  final TextStyle? baseStyle;
  final Color highlightColor;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final style = (baseStyle ?? const TextStyle())
        .merge(preferredStyle)
        .copyWith(backgroundColor: highlightColor.withOpacity(0.2));
    return Text.rich(TextSpan(text: element.textContent, style: style));
  }
}
