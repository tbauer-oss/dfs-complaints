// lib/models/customer_news_entry.dart
class CustomerNewsEntry {
  final String id;
  final String title;
  final String summary;
  final String category;
  final bool pinned;
  final bool draft;
  final bool published;
  final DateTime publishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? linkLabel;
  final String? linkUrl;
  final String audience;
  final String? language;
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
    required this.published,
    required this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
    this.linkLabel,
    this.linkUrl,
    this.audience = 'all',
    this.language,
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

    bool _parseBool(dynamic value, {required bool fallback}) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized.isEmpty) return fallback;
        if (['true', '1', 'yes', 'y', 'on'].contains(normalized)) return true;
        if (['false', '0', 'no', 'n', 'off'].contains(normalized)) return false;
      }
      return fallback;
    }

    String _parseAudience(dynamic value) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
      return 'all';
    }

    String? _parseLanguage(dynamic value) {
      if (value == null) return null;
      final lang = value.toString().trim();
      return lang.isEmpty ? null : lang;
    }

    final draft = _parseBool(json['draft'], fallback: false);
    final published = _parseBool(json['published'], fallback: !draft);
    final publishedAt = _parseTs(json['publishedAt'] ?? json['date']);
    final createdAt = _parseTs(json['createdAt'] ?? json['created_at'] ?? publishedAt);
    final updatedAt = _parseTs(json['updatedAt'] ?? json['updated_at'] ?? createdAt);

    return CustomerNewsEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? json['headline'] ?? '').toString(),
      summary: (json['summary'] ?? json['teaser'] ?? json['body'] ?? json['text'] ?? '').toString(),
      category: (json['category'] ?? 'general').toString(),
      pinned: json['pinned'] == true,
      draft: draft,
      published: published,
      linkLabel: (json['linkLabel'] ?? json['linkText'])?.toString(),
      linkUrl: (json['linkUrl'] ?? '').toString().trim().isEmpty ? null : json['linkUrl'].toString(),
      publishedAt: publishedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      audience: _parseAudience(json['audience']),
      language: _parseLanguage(json['language'] ?? json['lang']),
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
    bool? published,
    DateTime? publishedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? linkLabel,
    String? linkUrl,
    String? audience,
    String? language,
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
      published: published ?? this.published,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      linkLabel: linkLabel ?? this.linkLabel,
      linkUrl: linkUrl ?? this.linkUrl,
      audience: audience ?? this.audience,
      language: language ?? this.language,
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
