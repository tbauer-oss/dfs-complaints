import 'dart:convert';

/// Represents a structured help center with sections and topics.
class HelpCenterContent {
  final List<HelpSection> sections;

  const HelpCenterContent({required this.sections});

  factory HelpCenterContent.fromJson(Map<String, dynamic> json) {
    final List sectionsRaw = json['sections'] as List? ?? const [];
    return HelpCenterContent(
      sections: sectionsRaw
          .map((e) => HelpSection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static HelpCenterContent fromJsonString(String jsonString) {
    final decoded = json.decode(jsonString) as Map<String, dynamic>;
    return HelpCenterContent.fromJson(decoded);
  }

  HelpSection? sectionById(String? id) {
    if (id == null) return null;
    return sections.where((s) => s.id == id).firstOrNull;
  }
}

class HelpSection {
  final String id;
  final String title;
  final String audience;
  final String? description;
  final List<HelpTopic> topics;

  const HelpSection({
    required this.id,
    required this.title,
    required this.audience,
    this.description,
    this.topics = const [],
  });

  factory HelpSection.fromJson(Map<String, dynamic> json) {
    final List topicsRaw = json['topics'] as List? ?? const [];
    return HelpSection(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      audience: json['audience'] as String? ?? '',
      description: json['description'] as String?,
      topics: topicsRaw
          .map((e) => HelpTopic.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  HelpTopic? topicById(String? id) {
    if (id == null) return null;
    return topics.where((t) => t.id == id).firstOrNull;
  }
}

class HelpTopic {
  final String id;
  final String title;
  final String? summary;
  final List<String> tags;
  final List<HelpStep> steps;
  final List<String> tips;
  final List<String> screenshots;
  final List<String> deepLinks;

  const HelpTopic({
    required this.id,
    required this.title,
    this.summary,
    this.tags = const [],
    this.steps = const [],
    this.tips = const [],
    this.screenshots = const [],
    this.deepLinks = const [],
  });

  factory HelpTopic.fromJson(Map<String, dynamic> json) {
    final List stepsRaw = json['steps'] as List? ?? const [];
    final List tipsRaw = json['tips'] as List? ?? const [];
    final List shotsRaw = json['screenshots'] as List? ?? const [];
    final List tagsRaw = json['tags'] as List? ?? const [];
    final List linksRaw = json['links'] as List? ?? const [];
    return HelpTopic(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String?,
      tags: tagsRaw.cast<String>().toList(),
      steps: stepsRaw
          .map((e) => HelpStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      tips: tipsRaw.cast<String>().toList(),
      screenshots: shotsRaw.cast<String>().toList(),
      deepLinks: linksRaw.cast<String>().toList(),
    );
  }
}

class HelpStep {
  final String title;
  final String description;
  final String anchor;

  const HelpStep({
    required this.title,
    required this.description,
    required this.anchor,
  });

  factory HelpStep.fromJson(Map<String, dynamic> json) {
    return HelpStep(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      anchor: json['anchor'] as String? ?? '',
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
