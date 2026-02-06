class WikiCategory {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int sortOrder;
  final bool isActive;
  final Map<String, WikiCategoryTranslation> translations;

  const WikiCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.sortOrder,
    required this.isActive,
    this.translations = const {},
  });

  WikiCategory copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    int? sortOrder,
    bool? isActive,
    Map<String, WikiCategoryTranslation>? translations,
  }) {
    return WikiCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      translations: translations ?? this.translations,
    );
  }

  factory WikiCategory.fromJson(Map<String, dynamic> json) => WikiCategory(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? 'info',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        isActive: json['isActive'] as bool? ?? false,
        translations: _parseTranslations(json),
      );

  WikiCategoryTranslation translationFor(String lang) {
    if (translations.containsKey(lang)) return translations[lang]!;
    if (lang != 'de' && translations.containsKey('de')) return translations['de']!;
    return const WikiCategoryTranslation(name: '', description: '');
  }
}

class WikiCategoryTranslation {
  final String name;
  final String description;

  const WikiCategoryTranslation({required this.name, required this.description});

  factory WikiCategoryTranslation.fromJson(Map<String, dynamic> json) =>
      WikiCategoryTranslation(
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
      );
}

Map<String, WikiCategoryTranslation> _parseTranslations(Map<String, dynamic> json) {
  final translations = <String, WikiCategoryTranslation>{};
  final raw = json['translations'];
  if (raw is Map<String, dynamic>) {
    for (final entry in raw.entries) {
      if (entry.value is Map<String, dynamic>) {
        translations[entry.key] = WikiCategoryTranslation.fromJson(
          (entry.value as Map).cast<String, dynamic>(),
        );
      }
    }
  }
  if (!translations.containsKey('de')) {
    translations['de'] = WikiCategoryTranslation(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }
  return translations;
}
