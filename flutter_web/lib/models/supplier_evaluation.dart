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
  final String correspondenceLanguage;
  final String status;
  final String notes;
  final String blockedReason;
  final int? blockedAt;
  final String blockedBy;
  final int? archivedAt;
  final String archivedBy;
  final String archivedReason;
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
    required this.correspondenceLanguage,
    required this.status,
    required this.notes,
    required this.blockedReason,
    this.blockedAt,
    required this.blockedBy,
    this.archivedAt,
    required this.archivedBy,
    required this.archivedReason,
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
        correspondenceLanguage: (json['correspondenceLanguage'] ?? json['language'] ?? 'DE').toString().toUpperCase(),
        status: (json['status'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
        blockedReason: (json['blockedReason'] ?? '').toString(),
        blockedAt: json['blockedAt'] is int ? json['blockedAt'] as int : null,
        blockedBy: (json['blockedBy'] ?? '').toString(),
        archivedAt: json['archivedAt'] is int ? json['archivedAt'] as int : null,
        archivedBy: (json['archivedBy'] ?? '').toString(),
        archivedReason: (json['archivedReason'] ?? '').toString(),
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
        'correspondenceLanguage': correspondenceLanguage,
        'status': status,
        'notes': notes,
        'blockedReason': blockedReason,
        'blockedAt': blockedAt,
        'blockedBy': blockedBy,
        'archivedAt': archivedAt,
        'archivedBy': archivedBy,
        'archivedReason': archivedReason,
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
    String? correspondenceLanguage,
    String? status,
    String? notes,
    String? blockedReason,
    int? blockedAt,
    String? blockedBy,
    int? archivedAt,
    String? archivedBy,
    String? archivedReason,
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
      correspondenceLanguage: correspondenceLanguage ?? this.correspondenceLanguage,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      blockedReason: blockedReason ?? this.blockedReason,
      blockedAt: blockedAt ?? this.blockedAt,
      blockedBy: blockedBy ?? this.blockedBy,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      archivedReason: archivedReason ?? this.archivedReason,
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
        statuses: ['zugelassen', 'in bewertung', 'gesperrt', 'inaktiv'],
        updatedAt: 0,
        updatedBy: '',
        history: [],
      );

  factory SupplierLookups.fromJson(Map<String, dynamic> json) => SupplierLookups(
        categories: (json['categories'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        countries: (json['countries'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        statuses: (json['statuses'] as List?)?.map((e) => e.toString()).toList() ??
            const ['zugelassen', 'in bewertung', 'gesperrt', 'inaktiv'],
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
  final String description;
  final String referenceType;
  final String referenceNumber;
  final Map<String, int?> ratings;
  final Map<String, bool> ratingsNa;
  final bool communicationNa;
  final int ratingSchemaVersion;
  final List<dynamic> attachments;
  final bool includeInAnnual;
  final String status;
  final String cancelReason;
  final double? computedGrade;
  final double? computedScore;
  final int? computedAt;
  final int? deletedAt;
  final String deletedBy;
  final String deletedReason;
  final int createdAt;
  final int updatedAt;
  final String createdBy;
  final String updatedBy;
  final List<dynamic> history;

  const SupplierPerformanceEntry({
    required this.id,
    required this.supplierId,
    required this.date,
    required this.description,
    required this.referenceType,
    required this.referenceNumber,
    required this.ratings,
    required this.ratingsNa,
    required this.communicationNa,
    required this.ratingSchemaVersion,
    required this.attachments,
    required this.includeInAnnual,
    required this.status,
    required this.cancelReason,
    required this.computedGrade,
    required this.computedScore,
    required this.computedAt,
    required this.deletedAt,
    required this.deletedBy,
    required this.deletedReason,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.history,
  });

  static String _mapLegacyType(String type) {
    final value = type.toLowerCase();
    if (value.contains('qualität') || value.contains('qualitaet')) return 'quality';
    if (value.contains('termin') || value.contains('liefer')) return 'delivery';
    if (value.contains('preis')) return 'price';
    if (value.contains('menge')) return 'quantity';
    if (value.contains('nachliefer')) return 'backorders';
    if (value.contains('kommunik') || value.contains('dokument') || value.contains('service')) return 'communication';
    return '';
  }

  static int _resolveRatingSchemaVersion(Map<String, dynamic> json) {
    final version = json['ratingSchemaVersion'];
    if (version is num) return version.toInt();
    return int.tryParse(version?.toString() ?? '') ?? 1;
  }

  static int _mapLegacyRating(int value, int maxValue) {
    if (maxValue <= 4) {
      if (value <= 1) return 1;
      if (value == 2) return 2;
      if (value == 3) return 4;
      return 6;
    }
    if (maxValue == 5) {
      if (value <= 1) return 1;
      if (value == 2) return 2;
      if (value == 3) return 3;
      if (value == 4) return 5;
      return 6;
    }
    if (value < 1) return 1;
    if (value > 6) return 6;
    return value;
  }

  static int _normalizeRatingValue(int value, int schemaVersion, int maxValue) {
    if (schemaVersion < 3) {
      return _mapLegacyRating(value, maxValue);
    }
    if (value < 1) return 1;
    if (value > 6) return 6;
    return value;
  }

  static Map<String, int?> _normalizeRatings(Map<String, dynamic> json) {
    final schemaVersion = _resolveRatingSchemaVersion(json);
    final ratings = <String, int?>{
      'communication': null,
      'quality': null,
      'delivery': null,
      'price': null,
      'quantity': null,
      'backorders': null,
    };
    final rawRatings = json['ratings'];
    final maxRatingValues = <int>[];
    if (rawRatings is Map) {
      rawRatings.forEach((key, value) {
        final parsed = value is int ? value : int.tryParse(value.toString());
        final normalizedKey = key.toString();
        if (!ratings.containsKey(normalizedKey)) return;
        if (parsed != null) {
          maxRatingValues.add(parsed);
        }
        ratings[normalizedKey] = parsed == null ? null : parsed;
      });
    }
    final legacyRating = int.tryParse(json['rating']?.toString() ?? '');
    if (legacyRating != null) {
      maxRatingValues.add(legacyRating);
    }
    final maxRating = maxRatingValues.isEmpty ? 0 : maxRatingValues.reduce((a, b) => a > b ? a : b);
    ratings.updateAll((key, value) {
      if (value == null) return null;
      return _normalizeRatingValue(value, schemaVersion, maxRating);
    });
    if (ratings.values.every((value) => value == null)) {
      final legacyType = _mapLegacyType(json['type']?.toString() ?? '');
      final parsedLegacyRating = int.tryParse(json['rating']?.toString() ?? '');
      if (legacyType.isNotEmpty) {
        ratings[legacyType] = parsedLegacyRating == null
            ? null
            : _normalizeRatingValue(parsedLegacyRating, schemaVersion, parsedLegacyRating);
      }
    }
    return ratings;
  }

  static Map<String, bool> _normalizeRatingsNa(Map<String, dynamic> json, Map<String, int?> ratings) {
    final ratingsNa = <String, bool>{
      'communication': false,
      'quality': false,
      'delivery': false,
      'price': false,
      'quantity': false,
      'backorders': false,
    };
    final rawRatingsNa = json['ratingsNa'];
    if (rawRatingsNa is Map) {
      rawRatingsNa.forEach((key, value) {
        final normalizedKey = key.toString();
        if (!ratingsNa.containsKey(normalizedKey)) return;
        ratingsNa[normalizedKey] = value == true;
      });
    }
    if (json['communicationNa'] == true && ratings['communication'] == null) {
      ratingsNa['communication'] = true;
    }
    return ratingsNa;
  }

  factory SupplierPerformanceEntry.fromJson(Map<String, dynamic> json) {
    final ratings = _normalizeRatings(json);
    final ratingsNa = _normalizeRatingsNa(json, ratings);
    return SupplierPerformanceEntry(
        id: (json['id'] ?? json['entryId'] ?? '').toString(),
        supplierId: (json['supplierId'] ?? '').toString(),
        date: (json['date'] ?? 0) as int,
        description: (json['description'] ?? '').toString(),
        referenceType: (json['referenceType'] ?? (json['reference'] is Map ? json['reference']['referenceType'] : '') ?? '').toString(),
        referenceNumber: (json['referenceNumber'] ??
                (json['reference'] is Map ? json['reference']['referenceNumber'] : '') ??
                (json['reference'] is String ? json['reference'] : '') ??
                '')
            .toString(),
        ratings: ratings,
        ratingsNa: ratingsNa,
        communicationNa: json['communicationNa'] == true || ratingsNa['communication'] == true,
        ratingSchemaVersion: _resolveRatingSchemaVersion(json),
        attachments: (json['attachments'] as List?) ?? const [],
        includeInAnnual: json['includeInAnnual'] != false,
        status: (json['status'] ?? '').toString(),
        cancelReason: (json['cancelReason'] ?? '').toString(),
        computedGrade: json['computedGrade'] is num ? (json['computedGrade'] as num).toDouble() : null,
        computedScore: json['computedScore'] is num
            ? (json['computedScore'] as num).toDouble()
            : (json['computedGrade'] is num ? (json['computedGrade'] as num).toDouble() : null),
        computedAt: json['computedAt'] is int ? json['computedAt'] as int : null,
        deletedAt: json['deletedAt'] is int ? json['deletedAt'] as int : null,
        deletedBy: (json['deletedBy'] ?? '').toString(),
        deletedReason: (json['deletedReason'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? 0) as int,
        updatedAt: (json['updatedAt'] ?? 0) as int,
        createdBy: (json['createdBy'] ?? '').toString(),
        updatedBy: (json['updatedBy'] ?? '').toString(),
        history: (json['history'] as List?) ?? const [],
      );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplierId': supplierId,
        'date': date,
        'description': description,
        'referenceType': referenceType,
        'referenceNumber': referenceNumber,
        'ratings': ratings.map((key, value) => MapEntry(key, value)),
        'ratingsNa': ratingsNa.map((key, value) => MapEntry(key, value)),
        'communicationNa': communicationNa,
        'ratingSchemaVersion': ratingSchemaVersion,
        'attachments': attachments,
        'includeInAnnual': includeInAnnual,
        'status': status,
        'cancelReason': cancelReason,
        'computedGrade': computedGrade,
        'computedScore': computedScore,
        'computedAt': computedAt,
        'deletedAt': deletedAt,
        'deletedBy': deletedBy,
        'deletedReason': deletedReason,
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
  final int? archivedAt;
  final String archivedBy;
  final String archivedReason;
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
    this.archivedAt,
    required this.archivedBy,
    required this.archivedReason,
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
        archivedAt: json['archivedAt'] is int ? json['archivedAt'] as int : null,
        archivedBy: (json['archivedBy'] ?? '').toString(),
        archivedReason: (json['archivedReason'] ?? '').toString(),
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
        'archivedAt': archivedAt,
        'archivedBy': archivedBy,
        'archivedReason': archivedReason,
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

  SupplierAnnualEvaluation copyWith({
    String? id,
    int? evalYear,
    int? periodFrom,
    int? periodTo,
    String? supplierId,
    Map<String, dynamic>? aggregates,
    String? commentEk,
    String? commentQm,
    String? decision,
    String? decisionReason,
    String? status,
    int? archivedAt,
    String? archivedBy,
    String? archivedReason,
    int? configVersion,
    Map<String, dynamic>? configSnapshot,
    int? createdAt,
    int? updatedAt,
    String? createdBy,
    String? updatedBy,
    String? reviewedBy,
    String? approvedBy,
    List<dynamic>? history,
  }) {
    return SupplierAnnualEvaluation(
      id: id ?? this.id,
      evalYear: evalYear ?? this.evalYear,
      periodFrom: periodFrom ?? this.periodFrom,
      periodTo: periodTo ?? this.periodTo,
      supplierId: supplierId ?? this.supplierId,
      aggregates: aggregates ?? this.aggregates,
      commentEk: commentEk ?? this.commentEk,
      commentQm: commentQm ?? this.commentQm,
      decision: decision ?? this.decision,
      decisionReason: decisionReason ?? this.decisionReason,
      status: status ?? this.status,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      archivedReason: archivedReason ?? this.archivedReason,
      configVersion: configVersion ?? this.configVersion,
      configSnapshot: configSnapshot ?? this.configSnapshot,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      approvedBy: approvedBy ?? this.approvedBy,
      history: history ?? this.history,
    );
  }
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

class SupplierLetterLayoutConfig {
  final String id;
  final int version;
  final Map<String, double> page;
  final Map<String, double> header;
  final Map<String, double> recipientBlock;
  final Map<String, double> dateBlock;
  final Map<String, double> titleBlock;
  final double bodyStartMm;
  final SupplierLetterSignatureConfig signature;
  final int updatedAt;
  final String updatedBy;
  final List<dynamic> history;

  const SupplierLetterLayoutConfig({
    required this.id,
    required this.version,
    required this.page,
    required this.header,
    required this.recipientBlock,
    required this.dateBlock,
    required this.titleBlock,
    required this.bodyStartMm,
    required this.signature,
    required this.updatedAt,
    required this.updatedBy,
    required this.history,
  });

  factory SupplierLetterLayoutConfig.defaults() => SupplierLetterLayoutConfig(
        id: 'letter-default',
        version: 1,
        page: {'marginTopMm': 18, 'marginRightMm': 18, 'marginBottomMm': 18, 'marginLeftMm': 18},
        header: {'logoWidthMm': 35, 'headerTopMm': 10},
        recipientBlock: {'topMm': 45, 'leftMm': 20},
        dateBlock: {'topMm': 45, 'rightMm': 20},
        titleBlock: {'topMm': 85},
        bodyStartMm: 95,
        signature: SupplierLetterSignatureConfig.defaults(),
        updatedAt: 0,
        updatedBy: '',
        history: [],
      );

  factory SupplierLetterLayoutConfig.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value, double fallback) => value is num ? value.toDouble() : fallback;
    Map<String, double> toMap(Map? raw, Map<String, double> fallback) {
      final map = <String, double>{};
      fallback.forEach((key, value) {
        map[key] = toDouble(raw?[key], value);
      });
      return map;
    }

    final defaults = SupplierLetterLayoutConfig.defaults();
    return SupplierLetterLayoutConfig(
      id: (json['id'] ?? defaults.id).toString(),
      version: (json['version'] ?? defaults.version) as int,
      page: toMap(json['page'] as Map?, defaults.page),
      header: toMap(json['header'] as Map?, defaults.header),
      recipientBlock: toMap(json['recipientBlock'] as Map?, defaults.recipientBlock),
      dateBlock: toMap(json['dateBlock'] as Map?, defaults.dateBlock),
      titleBlock: toMap(json['titleBlock'] as Map?, defaults.titleBlock),
      bodyStartMm: toDouble(json['bodyStartMm'], defaults.bodyStartMm),
      signature: json['signature'] is Map
          ? SupplierLetterSignatureConfig.fromJson((json['signature'] as Map).cast<String, dynamic>())
          : defaults.signature,
      updatedAt: (json['updatedAt'] ?? 0) as int,
      updatedBy: (json['updatedBy'] ?? '').toString(),
      history: (json['history'] as List?) ?? const [],
    );
  }

  SupplierLetterLayoutConfig copyWith({
    Map<String, double>? page,
    Map<String, double>? header,
    Map<String, double>? recipientBlock,
    Map<String, double>? dateBlock,
    Map<String, double>? titleBlock,
    double? bodyStartMm,
    SupplierLetterSignatureConfig? signature,
  }) {
    return SupplierLetterLayoutConfig(
      id: id,
      version: version,
      page: page ?? this.page,
      header: header ?? this.header,
      recipientBlock: recipientBlock ?? this.recipientBlock,
      dateBlock: dateBlock ?? this.dateBlock,
      titleBlock: titleBlock ?? this.titleBlock,
      bodyStartMm: bodyStartMm ?? this.bodyStartMm,
      signature: signature ?? this.signature,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
      history: history,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'page': page,
        'header': header,
        'recipientBlock': recipientBlock,
        'dateBlock': dateBlock,
        'titleBlock': titleBlock,
        'bodyStartMm': bodyStartMm,
        'signature': signature.toJson(),
        'updatedAt': updatedAt,
        'updatedBy': updatedBy,
        'history': history,
      };
}

class SupplierLetterSignatureConfig {
  final Map<String, String> senderName;
  final bool enabled;
  final double startY;
  final bool compact;
  final bool showName;
  final bool showRole;
  final bool showEmail;
  final bool showLegalFooter;

  const SupplierLetterSignatureConfig({
    required this.senderName,
    required this.enabled,
    required this.startY,
    required this.compact,
    required this.showName,
    required this.showRole,
    required this.showEmail,
    required this.showLegalFooter,
  });

  factory SupplierLetterSignatureConfig.defaults() => const SupplierLetterSignatureConfig(
        senderName: {
          'de': 'DFS-Diamon Lieferantenmanagement',
          'en': 'DFS-Diamon Supplier Management',
        },
        enabled: true,
        startY: 230,
        compact: true,
        showName: true,
        showRole: false,
        showEmail: false,
        showLegalFooter: true,
      );

  factory SupplierLetterSignatureConfig.fromJson(Map<String, dynamic> json) {
    final defaults = SupplierLetterSignatureConfig.defaults();
    double toDouble(dynamic value, double fallback) => value is num ? value.toDouble() : fallback;
    bool toBool(dynamic value, bool fallback) => value is bool ? value : fallback;
    Map<String, String> toSenderName(Map? raw, Map<String, String> fallback) {
      final map = <String, String>{};
      fallback.forEach((key, value) {
        final rawValue = raw?[key];
        map[key] = rawValue is String && rawValue.isNotEmpty ? rawValue : value;
      });
      return map;
    }
    return SupplierLetterSignatureConfig(
      senderName: toSenderName(json['senderName'] as Map?, defaults.senderName),
      enabled: toBool(json['enabled'], defaults.enabled),
      startY: toDouble(json['startY'], defaults.startY),
      compact: toBool(json['compact'], defaults.compact),
      showName: toBool(json['showName'], defaults.showName),
      showRole: toBool(json['showRole'], defaults.showRole),
      showEmail: toBool(json['showEmail'], defaults.showEmail),
      showLegalFooter: toBool(json['showLegalFooter'], defaults.showLegalFooter),
    );
  }

  SupplierLetterSignatureConfig copyWith({
    Map<String, String>? senderName,
    bool? enabled,
    double? startY,
    bool? compact,
    bool? showName,
    bool? showRole,
    bool? showEmail,
    bool? showLegalFooter,
  }) {
    return SupplierLetterSignatureConfig(
      senderName: senderName ?? this.senderName,
      enabled: enabled ?? this.enabled,
      startY: startY ?? this.startY,
      compact: compact ?? this.compact,
      showName: showName ?? this.showName,
      showRole: showRole ?? this.showRole,
      showEmail: showEmail ?? this.showEmail,
      showLegalFooter: showLegalFooter ?? this.showLegalFooter,
    );
  }

  Map<String, dynamic> toJson() => {
        'senderName': senderName,
        'enabled': enabled,
        'startY': startY,
        'compact': compact,
        'showName': showName,
        'showRole': showRole,
        'showEmail': showEmail,
        'showLegalFooter': showLegalFooter,
      };
}
