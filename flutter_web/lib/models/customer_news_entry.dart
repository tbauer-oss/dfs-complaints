// lib/models/customer_news_entry.dart
class CustomerNewsEntry {
  final String id;
  final String title;
  final String summary;
  final String category;
  final bool pinned;
  final bool draft;
  final DateTime publishedAt;
  final DateTime updatedAt;
  final String? linkLabel;
  final String? linkUrl;

  const CustomerNewsEntry({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.pinned,
    required this.draft,
    required this.publishedAt,
    required this.updatedAt,
    this.linkLabel,
    this.linkUrl,
  });

  factory CustomerNewsEntry.fromJson(Map<String, dynamic> json) {
    DateTime _parseTs(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
      }
      if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true).toLocal();
      }
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toLocal();
      }
      return DateTime.now();
    }

    return CustomerNewsEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? json['text'] ?? '').toString(),
      category: (json['category'] ?? 'general').toString(),
      pinned: json['pinned'] == true,
      draft: json['draft'] == true,
      linkLabel: (json['linkLabel'] ?? json['linkText'])?.toString(),
      linkUrl: (json['linkUrl'] ?? '').toString().trim().isEmpty ? null : json['linkUrl'].toString(),
      publishedAt: _parseTs(json['publishedAt']),
      updatedAt: _parseTs(json['updatedAt'] ?? json['createdAt']),
    );
  }

  CustomerNewsEntry copyWith({
    String? title,
    String? summary,
    String? category,
    bool? pinned,
    bool? draft,
    DateTime? publishedAt,
    DateTime? updatedAt,
    String? linkLabel,
    String? linkUrl,
  }) {
    return CustomerNewsEntry(
      id: id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      category: category ?? this.category,
      pinned: pinned ?? this.pinned,
      draft: draft ?? this.draft,
      publishedAt: publishedAt ?? this.publishedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      linkLabel: linkLabel ?? this.linkLabel,
      linkUrl: linkUrl ?? this.linkUrl,
    );
  }
}
