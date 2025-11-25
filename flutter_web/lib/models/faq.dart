// lib/models/faq.dart

class FaqCategory {
  final String id;
  final String title;
  final String? description;
  final int order;
  final bool active;

  const FaqCategory({
    required this.id,
    required this.title,
    this.description,
    this.order = 0,
    this.active = true,
  });

  factory FaqCategory.fromJson(Map<String, dynamic> json) {
    return FaqCategory(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description'] == null
          ? null
          : json['description'].toString(),
      order: int.tryParse(json['order']?.toString() ?? '') ?? 0,
      active: json['active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'order': order,
        'active': active,
      };
}

class FaqEntry {
  final String id;
  final String categoryId;
  final String question;
  final String answer;
  final Map<String, String> questionIntl;
  final Map<String, String> answerIntl;
  final String audience; // customer, rep, both
  final int order;
  final bool active;

  const FaqEntry({
    required this.id,
    required this.categoryId,
    required this.question,
    required this.answer,
    this.questionIntl = const {},
    this.answerIntl = const {},
    required this.audience,
    this.order = 0,
    this.active = true,
  });

  factory FaqEntry.fromJson(Map<String, dynamic> json) {
    Map<String, String> _intlMap(dynamic raw) {
      if (raw is Map) {
        return raw.map((key, value) {
          final lang = _normLang(key.toString());
          final text = value?.toString().trim();
          if (lang.isEmpty || text == null || text.isEmpty) return MapEntry('', '');
          return MapEntry(lang, text);
        })..removeWhere((k, v) => k.isEmpty || v.isEmpty);
      }
      return const <String, String>{};
    }

    final qIntl = _intlMap(json['questionIntl']);
    final aIntl = _intlMap(json['answerIntl']);
    final preferredLang = _normLang(json['lang']?.toString() ?? json['language']?.toString());
    final question = _resolveIntl(qIntl, json['question']?.toString() ?? '', preferredLang);
    final answer = _resolveIntl(aIntl, json['answer']?.toString() ?? '', preferredLang);
    if (question.isNotEmpty && preferredLang.isNotEmpty && !qIntl.containsKey(preferredLang)) {
      qIntl[preferredLang] = question;
    }
    if (answer.isNotEmpty && preferredLang.isNotEmpty && !aIntl.containsKey(preferredLang)) {
      aIntl[preferredLang] = answer;
    }

    return FaqEntry(
      id: (json['id'] ?? '').toString(),
      categoryId: (json['categoryId'] ?? '').toString(),
      question: question,
      answer: answer,
      questionIntl: qIntl,
      answerIntl: aIntl,
      audience: (json['audience'] ?? 'both').toString(),
      order: int.tryParse(json['order']?.toString() ?? '') ?? 0,
      active: json['active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'question': question,
        'answer': answer,
        if (questionIntl.isNotEmpty) 'questionIntl': questionIntl,
        if (answerIntl.isNotEmpty) 'answerIntl': answerIntl,
        'audience': audience,
        'order': order,
        'active': active,
      };

  String localizedQuestion(String lang) => _resolveIntl(questionIntl, question, lang);

  String localizedAnswer(String lang) => _resolveIntl(answerIntl, answer, lang);
}

String _normLang(String? code) {
  final lc = (code ?? '').trim().toLowerCase();
  switch (lc) {
    case 'de':
    case 'en':
    case 'es':
    case 'fr':
    case 'it':
      return lc;
    default:
      return '';
  }
}

String _resolveIntl(Map<String, String> map, String fallback, String lang) {
  final normalized = _normLang(lang);
  if (normalized.isNotEmpty && map.containsKey(normalized)) return map[normalized]!;
  if (normalized != 'de' && map.containsKey('de')) return map['de']!;
  if (map.isNotEmpty) return map.values.first;
  return fallback;
}

class FaqData {
  final List<FaqCategory> categories;
  final List<FaqEntry> entries;
  final String? audience;

  const FaqData({
    required this.categories,
    required this.entries,
    this.audience,
  });

  factory FaqData.fromJson(Map<String, dynamic> json) {
    final cats = (json['categories'] is List)
        ? (json['categories'] as List)
            .whereType<Map>()
            .map((e) => FaqCategory.fromJson(e.cast<String, dynamic>()))
            .toList()
        : <FaqCategory>[];

    final items = (json['items'] is List)
        ? (json['items'] as List)
            .whereType<Map>()
            .map((e) => FaqEntry.fromJson(e.cast<String, dynamic>()))
            .toList()
        : <FaqEntry>[];

    return FaqData(
      categories: cats,
      entries: items,
      audience: json['audience']?.toString(),
    );
  }
}
