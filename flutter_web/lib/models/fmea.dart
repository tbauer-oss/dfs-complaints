import 'package:collection/collection.dart';

class FmeaRiskEntry {
  final String id;
  final String riskNumber;
  final String category;
  final String hazard;
  final String hazardSituation;
  final String harm;
  final String causes;
  final String affectedArea;
  final String processReference;
  final int? severity;
  final int? occurrence;
  final int? riskScore;
  final String? riskLevel;
  final String proposedAction;
  final String actionTaken;
  final String documents;
  final int? severityAfter;
  final int? occurrenceAfter;
  final int? riskScoreAfter;
  final String? riskLevelAfter;
  final bool newHazard;
  final bool residualRiskOk;
  final String riskBenefitAnalysis;
  final List<String> linkedComplaints;
  final List<String> linkedCapas;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FmeaRiskEntry({
    required this.id,
    required this.riskNumber,
    this.category = '',
    this.hazard = '',
    this.hazardSituation = '',
    this.harm = '',
    this.causes = '',
    this.affectedArea = '',
    this.processReference = '',
    this.severity,
    this.occurrence,
    this.riskScore,
    this.riskLevel,
    this.proposedAction = '',
    this.actionTaken = '',
    this.documents = '',
    this.severityAfter,
    this.occurrenceAfter,
    this.riskScoreAfter,
    this.riskLevelAfter,
    this.newHazard = false,
    this.residualRiskOk = true,
    this.riskBenefitAnalysis = '',
    this.linkedComplaints = const [],
    this.linkedCapas = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory FmeaRiskEntry.fromJson(Map<String, dynamic> json) {
    DateTime? _parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final n = int.tryParse(v.toString());
      if (n != null) return DateTime.fromMillisecondsSinceEpoch(n);
      return DateTime.tryParse(v.toString());
    }

    int? _parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    bool _parseBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      final s = v.toString().toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }

    List<String> _parseList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList(growable: false);
      return const [];
    }

    return FmeaRiskEntry(
      id: (json['id'] ?? json['riskId'] ?? '').toString(),
      riskNumber: (json['riskNumber'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      hazard: (json['hazard'] ?? '').toString(),
      hazardSituation: (json['hazardSituation'] ?? '').toString(),
      harm: (json['harm'] ?? '').toString(),
      causes: (json['causes'] ?? '').toString(),
      affectedArea: (json['affectedArea'] ?? '').toString(),
      processReference: (json['processReference'] ?? '').toString(),
      severity: _parseInt(json['severity']),
      occurrence: _parseInt(json['occurrence']),
      riskScore: _parseInt(json['riskScore']),
      riskLevel: (json['riskLevel'] ?? '').toString().isEmpty
          ? null
          : (json['riskLevel'] ?? '').toString(),
      proposedAction: (json['proposedAction'] ?? '').toString(),
      actionTaken: (json['actionTaken'] ?? '').toString(),
      documents: (json['documents'] ?? '').toString(),
      severityAfter: _parseInt(json['severityAfter']),
      occurrenceAfter: _parseInt(json['occurrenceAfter']),
      riskScoreAfter: _parseInt(json['riskScoreAfter']),
      riskLevelAfter: (json['riskLevelAfter'] ?? '').toString().isEmpty
          ? null
          : (json['riskLevelAfter'] ?? '').toString(),
      newHazard: _parseBool(json['newHazard']),
      residualRiskOk: _parseBool(json['residualRiskOk']),
      riskBenefitAnalysis: (json['riskBenefitAnalysis'] ?? '').toString(),
      linkedComplaints: _parseList(json['linkedComplaints']),
      linkedCapas: _parseList(json['linkedCapas']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'riskNumber': riskNumber,
        'category': category,
        'hazard': hazard,
        'hazardSituation': hazardSituation,
        'harm': harm,
        'causes': causes,
        'affectedArea': affectedArea,
        'processReference': processReference,
        'severity': severity,
        'occurrence': occurrence,
        'riskScore': riskScore,
        'riskLevel': riskLevel,
        'proposedAction': proposedAction,
        'actionTaken': actionTaken,
        'documents': documents,
        'severityAfter': severityAfter,
        'occurrenceAfter': occurrenceAfter,
        'riskScoreAfter': riskScoreAfter,
        'riskLevelAfter': riskLevelAfter,
        'newHazard': newHazard,
        'residualRiskOk': residualRiskOk,
        'riskBenefitAnalysis': riskBenefitAnalysis,
        'linkedComplaints': linkedComplaints,
        'linkedCapas': linkedCapas,
        'createdAt': createdAt?.millisecondsSinceEpoch,
        'updatedAt': updatedAt?.millisecondsSinceEpoch,
      };

  FmeaRiskEntry copyWith({
    String? id,
    String? riskNumber,
    String? category,
    String? hazard,
    String? hazardSituation,
    String? harm,
    String? causes,
    String? affectedArea,
    String? processReference,
    int? severity,
    int? occurrence,
    int? riskScore,
    String? riskLevel,
    String? proposedAction,
    String? actionTaken,
    String? documents,
    int? severityAfter,
    int? occurrenceAfter,
    int? riskScoreAfter,
    String? riskLevelAfter,
    bool? newHazard,
    bool? residualRiskOk,
    String? riskBenefitAnalysis,
    List<String>? linkedComplaints,
    List<String>? linkedCapas,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FmeaRiskEntry(
      id: id ?? this.id,
      riskNumber: riskNumber ?? this.riskNumber,
      category: category ?? this.category,
      hazard: hazard ?? this.hazard,
      hazardSituation: hazardSituation ?? this.hazardSituation,
      harm: harm ?? this.harm,
      causes: causes ?? this.causes,
      affectedArea: affectedArea ?? this.affectedArea,
      processReference: processReference ?? this.processReference,
      severity: severity ?? this.severity,
      occurrence: occurrence ?? this.occurrence,
      riskScore: riskScore ?? this.riskScore,
      riskLevel: riskLevel ?? this.riskLevel,
      proposedAction: proposedAction ?? this.proposedAction,
      actionTaken: actionTaken ?? this.actionTaken,
      documents: documents ?? this.documents,
      severityAfter: severityAfter ?? this.severityAfter,
      occurrenceAfter: occurrenceAfter ?? this.occurrenceAfter,
      riskScoreAfter: riskScoreAfter ?? this.riskScoreAfter,
      riskLevelAfter: riskLevelAfter ?? this.riskLevelAfter,
      newHazard: newHazard ?? this.newHazard,
      residualRiskOk: residualRiskOk ?? this.residualRiskOk,
      riskBenefitAnalysis: riskBenefitAnalysis ?? this.riskBenefitAnalysis,
      linkedComplaints: linkedComplaints ?? this.linkedComplaints,
      linkedCapas: linkedCapas ?? this.linkedCapas,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class FmeaRecord {
  final String id;
  final String title;
  final String mdrTd;
  final String productGroup;
  final String medicalProduct;
  final String moderator;
  final String revision;
  final bool prrcApproved;
  final String prrcName;
  final DateTime? prrcDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;
  final String updatedBy;
  final Map<String, int> riskMatrix;
  final List<FmeaRiskEntry> risks;

  const FmeaRecord({
    required this.id,
    this.title = '',
    this.mdrTd = '',
    this.productGroup = '',
    this.medicalProduct = '',
    this.moderator = '',
    this.revision = '',
    this.prrcApproved = false,
    this.prrcName = '',
    this.prrcDate,
    this.createdAt,
    this.updatedAt,
    this.createdBy = '',
    this.updatedBy = '',
    this.riskMatrix = const {'red': 15, 'yellow': 8},
    this.risks = const [],
  });

  factory FmeaRecord.fromJson(Map<String, dynamic> json) {
    DateTime? _parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final n = int.tryParse(v.toString());
      if (n != null) return DateTime.fromMillisecondsSinceEpoch(n);
      return DateTime.tryParse(v.toString());
    }

    bool _parseBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      final s = v.toString().toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }

    final riskList = (json['risks'] is List ? json['risks'] as List : const [])
        .whereType<Map>()
        .map((e) => FmeaRiskEntry.fromJson(e.cast<String, dynamic>()))
        .toList();

    final rm = (json['riskMatrix'] is Map)
        ? (json['riskMatrix'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return FmeaRecord(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      mdrTd: (json['mdrTd'] ?? '').toString(),
      productGroup: (json['productGroup'] ?? '').toString(),
      medicalProduct: (json['medicalProduct'] ?? '').toString(),
      moderator: (json['moderator'] ?? '').toString(),
      revision: (json['revision'] ?? '').toString(),
      prrcApproved: _parseBool(json['prrcApproved']),
      prrcName: (json['prrcName'] ?? '').toString(),
      prrcDate: _parseDate(json['prrcDate']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      createdBy: (json['createdBy'] ?? '').toString(),
      updatedBy: (json['updatedBy'] ?? '').toString(),
      riskMatrix: {
        'red': (rm['red'] is num) ? (rm['red'] as num).toInt() : 15,
        'yellow': (rm['yellow'] is num) ? (rm['yellow'] as num).toInt() : 8,
      },
      risks: riskList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'mdrTd': mdrTd,
        'productGroup': productGroup,
        'medicalProduct': medicalProduct,
        'moderator': moderator,
        'revision': revision,
        'prrcApproved': prrcApproved,
        'prrcName': prrcName,
        'prrcDate': prrcDate?.millisecondsSinceEpoch,
        'createdAt': createdAt?.millisecondsSinceEpoch,
        'updatedAt': updatedAt?.millisecondsSinceEpoch,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'riskMatrix': riskMatrix,
        'risks': risks.map((e) => e.toJson()).toList(),
      };

  FmeaRecord copyWith({
    String? id,
    String? title,
    String? mdrTd,
    String? productGroup,
    String? medicalProduct,
    String? moderator,
    String? revision,
    bool? prrcApproved,
    String? prrcName,
    DateTime? prrcDate,
    bool clearPrrcDate = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
    Map<String, int>? riskMatrix,
    List<FmeaRiskEntry>? risks,
  }) {
    return FmeaRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      mdrTd: mdrTd ?? this.mdrTd,
      productGroup: productGroup ?? this.productGroup,
      medicalProduct: medicalProduct ?? this.medicalProduct,
      moderator: moderator ?? this.moderator,
      revision: revision ?? this.revision,
      prrcApproved: prrcApproved ?? this.prrcApproved,
      prrcName: prrcName ?? this.prrcName,
      prrcDate: clearPrrcDate ? null : (prrcDate ?? this.prrcDate),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      riskMatrix: riskMatrix ?? this.riskMatrix,
      risks: risks ?? this.risks,
    );
  }

  static int Function(FmeaRecord a, FmeaRecord b) sortByUpdatedDesc() {
    return (a, b) {
      final aTs = a.updatedAt?.millisecondsSinceEpoch ?? 0;
      final bTs = b.updatedAt?.millisecondsSinceEpoch ?? 0;
      return bTs.compareTo(aTs);
    };
  }

  @override
  String toString() => 'FMEA($mdrTd · ${risks.length} Risiken)';

  @override
  int get hashCode => Object.hashAll([
        id,
        title,
        mdrTd,
        productGroup,
        medicalProduct,
        moderator,
        revision,
        prrcApproved,
        prrcName,
        prrcDate?.millisecondsSinceEpoch,
        createdAt?.millisecondsSinceEpoch,
        updatedAt?.millisecondsSinceEpoch,
        createdBy,
        updatedBy,
        riskMatrix['red'],
        riskMatrix['yellow'],
        const ListEquality().hash(risks),
      ]);

  @override
  bool operator ==(Object other) {
    return other is FmeaRecord &&
        other.id == id &&
        other.title == title &&
        other.mdrTd == mdrTd &&
        other.productGroup == productGroup &&
        other.medicalProduct == medicalProduct &&
        other.moderator == moderator &&
        other.revision == revision &&
        other.prrcApproved == prrcApproved &&
        other.prrcName == prrcName &&
        other.prrcDate == prrcDate &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.createdBy == createdBy &&
        other.updatedBy == updatedBy &&
        const MapEquality().equals(other.riskMatrix, riskMatrix) &&
        const ListEquality().equals(other.risks, risks);
  }
}
