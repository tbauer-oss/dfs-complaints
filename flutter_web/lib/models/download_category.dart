class DownloadCategory {
  final String name;
  final int count;

  const DownloadCategory({required this.name, required this.count});

  factory DownloadCategory.fromJson(Map<String, dynamic> json) {
    return DownloadCategory(
      name: (json['name'] ?? json['category'] ?? '').toString(),
      count: json['count'] is num ? (json['count'] as num).round() : 0,
    );
  }
}
