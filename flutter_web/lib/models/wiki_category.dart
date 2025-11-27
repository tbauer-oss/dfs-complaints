class WikiCategory {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int sortOrder;
  final bool isActive;

  const WikiCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.sortOrder,
    required this.isActive,
  });

  WikiCategory copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    int? sortOrder,
    bool? isActive,
  }) {
    return WikiCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }

  factory WikiCategory.fromJson(Map<String, dynamic> json) => WikiCategory(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? 'info',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        isActive: json['isActive'] as bool? ?? false,
      );
}
