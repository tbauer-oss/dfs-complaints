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
  final String kind;
  final bool acknowledged;
  final List<NewsAcknowledgement> acknowledgedBy;

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
    this.kind = 'news',
    this.acknowledged = false,
    this.acknowledgedBy = const [],
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
      kind: (json['kind'] ?? 'news').toString(),
      acknowledged: json['acknowledged'] == true,
      acknowledgedBy: (json['acknowledgedBy'] is List
              ? (json['acknowledgedBy'] as List)
              : const [])
          .whereType<Map>()
          .map(NewsAcknowledgement.fromJson)
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
    String? kind,
    bool? acknowledged,
    List<NewsAcknowledgement>? acknowledgedBy,
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
      kind: kind ?? this.kind,
      acknowledged: acknowledged ?? this.acknowledged,
      acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
    );
  }
}

class NewsAcknowledgement {
  final String? id;
  final String? email;
  final String? name;
  final DateTime at;

  const NewsAcknowledgement({this.id, this.email, this.name, required this.at});

  factory NewsAcknowledgement.fromJson(Map<dynamic, dynamic> json) {
    DateTime _parse(dynamic v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
      if (v is double) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true).toLocal();
      if (v is String && v.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(v);
        if (parsed != null) return parsed.toLocal();
      }
      return DateTime.now();
    }

    return NewsAcknowledgement(
      id: json['id']?.toString(),
      email: (json['email'] ?? json['mail'])?.toString(),
      name: (json['name'] ?? json['displayName'])?.toString(),
      at: _parse(json['at']),
    );
  }
}
