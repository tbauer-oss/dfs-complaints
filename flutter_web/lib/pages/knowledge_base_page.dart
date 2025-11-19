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
  String _searchQuery = "";
  KnowledgeCategory? _selectedCategory;

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
    return _knowledgeItems.where((item) {
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
                            child: Text(
                              a,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.4,
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
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
                      const SizedBox(width: 8),
                      ...KnowledgeCategory.values.map((cat) {
                        final label = _categoryLabel(cat, t);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _selectedCategory == cat,
                            onSelected: (sel) {
                              setState(() {
                                _selectedCategory = sel ? cat : null;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ],
                  ),
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
