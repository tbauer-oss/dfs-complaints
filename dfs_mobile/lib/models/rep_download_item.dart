// lib/models/rep_download_item.dart
class RepDownloadItem {
  final String id;
  final String title;
  final String description;
  final String category;
  final String language;
  final String badge;
  final String downloadUrl;
  final String fileName;
  final String mime;
  final int size;
  final int updatedAt;
  final int version;
  final bool active;
  final String language;
  final List<String> allowedRepresentatives;

  bool get visibleForAll => allowedRepresentatives.isEmpty;

  const RepDownloadItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.language,
    required this.badge,
    required this.downloadUrl,
    required this.fileName,
    required this.mime,
    required this.size,
    required this.updatedAt,
    required this.version,
    required this.active,
    this.language = '',
    this.allowedRepresentatives = const [],
  });

  factory RepDownloadItem.fromJson(Map<String, dynamic> json) {
    return RepDownloadItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      language: (json['language'] ?? '').toString().trim(),
      badge: (json['badge'] ?? '').toString(),
      downloadUrl: (json['downloadUrl'] ?? json['url'] ?? '').toString(),
      fileName: (json['fileName'] ?? json['name'] ?? '').toString(),
      mime: (json['mime'] ?? '').toString(),
      size: json['size'] is num ? (json['size'] as num).round() : 0,
      updatedAt: json['updatedAt'] is num ? (json['updatedAt'] as num).round() : 0,
      version: json['version'] is num ? (json['version'] as num).round() : 1,
      active: json['active'] != false,
      language: (json['language'] ?? '').toString(),
      allowedRepresentatives: json['allowedRepresentatives'] is List
          ? (json['allowedRepresentatives'] as List)
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }
}
