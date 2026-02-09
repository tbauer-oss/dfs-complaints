import 'package:flutter/foundation.dart';

enum GsprStatus {
  draft,
  inReview,
  approved,
}

enum GsprAssessmentStatus {
  notAssessed,
  fulfilled,
  partial,
  notFulfilled,
  notApplicable,
}

String normalizeGsprTdLabel(String value) {
  var text = value.trim();
  if (text.isEmpty) return '';
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  text = text.replaceAll(RegExp(r'\s*[-–—]\s*'), ' – ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

String gsprTdCodeFromLabel(String label) {
  final normalized = normalizeGsprTdLabel(label);
  if (!normalized.startsWith('MDR-TD')) return '';
  final parts = normalized.split(' – ');
  return parts.first.trim();
}

int? gsprTdIndexFromLabel(String label) {
  final code = gsprTdCodeFromLabel(label);
  final match = RegExp(r'^MDR-TD\s*([0-9]+)').firstMatch(code);
  if (match == null) return null;
  final idx = int.tryParse(match.group(1) ?? '');
  return idx;
}

int compareGsprTdLabels(String a, String b) {
  final aIndex = gsprTdIndexFromLabel(a);
  final bIndex = gsprTdIndexFromLabel(b);
  if (aIndex != null && bIndex != null && aIndex != bIndex) return aIndex - bIndex;
  if (aIndex != null && bIndex == null) return -1;
  if (aIndex == null && bIndex != null) return 1;
  return a.compareTo(b);
}

List<String> dedupeAndSortGsprTdLabels(Iterable<String> raw) {
  final deduped = <String>{};
  for (final entry in raw) {
    final normalized = normalizeGsprTdLabel(entry);
    if (!normalized.startsWith('MDR-TD')) continue;
    deduped.add(normalized);
  }
  final list = deduped.toList()..sort(compareGsprTdLabels);
  return list;
}

@immutable
class GsprTdOption {
  final String id;
  final String label;
  final String mdrTd;
  final bool hasFmea;

  const GsprTdOption({
    required this.id,
    required this.label,
    required this.mdrTd,
    required this.hasFmea,
  });

  String get displayLabel => label.isNotEmpty ? label : id;
  String get displayCode {
    if (mdrTd.isNotEmpty) return mdrTd;
    final code = gsprTdCodeFromLabel(label);
    return code.isNotEmpty ? code : id;
  }

  factory GsprTdOption.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] ?? '').toString();
    final id = (json['key'] ?? json['id'] ?? label).toString();
    final mdrTd = (json['mdrTd'] ?? gsprTdCodeFromLabel(label)).toString();
    return GsprTdOption(
      id: id,
      label: normalizeGsprTdLabel(label),
      mdrTd: mdrTd,
      hasFmea: json['hasFmea'] == true,
    );
  }
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

GsprAssessmentStatus gsprAssessmentStatusFromString(String? value) {
  switch ((value ?? '').toLowerCase()) {
    case 'fulfilled':
      return GsprAssessmentStatus.fulfilled;
    case 'partial':
      return GsprAssessmentStatus.partial;
    case 'not_fulfilled':
      return GsprAssessmentStatus.notFulfilled;
    case 'not_applicable':
      return GsprAssessmentStatus.notApplicable;
    case 'not_assessed':
    default:
      return GsprAssessmentStatus.notAssessed;
  }
}

String gsprAssessmentStatusToString(GsprAssessmentStatus status) {
  switch (status) {
    case GsprAssessmentStatus.fulfilled:
      return 'fulfilled';
    case GsprAssessmentStatus.partial:
      return 'partial';
    case GsprAssessmentStatus.notFulfilled:
      return 'not_fulfilled';
    case GsprAssessmentStatus.notApplicable:
      return 'not_applicable';
    case GsprAssessmentStatus.notAssessed:
    default:
      return 'not_assessed';
  }
}

@immutable
class GsprRequirement {
  final String id;
  final String ref;
  final int chapter;
  final String title;
  final String sortKey;
  final String? parentId;
  final int level;
  final String text;
  final bool isAssessable;
  final List<String> contextIds;
  final String? contextText;

  const GsprRequirement({
    required this.id,
    required this.ref,
    required this.chapter,
    required this.title,
    required this.sortKey,
    required this.parentId,
    required this.level,
    required this.text,
    required this.isAssessable,
    required this.contextIds,
    required this.contextText,
  });

  String get fullText => text;

  factory GsprRequirement.fromJson(Map<String, dynamic> json) {
    return GsprRequirement(
      id: (json['id'] ?? '').toString(),
      ref: (json['ref'] ?? '').toString(),
      chapter: (json['chapter'] is num) ? (json['chapter'] as num).toInt() : 0,
      title: (json['title'] ?? '').toString(),
      sortKey: (json['sortKey'] ?? '').toString(),
      parentId: json['parentId']?.toString(),
      level: (json['level'] is num) ? (json['level'] as num).toInt() : 0,
      text: (json['text'] ?? json['fullText'] ?? '').toString(),
      isAssessable: json['isAssessable'] != false,
      contextIds: (json['contextIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .toList(growable: false),
      contextText: json['contextText']?.toString(),
    );
  }
}

@immutable
class GsprEvidence {
  final String docId;
  final String revision;
  final String link;
  final String label;

  const GsprEvidence({
    required this.docId,
    required this.revision,
    required this.link,
    required this.label,
  });

  factory GsprEvidence.fromJson(Map<String, dynamic> json) {
    return GsprEvidence(
      docId: (json['docId'] ?? '').toString(),
      revision: (json['revision'] ?? '').toString(),
      link: (json['link'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'docId': docId,
        'revision': revision,
        'link': link,
        'label': label,
      };
}

@immutable
class GsprAssessment {
  final String id;
  final String tdId;
  final String requirementId;
  final bool applicable;
  final GsprAssessmentStatus status;
  final String rationale;
  final List<GsprEvidence> evidence;
  final String owner;
  final DateTime? dueDate;
  final String standards;
  final String edition;
  final String supportingDocs;
  final String revision;
  final DateTime? date;
  final String comments;
  final String additionalDataRequired;
  final int version;
  final DateTime? updatedAt;
  final String updatedBy;

  const GsprAssessment({
    required this.id,
    required this.tdId,
    required this.requirementId,
    required this.applicable,
    required this.status,
    required this.rationale,
    required this.evidence,
    required this.owner,
    required this.dueDate,
    required this.standards,
    required this.edition,
    required this.supportingDocs,
    required this.revision,
    required this.date,
    required this.comments,
    required this.additionalDataRequired,
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
      status: GsprAssessmentStatus.notAssessed,
      rationale: '',
      evidence: const [],
      owner: '',
      dueDate: null,
      standards: '',
      edition: '',
      supportingDocs: '',
      revision: '',
      date: null,
      comments: '',
      additionalDataRequired: '',
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
      status: gsprAssessmentStatusFromString(json['status']?.toString()),
      rationale: (json['rationale'] ?? '').toString(),
      evidence: (json['evidence'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((entry) => GsprEvidence.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      owner: (json['owner'] ?? '').toString(),
      dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? ''),
      standards: (json['standards'] ?? '').toString(),
      edition: (json['edition'] ?? '').toString(),
      supportingDocs: (json['supportingDocs'] ?? '').toString(),
      revision: (json['revision'] ?? '').toString(),
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      comments: (json['comments'] ?? '').toString(),
      additionalDataRequired: (json['additionalDataRequired'] ?? '').toString(),
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
        'status': gsprAssessmentStatusToString(status),
        'rationale': rationale,
        'evidence': evidence.map((e) => e.toJson()).toList(growable: false),
        'owner': owner,
        'dueDate': dueDate?.toIso8601String(),
        'standards': standards,
        'edition': edition,
        'supportingDocs': supportingDocs,
        'revision': revision,
        'date': date?.toIso8601String(),
        'comments': comments,
        'additionalDataRequired': additionalDataRequired,
        'version': version,
        'updatedAt': updatedAt?.toIso8601String(),
        'updatedBy': updatedBy,
      };

  GsprAssessment copyWith({
    String? id,
    String? tdId,
    String? requirementId,
    bool? applicable,
    GsprAssessmentStatus? status,
    String? rationale,
    List<GsprEvidence>? evidence,
    String? owner,
    DateTime? dueDate,
    String? standards,
    String? edition,
    String? supportingDocs,
    String? revision,
    DateTime? date,
    String? comments,
    String? additionalDataRequired,
    int? version,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return GsprAssessment(
      id: id ?? this.id,
      tdId: tdId ?? this.tdId,
      requirementId: requirementId ?? this.requirementId,
      applicable: applicable ?? this.applicable,
      status: status ?? this.status,
      rationale: rationale ?? this.rationale,
      evidence: evidence ?? this.evidence,
      owner: owner ?? this.owner,
      dueDate: dueDate ?? this.dueDate,
      standards: standards ?? this.standards,
      edition: edition ?? this.edition,
      supportingDocs: supportingDocs ?? this.supportingDocs,
      revision: revision ?? this.revision,
      date: date ?? this.date,
      comments: comments ?? this.comments,
      additionalDataRequired: additionalDataRequired ?? this.additionalDataRequired,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

@immutable
class GsprChapterEntry {
  final GsprRequirement requirement;
  final GsprAssessment? assessment;

  const GsprChapterEntry({
    required this.requirement,
    required this.assessment,
  });

  factory GsprChapterEntry.fromJson(Map<String, dynamic> json, {required String tdId}) {
    final req = GsprRequirement.fromJson((json['requirement'] as Map).cast<String, dynamic>());
    final assessmentJson = json['assessment'] is Map ? json['assessment'] as Map : <String, dynamic>{};
    final assessment = assessmentJson.isNotEmpty
        ? GsprAssessment.fromJson(assessmentJson.cast<String, dynamic>())
        : (req.isAssessable ? GsprAssessment.empty(tdId: tdId, requirementId: req.id) : null);
    return GsprChapterEntry(requirement: req, assessment: assessment);
  }
}

@immutable
class GsprAnalysisSummary {
  final int total;
  final int fulfilled;
  final int notApplicable;
  final int open;
  final int overdue;
  final int dueSoon;

  const GsprAnalysisSummary({
    required this.total,
    required this.fulfilled,
    required this.notApplicable,
    required this.open,
    required this.overdue,
    required this.dueSoon,
  });

  factory GsprAnalysisSummary.fromJson(Map<String, dynamic> json) {
    return GsprAnalysisSummary(
      total: (json['total'] is num) ? (json['total'] as num).toInt() : 0,
      fulfilled: (json['fulfilled'] is num) ? (json['fulfilled'] as num).toInt() : 0,
      notApplicable: (json['notApplicable'] is num) ? (json['notApplicable'] as num).toInt() : 0,
      open: (json['open'] is num) ? (json['open'] as num).toInt() : 0,
      overdue: (json['overdue'] is num) ? (json['overdue'] as num).toInt() : 0,
      dueSoon: (json['dueSoon'] is num) ? (json['dueSoon'] as num).toInt() : 0,
    );
  }
}

@immutable
class GsprAnalysisRow {
  final String tdId;
  final String mdrTd;
  final String requirementId;
  final String ref;
  final String title;
  final int chapter;
  final GsprAssessmentStatus status;
  final String owner;
  final DateTime? dueDate;
  final DateTime? updatedAt;
  final bool missingEvidence;
  final bool overdue;
  final bool dueSoon;

  const GsprAnalysisRow({
    required this.tdId,
    required this.mdrTd,
    required this.requirementId,
    required this.ref,
    required this.title,
    required this.chapter,
    required this.status,
    required this.owner,
    required this.dueDate,
    required this.updatedAt,
    required this.missingEvidence,
    required this.overdue,
    required this.dueSoon,
  });

  factory GsprAnalysisRow.fromJson(Map<String, dynamic> json) {
    return GsprAnalysisRow(
      tdId: (json['tdId'] ?? '').toString(),
      mdrTd: (json['mdrTd'] ?? '').toString(),
      requirementId: (json['requirementId'] ?? '').toString(),
      ref: (json['ref'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      chapter: (json['chapter'] is num) ? (json['chapter'] as num).toInt() : 0,
      status: gsprAssessmentStatusFromString(json['status']?.toString()),
      owner: (json['owner'] ?? '').toString(),
      dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      missingEvidence: json['missingEvidence'] == true,
      overdue: json['overdue'] == true,
      dueSoon: json['dueSoon'] == true,
    );
  }
}

@immutable
class GsprAnalysisResponse {
  final String tdId;
  final GsprAnalysisSummary summary;
  final int total;
  final int page;
  final int pageSize;
  final List<GsprAnalysisRow> items;

  const GsprAnalysisResponse({
    required this.tdId,
    required this.summary,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.items,
  });

  factory GsprAnalysisResponse.fromJson(Map<String, dynamic> json) {
    final summaryMap = json['summary'] is Map ? json['summary'] as Map : <String, dynamic>{};
    final list = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((entry) => GsprAnalysisRow.fromJson(entry.cast<String, dynamic>()))
        .toList(growable: false);
    return GsprAnalysisResponse(
      tdId: (json['tdId'] ?? '').toString(),
      summary: GsprAnalysisSummary.fromJson(summaryMap.cast<String, dynamic>()),
      total: (json['total'] is num) ? (json['total'] as num).toInt() : list.length,
      page: (json['page'] is num) ? (json['page'] as num).toInt() : 1,
      pageSize: (json['pageSize'] is num) ? (json['pageSize'] as num).toInt() : list.length,
      items: list,
    );
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
