class ChangeHistoryEntry {
  final String action;
  final String actor;
  final DateTime? at;
  final String note;
  final List<String> fields;

  const ChangeHistoryEntry({
    this.action = '',
    this.actor = '',
    this.at,
    this.note = '',
    this.fields = const [],
  });

  factory ChangeHistoryEntry.fromJson(Map<String, dynamic> json) => ChangeHistoryEntry(
        action: (json['action'] ?? '').toString(),
        actor: (json['actor'] ?? '').toString(),
        at: _parseDate(json['at']),
        note: (json['note'] ?? '').toString(),
        fields: (json['fields'] is List)
            ? (json['fields'] as List).map((e) => e.toString()).toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        'actor': actor,
        'at': at?.millisecondsSinceEpoch,
        'note': note,
        'fields': fields,
      };
}

class ChangeManagementRecord {
  final String id;
  final String changeId;
  final String title;
  final String description;
  final String justification;
  final String changeType;
  final String initiator;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final List<String> affectedDocuments;
  final List<String> affectedProcesses;
  final String affectedProcessOther;
  final String trigger;

  final String productImpact;
  final String documentationImpact;
  final String processImpact;
  final String regulatoryImpact;
  final String safetyRelevance;
  final String riskChange;
  final String furtherAnalysis;

  final String evaluator;
  final DateTime? evaluatedAt;

  final String decision;
  final List<String> followUps;
  final String followUpLink;
  final String decisionNote;
  final String decisionBy;
  final DateTime? decisionAt;
  final String prrcDecision;
  final String prrcNote;
  final String prrcBy;
  final DateTime? prrcAt;

  final String fmeaId;
  final String fmeaStatus;
  final String capaId;
  final String capaStatus;

  final String implementationOwner;
  final DateTime? plannedDate;
  final DateTime? implementedAt;
  final bool implemented;
  final bool documentsUpdated;
  final String status;
  final String implementationBy;

  final List<ChangeHistoryEntry> history;

  const ChangeManagementRecord({
    this.id = '',
    this.changeId = '',
    this.title = '',
    this.description = '',
    this.justification = '',
    this.changeType = 'other',
    this.initiator = '',
    this.createdAt,
    this.updatedAt,
    this.affectedDocuments = const [],
    this.affectedProcesses = const [],
    this.affectedProcessOther = '',
    this.trigger = '',
    this.productImpact = 'none',
    this.documentationImpact = 'none',
    this.processImpact = 'none',
    this.regulatoryImpact = 'none',
    this.safetyRelevance = 'none',
    this.riskChange = 'none',
    this.furtherAnalysis = 'no',
    this.evaluator = '',
    this.evaluatedAt,
    this.decision = '',
    this.followUps = const [],
    this.followUpLink = '',
    this.decisionNote = '',
    this.decisionBy = '',
    this.decisionAt,
    this.prrcDecision = '',
    this.prrcNote = '',
    this.prrcBy = '',
    this.prrcAt,
    this.fmeaId = '',
    this.fmeaStatus = '',
    this.capaId = '',
    this.capaStatus = '',
    this.implementationOwner = '',
    this.plannedDate,
    this.implementedAt,
    this.implemented = false,
    this.documentsUpdated = false,
    this.status = 'open',
    this.implementationBy = '',
    this.history = const [],
  });

  factory ChangeManagementRecord.fromJson(Map<String, dynamic> json) => ChangeManagementRecord(
        id: (json['id'] ?? '').toString(),
        changeId: (json['changeId'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        justification: (json['justification'] ?? '').toString(),
        changeType: (json['changeType'] ?? 'other').toString(),
        initiator: (json['initiator'] ?? '').toString(),
        createdAt: _parseDate(json['createdAt']),
        updatedAt: _parseDate(json['updatedAt']),
        affectedDocuments: (json['affectedDocuments'] is List)
            ? (json['affectedDocuments'] as List).map((e) => e.toString()).toList()
            : const [],
        affectedProcesses: (json['affectedProcesses'] is List)
            ? (json['affectedProcesses'] as List).map((e) => e.toString()).toList()
            : const [],
        affectedProcessOther: (json['affectedProcessOther'] ?? '').toString(),
        trigger: (json['trigger'] ?? '').toString(),
        productImpact: (json['productImpact'] ?? 'none').toString(),
        documentationImpact: (json['documentationImpact'] ?? 'none').toString(),
        processImpact: (json['processImpact'] ?? 'none').toString(),
        regulatoryImpact: (json['regulatoryImpact'] ?? 'none').toString(),
        safetyRelevance: (json['safetyRelevance'] ?? 'none').toString(),
        riskChange: (json['riskChange'] ?? 'none').toString(),
        furtherAnalysis: (json['furtherAnalysis'] ?? 'no').toString(),
        evaluator: (json['evaluator'] ?? '').toString(),
        evaluatedAt: _parseDate(json['evaluatedAt']),
        decision: (json['decision'] ?? '').toString(),
        followUps: (json['followUps'] is List)
            ? (json['followUps'] as List).map((e) => e.toString()).toList()
            : const [],
        followUpLink: (json['followUpLink'] ?? '').toString(),
        decisionNote: (json['decisionNote'] ?? '').toString(),
        decisionBy: (json['decisionBy'] ?? '').toString(),
        decisionAt: _parseDate(json['decisionAt']),
        prrcDecision: (json['prrcDecision'] ?? '').toString(),
        prrcNote: (json['prrcNote'] ?? '').toString(),
        prrcBy: (json['prrcBy'] ?? '').toString(),
        prrcAt: _parseDate(json['prrcAt']),
        fmeaId: (json['fmeaId'] ?? '').toString(),
        fmeaStatus: (json['fmeaStatus'] ?? '').toString(),
        capaId: (json['capaId'] ?? '').toString(),
        capaStatus: (json['capaStatus'] ?? '').toString(),
        implementationOwner: (json['implementationOwner'] ?? '').toString(),
        plannedDate: _parseDate(json['plannedDate']),
        implementedAt: _parseDate(json['implementedAt']),
        implemented: json['implemented'] == true || json['implemented'] == 'true' || json['implemented'] == 1,
        documentsUpdated: json['documentsUpdated'] == true || json['documentsUpdated'] == 'true' || json['documentsUpdated'] == 1,
        status: (json['status'] ?? 'open').toString(),
        implementationBy: (json['implementationBy'] ?? '').toString(),
        history: (json['history'] is List)
            ? (json['history'] as List)
                .whereType<Map>()
                .map((e) => ChangeHistoryEntry.fromJson(e.cast<String, dynamic>()))
                .toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'changeId': changeId,
        'title': title,
        'description': description,
        'justification': justification,
        'changeType': changeType,
        'initiator': initiator,
        'createdAt': createdAt?.millisecondsSinceEpoch,
        'updatedAt': updatedAt?.millisecondsSinceEpoch,
        'affectedDocuments': affectedDocuments,
        'affectedProcesses': affectedProcesses,
        'affectedProcessOther': affectedProcessOther,
        'trigger': trigger,
        'productImpact': productImpact,
        'documentationImpact': documentationImpact,
        'processImpact': processImpact,
        'regulatoryImpact': regulatoryImpact,
        'safetyRelevance': safetyRelevance,
        'riskChange': riskChange,
        'furtherAnalysis': furtherAnalysis,
        'evaluator': evaluator,
        'evaluatedAt': evaluatedAt?.millisecondsSinceEpoch,
        'decision': decision,
        'followUps': followUps,
        'followUpLink': followUpLink,
        'decisionNote': decisionNote,
        'decisionBy': decisionBy,
        'decisionAt': decisionAt?.millisecondsSinceEpoch,
        'prrcDecision': prrcDecision,
        'prrcNote': prrcNote,
        'prrcBy': prrcBy,
        'prrcAt': prrcAt?.millisecondsSinceEpoch,
        'fmeaId': fmeaId,
        'fmeaStatus': fmeaStatus,
        'capaId': capaId,
        'capaStatus': capaStatus,
        'implementationOwner': implementationOwner,
        'plannedDate': plannedDate?.millisecondsSinceEpoch,
        'implementedAt': implementedAt?.millisecondsSinceEpoch,
        'implemented': implemented,
        'documentsUpdated': documentsUpdated,
        'status': status,
        'implementationBy': implementationBy,
        'history': history.map((e) => e.toJson()).toList(),
      };

  ChangeManagementRecord copyWith({
    String? id,
    String? changeId,
    String? title,
    String? description,
    String? justification,
    String? changeType,
    String? initiator,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? affectedDocuments,
    List<String>? affectedProcesses,
    String? affectedProcessOther,
    String? trigger,
    String? productImpact,
    String? documentationImpact,
    String? processImpact,
    String? regulatoryImpact,
    String? safetyRelevance,
    String? riskChange,
    String? furtherAnalysis,
    String? evaluator,
    DateTime? evaluatedAt,
    String? decision,
    List<String>? followUps,
    String? followUpLink,
    String? decisionNote,
    String? decisionBy,
    DateTime? decisionAt,
    String? prrcDecision,
    String? prrcNote,
    String? prrcBy,
    DateTime? prrcAt,
    String? fmeaId,
    String? fmeaStatus,
    String? capaId,
    String? capaStatus,
    String? implementationOwner,
    DateTime? plannedDate,
    DateTime? implementedAt,
    bool? implemented,
    bool? documentsUpdated,
    String? status,
    String? implementationBy,
    List<ChangeHistoryEntry>? history,
  }) =>
      ChangeManagementRecord(
        id: id ?? this.id,
        changeId: changeId ?? this.changeId,
        title: title ?? this.title,
        description: description ?? this.description,
        justification: justification ?? this.justification,
        changeType: changeType ?? this.changeType,
        initiator: initiator ?? this.initiator,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        affectedDocuments: affectedDocuments ?? this.affectedDocuments,
        affectedProcesses: affectedProcesses ?? this.affectedProcesses,
        affectedProcessOther: affectedProcessOther ?? this.affectedProcessOther,
        trigger: trigger ?? this.trigger,
        productImpact: productImpact ?? this.productImpact,
        documentationImpact: documentationImpact ?? this.documentationImpact,
        processImpact: processImpact ?? this.processImpact,
        regulatoryImpact: regulatoryImpact ?? this.regulatoryImpact,
        safetyRelevance: safetyRelevance ?? this.safetyRelevance,
        riskChange: riskChange ?? this.riskChange,
        furtherAnalysis: furtherAnalysis ?? this.furtherAnalysis,
        evaluator: evaluator ?? this.evaluator,
        evaluatedAt: evaluatedAt ?? this.evaluatedAt,
        decision: decision ?? this.decision,
        followUps: followUps ?? this.followUps,
        followUpLink: followUpLink ?? this.followUpLink,
        decisionNote: decisionNote ?? this.decisionNote,
        decisionBy: decisionBy ?? this.decisionBy,
        decisionAt: decisionAt ?? this.decisionAt,
        prrcDecision: prrcDecision ?? this.prrcDecision,
        prrcNote: prrcNote ?? this.prrcNote,
        prrcBy: prrcBy ?? this.prrcBy,
        prrcAt: prrcAt ?? this.prrcAt,
        fmeaId: fmeaId ?? this.fmeaId,
        fmeaStatus: fmeaStatus ?? this.fmeaStatus,
        capaId: capaId ?? this.capaId,
        capaStatus: capaStatus ?? this.capaStatus,
        implementationOwner: implementationOwner ?? this.implementationOwner,
        plannedDate: plannedDate ?? this.plannedDate,
        implementedAt: implementedAt ?? this.implementedAt,
        implemented: implemented ?? this.implemented,
        documentsUpdated: documentsUpdated ?? this.documentsUpdated,
        status: status ?? this.status,
        implementationBy: implementationBy ?? this.implementationBy,
        history: history ?? this.history,
      );
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final num? parsed = (value is num) ? value : num.tryParse(value.toString());
  if (parsed == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(parsed.toInt());
}
