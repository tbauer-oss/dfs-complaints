class TdSummary {
  final int complianceScore;
  final String readinessStatus;
  final int overdueReviews;
  final int openCapaCount;
  final List<String> reasons;

  const TdSummary({
    required this.complianceScore,
    required this.readinessStatus,
    required this.overdueReviews,
    required this.openCapaCount,
    required this.reasons,
  });

  factory TdSummary.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TdSummary(
      complianceScore: (map['complianceScore'] as num?)?.toInt() ?? 0,
      readinessStatus: (map['readinessStatus'] ?? 'Yellow').toString(),
      overdueReviews: (map['overdueReviews'] as num?)?.toInt() ?? 0,
      openCapaCount: (map['openCapaCount'] as num?)?.toInt() ?? 0,
      reasons: (map['reasons'] as List?)?.map((e) => '$e').toList(growable: false) ?? const [],
    );
  }
}

class TdFile {
  final String id;
  final String code;
  final String title;
  final String lifecycleState;
  final String? productGroup;
  final String? classification;
  final String? rule;
  final String status;
  final TdSummary summary;

  const TdFile({
    required this.id,
    required this.code,
    required this.title,
    required this.lifecycleState,
    required this.productGroup,
    required this.classification,
    required this.rule,
    required this.status,
    required this.summary,
  });

  factory TdFile.fromJson(Map<String, dynamic> json) => TdFile(
        id: (json['id'] ?? '').toString(),
        code: (json['code'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        lifecycleState: (json['lifecycleState'] ?? 'Development').toString(),
        productGroup: json['productGroup']?.toString(),
        classification: json['classification']?.toString(),
        rule: json['rule']?.toString(),
        status: (json['status'] ?? 'Draft').toString(),
        summary: TdSummary.fromJson((json['summary'] as Map?)?.cast<String, dynamic>()),
      );
}

class TdSection {
  final String id;
  final String templateKey;
  final String name;
  final String status;
  final String? ownerUserId;
  final String? nextReviewAt;

  const TdSection({
    required this.id,
    required this.templateKey,
    required this.name,
    required this.status,
    required this.ownerUserId,
    required this.nextReviewAt,
  });

  factory TdSection.fromJson(Map<String, dynamic> json) => TdSection(
        id: '${json['id'] ?? ''}',
        templateKey: '${json['templateKey'] ?? ''}',
        name: '${json['name'] ?? ''}',
        status: '${json['status'] ?? 'NotStarted'}',
        ownerUserId: json['ownerUserId']?.toString(),
        nextReviewAt: json['nextReviewAt']?.toString(),
      );
}

class TdChangeRequest {
  final String id;
  final String title;
  final String status;
  final String severity;
  final String changeType;

  const TdChangeRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.severity,
    required this.changeType,
  });

  factory TdChangeRequest.fromJson(Map<String, dynamic> json) => TdChangeRequest(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        status: '${json['status'] ?? 'Draft'}',
        severity: '${json['severity'] ?? 'Low'}',
        changeType: '${json['changeType'] ?? 'Other'}',
      );
}
