import 'dart:convert';

class AuditorEvidence {
  final String name;
  final String? url;
  final String? downloadUrl;
  final int size;
  final DateTime? uploadedAt;
  final String? mime;
  final String? preview;

  const AuditorEvidence({
    required this.name,
    this.url,
    this.downloadUrl,
    this.size = 0,
    this.uploadedAt,
    this.mime,
    this.preview,
  });

  bool get hasLink => (downloadUrl ?? url ?? '').isNotEmpty;

  factory AuditorEvidence.fromJson(Map<String, dynamic> json) => AuditorEvidence(
        name: (json['name'] ?? '').toString(),
        url: json['url']?.toString(),
        downloadUrl: json['downloadUrl']?.toString(),
        size: json['size'] is int
            ? json['size'] as int
            : int.tryParse(json['size']?.toString() ?? '') ?? 0,
        uploadedAt: json['uploadedAt'] == null
            ? null
            : DateTime.tryParse(json['uploadedAt'].toString()) ??
                DateTime.fromMillisecondsSinceEpoch(
                    int.tryParse(json['uploadedAt'].toString()) ?? 0,
                    isUtc: true),
        mime: json['mime']?.toString(),
        preview: json['preview']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (url != null) 'url': url,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        if (size > 0) 'size': size,
        if (uploadedAt != null) 'uploadedAt': uploadedAt!.toIso8601String(),
        if (mime != null) 'mime': mime,
        if (preview != null) 'preview': preview,
      };
}

class Auditor {
  final String id;
  final String? userId;
  final String name;
  final String email;
  final String? orgUnit;
  final String? role;
  final String status;
  final String trainingType;
  final List<String> restrictedProcessOwners;
  final List<String> restrictedOrgUnits;
  final DateTime? internalAuditorTrainingDate;
  final int? experienceYears;
  final List<String> standardsKnowledge;
  final DateTime? requalificationDueDate;
  final List<AuditorEvidence> evidenceAttachments;
  final int coAuditCount;
  final int leadAuditCount;
  final DateTime? trainingDate;

  DateTime? get nextRequalification => requalificationDueDate;

  const Auditor({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    this.userId,
    this.trainingType = 'internal',
    this.orgUnit,
    this.role,
    this.restrictedProcessOwners = const [],
    this.restrictedOrgUnits = const [],
    this.internalAuditorTrainingDate,
    this.experienceYears,
    this.standardsKnowledge = const [],
    this.requalificationDueDate,
    this.evidenceAttachments = const [],
    this.coAuditCount = 0,
    this.leadAuditCount = 0,
    this.trainingDate,
  });

  bool get hasTraining => internalAuditorTrainingDate != null || trainingDate != null;

  bool get experienceOk => (experienceYears ?? 0) >= 3;

  bool get hasEvidence => evidenceAttachments.isNotEmpty;

  bool get auditCountOk => coAuditCount >= 2 || leadAuditCount >= 1;

  bool get requalificationValid =>
      requalificationDueDate == null || !requalificationDueDate!.isBefore(DateTime.now());

  bool get isQualified => hasTraining && auditCountOk && requalificationValid;

  String get qualificationStatus {
    if (isQualified && hasEvidence && experienceOk) return 'qualifiziert';
    if (hasTraining && !hasEvidence) return 'in Arbeit';
    return 'nicht qualifiziert';
  }

  factory Auditor.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) => v == null || v.toString().isEmpty
        ? null
        : DateTime.tryParse(v.toString());
    List<String> parseList(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];
    int? parseInt(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '');
    final qualifications = (json['qualifications'] as Map?)?.cast<String, dynamic>();
    final independence = (json['independenceRules'] as Map?)?.cast<String, dynamic>();
    return Auditor(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString(),
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      orgUnit: json['orgUnit']?.toString(),
      role: json['role']?.toString(),
      status: json['status']?.toString() ?? 'active',
      trainingType: qualifications?['trainingType']?.toString() ?? 'internal',
      restrictedProcessOwners: parseList(independence?['restrictedProcessOwners'] ?? json['restrictedProcessOwners']),
      restrictedOrgUnits: parseList(independence?['restrictedOrgUnits'] ?? json['restrictedOrgUnits']),
      internalAuditorTrainingDate:
          parseDate(qualifications?['internalAuditorTrainingDate'] ?? json['internalAuditorTrainingDate']),
      experienceYears:
          parseInt(qualifications?['experienceYears'] ?? json['experienceYears']),
      standardsKnowledge: parseList(qualifications?['standardsKnowledge']),
      requalificationDueDate: parseDate(qualifications?['requalificationDueDate'] ?? json['requalificationDueDate']),
      evidenceAttachments: ((qualifications?['evidence'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AuditorEvidence.fromJson(e.cast<String, dynamic>()))
          .toList(),
      coAuditCount:
          parseInt(qualifications?['coAuditCount'] ?? json['coAuditCount']) ?? 0,
      leadAuditCount:
          parseInt(qualifications?['leadAuditCount'] ?? json['leadAuditCount']) ?? 0,
      trainingDate: parseDate(qualifications?['trainingDate'] ?? json['trainingDate']),
    );
  }
}

class AuditProgram {
  final String id;
  final int year;
  final String title;
  final String status;
  final DateTime? approvedAt;
  final String? approvedBy;
  final List<String> clusters;

  const AuditProgram({
    required this.id,
    required this.year,
    required this.title,
    required this.status,
    this.approvedAt,
    this.approvedBy,
    this.clusters = const [],
  });

  factory AuditProgram.fromJson(Map<String, dynamic> json) {
    List<String> parseList(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];
    DateTime? parseDate(dynamic v) => v == null || v.toString().isEmpty
        ? null
        : DateTime.tryParse(v.toString());
    return AuditProgram(
      id: json['id']?.toString() ?? '',
      year: json['year'] is int ? json['year'] as int : int.tryParse('${json['year']}') ?? 0,
      title: json['title']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      approvedAt: parseDate(json['approvedAt']),
      approvedBy: json['approvedBy']?.toString(),
      clusters: parseList(json['clusters']),
    );
  }
}

class AuditFinding {
  final String id;
  final String auditId;
  final String type;
  final String description;
  final String? requirementRef;
  final String? evidenceText;
  final List<String> linkedComplaintIds;
  final List<String> linkedCapaIds;
  final String? ownerOrgUnit;
  final String? processOwner;
  final String? createdInMeeting;
  final String status;

  const AuditFinding({
    required this.id,
    required this.auditId,
    required this.type,
    required this.description,
    this.requirementRef,
    this.evidenceText,
    this.linkedComplaintIds = const [],
    this.linkedCapaIds = const [],
    this.ownerOrgUnit,
    this.processOwner,
    this.createdInMeeting,
    this.status = 'open',
  });

  factory AuditFinding.fromJson(Map<String, dynamic> json) {
    List<String> parseList(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];
    return AuditFinding(
      id: json['id']?.toString() ?? '',
      auditId: json['auditId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Hinweis',
      description: json['description']?.toString() ?? '',
      requirementRef: json['requirementRef']?.toString(),
      evidenceText: json['evidenceText']?.toString(),
      linkedComplaintIds: parseList(json['linkedComplaintIds']),
      linkedCapaIds: parseList(json['linkedCapaIds']),
      ownerOrgUnit: json['ownerOrgUnit']?.toString(),
      processOwner: json['processOwner']?.toString(),
      createdInMeeting: json['createdInMeeting']?.toString(),
      status: json['status']?.toString() ?? 'open',
    );
  }
}

class AuditAction {
  final String id;
  final String auditId;
  final String? findingId;
  final String actionType;
  final String description;
  final String? responsibleUserId;
  final String? responsibleOrgUnit;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final bool effectivenessCheckRequired;
  final String? effectivenessCheckMethod;
  final DateTime? effectivenessCheckedAt;
  final String? effectivenessResult;
  final String escalationLevel;
  final String? escalationReason;
  final String status;

  const AuditAction({
    required this.id,
    required this.auditId,
    required this.actionType,
    required this.description,
    this.findingId,
    this.responsibleUserId,
    this.responsibleOrgUnit,
    this.dueDate,
    this.completedAt,
    this.effectivenessCheckRequired = false,
    this.effectivenessCheckMethod,
    this.effectivenessCheckedAt,
    this.effectivenessResult,
    this.escalationLevel = 'none',
    this.escalationReason,
    this.status = 'open',
  });

  factory AuditAction.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) => v == null || v.toString().isEmpty
        ? null
        : DateTime.tryParse(v.toString());
    return AuditAction(
      id: json['id']?.toString() ?? '',
      auditId: json['auditId']?.toString() ?? '',
      findingId: json['findingId']?.toString(),
      actionType: json['actionType']?.toString() ?? 'Korrektur',
      description: json['description']?.toString() ?? '',
      responsibleUserId: json['responsibleUserId']?.toString(),
      responsibleOrgUnit: json['responsibleOrgUnit']?.toString(),
      dueDate: parseDate(json['dueDate']),
      completedAt: parseDate(json['completedAt']),
      effectivenessCheckRequired: json['effectivenessCheckRequired'] == true,
      effectivenessCheckMethod: json['effectivenessCheckMethod']?.toString(),
      effectivenessCheckedAt: parseDate(json['effectivenessCheckedAt']),
      effectivenessResult: json['effectivenessResult']?.toString(),
      escalationLevel: json['escalationLevel']?.toString() ?? 'none',
      escalationReason: json['escalationReason']?.toString(),
      status: json['status']?.toString() ?? 'open',
    );
  }
}

class AuditAnnualReport {
  final String id;
  final int year;
  final DateTime? generatedAt;
  final String? generatedBy;
  final List<ExportFile> exportFiles;

  const AuditAnnualReport({
    required this.id,
    required this.year,
    this.generatedAt,
    this.generatedBy,
    this.exportFiles = const [],
  });

  factory AuditAnnualReport.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) => v == null || v.toString().isEmpty
        ? null
        : DateTime.tryParse(v.toString());
    List<ExportFile> parseFiles(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => ExportFile.fromJson(e.cast<String, dynamic>())).toList()
        : const <ExportFile>[];
    return AuditAnnualReport(
      id: json['id']?.toString() ?? '',
      year: json['year'] is int ? json['year'] as int : int.tryParse('${json['year']}') ?? 0,
      generatedAt: parseDate(json['generatedAt']),
      generatedBy: json['generatedBy']?.toString(),
      exportFiles: parseFiles(json['exportFiles']),
    );
  }
}

class AuditHistoryEntry {
  final String id;
  final String entityId;
  final String entityType;
  final String action;
  final String? user;
  final DateTime createdAt;
  final Map<String, dynamic>? diff;

  const AuditHistoryEntry({
    required this.id,
    required this.entityId,
    required this.entityType,
    required this.action,
    required this.createdAt,
    this.user,
    this.diff,
  });

  factory AuditHistoryEntry.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    return AuditHistoryEntry(
      id: json['id']?.toString() ?? '',
      entityId: json['entityId']?.toString() ?? '',
      entityType: json['entityType']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      user: json['user']?.toString(),
      createdAt: parseDate(json['createdAt']),
      diff: json['diff'] is Map ? (json['diff'] as Map).cast<String, dynamic>() : null,
    );
  }
}

class Audit {
  final String id;
  final String auditNumber;
  final int year;
  final String? cluster;
  final String auditType;
  final String title;
  final String? site;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final String status;
  final String? scopeText;
  final List<String> objectives;
  final List<String> criteria;
  final List<String> references;
  final List<String> auditeesOrgUnits;
  final List<String> processOwners;
  final List<String> participants;
  final String? leadAuditorId;
  final List<String> coAuditorIds;
  final List<String> linkedDocs;
  final List<AuditFinding> findings;
  final List<AuditAction> actions;
  final int? openFindings;
  final int? overdueActions;

  String get displayPeriod {
    String fmt(DateTime d) {
      final day = d.day.toString().padLeft(2, '0');
      final month = d.month.toString().padLeft(2, '0');
      final year = d.year.toString();
      return '$day.$month.$year';
    }

    if (plannedStart != null && plannedEnd != null) {
      return '${fmt(plannedStart!)} – ${fmt(plannedEnd!)}';
    }
    if (plannedStart != null) return fmt(plannedStart!);
    if (plannedEnd != null) return fmt(plannedEnd!);
    return '-';
  }

  const Audit({
    required this.id,
    required this.auditNumber,
    required this.year,
    this.cluster,
    required this.auditType,
    required this.title,
    this.site,
    this.plannedStart,
    this.plannedEnd,
    this.actualStart,
    this.actualEnd,
    this.status = 'planned',
    this.scopeText,
    this.objectives = const [],
    this.criteria = const [],
    this.references = const [],
    this.auditeesOrgUnits = const [],
    this.processOwners = const [],
    this.participants = const [],
    this.leadAuditorId,
    this.coAuditorIds = const [],
    this.linkedDocs = const [],
    this.findings = const [],
    this.actions = const [],
    this.openFindings,
    this.overdueActions,
  });

  factory Audit.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) => v == null || v.toString().isEmpty
        ? null
        : DateTime.tryParse(v.toString());
    List<String> parseList(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];
    List<AuditFinding> parseFindings(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => AuditFinding.fromJson(e.cast<String, dynamic>())).toList()
        : const <AuditFinding>[];
    List<AuditAction> parseActions(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => AuditAction.fromJson(e.cast<String, dynamic>())).toList()
        : const <AuditAction>[];
    final numOpenFindings = json['openFindings'] ?? json['open_findings'];
    final numOverdue = json['overdueActions'] ?? json['overdue_actions'];
    return Audit(
      id: json['id']?.toString() ?? '',
      auditNumber: json['auditNumber']?.toString() ?? '',
      year: json['year'] is int ? json['year'] as int : int.tryParse('${json['year']}') ?? 0,
      cluster: json['cluster']?.toString(),
      auditType: json['auditType']?.toString() ?? 'System',
      title: json['title']?.toString() ?? json['auditName']?.toString() ?? '',
      site: json['site']?.toString() ?? json['location']?.toString(),
      plannedStart: parseDate(json['plannedStart']),
      plannedEnd: parseDate(json['plannedEnd']),
      actualStart: parseDate(json['actualStart']),
      actualEnd: parseDate(json['actualEnd']),
      status: json['status']?.toString() ?? 'planned',
      scopeText: json['scopeText']?.toString(),
      objectives: parseList(json['objectives']),
      criteria: parseList(json['criteria']),
      references: parseList(json['references']),
      auditeesOrgUnits: parseList(json['auditeesOrgUnits']),
      processOwners: parseList(json['processOwners']),
      participants: parseList(json['participants']),
      leadAuditorId: json['leadAuditorId']?.toString(),
      coAuditorIds: parseList(json['coAuditorIds']),
      linkedDocs: parseList(json['linkedDocs']),
      findings: parseFindings(json['findings']),
      actions: parseActions(json['actions']),
      openFindings: numOpenFindings is int
          ? numOpenFindings
          : int.tryParse(numOpenFindings?.toString() ?? ''),
      overdueActions: numOverdue is int ? numOverdue : int.tryParse(numOverdue?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'auditNumber': auditNumber,
        'year': year,
        if (cluster != null) 'cluster': cluster,
        'auditType': auditType,
        'title': title,
        if (site != null) 'site': site,
        if (plannedStart != null) 'plannedStart': _fmt(plannedStart!),
        if (plannedEnd != null) 'plannedEnd': _fmt(plannedEnd!),
        if (actualStart != null) 'actualStart': _fmt(actualStart!),
        if (actualEnd != null) 'actualEnd': _fmt(actualEnd!),
        'status': status,
        if (scopeText != null) 'scopeText': scopeText,
        if (objectives.isNotEmpty) 'objectives': objectives,
        if (criteria.isNotEmpty) 'criteria': criteria,
        if (references.isNotEmpty) 'references': references,
        if (auditeesOrgUnits.isNotEmpty) 'auditeesOrgUnits': auditeesOrgUnits,
        if (processOwners.isNotEmpty) 'processOwners': processOwners,
        if (participants.isNotEmpty) 'participants': participants,
        if (leadAuditorId != null) 'leadAuditorId': leadAuditorId,
        if (coAuditorIds.isNotEmpty) 'coAuditorIds': coAuditorIds,
        if (linkedDocs.isNotEmpty) 'linkedDocs': linkedDocs,
      };
}

class ExportFile {
  final String fileName;
  final String fileType;
  final String? url;
  const ExportFile({required this.fileName, required this.fileType, this.url});

  factory ExportFile.fromJson(Map<String, dynamic> json) => ExportFile(
        fileName: json['fileName']?.toString() ?? json['name']?.toString() ?? '',
        fileType: json['fileType']?.toString() ?? json['type']?.toString() ?? 'pdf',
        url: json['url']?.toString(),
      );

  Map<String, dynamic> toJson() => {'fileName': fileName, 'fileType': fileType, if (url != null) 'url': url};
}

String encodeAuditToJson(Audit audit) => jsonEncode(audit.toJson());

String? _fmt(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
