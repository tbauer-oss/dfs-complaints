import 'package:flutter/foundation.dart';

enum WorkflowStatus {
  draft,
  qmReview,
  prrcReview,
  approved,
  rejected,
}

WorkflowStatus workflowStatusFromString(String? value) {
  switch ((value ?? '').toUpperCase()) {
    case 'QM_REVIEW':
      return WorkflowStatus.qmReview;
    case 'PRRC_REVIEW':
      return WorkflowStatus.prrcReview;
    case 'APPROVED':
      return WorkflowStatus.approved;
    case 'REJECTED':
      return WorkflowStatus.rejected;
    case 'DRAFT':
    default:
      return WorkflowStatus.draft;
  }
}

String workflowStatusToString(WorkflowStatus status) {
  switch (status) {
    case WorkflowStatus.qmReview:
      return 'QM_REVIEW';
    case WorkflowStatus.prrcReview:
      return 'PRRC_REVIEW';
    case WorkflowStatus.approved:
      return 'APPROVED';
    case WorkflowStatus.rejected:
      return 'REJECTED';
    case WorkflowStatus.draft:
    default:
      return 'DRAFT';
  }
}

@immutable
class EvidenceRef {
  final String type;
  final String label;
  final String ref;

  const EvidenceRef({
    required this.type,
    required this.label,
    required this.ref,
  });

  factory EvidenceRef.fromJson(Map<String, dynamic> json) {
    return EvidenceRef(
      type: (json['type'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      ref: (json['ref'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'label': label,
        'ref': ref,
      };
}

@immutable
class LinkRef {
  final String type;
  final String label;
  final String targetRef;

  const LinkRef({
    required this.type,
    required this.label,
    required this.targetRef,
  });

  factory LinkRef.fromJson(Map<String, dynamic> json) {
    return LinkRef(
      type: (json['type'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      targetRef: (json['targetRef'] ?? json['ref'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'label': label,
        'targetRef': targetRef,
      };
}

@immutable
class GsprItem {
  final String id;
  final String chapter;
  final String gsprCode;
  final String annexRefDe;
  final String annexRefEn;
  final String? requirementTitleDe;
  final String? requirementTitleEn;
  final String textDe;
  final String textEn;
  final bool applicable;
  final String? justificationNa;
  final String? implementation;
  final List<EvidenceRef> evidence;
  final List<LinkRef> links;
  final WorkflowStatus status;
  final int version;
  final DateTime updatedAt;
  final String updatedBy;
  final DateTime? approvedAt;
  final String? approvedBy;

  const GsprItem({
    required this.id,
    required this.chapter,
    required this.gsprCode,
    required this.annexRefDe,
    required this.annexRefEn,
    required this.requirementTitleDe,
    required this.requirementTitleEn,
    required this.textDe,
    required this.textEn,
    required this.applicable,
    required this.justificationNa,
    required this.implementation,
    required this.evidence,
    required this.links,
    required this.status,
    required this.version,
    required this.updatedAt,
    required this.updatedBy,
    required this.approvedAt,
    required this.approvedBy,
  });

  factory GsprItem.empty({required String chapter}) {
    final now = DateTime.now();
    return GsprItem(
      id: '',
      chapter: chapter,
      gsprCode: '',
      annexRefDe: '',
      annexRefEn: '',
      requirementTitleDe: '',
      requirementTitleEn: '',
      textDe: '',
      textEn: '',
      applicable: true,
      justificationNa: '',
      implementation: '',
      evidence: const [],
      links: const [],
      status: WorkflowStatus.draft,
      version: 1,
      updatedAt: now,
      updatedBy: '',
      approvedAt: null,
      approvedBy: null,
    );
  }

  factory GsprItem.fromJson(Map<String, dynamic> json) {
    return GsprItem(
      id: (json['id'] ?? '').toString(),
      chapter: (json['chapter'] ?? '').toString(),
      gsprCode: (json['gsprCode'] ?? '').toString(),
      annexRefDe: (json['annexRefDe'] ?? '').toString(),
      annexRefEn: (json['annexRefEn'] ?? '').toString(),
      requirementTitleDe: json['requirementTitleDe']?.toString(),
      requirementTitleEn: json['requirementTitleEn']?.toString(),
      textDe: (json['textDe'] ?? '').toString(),
      textEn: (json['textEn'] ?? '').toString(),
      applicable: json['applicable'] == true,
      justificationNa: json['justificationNa']?.toString(),
      implementation: json['implementation']?.toString(),
      evidence: (json['evidence'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => EvidenceRef.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      links: (json['links'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => LinkRef.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      status: workflowStatusFromString(json['status']?.toString()),
      version: (json['version'] is num) ? (json['version'] as num).toInt() : 1,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      updatedBy: (json['updatedBy'] ?? '').toString(),
      approvedAt: DateTime.tryParse(json['approvedAt']?.toString() ?? ''),
      approvedBy: json['approvedBy']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chapter': chapter,
        'gsprCode': gsprCode,
        'annexRefDe': annexRefDe,
        'annexRefEn': annexRefEn,
        'requirementTitleDe': requirementTitleDe,
        'requirementTitleEn': requirementTitleEn,
        'textDe': textDe,
        'textEn': textEn,
        'applicable': applicable,
        'justificationNa': justificationNa,
        'implementation': implementation,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'links': links.map((e) => e.toJson()).toList(),
        'status': workflowStatusToString(status),
        'version': version,
        'updatedAt': updatedAt.toIso8601String(),
        'updatedBy': updatedBy,
        'approvedAt': approvedAt?.toIso8601String(),
        'approvedBy': approvedBy,
      };

  GsprItem copyWith({
    String? id,
    String? chapter,
    String? gsprCode,
    String? annexRefDe,
    String? annexRefEn,
    String? requirementTitleDe,
    String? requirementTitleEn,
    String? textDe,
    String? textEn,
    bool? applicable,
    String? justificationNa,
    String? implementation,
    List<EvidenceRef>? evidence,
    List<LinkRef>? links,
    WorkflowStatus? status,
    int? version,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? approvedAt,
    String? approvedBy,
  }) {
    return GsprItem(
      id: id ?? this.id,
      chapter: chapter ?? this.chapter,
      gsprCode: gsprCode ?? this.gsprCode,
      annexRefDe: annexRefDe ?? this.annexRefDe,
      annexRefEn: annexRefEn ?? this.annexRefEn,
      requirementTitleDe: requirementTitleDe ?? this.requirementTitleDe,
      requirementTitleEn: requirementTitleEn ?? this.requirementTitleEn,
      textDe: textDe ?? this.textDe,
      textEn: textEn ?? this.textEn,
      applicable: applicable ?? this.applicable,
      justificationNa: justificationNa ?? this.justificationNa,
      implementation: implementation ?? this.implementation,
      evidence: evidence ?? this.evidence,
      links: links ?? this.links,
      status: status ?? this.status,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
    );
  }
}

@immutable
class AuditEvent {
  final String id;
  final String gsprItemId;
  final DateTime timestamp;
  final String actorUserId;
  final String actorName;
  final String action;
  final String? fromStatus;
  final String? toStatus;
  final String? comment;

  const AuditEvent({
    required this.id,
    required this.gsprItemId,
    required this.timestamp,
    required this.actorUserId,
    required this.actorName,
    required this.action,
    required this.fromStatus,
    required this.toStatus,
    required this.comment,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    return AuditEvent(
      id: (json['id'] ?? '').toString(),
      gsprItemId: (json['gsprItemId'] ?? '').toString(),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      actorUserId: (json['actorUserId'] ?? '').toString(),
      actorName: (json['actorName'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      fromStatus: json['fromStatus']?.toString(),
      toStatus: json['toStatus']?.toString(),
      comment: json['comment']?.toString(),
    );
  }
}
