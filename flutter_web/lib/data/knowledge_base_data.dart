import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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

  const KnowledgeItem({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
  });
}

String knowledgeCategoryLabel(KnowledgeCategory cat, AppLocalizations t) {
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

/// Liefert einen stabilen Identifier für eine Kategorie
String knowledgeCategoryCode(KnowledgeCategory cat) {
  switch (cat) {
    case KnowledgeCategory.aGeneral:
      return 'a_general';
    case KnowledgeCategory.bDiamond:
      return 'b_diamond';
    case KnowledgeCategory.cCarbide:
      return 'c_carbide';
    case KnowledgeCategory.dCeramic:
      return 'd_ceramic';
    case KnowledgeCategory.ePolishers:
      return 'e_polishers';
    case KnowledgeCategory.fReprocessing:
      return 'f_reprocessing';
    case KnowledgeCategory.gApp:
      return 'g_app';
    case KnowledgeCategory.hAnalysis:
      return 'h_analysis';
    case KnowledgeCategory.iPhotos:
      return 'i_photos';
    case KnowledgeCategory.jMisconceptions:
      return 'j_misconceptions';
  }
}

/// Alle 48 Einträge, verknüpft mit den ARB-Keys
final List<KnowledgeItem> knowledgeItems = [
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

