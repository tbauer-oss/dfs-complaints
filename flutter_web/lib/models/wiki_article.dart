class WikiArticle {
  final String id;
  final String categoryId;
  final String? categoryName;
  final List<String> productGroups;
  final String type;
  final String title;
  final String teaser;
  final String importance;
  final String contentMarkdown;
  final List<String> tags;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, WikiArticleTranslation> translations;

  const WikiArticle({
    required this.id,
    required this.categoryId,
    required this.productGroups,
    required this.type,
    required this.title,
    required this.teaser,
    required this.importance,
    required this.contentMarkdown,
    required this.tags,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.categoryName,
    this.translations = const {},
  });

  factory WikiArticle.fromJson(Map<String, dynamic> json) => WikiArticle(
        id: json['id'] as String,
        categoryId: json['categoryId'] as String,
        categoryName: json['categoryName'] as String?,
        productGroups: (json['productGroups'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        type: json['type'] as String? ?? 'faq',
        title: json['title'] as String? ?? '',
        teaser: json['teaser'] as String? ?? '',
        importance: json['importance'] as String? ?? 'normal',
        contentMarkdown: json['contentMarkdown'] as String? ?? '',
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        isActive: json['isActive'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
        translations: _parseTranslations(json),
      );

  WikiArticleTranslation translationFor(String lang) {
    if (translations.containsKey(lang)) return translations[lang]!;
    if (lang != 'de' && translations.containsKey('de')) return translations['de']!;
    return const WikiArticleTranslation(title: '', teaser: '', contentMarkdown: '');
  }
}

class WikiArticleTranslation {
  final String title;
  final String teaser;
  final String contentMarkdown;

  const WikiArticleTranslation({
    required this.title,
    required this.teaser,
    required this.contentMarkdown,
  });

  factory WikiArticleTranslation.fromJson(Map<String, dynamic> json) => WikiArticleTranslation(
        title: json['title']?.toString() ?? '',
        teaser: json['teaser']?.toString() ?? '',
        contentMarkdown: json['contentMarkdown']?.toString() ?? '',
      );
}

Map<String, WikiArticleTranslation> _parseTranslations(Map<String, dynamic> json) {
  final translations = <String, WikiArticleTranslation>{};
  final raw = json['translations'];
  if (raw is Map<String, dynamic>) {
    for (final entry in raw.entries) {
      if (entry.value is Map<String, dynamic>) {
        translations[entry.key] = WikiArticleTranslation.fromJson(
          (entry.value as Map).cast<String, dynamic>(),
        );
      }
    }
  }
  if (!translations.containsKey('de')) {
    translations['de'] = WikiArticleTranslation(
      title: json['title']?.toString() ?? '',
      teaser: json['teaser']?.toString() ?? '',
      contentMarkdown: json['contentMarkdown']?.toString() ?? '',
    );
  }
  return translations;
}
