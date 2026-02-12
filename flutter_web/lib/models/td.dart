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

class TdSectionContent {
  final String summaryMarkdown;
  final Map<String, dynamic>? contentJson;
  final String? updatedByUserId;
  final String? updatedAt;

  const TdSectionContent({
    required this.summaryMarkdown,
    required this.contentJson,
    required this.updatedByUserId,
    required this.updatedAt,
  });

  factory TdSectionContent.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TdSectionContent(
      summaryMarkdown: (map['summaryMarkdown'] ?? '').toString(),
      contentJson: (map['contentJson'] as Map?)?.cast<String, dynamic>(),
      updatedByUserId: map['updatedByUserId']?.toString(),
      updatedAt: map['updatedAt']?.toString(),
    );
  }
}

class TdArtifactLink {
  final String id;
  final String type;
  final String label;
  final String? refId;
  final String? url;
  final String? sectionId;

  const TdArtifactLink({required this.id, required this.type, required this.label, this.refId, this.url, this.sectionId});

  factory TdArtifactLink.fromJson(Map<String, dynamic> json) => TdArtifactLink(
        id: '${json['id'] ?? ''}',
        type: '${json['type'] ?? 'Document'}',
        label: '${json['label'] ?? ''}',
        refId: json['refId']?.toString(),
        url: json['url']?.toString(),
        sectionId: json['sectionId']?.toString(),
      );
}

class TdSection {
  final String id;
  final String templateKey;
  final String name;
  final String status;
  final String? ownerUserId;
  final String? nextReviewAt;
  final TdSectionContent? content;
  final int? linkCount;

  const TdSection({
    required this.id,
    required this.templateKey,
    required this.name,
    required this.status,
    required this.ownerUserId,
    required this.nextReviewAt,
    this.content,
    this.linkCount,
  });

  factory TdSection.fromJson(Map<String, dynamic> json) => TdSection(
        id: '${json['id'] ?? ''}',
        templateKey: '${json['templateKey'] ?? ''}',
        name: '${json['name'] ?? ''}',
        status: '${json['status'] ?? 'NotStarted'}',
        ownerUserId: json['ownerUserId']?.toString(),
        nextReviewAt: json['nextReviewAt']?.toString(),
        content: json['content'] is Map ? TdSectionContent.fromJson((json['content'] as Map).cast<String, dynamic>()) : null,
        linkCount: (json['linkCount'] as num?)?.toInt(),
      );
}

class TdImpactItem {
  final String id;
  final String impactType;
  final String requiredAction;
  final String status;

  const TdImpactItem({required this.id, required this.impactType, required this.requiredAction, required this.status});

  factory TdImpactItem.fromJson(Map<String, dynamic> json) => TdImpactItem(
        id: '${json['id'] ?? ''}',
        impactType: '${json['impactType'] ?? 'Other'}',
        requiredAction: '${json['requiredAction'] ?? ''}',
        status: '${json['status'] ?? 'Open'}',
      );
}

class TdChangeRequest {
  final String id;
  final String title;
  final String status;
  final String severity;
  final String changeType;
  final String description;
  final List<TdImpactItem> impactItems;

  const TdChangeRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.severity,
    required this.changeType,
    required this.description,
    this.impactItems = const [],
  });

  factory TdChangeRequest.fromJson(Map<String, dynamic> json) => TdChangeRequest(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        status: '${json['status'] ?? 'Draft'}',
        severity: '${json['severity'] ?? 'Low'}',
        changeType: '${json['changeType'] ?? 'Other'}',
        description: '${json['description'] ?? ''}',
        impactItems: (json['impactItems'] as List?)?.whereType<Map>().map((e) => TdImpactItem.fromJson(e.cast<String, dynamic>())).toList(growable: false) ?? const [],
      );
}
