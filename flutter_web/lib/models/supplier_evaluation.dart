class Supplier {
  final String id;
  final String supplierNumber;
  final String name;
  final String address;
  final String contactName;
  final String contactEmail;
  final String contactPhone;
  final String website;
  final String country;
  final String category;
  final bool critical;
  final String status;
  final String notes;
  final String blockedReason;
  final int? blockedAt;
  final String blockedBy;
  final int createdAt;
  final int updatedAt;
  final String createdBy;
  final String updatedBy;
  final List<dynamic> history;

  const Supplier({
    required this.id,
    required this.supplierNumber,
    required this.name,
    required this.address,
    required this.contactName,
    required this.contactEmail,
    required this.contactPhone,
    required this.website,
    required this.country,
    required this.category,
    required this.critical,
    required this.status,
    required this.notes,
    required this.blockedReason,
    this.blockedAt,
    required this.blockedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.history,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: (json['id'] ?? json['supplierId'] ?? '').toString(),
        supplierNumber: (json['supplierNumber'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        contactName: (json['contactName'] ?? '').toString(),
        contactEmail: (json['contactEmail'] ?? '').toString(),
        contactPhone: (json['contactPhone'] ?? '').toString(),
        website: (json['website'] ?? '').toString(),
        country: (json['country'] ?? '').toString(),
        category: (json['category'] ?? '').toString(),
        critical: json['critical'] == true,
        status: (json['status'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
        blockedReason: (json['blockedReason'] ?? '').toString(),
        blockedAt: json['blockedAt'] is int ? json['blockedAt'] as int : null,
        blockedBy: (json['blockedBy'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? 0) as int,
        updatedAt: (json['updatedAt'] ?? 0) as int,
        createdBy: (json['createdBy'] ?? '').toString(),
        updatedBy: (json['updatedBy'] ?? '').toString(),
        history: (json['history'] as List?) ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplierNumber': supplierNumber,
        'name': name,
        'address': address,
        'contactName': contactName,
        'contactEmail': contactEmail,
        'contactPhone': contactPhone,
        'website': website,
        'country': country,
        'category': category,
        'critical': critical,
        'status': status,
        'notes': notes,
        'blockedReason': blockedReason,
        'blockedAt': blockedAt,
        'blockedBy': blockedBy,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'history': history,
      };

  Supplier copyWith({
    String? id,
    String? supplierNumber,
    String? name,
    String? address,
    String? contactName,
    String? contactEmail,
    String? contactPhone,
    String? website,
    String? country,
    String? category,
    bool? critical,
    String? status,
    String? notes,
    String? blockedReason,
    int? blockedAt,
    String? blockedBy,
    int? createdAt,
    int? updatedAt,
    String? createdBy,
    String? updatedBy,
    List<dynamic>? history,
  }) {
    return Supplier(
      id: id ?? this.id,
      supplierNumber: supplierNumber ?? this.supplierNumber,
      name: name ?? this.name,
      address: address ?? this.address,
      contactName: contactName ?? this.contactName,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      website: website ?? this.website,
      country: country ?? this.country,
      category: category ?? this.category,
      critical: critical ?? this.critical,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      blockedReason: blockedReason ?? this.blockedReason,
      blockedAt: blockedAt ?? this.blockedAt,
      blockedBy: blockedBy ?? this.blockedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      history: history ?? this.history,
    );
  }
}

class SupplierLookups {
  final List<String> categories;
  final List<String> countries;
  final List<String> statuses;
  final int updatedAt;
  final String updatedBy;
  final List<dynamic> history;

  const SupplierLookups({
    required this.categories,
    required this.countries,
    required this.statuses,
    required this.updatedAt,
    required this.updatedBy,
    required this.history,
  });

  factory SupplierLookups.empty() => const SupplierLookups(
        categories: [],
        countries: [],
        statuses: ['zugelassen', 'in bewertung', 'gesperrt'],
        updatedAt: 0,
        updatedBy: '',
        history: [],
      );

  factory SupplierLookups.fromJson(Map<String, dynamic> json) => SupplierLookups(
        categories: (json['categories'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        countries: (json['countries'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        statuses: (json['statuses'] as List?)?.map((e) => e.toString()).toList() ??
            const ['zugelassen', 'in bewertung', 'gesperrt'],
        updatedAt: (json['updatedAt'] ?? 0) as int,
        updatedBy: (json['updatedBy'] ?? '').toString(),
        history: (json['history'] as List?) ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'categories': categories,
        'countries': countries,
        'statuses': statuses,
        'updatedAt': updatedAt,
        'updatedBy': updatedBy,
        'history': history,
      };
}

class SupplierPerformanceEntry {
  final String id;
  final String supplierId;
  final int date;
  final String type;
  final String rating;
  final String description;
  final String reference;
  final List<dynamic> attachments;
  final bool includeInAnnual;
  final String status;
  final String cancelReason;
  final int createdAt;
  final int updatedAt;
  final String createdBy;
  final String updatedBy;
  final List<dynamic> history;

  const SupplierPerformanceEntry({
    required this.id,
    required this.supplierId,
    required this.date,
    required this.type,
    required this.rating,
    required this.description,
    required this.reference,
    required this.attachments,
    required this.includeInAnnual,
    required this.status,
    required this.cancelReason,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.history,
  });

  factory SupplierPerformanceEntry.fromJson(Map<String, dynamic> json) => SupplierPerformanceEntry(
        id: (json['id'] ?? json['entryId'] ?? '').toString(),
        supplierId: (json['supplierId'] ?? '').toString(),
        date: (json['date'] ?? 0) as int,
        type: (json['type'] ?? '').toString(),
        rating: (json['rating'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        reference: (json['reference'] ?? '').toString(),
        attachments: (json['attachments'] as List?) ?? const [],
        includeInAnnual: json['includeInAnnual'] != false,
        status: (json['status'] ?? '').toString(),
        cancelReason: (json['cancelReason'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? 0) as int,
        updatedAt: (json['updatedAt'] ?? 0) as int,
        createdBy: (json['createdBy'] ?? '').toString(),
        updatedBy: (json['updatedBy'] ?? '').toString(),
        history: (json['history'] as List?) ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplierId': supplierId,
        'date': date,
        'type': type,
        'rating': rating,
        'description': description,
        'reference': reference,
        'attachments': attachments,
        'includeInAnnual': includeInAnnual,
        'status': status,
        'cancelReason': cancelReason,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'history': history,
      };
}

class SupplierAnnualEvaluation {
  final String id;
  final int evalYear;
  final int? periodFrom;
  final int? periodTo;
  final String supplierId;
  final Map<String, dynamic> aggregates;
  final String commentEk;
  final String commentQm;
  final String decision;
  final String decisionReason;
  final String status;
  final int configVersion;
  final Map<String, dynamic> configSnapshot;
  final int createdAt;
  final int updatedAt;
  final String createdBy;
  final String updatedBy;
  final String reviewedBy;
  final String approvedBy;
  final List<dynamic> history;

  const SupplierAnnualEvaluation({
    required this.id,
    required this.evalYear,
    required this.periodFrom,
    required this.periodTo,
    required this.supplierId,
    required this.aggregates,
    required this.commentEk,
    required this.commentQm,
    required this.decision,
    required this.decisionReason,
    required this.status,
    required this.configVersion,
    required this.configSnapshot,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.reviewedBy,
    required this.approvedBy,
    required this.history,
  });

  factory SupplierAnnualEvaluation.fromJson(Map<String, dynamic> json) => SupplierAnnualEvaluation(
        id: (json['id'] ?? json['evalId'] ?? '').toString(),
        evalYear: (json['evalYear'] ?? 0) as int,
        periodFrom: json['periodFrom'] is int ? json['periodFrom'] as int : null,
        periodTo: json['periodTo'] is int ? json['periodTo'] as int : null,
        supplierId: (json['supplierId'] ?? '').toString(),
        aggregates: (json['aggregates'] as Map?)?.cast<String, dynamic>() ?? const {},
        commentEk: (json['commentEk'] ?? '').toString(),
        commentQm: (json['commentQm'] ?? '').toString(),
        decision: (json['decision'] ?? '').toString(),
        decisionReason: (json['decisionReason'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        configVersion: (json['configVersion'] ?? 0) as int,
        configSnapshot: (json['configSnapshot'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: (json['createdAt'] ?? 0) as int,
        updatedAt: (json['updatedAt'] ?? 0) as int,
        createdBy: (json['createdBy'] ?? '').toString(),
        updatedBy: (json['updatedBy'] ?? '').toString(),
        reviewedBy: (json['reviewedBy'] ?? '').toString(),
        approvedBy: (json['approvedBy'] ?? '').toString(),
        history: (json['history'] as List?) ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'evalYear': evalYear,
        'periodFrom': periodFrom,
        'periodTo': periodTo,
        'supplierId': supplierId,
        'aggregates': aggregates,
        'commentEk': commentEk,
        'commentQm': commentQm,
        'decision': decision,
        'decisionReason': decisionReason,
        'status': status,
        'configVersion': configVersion,
        'configSnapshot': configSnapshot,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'reviewedBy': reviewedBy,
        'approvedBy': approvedBy,
        'history': history,
      };
}

class SupplierEscalation {
  final String id;
  final String supplierId;
  final String trigger;
  final String reason;
  final String severity;
  final String status;
  final String owner;
  final int? dueDate;
  final Map<String, dynamic> links;
  final String actions;
  final String effectiveness;
  final int createdAt;
  final int updatedAt;
  final String createdBy;
  final String updatedBy;
  final List<dynamic> history;

  const SupplierEscalation({
    required this.id,
    required this.supplierId,
    required this.trigger,
    required this.reason,
    required this.severity,
    required this.status,
    required this.owner,
    required this.dueDate,
    required this.links,
    required this.actions,
    required this.effectiveness,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.history,
  });

  factory SupplierEscalation.fromJson(Map<String, dynamic> json) => SupplierEscalation(
        id: (json['id'] ?? json['escalationId'] ?? '').toString(),
        supplierId: (json['supplierId'] ?? '').toString(),
        trigger: (json['trigger'] ?? '').toString(),
        reason: (json['reason'] ?? '').toString(),
        severity: (json['severity'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        owner: (json['owner'] ?? '').toString(),
        dueDate: json['dueDate'] is int ? json['dueDate'] as int : null,
        links: (json['links'] as Map?)?.cast<String, dynamic>() ?? const {},
        actions: (json['actions'] ?? '').toString(),
        effectiveness: (json['effectiveness'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? 0) as int,
        updatedAt: (json['updatedAt'] ?? 0) as int,
        createdBy: (json['createdBy'] ?? '').toString(),
        updatedBy: (json['updatedBy'] ?? '').toString(),
        history: (json['history'] as List?) ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplierId': supplierId,
        'trigger': trigger,
        'reason': reason,
        'severity': severity,
        'status': status,
        'owner': owner,
        'dueDate': dueDate,
        'links': links,
        'actions': actions,
        'effectiveness': effectiveness,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'history': history,
      };
}

class SupplierEvaluationConfig {
  final String id;
  final int version;
  final List<dynamic> categories;
  final Map<String, dynamic> thresholds;
  final Map<String, dynamic> trend;
  final Map<String, dynamic> annualWindow;
  final Map<String, dynamic> approval;
  final Map<String, dynamic> editRules;
  final Map<String, dynamic> notifications;
  final int updatedAt;
  final String updatedBy;
  final List<dynamic> history;

  const SupplierEvaluationConfig({
    required this.id,
    required this.version,
    required this.categories,
    required this.thresholds,
    required this.trend,
    required this.annualWindow,
    required this.approval,
    required this.editRules,
    required this.notifications,
    required this.updatedAt,
    required this.updatedBy,
    required this.history,
  });

  factory SupplierEvaluationConfig.fromJson(Map<String, dynamic> json) => SupplierEvaluationConfig(
        id: (json['id'] ?? '').toString(),
        version: (json['version'] ?? 0) as int,
        categories: (json['categories'] as List?) ?? const [],
        thresholds: (json['thresholds'] as Map?)?.cast<String, dynamic>() ?? const {},
        trend: (json['trend'] as Map?)?.cast<String, dynamic>() ?? const {},
        annualWindow: (json['annualWindow'] as Map?)?.cast<String, dynamic>() ?? const {},
        approval: (json['approval'] as Map?)?.cast<String, dynamic>() ?? const {},
        editRules: (json['editRules'] as Map?)?.cast<String, dynamic>() ?? const {},
        notifications: (json['notifications'] as Map?)?.cast<String, dynamic>() ?? const {},
        updatedAt: (json['updatedAt'] ?? 0) as int,
        updatedBy: (json['updatedBy'] ?? '').toString(),
        history: (json['history'] as List?) ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'categories': categories,
        'thresholds': thresholds,
        'trend': trend,
        'annualWindow': annualWindow,
        'approval': approval,
        'editRules': editRules,
        'notifications': notifications,
        'updatedAt': updatedAt,
        'updatedBy': updatedBy,
        'history': history,
      };
}
