import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Kategorien der Wissensdatenbank
enum KnowledgeCategory {
  aGeneral,
  bDiamond,
  cCarbide,
  dCeramic,
  ePolishers,
  fReprocessing,
  gApp,
  hAnalysis,
  iPhotos,
  jMisconceptions,
}

/// Datensatz für eine Frage/Antwort
class KnowledgeItem {
  final int id;
  final KnowledgeCategory category;
  final String Function(AppLocalizations) question;
  final String Function(AppLocalizations) answer;

  KnowledgeItem({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
  });
}

/// Alle 48 Einträge, verknüpft mit den ARB-Keys
final List<KnowledgeItem> _knowledgeItems = [
  // 🔵 Kategorie A – Allgemeine Reklamationsfragen
  KnowledgeItem(
    id: 1,
    category: KnowledgeCategory.aGeneral,
    question: (t) => t.kb_q1_question,
    answer: (t) => t.kb_q1_answer,
  ),
  KnowledgeItem(
    id: 2,
    category: KnowledgeCategory.aGeneral,
    question: (t) => t.kb_q2_question,
    answer: (t) => t.kb_q2_answer,
  ),
  KnowledgeItem(
    id: 3,
    category: KnowledgeCategory.aGeneral,
    question: (t) => t.kb_q3_question,
    answer: (t) => t.kb_q3_answer,
  ),
  KnowledgeItem(
    id: 4,
    category: KnowledgeCategory.aGeneral,
    question: (t) => t.kb_q4_question,
    answer: (t) => t.kb_q4_answer,
  ),
  KnowledgeItem(
    id: 5,
    category: KnowledgeCategory.aGeneral,
    question: (t) => t.kb_q5_question,
    answer: (t) => t.kb_q5_answer,
  ),
  KnowledgeItem(
    id: 6,
    category: KnowledgeCategory.aGeneral,
    question: (t) => t.kb_q6_question,
    answer: (t) => t.kb_q6_answer,
  ),

  // 🔵 Kategorie B – Diamantinstrumente
  KnowledgeItem(
    id: 7,
    category: KnowledgeCategory.bDiamond,
    question: (t) => t.kb_q7_question,
    answer: (t) => t.kb_q7_answer,
  ),
  KnowledgeItem(
    id: 8,
    category: KnowledgeCategory.bDiamond,
    question: (t) => t.kb_q8_question,
    answer: (t) => t.kb_q8_answer,
  ),
  KnowledgeItem(
    id: 9,
    category: KnowledgeCategory.bDiamond,
    question: (t) => t.kb_q9_question,
    answer: (t) => t.kb_q9_answer,
  ),
  KnowledgeItem(
    id: 10,
    category: KnowledgeCategory.bDiamond,
    question: (t) => t.kb_q10_question,
    answer: (t) => t.kb_q10_answer,
  ),
  KnowledgeItem(
    id: 11,
    category: KnowledgeCategory.bDiamond,
    question: (t) => t.kb_q11_question,
    answer: (t) => t.kb_q11_answer,
  ),
  KnowledgeItem(
    id: 12,
    category: KnowledgeCategory.bDiamond,
    question: (t) => t.kb_q12_question,
    answer: (t) => t.kb_q12_answer,
  ),
  KnowledgeItem(
    id: 13,
    category: KnowledgeCategory.bDiamond,
    question: (t) => t.kb_q13_question,
    answer: (t) => t.kb_q13_answer,
  ),
  KnowledgeItem(
    id: 14,
    category: KnowledgeCategory.bDiamond,
    question: (t) => t.kb_q14_question,
    answer: (t) => t.kb_q14_answer,
  ),

  // 🔵 Kategorie C – Hartmetallinstrumente
  KnowledgeItem(
    id: 15,
    category: KnowledgeCategory.cCarbide,
    question: (t) => t.kb_q15_question,
    answer: (t) => t.kb_q15_answer,
  ),
  KnowledgeItem(
    id: 16,
    category: KnowledgeCategory.cCarbide,
    question: (t) => t.kb_q16_question,
    answer: (t) => t.kb_q16_answer,
  ),
  KnowledgeItem(
    id: 17,
    category: KnowledgeCategory.cCarbide,
    question: (t) => t.kb_q17_question,
    answer: (t) => t.kb_q17_answer,
  ),
  KnowledgeItem(
    id: 18,
    category: KnowledgeCategory.cCarbide,
    question: (t) => t.kb_q18_question,
    answer: (t) => t.kb_q18_answer,
  ),
  KnowledgeItem(
    id: 19,
    category: KnowledgeCategory.cCarbide,
    question: (t) => t.kb_q19_question,
    answer: (t) => t.kb_q19_answer,
  ),

  // 🔵 Kategorie D – Keramikfräser
  KnowledgeItem(
    id: 20,
    category: KnowledgeCategory.dCeramic,
    question: (t) => t.kb_q20_question,
    answer: (t) => t.kb_q20_answer,
  ),
  KnowledgeItem(
    id: 21,
    category: KnowledgeCategory.dCeramic,
    question: (t) => t.kb_q21_question,
    answer: (t) => t.kb_q21_answer,
  ),
  KnowledgeItem(
    id: 22,
    category: KnowledgeCategory.dCeramic,
    question: (t) => t.kb_q22_question,
    answer: (t) => t.kb_q22_answer,
  ),

  // 🔵 Kategorie E – Polierer
  KnowledgeItem(
    id: 23,
    category: KnowledgeCategory.ePolishers,
    question: (t) => t.kb_q23_question,
    answer: (t) => t.kb_q23_answer,
  ),
  KnowledgeItem(
    id: 24,
    category: KnowledgeCategory.ePolishers,
    question: (t) => t.kb_q24_question,
    answer: (t) => t.kb_q24_answer,
  ),
  KnowledgeItem(
    id: 25,
    category: KnowledgeCategory.ePolishers,
    question: (t) => t.kb_q25_question,
    answer: (t) => t.kb_q25_answer,
  ),

  // 🔵 Kategorie F – Aufbereitung & Sterilisation
  KnowledgeItem(
    id: 26,
    category: KnowledgeCategory.fReprocessing,
    question: (t) => t.kb_q26_question,
    answer: (t) => t.kb_q26_answer,
  ),
  KnowledgeItem(
    id: 27,
    category: KnowledgeCategory.fReprocessing,
    question: (t) => t.kb_q27_question,
    answer: (t) => t.kb_q27_answer,
  ),
  KnowledgeItem(
    id: 28,
    category: KnowledgeCategory.fReprocessing,
    question: (t) => t.kb_q28_question,
    answer: (t) => t.kb_q28_answer,
  ),
  KnowledgeItem(
    id: 29,
    category: KnowledgeCategory.fReprocessing,
    question: (t) => t.kb_q29_question,
    answer: (t) => t.kb_q29_answer,
  ),
  KnowledgeItem(
    id: 30,
    category: KnowledgeCategory.fReprocessing,
    question: (t) => t.kb_q30_question,
    answer: (t) => t.kb_q30_answer,
  ),

  // 🔵 Kategorie G – DFS Complaint App Nutzung
  KnowledgeItem(
    id: 31,
    category: KnowledgeCategory.gApp,
    question: (t) => t.kb_q31_question,
    answer: (t) => t.kb_q31_answer,
  ),
  KnowledgeItem(
    id: 32,
    category: KnowledgeCategory.gApp,
    question: (t) => t.kb_q32_question,
    answer: (t) => t.kb_q32_answer,
  ),
  KnowledgeItem(
    id: 33,
    category: KnowledgeCategory.gApp,
    question: (t) => t.kb_q33_question,
    answer: (t) => t.kb_q33_answer,
  ),
  KnowledgeItem(
    id: 34,
    category: KnowledgeCategory.gApp,
    question: (t) => t.kb_q34_question,
    answer: (t) => t.kb_q34_answer,
  ),
  KnowledgeItem(
    id: 35,
    category: KnowledgeCategory.gApp,
    question: (t) => t.kb_q35_question,
    answer: (t) => t.kb_q35_answer,
  ),

  // 🔵 Kategorie H – Entscheidung & technische Analyse
  KnowledgeItem(
    id: 36,
    category: KnowledgeCategory.hAnalysis,
    question: (t) => t.kb_q36_question,
    answer: (t) => t.kb_q36_answer,
  ),
  KnowledgeItem(
    id: 37,
    category: KnowledgeCategory.hAnalysis,
    question: (t) => t.kb_q37_question,
    answer: (t) => t.kb_q37_answer,
  ),
  KnowledgeItem(
    id: 38,
    category: KnowledgeCategory.hAnalysis,
    question: (t) => t.kb_q38_question,
    answer: (t) => t.kb_q38_answer,
  ),
  KnowledgeItem(
    id: 39,
    category: KnowledgeCategory.hAnalysis,
    question: (t) => t.kb_q39_question,
    answer: (t) => t.kb_q39_answer,
  ),
  KnowledgeItem(
    id: 40,
    category: KnowledgeCategory.hAnalysis,
    question: (t) => t.kb_q40_question,
    answer: (t) => t.kb_q40_answer,
  ),

  // 🔵 Kategorie I – Fotos & Rücksendung
  KnowledgeItem(
    id: 41,
    category: KnowledgeCategory.iPhotos,
    question: (t) => t.kb_q41_question,
    answer: (t) => t.kb_q41_answer,
  ),
  KnowledgeItem(
    id: 42,
    category: KnowledgeCategory.iPhotos,
    question: (t) => t.kb_q42_question,
    answer: (t) => t.kb_q42_answer,
  ),
  KnowledgeItem(
    id: 43,
    category: KnowledgeCategory.iPhotos,
    question: (t) => t.kb_q43_question,
    answer: (t) => t.kb_q43_answer,
  ),
  KnowledgeItem(
    id: 44,
    category: KnowledgeCategory.iPhotos,
    question: (t) => t.kb_q44_question,
    answer: (t) => t.kb_q44_answer,
  ),
  KnowledgeItem(
    id: 45,
    category: KnowledgeCategory.iPhotos,
    question: (t) => t.kb_q45_question,
    answer: (t) => t.kb_q45_answer,
  ),
  KnowledgeItem(
    id: 46,
    category: KnowledgeCategory.iPhotos,
    question: (t) => t.kb_q46_question,
    answer: (t) => t.kb_q46_answer,
  ),

  // 🔵 Kategorie J – Häufige Missverständnisse
  KnowledgeItem(
    id: 47,
    category: KnowledgeCategory.jMisconceptions,
    question: (t) => t.kb_q47_question,
    answer: (t) => t.kb_q47_answer,
  ),
  KnowledgeItem(
    id: 48,
    category: KnowledgeCategory.jMisconceptions,
    question: (t) => t.kb_q48_question,
    answer: (t) => t.kb_q48_answer,
  ),
];

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

  String _categoryLabel(KnowledgeCategory cat, AppLocalizations t) {
    switch (cat) {
      case KnowledgeCategory.aGeneral:
        return t.kb_cat_a_title;
      case KnowledgeCategory.bDiamond:
        return t.kb_cat_b_title;
      case KnowledgeCategory.cCarbide:
        return t.kb_cat_c_title;
      case KnowledgeCategory.dCeramic:
        return t.kb_cat_d_title;
      case KnowledgeCategory.ePolishers:
        return t.kb_cat_e_title;
      case KnowledgeCategory.fReprocessing:
        return t.kb_cat_f_title;
      case KnowledgeCategory.gApp:
        return t.kb_cat_g_title;
      case KnowledgeCategory.hAnalysis:
        return t.kb_cat_h_title;
      case KnowledgeCategory.iPhotos:
        return t.kb_cat_i_title;
      case KnowledgeCategory.jMisconceptions:
        return t.kb_cat_j_title;
    }
  }

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
                            child: Text(
                              line,
                              style:
                                  theme.textTheme.bodyMedium?.copyWith(height: 1.45),
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
