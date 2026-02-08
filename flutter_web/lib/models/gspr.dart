import 'package:flutter/foundation.dart';

enum GsprStatus {
  draft,
  inReview,
  approved,
}

GsprStatus gsprStatusFromString(String? value) {
  switch ((value ?? '').toLowerCase()) {
    case 'in_review':
      return GsprStatus.inReview;
    case 'approved':
      return GsprStatus.approved;
    case 'draft':
    default:
      return GsprStatus.draft;
  }
}

String gsprStatusToString(GsprStatus status) {
  switch (status) {
    case GsprStatus.inReview:
      return 'in_review';
    case GsprStatus.approved:
      return 'approved';
    case GsprStatus.draft:
    default:
      return 'draft';
  }
}

@immutable
class GsprRequirement {
  final String id;
  final String ref;
  final int chapter;
  final String title;
  final String fullText;
  final int sort;

  const GsprRequirement({
    required this.id,
    required this.ref,
    required this.chapter,
    required this.title,
    required this.fullText,
    required this.sort,
  });

  factory GsprRequirement.fromJson(Map<String, dynamic> json) {
    return GsprRequirement(
      id: (json['id'] ?? '').toString(),
      ref: (json['ref'] ?? '').toString(),
      chapter: (json['chapter'] is num) ? (json['chapter'] as num).toInt() : 0,
      title: (json['title'] ?? '').toString(),
      fullText: (json['fullText'] ?? '').toString(),
      sort: (json['sort'] is num) ? (json['sort'] as num).toInt() : 0,
    );
  }
}

@immutable
class GsprAssessment {
  final String id;
  final String tdId;
  final String requirementId;
  final bool applicable;
  final String standards;
  final String edition;
  final String supportingDocs;
  final String revision;
  final DateTime? date;
  final String comments;
  final String additionalDataRequired;
  final GsprStatus status;
  final int version;
  final DateTime? updatedAt;
  final String updatedBy;

  const GsprAssessment({
    required this.id,
    required this.tdId,
    required this.requirementId,
    required this.applicable,
    required this.standards,
    required this.edition,
    required this.supportingDocs,
    required this.revision,
    required this.date,
    required this.comments,
    required this.additionalDataRequired,
    required this.status,
    required this.version,
    required this.updatedAt,
    required this.updatedBy,
  });

  factory GsprAssessment.empty({required String tdId, required String requirementId}) {
    return GsprAssessment(
      id: '',
      tdId: tdId,
      requirementId: requirementId,
      applicable: true,
      standards: '',
      edition: '',
      supportingDocs: '',
      revision: '',
      date: null,
      comments: '',
      additionalDataRequired: '',
      status: GsprStatus.draft,
      version: 1,
      updatedAt: DateTime.now(),
      updatedBy: '',
    );
  }

  factory GsprAssessment.fromJson(Map<String, dynamic> json) {
    return GsprAssessment(
      id: (json['id'] ?? '').toString(),
      tdId: (json['tdId'] ?? '').toString(),
      requirementId: (json['requirementId'] ?? '').toString(),
      applicable: json['applicable'] != false,
      standards: (json['standards'] ?? '').toString(),
      edition: (json['edition'] ?? '').toString(),
      supportingDocs: (json['supportingDocs'] ?? '').toString(),
      revision: (json['revision'] ?? '').toString(),
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      comments: (json['comments'] ?? '').toString(),
      additionalDataRequired: (json['additionalDataRequired'] ?? '').toString(),
      status: gsprStatusFromString(json['status']?.toString()),
      version: (json['version'] is num) ? (json['version'] as num).toInt() : 1,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      updatedBy: (json['updatedBy'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tdId': tdId,
        'requirementId': requirementId,
        'applicable': applicable,
        'standards': standards,
        'edition': edition,
        'supportingDocs': supportingDocs,
        'revision': revision,
        'date': date?.toIso8601String(),
        'comments': comments,
        'additionalDataRequired': additionalDataRequired,
        'status': gsprStatusToString(status),
        'version': version,
        'updatedAt': updatedAt?.toIso8601String(),
        'updatedBy': updatedBy,
      };

  GsprAssessment copyWith({
    String? id,
    String? tdId,
    String? requirementId,
    bool? applicable,
    String? standards,
    String? edition,
    String? supportingDocs,
    String? revision,
    DateTime? date,
    String? comments,
    String? additionalDataRequired,
    GsprStatus? status,
    int? version,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return GsprAssessment(
      id: id ?? this.id,
      tdId: tdId ?? this.tdId,
      requirementId: requirementId ?? this.requirementId,
      applicable: applicable ?? this.applicable,
      standards: standards ?? this.standards,
      edition: edition ?? this.edition,
      supportingDocs: supportingDocs ?? this.supportingDocs,
      revision: revision ?? this.revision,
      date: date ?? this.date,
      comments: comments ?? this.comments,
      additionalDataRequired: additionalDataRequired ?? this.additionalDataRequired,
      status: status ?? this.status,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

@immutable
class GsprChapterEntry {
  final GsprRequirement requirement;
  final GsprAssessment assessment;

  const GsprChapterEntry({
    required this.requirement,
    required this.assessment,
  });

  factory GsprChapterEntry.fromJson(Map<String, dynamic> json, {required String tdId}) {
    final req = GsprRequirement.fromJson((json['requirement'] as Map).cast<String, dynamic>());
    final assessmentJson = json['assessment'] is Map ? json['assessment'] as Map : <String, dynamic>{};
    final assessment = assessmentJson.isNotEmpty
        ? GsprAssessment.fromJson(assessmentJson.cast<String, dynamic>())
        : GsprAssessment.empty(tdId: tdId, requirementId: req.id);
    return GsprChapterEntry(requirement: req, assessment: assessment);
  }
}

@immutable
class GsprChapterResponse {
  final List<GsprChapterEntry> items;
  final GsprStatus status;
  final bool readOnly;

  const GsprChapterResponse({
    required this.items,
    required this.status,
    required this.readOnly,
  });

  factory GsprChapterResponse.fromJson(Map<String, dynamic> json, {required String tdId}) {
    final list = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => GsprChapterEntry.fromJson(e.cast<String, dynamic>(), tdId: tdId))
        .toList(growable: false);
    return GsprChapterResponse(
      items: list,
      status: gsprStatusFromString(json['status']?.toString()),
      readOnly: json['readOnly'] == true,
    );
  }
}

@immutable
class GsprSummaryChapter {
  final int chapter;
  final int total;
  final int assessed;
  final int notApplicable;

  const GsprSummaryChapter({
    required this.chapter,
    required this.total,
    required this.assessed,
    required this.notApplicable,
  });

  factory GsprSummaryChapter.fromJson(Map<String, dynamic> json) {
    return GsprSummaryChapter(
      chapter: (json['chapter'] is num) ? (json['chapter'] as num).toInt() : 0,
      total: (json['total'] is num) ? (json['total'] as num).toInt() : 0,
      assessed: (json['assessed'] is num) ? (json['assessed'] as num).toInt() : 0,
      notApplicable: (json['notApplicable'] is num) ? (json['notApplicable'] as num).toInt() : 0,
    );
  }
}

@immutable
class GsprSummary {
  final String tdId;
  final GsprStatus status;
  final List<GsprSummaryChapter> chapters;
  final DateTime? submittedAt;
  final String submittedBy;
  final DateTime? approvedAt;
  final String approvedBy;
  final bool readOnly;

  const GsprSummary({
    required this.tdId,
    required this.status,
    required this.chapters,
    required this.submittedAt,
    required this.submittedBy,
    required this.approvedAt,
    required this.approvedBy,
    required this.readOnly,
  });

  factory GsprSummary.fromJson(Map<String, dynamic> json) {
    final chapters = (json['chapters'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => GsprSummaryChapter.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
    return GsprSummary(
      tdId: (json['tdId'] ?? '').toString(),
      status: gsprStatusFromString(json['status']?.toString()),
      chapters: chapters,
      submittedAt: DateTime.tryParse(json['submittedAt']?.toString() ?? ''),
      submittedBy: (json['submittedBy'] ?? '').toString(),
      approvedAt: DateTime.tryParse(json['approvedAt']?.toString() ?? ''),
      approvedBy: (json['approvedBy'] ?? '').toString(),
      readOnly: json['readOnly'] == true,
    );
  }
}
