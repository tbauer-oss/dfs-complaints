import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../data/knowledge_base_data.dart';
import '../l10n/app_localizations.dart';

class KnowledgeBasePage extends StatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  KnowledgeCategory? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _categoryLabel(KnowledgeCategory cat, AppLocalizations t) =>
      knowledgeCategoryLabel(cat, t);

  IconData _categoryIcon(KnowledgeCategory cat) {
    switch (cat) {
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
    }
  }

  List<String> _splitAnswer(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.replaceFirst(RegExp(r'^[•\-\u2022]\s*'), ''))
        .toList();
  }

  List<KnowledgeItem> _filteredItems(AppLocalizations t) {
    final query = _searchQuery.trim().toLowerCase();
    return knowledgeItems.where((item) {
      final matchesCategory =
          _selectedCategory == null || item.category == _selectedCategory;
      if (!matchesCategory) return false;

      if (query.isEmpty) return true;

      final q = item.question(t).toLowerCase();
      final a = item.answer(t).toLowerCase();
      return q.contains(query) || a.contains(query);
    }).toList();
  }

  Widget _buildQuestionCard({
    required BuildContext context,
    required String question,
    required List<String> answers,
    required KnowledgeCategory category,
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
            _categoryIcon(category),
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

    final items = _filteredItems(t);

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
                        setState(() {
                          _selectedCategory = null;
                        });
                      },
                    ),
                    ...KnowledgeCategory.values.map((cat) {
                      final label = _categoryLabel(cat, t);
                      return ChoiceChip(
                        label: Text(label),
                        selected: _selectedCategory == cat,
                        onSelected: (sel) {
                          setState(() {
                            _selectedCategory = sel ? cat : null;
                          });
                        },
                      );
                    }).toList(),
                  ],
                ),

                const SizedBox(height: 10),

                // Liste der Einträge
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            t.kb_empty_message,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final question = item.question(t);
                            final answerLines =
                                _splitAnswer(item.answer(t));

                            // Kategorie-Überschrift einblenden,
                            // wenn sich die Kategorie ändert
                            final bool showCategoryHeader;
                            if (index == 0) {
                              showCategoryHeader = true;
                            } else {
                              showCategoryHeader =
                                  items[index - 1].category !=
                                      item.category;
                            }

                            final widgets = <Widget>[];

                            if (showCategoryHeader) {
                              widgets.add(
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 16, bottom: 4),
                                  child: Text(
                                    _categoryLabel(item.category, t),
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
                                category: item.category,
                                primary: primary,
                              ),
                            );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: widgets,
                            );
                          },
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
