import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../data/knowledge_base_data.dart';
import '../l10n/app_localizations.dart';

/// Alle 48 Einträge, verknüpft mit den ARB-Keys
const List<KnowledgeItem> _knowledgeItems = knowledgeItems;

class KnowledgeBasePage extends StatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<KnowledgeCategory> _selectedCategories = <KnowledgeCategory>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _categoryLabel(KnowledgeCategory cat, AppLocalizations t) =>
      knowledgeCategoryLabel(cat, t);

  List<KnowledgeItem> _filteredItems(AppLocalizations t) {
    final query = _searchController.text.trim().toLowerCase();
    final hasQuery = query.isNotEmpty;
    final hasCategoryFilter = _selectedCategories.isNotEmpty;

    return _knowledgeItems.where((item) {
      if (hasCategoryFilter && !_selectedCategories.contains(item.category)) {
        return false;
      }
      if (!hasQuery) return true;

      final question = item.question(t).toLowerCase();
      final answer = item.answer(t).toLowerCase();
      return question.contains(query) || answer.contains(query);
    }).toList(growable: false);
  }

  void _toggleCategory(KnowledgeCategory category, bool selected) {
    setState(() {
      if (selected) {
        _selectedCategories.add(category);
      } else {
        _selectedCategories.remove(category);
      }
    });
  }

  Widget _buildHeaderCard(
    AppLocalizations t,
    ThemeData theme,
    int visibleResults,
  ) {
    final cs = theme.colorScheme;
    final baseText = theme.textTheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withOpacity(theme.brightness == Brightness.dark ? 0.14 : 0.18),
            cs.surfaceVariant.withOpacity(0.45),
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.onPrimary.withOpacity(0.06),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: cs.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.kb_title,
                        style: baseText.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.kb_intro,
                        style: baseText.bodyMedium?.copyWith(
                          height: 1.5,
                          color: baseText.bodyMedium?.color?.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(
                  icon: Icons.category_outlined,
                  label: t.kb_filter_all,
                  value: '${KnowledgeCategory.values.length} Kategorien',
                ),
                _InfoPill(
                  icon: Icons.library_books_outlined,
                  label: 'Einträge',
                  value: '${_knowledgeItems.length} Artikel',
                ),
                _InfoPill(
                  icon: Icons.auto_awesome,
                  label: 'Aktuelle Ansicht',
                  value: '$visibleResults Ergebnisse',
                  emphasize: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: cs.surface.withOpacity(theme.brightness == Brightness.dark ? 0.75 : 0.92),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  labelText: t.search,
                  hintText: t.kb_search_hint,
                  labelStyle: baseText.labelLarge,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Schnellfilter',
              style: baseText.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _buildCategoryChips(t),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips(AppLocalizations t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    ChoiceChip buildChip({required Widget label, required bool selected, required void Function(bool) onSelected}) {
      return ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        selectedColor: cs.primaryContainer.withOpacity(0.8),
        backgroundColor: cs.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.5 : 0.7),
        labelStyle: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
        ),
      );
    }

    final chips = <Widget>[
      buildChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.all_inclusive, size: 18),
            const SizedBox(width: 6),
            Text(t.kb_filter_all),
          ],
        ),
        selected: _selectedCategories.isEmpty,
        onSelected: (_) => setState(() => _selectedCategories.clear()),
      ),
    ];

    for (final cat in KnowledgeCategory.values) {
      chips.add(
        buildChip(
          label: Text(_categoryLabel(cat, t)),
          selected: _selectedCategories.contains(cat),
          onSelected: (value) => _toggleCategory(cat, value),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  List<String> _splitAnswer(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.replaceFirst(RegExp(r'^[•\-\u2022]\s*'), ''))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final items = _filteredItems(t);
    final visibleResults = items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.knowledgeBaseTile ?? 'Knowledge base (FAQ)'),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                child: _buildHeaderCard(t, theme, visibleResults),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      t.kb_empty_message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  16 + MediaQuery.of(context).padding.bottom,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = items[index];
                      return _KnowledgeEntryCard(
                        question: item.question(t),
                        answers: _splitAnswer(item.answer(t)),
                        categoryLabel: _categoryLabel(item.category, t),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeEntryCard extends StatelessWidget {
  final String question;
  final List<String> answers;
  final String categoryLabel;

  const _KnowledgeEntryCard({
    required this.question,
    required this.answers,
    required this.categoryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            question,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              categoryLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: answers
                  .map(
                    (line) => Padding(
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
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MarkdownBody(
                              data: line,
                              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                                p: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                                strong: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.45,
                                ),
                                em: theme.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  height: 1.45,
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
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: emphasize
            ? cs.primaryContainer.withOpacity(0.3)
            : cs.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.55),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: emphasize ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
