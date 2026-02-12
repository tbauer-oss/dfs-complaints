class TdApplicabilityResult {
  final String? sectionId;
  final String? queryKey;
  final String state;
  final bool? isConditionMet;
  final String? conditionSummary;

  const TdApplicabilityResult({required this.sectionId, required this.queryKey, required this.state, required this.isConditionMet, required this.conditionSummary});

  factory TdApplicabilityResult.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TdApplicabilityResult(
      sectionId: map['sectionId']?.toString(),
      queryKey: map['queryKey']?.toString(),
      state: (map['state'] ?? 'MANDATORY').toString(),
      isConditionMet: map['isConditionMet'] is bool ? map['isConditionMet'] as bool : null,
      conditionSummary: map['conditionSummary']?.toString(),
    );
  }
}

class TdApplicabilityProfile {
  final String profileType;
  final bool isReusable;
  final bool isSterile;
  final String packagingType;
  final String? classificationRule;
  final bool hasSoftware;
  final String? notes;

  const TdApplicabilityProfile({
    required this.profileType,
    required this.isReusable,
    required this.isSterile,
    required this.packagingType,
    required this.classificationRule,
    required this.hasSoftware,
    required this.notes,
  });

  factory TdApplicabilityProfile.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TdApplicabilityProfile(
      profileType: (map['profileType'] ?? 'ROTARY_REUSABLE_NONSTERILE').toString(),
      isReusable: map['isReusable'] == true,
      isSterile: map['isSterile'] == true,
      packagingType: (map['packagingType'] ?? 'BULK_NONSTERILE').toString(),
      classificationRule: map['classificationRule']?.toString(),
      hasSoftware: map['hasSoftware'] == true,
      notes: map['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'profileType': profileType,
        'isReusable': isReusable,
        'isSterile': isSterile,
        'packagingType': packagingType,
        'classificationRule': classificationRule,
        'hasSoftware': hasSoftware,
        'notes': notes,
      };
}

class TdApplicabilityBundle {
  final TdApplicabilityProfile profile;
  final List<TdApplicabilityResult> results;
  final List<Map<String, dynamic>> overrides;

  const TdApplicabilityBundle({required this.profile, required this.results, required this.overrides});

  factory TdApplicabilityBundle.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TdApplicabilityBundle(
      profile: TdApplicabilityProfile.fromJson((map['profile'] as Map?)?.cast<String, dynamic>()),
      results: (map['results'] as List?)?.whereType<Map>().map((e) => TdApplicabilityResult.fromJson(e.cast<String, dynamic>())).toList(growable: false) ?? const [],
      overrides: (map['overrides'] as List?)?.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(growable: false) ?? const [],
    );
  }
}

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
  final int? completion;
  final int? queryTotal;
  final TdApplicabilityResult? applicability;

  const TdSection({
    required this.id,
    required this.templateKey,
    required this.name,
    required this.status,
    required this.ownerUserId,
    required this.nextReviewAt,
    this.content,
    this.linkCount,
    this.completion,
    this.queryTotal,
    this.applicability,
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
        completion: ((json['queryStats'] as Map?)?['completion'] as num?)?.toInt(),
        queryTotal: ((json['queryStats'] as Map?)?['total'] as num?)?.toInt(),
        applicability: json['applicability'] is Map ? TdApplicabilityResult.fromJson((json['applicability'] as Map).cast<String, dynamic>()) : null,
      );
}



class TdQueryLink {
  final String id;
  final String type;
  final String label;
  final String? refId;
  final String? url;

  const TdQueryLink({required this.id, required this.type, required this.label, this.refId, this.url});

  factory TdQueryLink.fromJson(Map<String, dynamic> json) => TdQueryLink(
        id: '${json['id'] ?? ''}',
        type: '${json['type'] ?? 'Document'}',
        label: '${json['label'] ?? ''}',
        refId: json['refId']?.toString(),
        url: json['url']?.toString(),
      );
}

class TdQueryTemplate {
  final String templateKey;
  final String title;
  final String description;
  final bool mandatory;
  final List<String> suggestedLinkTypes;
  final List<String> tags;

  const TdQueryTemplate({required this.templateKey, required this.title, required this.description, required this.mandatory, required this.suggestedLinkTypes, required this.tags});

  factory TdQueryTemplate.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return TdQueryTemplate(
      templateKey: (map['templateKey'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      mandatory: map['mandatory'] != false,
      suggestedLinkTypes: (map['suggestedLinkTypes'] as List?)?.map((e) => '$e').toList(growable: false) ?? const [],
      tags: (map['tags'] as List?)?.map((e) => '$e').toList(growable: false) ?? const [],
    );
  }
}

class TdQueryAnswer {
  final String id;
  final String sectionId;
  final String status;
  final String answerMarkdown;
  final String rationaleMarkdown;
  final String? ownerUserId;
  final String? dueAt;
  final TdQueryTemplate template;
  final List<TdQueryLink> links;
  final TdApplicabilityResult? applicability;

  const TdQueryAnswer({required this.id, required this.sectionId, required this.status, required this.answerMarkdown, required this.rationaleMarkdown, required this.ownerUserId, required this.dueAt, required this.template, required this.links, required this.applicability});

  factory TdQueryAnswer.fromJson(Map<String, dynamic> json) => TdQueryAnswer(
        id: (json['id'] ?? '').toString(),
        sectionId: (json['sectionId'] ?? '').toString(),
        status: (json['status'] ?? 'NotStarted').toString(),
        answerMarkdown: (json['answerMarkdown'] ?? '').toString(),
        rationaleMarkdown: (json['rationaleMarkdown'] ?? '').toString(),
        ownerUserId: json['ownerUserId']?.toString(),
        dueAt: json['dueAt']?.toString(),
        template: TdQueryTemplate.fromJson((json['template'] as Map?)?.cast<String, dynamic>()),
        links: (json['links'] as List?)?.whereType<Map>().map((e) => TdQueryLink.fromJson(e.cast<String, dynamic>())).toList(growable: false) ?? const [],
        applicability: json['applicability'] is Map ? TdApplicabilityResult.fromJson((json['applicability'] as Map).cast<String, dynamic>()) : null,
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
