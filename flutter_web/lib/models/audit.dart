import 'dart:convert';

class AuditorEvidence {
  final String? id;
  final String name;
  final String? url;
  final String? downloadUrl;
  final int size;
  final DateTime? uploadedAt;
  final String? mime;
  final String? preview;

  const AuditorEvidence({
    this.id,
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
        id: json['id']?.toString(),
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
        if (id != null) 'id': id,
        'name': name,
        if (url != null) 'url': url,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        if (size > 0) 'size': size,
        if (uploadedAt != null) 'uploadedAt': uploadedAt!.toIso8601String(),
        if (mime != null) 'mime': mime,
        if (preview != null) 'preview': preview,
      };
}

class AuditPlanEntry {
  final String from;
  final String to;
  final String agenda;
  final String process;
  final String participants;
  final String auditor;
  final String? auditorId;
  final String reference;
  final String notes;
  final bool done;

  const AuditPlanEntry({
    this.from = '',
    this.to = '',
    this.agenda = '',
    this.process = '',
    this.participants = '',
    this.auditor = '',
    this.notes = '',
    this.auditorId,
    this.reference = '',
    this.done = false,
  });

  factory AuditPlanEntry.fromJson(Map<String, dynamic> json) => AuditPlanEntry(
        from: json['from']?.toString() ?? '',
        to: json['to']?.toString() ?? '',
        agenda: json['agenda']?.toString() ?? '',
        process: json['process']?.toString() ?? '',
        participants: json['participants']?.toString() ?? '',
        auditor: json['auditor']?.toString() ?? '',
        auditorId: json['auditorId']?.toString(),
        reference: json['reference']?.toString() ?? json['norm']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        done: json['done'] == true,
      );

  Map<String, dynamic> toJson() => {
        if (from.isNotEmpty) 'from': from,
        if (to.isNotEmpty) 'to': to,
        if (agenda.isNotEmpty) 'agenda': agenda,
        if (process.isNotEmpty) 'process': process,
        if (participants.isNotEmpty) 'participants': participants,
        if (auditor.isNotEmpty) 'auditor': auditor,
        if (auditorId?.isNotEmpty == true) 'auditorId': auditorId,
        if (reference.isNotEmpty) 'reference': reference,
        if (notes.isNotEmpty) 'notes': notes,
        'done': done,
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
  final bool qualificationOverride;
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
    this.qualificationOverride = false,
    this.evidenceAttachments = const [],
    this.coAuditCount = 0,
    this.leadAuditCount = 0,
    this.trainingDate,
  });

  bool get hasTraining => internalAuditorTrainingDate != null || trainingDate != null;

  bool get requalificationValid =>
      requalificationDueDate == null || !requalificationDueDate!.isBefore(DateTime.now());

  bool get experienceOk => (experienceYears ?? 0) >= 3;

  bool get hasOverride => qualificationOverride;

  /// Frontend-Logik an Backend angeglichen: Qualifiziert mit Training,
  /// ausreichender Erfahrung (>= 3 Jahre) und gültiger Re-Qualifikation.
  bool get isQualified => hasTraining && (experienceOk || hasOverride) && requalificationValid;

  String get qualificationStatus {
    if (isQualified) return 'qualifiziert';
    if (hasTraining) return 'in Arbeit';
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
    final status = json['status'] ?? (json['active'] == false ? 'inactive' : 'active');
    return Auditor(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString(),
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      orgUnit: json['orgUnit']?.toString(),
      role: json['role']?.toString(),
      status: status.toString(),
      trainingType: qualifications?['trainingType']?.toString() ?? 'internal',
      restrictedProcessOwners: parseList(independence?['restrictedProcessOwners'] ?? json['restrictedProcessOwners']),
      restrictedOrgUnits: parseList(independence?['restrictedOrgUnits'] ?? json['restrictedOrgUnits']),
      internalAuditorTrainingDate:
          parseDate(qualifications?['internalAuditorTrainingDate'] ?? json['internalAuditorTrainingDate']),
      experienceYears:
          parseInt(qualifications?['experienceYears'] ?? json['experienceYears']),
      standardsKnowledge: parseList(qualifications?['standardsKnowledge']),
      requalificationDueDate: parseDate(qualifications?['requalificationDueDate'] ?? json['requalificationDueDate']),
      qualificationOverride: (qualifications?['override'] ?? qualifications?['qualificationOverride']) == true,
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

class AuditProgramEntry {
  final String auditId;
  final String auditNumber;
  final String title;
  final String? cluster;
  final String? scope;
  final List<String> processes;
  final List<String> references;
  final List<String> responsible;
  final List<String> participants;
  final String? site;
  final String? plannedPeriod;
  final String? leadAuditor;
  final String? coAuditor;
  final String status;

  const AuditProgramEntry({
    required this.auditId,
    required this.auditNumber,
    required this.title,
    this.cluster,
    this.scope,
    this.processes = const [],
    this.references = const [],
    this.responsible = const [],
    this.participants = const [],
    this.site,
    this.plannedPeriod,
    this.leadAuditor,
    this.coAuditor,
    this.status = 'planned',
  });

  factory AuditProgramEntry.fromJson(Map<String, dynamic> json) => AuditProgramEntry(
        auditId: json['auditId']?.toString() ?? '',
        auditNumber: json['auditNumber']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        cluster: json['cluster']?.toString(),
        scope: json['scope']?.toString(),
        processes: _parseStringList(json['processes']),
        references: _parseStringList(json['references']),
        responsible: _parseStringList(json['responsible']),
        participants: _parseStringList(json['participants']),
        site: json['site']?.toString(),
        plannedPeriod: json['plannedPeriod']?.toString(),
        leadAuditor: json['leadAuditor']?.toString(),
        coAuditor: json['coAuditor']?.toString(),
        status: json['status']?.toString() ?? 'planned',
      );
}

class AuditProgram {
  final String id;
  final int year;
  final String title;
  final String status;
  final DateTime? approvedAt;
  final String? approvedBy;
  final List<String> clusters;
  final List<AuditProgramEntry> entries;
  final int totalAudits;

  const AuditProgram({
    required this.id,
    required this.year,
    required this.title,
    required this.status,
    this.approvedAt,
    this.approvedBy,
    this.clusters = const [],
    this.entries = const [],
    this.totalAudits = 0,
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
      entries: (json['entries'] as List?)
              ?.whereType<Map>()
              .map((e) => AuditProgramEntry.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <AuditProgramEntry>[],
      totalAudits: json['totalAudits'] is int
          ? json['totalAudits'] as int
          : int.tryParse('${json['totalAudits'] ?? 0}') ??
              ((json['entries'] as List?)?.length ?? 0),
    );
  }
}

List<String> _parseStringList(dynamic v) => v is List ? v.whereType<String>().toList() : const <String>[];

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
  final String? coAuditorId;
  final List<String> linkedDocs;
  final List<AuditFinding> findings;
  final List<AuditAction> actions;
  final List<AuditPlanEntry> planEntries;
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
    this.coAuditorId,
    this.linkedDocs = const [],
    this.findings = const [],
    this.actions = const [],
    this.planEntries = const [],
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
    List<AuditPlanEntry> parsePlan(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => AuditPlanEntry.fromJson(e.cast<String, dynamic>())).toList()
        : const <AuditPlanEntry>[];
    final numOpenFindings = json['openFindings'] ?? json['open_findings'];
    final numOverdue = json['overdueActions'] ?? json['overdue_actions'];
    final v2Date = parseDate(json['date'] ?? json['plannedDate']);
    final plannedStart = parseDate(json['plannedStart']) ?? v2Date;
    final plannedEnd = parseDate(json['plannedEnd']) ?? v2Date;
    final derivedYear = v2Date?.year ?? DateTime.now().year;
    return Audit(
      id: json['id']?.toString() ?? '',
      auditNumber: json['auditNumber']?.toString() ?? '',
      year: json['year'] is int
          ? json['year'] as int
          : int.tryParse('${json['year']}') ?? derivedYear,
      cluster: json['cluster']?.toString(),
      auditType: json['auditType']?.toString() ?? 'System',
      title: json['title']?.toString() ?? json['auditName']?.toString() ?? '',
      site: json['site']?.toString() ?? json['location']?.toString(),
      plannedStart: plannedStart,
      plannedEnd: plannedEnd,
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
      coAuditorId: json['coAuditorId']?.toString() ??
          (parseList(json['coAuditorIds']).isNotEmpty ? parseList(json['coAuditorIds']).first : null),
      linkedDocs: parseList(json['linkedDocs']),
      findings: parseFindings(json['findings']),
      actions: parseActions(json['actions']),
      planEntries: parsePlan(json['planEntries'] ?? json['plan']),
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
        if (coAuditorId != null) 'coAuditorId': coAuditorId,
        if (linkedDocs.isNotEmpty) 'linkedDocs': linkedDocs,
        if (planEntries.isNotEmpty) 'planEntries': planEntries.map((p) => p.toJson()).toList(),
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
