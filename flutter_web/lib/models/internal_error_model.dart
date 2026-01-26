import 'dart:convert';

class InternalError {
  final String id;
  final String errorCode;
  final int year;
  final int sequence;
  final DateTime createdAt;
  final String createdBy;
  final String processArea;
  final String errorType;
  final String articleOrProduct;
  final String description;
  final String rootCause;
  final String detectedBy;
  final bool customerRelated;
  final bool supplierRelated;
  final String correctionAction;
  final DateTime? dueDate;
  final String responsiblePerson;
  final DateTime? effectivenessCheckDate;
  final bool? effectivenessOk;
  final String checker;
  final String notes;
  final int severity;
  final int occurrence;
  final int points;
  final String escalation;
  final bool capaRequired;
  final String? capaNumber;
  final String status;
  final bool capaOverride;
  final String capaOverrideReason;

  const InternalError({
    this.id = '',
    this.errorCode = '',
    this.year = 0,
    this.sequence = 0,
    DateTime? createdAt,
    this.createdBy = '',
    this.processArea = '',
    this.errorType = '',
    this.articleOrProduct = '',
    this.description = '',
    this.rootCause = '',
    this.detectedBy = '',
    this.customerRelated = false,
    this.supplierRelated = false,
    this.correctionAction = '',
    this.dueDate,
    this.responsiblePerson = '',
    this.effectivenessCheckDate,
    this.effectivenessOk,
    this.checker = '',
    this.notes = '',
    this.severity = 0,
    this.occurrence = 0,
    this.points = 0,
    this.escalation = 'A',
    this.capaRequired = false,
    this.capaNumber,
    this.status = 'Open',
    this.capaOverride = false,
    this.capaOverrideReason = '',
  }) : createdAt = createdAt ?? DateTime.now();

  InternalError copyWith({
    String? id,
    String? errorCode,
    int? year,
    int? sequence,
    DateTime? createdAt,
    String? createdBy,
    String? processArea,
    String? errorType,
    String? articleOrProduct,
    String? description,
    String? rootCause,
    String? detectedBy,
    bool? customerRelated,
    bool? supplierRelated,
    String? correctionAction,
    DateTime? dueDate,
    String? responsiblePerson,
    DateTime? effectivenessCheckDate,
    bool? effectivenessOk,
    String? checker,
    String? notes,
    int? severity,
    int? occurrence,
    int? points,
    String? escalation,
    bool? capaRequired,
    String? capaNumber,
    String? status,
    bool? capaOverride,
    String? capaOverrideReason,
  }) {
    return InternalError(
      id: id ?? this.id,
      errorCode: errorCode ?? this.errorCode,
      year: year ?? this.year,
      sequence: sequence ?? this.sequence,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      processArea: processArea ?? this.processArea,
      errorType: errorType ?? this.errorType,
      articleOrProduct: articleOrProduct ?? this.articleOrProduct,
      description: description ?? this.description,
      rootCause: rootCause ?? this.rootCause,
      detectedBy: detectedBy ?? this.detectedBy,
      customerRelated: customerRelated ?? this.customerRelated,
      supplierRelated: supplierRelated ?? this.supplierRelated,
      correctionAction: correctionAction ?? this.correctionAction,
      dueDate: dueDate ?? this.dueDate,
      responsiblePerson: responsiblePerson ?? this.responsiblePerson,
      effectivenessCheckDate: effectivenessCheckDate ?? this.effectivenessCheckDate,
      effectivenessOk: effectivenessOk ?? this.effectivenessOk,
      checker: checker ?? this.checker,
      notes: notes ?? this.notes,
      severity: severity ?? this.severity,
      occurrence: occurrence ?? this.occurrence,
      points: points ?? this.points,
      escalation: escalation ?? this.escalation,
      capaRequired: capaRequired ?? this.capaRequired,
      capaNumber: capaNumber ?? this.capaNumber,
      status: status ?? this.status,
      capaOverride: capaOverride ?? this.capaOverride,
      capaOverrideReason: capaOverrideReason ?? this.capaOverrideReason,
    );
  }

  InternalError recalcDerived() {
    final computedPoints = pointsFor(severity, occurrence);
    final computedEscalation = escalationForPoints(computedPoints);
    final computedCapa = capaRequiredForEscalation(computedEscalation);
    return copyWith(
      points: computedPoints,
      escalation: computedEscalation,
      capaRequired: capaOverride ? capaRequired : computedCapa,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'errorCode': errorCode,
      'year': year,
      'sequence': sequence,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'processArea': processArea,
      'errorType': errorType,
      'articleOrProduct': articleOrProduct,
      'description': description,
      'rootCause': rootCause,
      'detectedBy': detectedBy,
      'customerRelated': customerRelated,
      'supplierRelated': supplierRelated,
      'correctionAction': correctionAction,
      'dueDate': dueDate?.toIso8601String(),
      'responsiblePerson': responsiblePerson,
      'effectivenessCheckDate': effectivenessCheckDate?.toIso8601String(),
      'effectivenessOk': effectivenessOk,
      'checker': checker,
      'notes': notes,
      'severity': severity,
      'occurrence': occurrence,
      'points': points,
      'escalation': escalation,
      'capaRequired': capaRequired,
      'capaNumber': capaNumber,
      'status': status,
      'capaOverride': capaOverride,
      'capaOverrideReason': capaOverrideReason,
    };
  }

  factory InternalError.fromJson(Map<String, dynamic> json) {
    return InternalError(
      id: json['id'] as String? ?? '',
      errorCode: json['errorCode'] as String? ?? '',
      year: json['year'] as int? ?? 0,
      sequence: json['sequence'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      createdBy: json['createdBy'] as String? ?? '',
      processArea: json['processArea'] as String? ?? '',
      errorType: json['errorType'] as String? ?? '',
      articleOrProduct: json['articleOrProduct'] as String? ?? '',
      description: json['description'] as String? ?? '',
      rootCause: json['rootCause'] as String? ?? '',
      detectedBy: json['detectedBy'] as String? ?? '',
      customerRelated: json['customerRelated'] as bool? ?? false,
      supplierRelated: json['supplierRelated'] as bool? ?? false,
      correctionAction: json['correctionAction'] as String? ?? '',
      dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
      responsiblePerson: json['responsiblePerson'] as String? ?? '',
      effectivenessCheckDate: DateTime.tryParse(json['effectivenessCheckDate'] as String? ?? ''),
      effectivenessOk: json['effectivenessOk'] as bool?,
      checker: json['checker'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      severity: json['severity'] as int? ?? 0,
      occurrence: json['occurrence'] as int? ?? 0,
      points: json['points'] as int? ?? 0,
      escalation: json['escalation'] as String? ?? 'A',
      capaRequired: json['capaRequired'] as bool? ?? false,
      capaNumber: json['capaNumber'] as String?,
      status: json['status'] as String? ?? 'Open',
      capaOverride: json['capaOverride'] as bool? ?? false,
      capaOverrideReason: json['capaOverrideReason'] as String? ?? '',
    );
  }

  static const Map<int, int> severityMultipliers = {
    1: 2,
    2: 3,
    3: 5,
    4: 10,
    5: 15,
  };

  static int pointsFor(int severity, int occurrence) {
    if (severity <= 0 || occurrence <= 0) return 0;
    // FB852: points = occurrence * severityMultiplier
    return occurrence * (severityMultipliers[severity] ?? 0);
  }

  static String escalationForPoints(int points) {
    // Eskalation A-D thresholds
    if (points <= 25) return 'A';
    if (points <= 37) return 'B';
    if (points <= 50) return 'C';
    return 'D';
  }

  static bool capaRequiredForEscalation(String escalation) {
    return escalation == 'C' || escalation == 'D';
  }

  static String encodeList(List<InternalError> list) => jsonEncode(list.map((e) => e.toJson()).toList());

  static List<InternalError> decodeList(String raw) {
    final data = jsonDecode(raw);
    if (data is! List) return [];
    return data.map((item) => InternalError.fromJson(item as Map<String, dynamic>)).toList();
  }
}
