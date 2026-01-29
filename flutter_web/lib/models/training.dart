class TrainingNeedItem {
  TrainingNeedItem({
    required this.id,
    required this.topic,
    required this.timeframe,
    required this.format,
    required this.participants,
    required this.budget,
    required this.requirements,
  });

  final String id;
  final String topic;
  final String timeframe;
  final String format;
  final int participants;
  final double budget;
  final String requirements;

  factory TrainingNeedItem.fromJson(Map<String, dynamic> json) {
    return TrainingNeedItem(
      id: (json['id'] ?? '').toString(),
      topic: (json['topic'] ?? '').toString(),
      timeframe: (json['timeframe'] ?? '').toString(),
      format: (json['format'] ?? '').toString(),
      participants: (json['participants'] ?? 0) is num ? (json['participants'] as num).toInt() : 0,
      budget: (json['budget'] ?? 0) is num ? (json['budget'] as num).toDouble() : 0,
      requirements: (json['requirements'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'timeframe': timeframe,
        'format': format,
        'participants': participants,
        'budget': budget,
        'requirements': requirements,
      };
}

class TrainingNeed {
  TrainingNeed({
    required this.id,
    required this.year,
    required this.contactName,
    required this.position,
    required this.department,
    required this.team,
    required this.items,
    required this.comments,
    required this.departmentTeamSelected,
    required this.departmentTeamFreeText,
    required this.plannedPeriodType,
    required this.plannedPeriodValue,
    required this.trainingFormat,
    required this.intervalType,
    required this.intervalValue,
    required this.intervalValueFreeText,
    required this.plannedBudget,
    required this.additionalNotes,
    required this.topicPriorities,
    required this.preferredTrainers,
    required this.specialRequirements,
    required this.status,
    required this.noNeed,
  });

  final String id;
  final int year;
  final String contactName;
  final String position;
  final String department;
  final String team;
  final List<TrainingNeedItem> items;
  final String comments;
  final String departmentTeamSelected;
  final String? departmentTeamFreeText;
  final String plannedPeriodType;
  final String plannedPeriodValue;
  final String trainingFormat;
  final String intervalType;
  final String? intervalValue;
  final String? intervalValueFreeText;
  final double? plannedBudget;
  final String? additionalNotes;
  final String? topicPriorities;
  final String? preferredTrainers;
  final String? specialRequirements;
  final String status;
  final bool noNeed;

  factory TrainingNeed.fromJson(Map<String, dynamic> json) {
    return TrainingNeed(
      id: (json['id'] ?? '').toString(),
      year: (json['year'] ?? 0) is num ? (json['year'] as num).toInt() : 0,
      contactName: (json['contactName'] ?? '').toString(),
      position: (json['position'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      team: (json['team'] ?? '').toString(),
      items: (json['items'] as List? ?? [])
          .whereType<Map>()
          .map((item) => TrainingNeedItem.fromJson(item.cast<String, dynamic>()))
          .toList(),
      comments: (json['comments'] ?? '').toString(),
      departmentTeamSelected: (json['departmentTeamSelected'] ?? json['departmentTeam'] ?? '').toString(),
      departmentTeamFreeText: (json['departmentTeamFreeText'] ?? json['departmentTeamOther'])?.toString(),
      plannedPeriodType: (json['plannedPeriodType'] ?? '').toString(),
      plannedPeriodValue: (json['plannedPeriodValue'] ?? '').toString(),
      trainingFormat: (() {
        final raw = json['trainingFormat'];
        if (raw != null) return raw.toString();
        final items = json['items'];
        if (items is List && items.isNotEmpty) {
          final first = items.first;
          if (first is Map && first['format'] != null) return first['format'].toString();
        }
        return '';
      })(),
      intervalType: (json['intervalType'] ?? '').toString(),
      intervalValue: (json['intervalValue'] ?? '').toString().isEmpty ? null : (json['intervalValue'] ?? '').toString(),
      intervalValueFreeText:
          (json['intervalValueFreeText'] ?? '').toString().isEmpty ? null : (json['intervalValueFreeText'] ?? '').toString(),
      plannedBudget: (() {
        final raw = json['plannedBudget'] ?? json['budget'];
        if (raw is num) return raw.toDouble();
        if (raw == null) return null;
        return double.tryParse(raw.toString());
      })(),
      additionalNotes: (json['additionalNotes'] ?? json['comments'])?.toString(),
      topicPriorities: (json['topicPriorities'] ?? '').toString().isEmpty ? null : (json['topicPriorities'] ?? '').toString(),
      preferredTrainers:
          (json['preferredTrainers'] ?? '').toString().isEmpty ? null : (json['preferredTrainers'] ?? '').toString(),
      specialRequirements:
          (json['specialRequirements'] ?? '').toString().isEmpty ? null : (json['specialRequirements'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      noNeed: json['noNeed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'year': year,
        'contactName': contactName,
        'position': position,
        'department': department,
        'team': team,
        'items': items.map((item) => item.toJson()).toList(),
        'comments': comments,
        'departmentTeamSelected': departmentTeamSelected,
        'departmentTeamFreeText': departmentTeamFreeText,
        'plannedPeriodType': plannedPeriodType,
        'plannedPeriodValue': plannedPeriodValue,
        'trainingFormat': trainingFormat,
        'intervalType': intervalType,
        'intervalValue': intervalValue,
        'intervalValueFreeText': intervalValueFreeText,
        'plannedBudget': plannedBudget,
        'additionalNotes': additionalNotes,
        'topicPriorities': topicPriorities,
        'preferredTrainers': preferredTrainers,
        'specialRequirements': specialRequirements,
        'status': status,
        'noNeed': noNeed,
      };
}

class TrainingNeedSubmitResult {
  TrainingNeedSubmitResult({required this.need, this.warning});

  final TrainingNeed need;
  final String? warning;
}

class TrainingProgram {
  TrainingProgram({
    required this.id,
    required this.year,
    required this.title,
    required this.status,
    required this.owner,
    required this.department,
    required this.needIds,
    required this.trainingIds,
    required this.budgetTotal,
  });

  final String id;
  final int year;
  final String title;
  final String status;
  final String owner;
  final String department;
  final List<String> needIds;
  final List<String> trainingIds;
  final double budgetTotal;

  factory TrainingProgram.fromJson(Map<String, dynamic> json) {
    return TrainingProgram(
      id: (json['id'] ?? '').toString(),
      year: (json['year'] ?? 0) is num ? (json['year'] as num).toInt() : 0,
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      owner: (json['owner'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      needIds: (json['needIds'] as List? ?? []).map((e) => e.toString()).toList(),
      trainingIds: (json['trainingIds'] as List? ?? []).map((e) => e.toString()).toList(),
      budgetTotal: (json['budgetTotal'] ?? 0) is num ? (json['budgetTotal'] as num).toDouble() : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'year': year,
        'title': title,
        'status': status,
        'owner': owner,
        'department': department,
        'needIds': needIds,
        'trainingIds': trainingIds,
        'budgetTotal': budgetTotal,
      };
}

class TrainingParticipant {
  TrainingParticipant({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.external,
  });

  final String id;
  final String name;
  final String email;
  final String status;
  final bool external;

  factory TrainingParticipant.fromJson(Map<String, dynamic> json) {
    return TrainingParticipant(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      external: json['external'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'status': status,
        'external': external,
      };
}

class TrainingRecord {
  TrainingRecord({
    required this.id,
    required this.trainingNumber,
    required this.year,
    required this.title,
    required this.category,
    required this.type,
    required this.format,
    required this.startDate,
    required this.endDate,
    required this.trainer,
    required this.location,
    required this.status,
    required this.owner,
    required this.targetGroup,
    required this.reason,
    required this.departments,
    required this.isMandatory,
    required this.isExternal,
    required this.participants,
    required this.defaultQuestionnaireTemplateId,
  });

  final String id;
  final String trainingNumber;
  final int year;
  final String title;
  final String category;
  final String type;
  final String format;
  final String startDate;
  final String endDate;
  final String trainer;
  final String location;
  final String status;
  final String owner;
  final String targetGroup;
  final String reason;
  final List<String> departments;
  final bool isMandatory;
  final bool isExternal;
  final List<TrainingParticipant> participants;
  final String defaultQuestionnaireTemplateId;

  factory TrainingRecord.fromJson(Map<String, dynamic> json) {
    return TrainingRecord(
      id: (json['id'] ?? '').toString(),
      trainingNumber: (json['trainingNumber'] ?? '').toString(),
      year: (json['year'] ?? 0) is num ? (json['year'] as num).toInt() : 0,
      title: (json['title'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      format: (json['format'] ?? '').toString(),
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? '').toString(),
      trainer: (json['trainer'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      owner: (json['owner'] ?? '').toString(),
      targetGroup: (json['targetGroup'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      departments: (json['departments'] as List? ?? []).map((e) => e.toString()).toList(),
      isMandatory: json['isMandatory'] == true,
      isExternal: json['isExternal'] == true,
      participants: (json['participants'] as List? ?? [])
          .whereType<Map>()
          .map((item) => TrainingParticipant.fromJson(item.cast<String, dynamic>()))
          .toList(),
      defaultQuestionnaireTemplateId: (json['defaultQuestionnaireTemplateId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trainingNumber': trainingNumber,
        'year': year,
        'title': title,
        'category': category,
        'type': type,
        'format': format,
        'startDate': startDate,
        'endDate': endDate,
        'trainer': trainer,
        'location': location,
        'status': status,
        'owner': owner,
        'targetGroup': targetGroup,
        'reason': reason,
        'departments': departments,
        'isMandatory': isMandatory,
        'isExternal': isExternal,
        'participants': participants.map((p) => p.toJson()).toList(),
        'defaultQuestionnaireTemplateId': defaultQuestionnaireTemplateId,
      };
}

class TrainingQuestionnaireTemplate {
  TrainingQuestionnaireTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.questions,
  });

  final String id;
  final String title;
  final String description;
  final List<Map<String, dynamic>> questions;

  factory TrainingQuestionnaireTemplate.fromJson(Map<String, dynamic> json) {
    return TrainingQuestionnaireTemplate(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      questions: (json['questions'] as List? ?? [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'questions': questions,
      };
}
