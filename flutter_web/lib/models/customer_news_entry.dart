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
  final List<String> audienceEmails;
  final List<String> audienceDepartments;
  final List<String> audienceRoles;

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
    this.audienceEmails = const [],
    this.audienceDepartments = const [],
    this.audienceRoles = const [],
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
      audienceEmails: (json['audience'] is Map && (json['audience']['emails'] is List)
              ? (json['audience']['emails'] as List)
              : const [])
          .map((e) => (e ?? '').toString())
          .where((e) => e.trim().isNotEmpty)
          .map((e) => e.trim())
          .toList(),
      audienceDepartments: (json['audience'] is Map && (json['audience']['departments'] is List)
              ? (json['audience']['departments'] as List)
              : const [])
          .map((e) => (e ?? '').toString())
          .where((e) => e.trim().isNotEmpty)
          .map((e) => e.trim())
          .toList(),
      audienceRoles: (json['audience'] is Map && (json['audience']['roles'] is List)
              ? (json['audience']['roles'] as List)
              : const [])
          .map((e) => (e ?? '').toString())
          .where((e) => e.trim().isNotEmpty)
          .map((e) => e.trim())
          .toList(),
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
    List<String>? audienceEmails,
    List<String>? audienceDepartments,
    List<String>? audienceRoles,
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
      audienceEmails: audienceEmails ?? this.audienceEmails,
      audienceDepartments: audienceDepartments ?? this.audienceDepartments,
      audienceRoles: audienceRoles ?? this.audienceRoles,
    );
  }
}
