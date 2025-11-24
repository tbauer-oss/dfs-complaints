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
  final String audience; // customer, rep, both
  final int order;
  final bool active;

  const FaqEntry({
    required this.id,
    required this.categoryId,
    required this.question,
    required this.answer,
    required this.audience,
    this.order = 0,
    this.active = true,
  });

  factory FaqEntry.fromJson(Map<String, dynamic> json) {
    return FaqEntry(
      id: (json['id'] ?? '').toString(),
      categoryId: (json['categoryId'] ?? '').toString(),
      question: (json['question'] ?? '').toString(),
      answer: (json['answer'] ?? '').toString(),
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
        'audience': audience,
        'order': order,
        'active': active,
      };
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
