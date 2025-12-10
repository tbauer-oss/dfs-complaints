import 'package:collection/collection.dart';

class CapaTeamMember {
  final String name;
  final String role;

  const CapaTeamMember({this.name = '', this.role = ''});

  factory CapaTeamMember.fromJson(Map<String, dynamic> json) => CapaTeamMember(
        name: (json['name'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role,
      };

  CapaTeamMember copyWith({String? name, String? role}) => CapaTeamMember(
        name: name ?? this.name,
        role: role ?? this.role,
      );
}

class CapaImmediateAction {
  final String action;
  final DateTime? doneAt;
  final String notes;
  final bool selected;

  const CapaImmediateAction({
    this.action = '',
    this.doneAt,
    this.notes = '',
    this.selected = false,
  });

  factory CapaImmediateAction.fromJson(Map<String, dynamic> json) => CapaImmediateAction(
        action: (json['action'] ?? '').toString(),
        doneAt: _parseDate(json['doneAt']),
        notes: (json['notes'] ?? '').toString(),
        selected: json['selected'] == true || json['selected'] == 'true' || json['selected'] == 1,
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        'doneAt': doneAt?.millisecondsSinceEpoch,
        'notes': notes,
        'selected': selected,
      };

  CapaImmediateAction copyWith({String? action, DateTime? doneAt, bool clearDoneAt = false, String? notes, bool? selected}) =>
      CapaImmediateAction(
        action: action ?? this.action,
        doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
        notes: notes ?? this.notes,
        selected: selected ?? this.selected,
      );
}

class CapaCauseEntry {
  final String why;
  final String root;

  const CapaCauseEntry({this.why = '', this.root = ''});

  factory CapaCauseEntry.fromJson(Map<String, dynamic> json) => CapaCauseEntry(
        why: (json['why'] ?? '').toString(),
        root: (json['root'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'why': why,
        'root': root,
      };

  CapaCauseEntry copyWith({String? why, String? root}) => CapaCauseEntry(
        why: why ?? this.why,
        root: root ?? this.root,
      );
}

class CapaCorrectiveAction {
  final String description;
  final String owner;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String status;
  final String changeType;
  final String notes;

  const CapaCorrectiveAction({
    this.description = '',
    this.owner = '',
    this.dueDate,
    this.completedAt,
    this.status = '',
    this.changeType = '',
    this.notes = '',
  });

  factory CapaCorrectiveAction.fromJson(Map<String, dynamic> json) => CapaCorrectiveAction(
        description: (json['description'] ?? '').toString(),
        owner: (json['owner'] ?? '').toString(),
        dueDate: _parseDate(json['dueDate']),
        completedAt: _parseDate(json['completedAt']),
        status: (json['status'] ?? '').toString(),
        changeType: (json['changeType'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'description': description,
        'owner': owner,
        'dueDate': dueDate?.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'status': status,
        'changeType': changeType,
        'notes': notes,
      };

  CapaCorrectiveAction copyWith({
    String? description,
    String? owner,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? status,
    String? changeType,
    String? notes,
  }) =>
      CapaCorrectiveAction(
        description: description ?? this.description,
        owner: owner ?? this.owner,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
        status: status ?? this.status,
        changeType: changeType ?? this.changeType,
        notes: notes ?? this.notes,
      );
}

class CapaApprovalEntry {
  final String name;
  final String role;
  final DateTime? date;
  final String signature;

  const CapaApprovalEntry({this.name = '', this.role = '', this.date, this.signature = ''});

  factory CapaApprovalEntry.fromJson(Map<String, dynamic> json) => CapaApprovalEntry(
        name: (json['name'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        date: _parseDate(json['date']),
        signature: (json['signature'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role,
        'date': date?.millisecondsSinceEpoch,
        'signature': signature,
      };

  CapaApprovalEntry copyWith({String? name, String? role, DateTime? date, bool clearDate = false, String? signature}) =>
      CapaApprovalEntry(
        name: name ?? this.name,
        role: role ?? this.role,
        date: clearDate ? null : (date ?? this.date),
        signature: signature ?? this.signature,
      );
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final num? parsed = (value is num) ? value : num.tryParse(value.toString());
  if (parsed == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(parsed.toInt());
}

class CapaSections {
  final String area;
  final DateTime? date;
  final String teamLead;
  final String product;
  final String batch;
  final String problem;
  final List<CapaTeamMember> teamMembers;

  final List<CapaImmediateAction> immediateActions;
  final String immediateDetails;

  final List<CapaCauseEntry> causes;
  final String causeSummary;

  final List<CapaCorrectiveAction> correctiveActions;

  final String d5Description;
  final DateTime? d5Date;
  final bool d5Effective;
  final String d5FollowUp;

  final List<String> preventiveActions;

  final List<String> lessons;
  final String transfer;

  final List<CapaApprovalEntry> approvals;
  final String closingNote;

  const CapaSections({
    this.area = '',
    this.date,
    this.teamLead = '',
    this.product = '',
    this.batch = '',
    this.problem = '',
    this.teamMembers = const [],
    this.immediateActions = const [],
    this.immediateDetails = '',
    this.causes = const [],
    this.causeSummary = '',
    this.correctiveActions = const [],
    this.d5Description = '',
    this.d5Date,
    this.d5Effective = false,
    this.d5FollowUp = '',
    this.preventiveActions = const [],
    this.lessons = const [],
    this.transfer = '',
    this.approvals = const [],
    this.closingNote = '',
  });

  factory CapaSections.fromJson(Map<String, dynamic> json) {
    final d1 = (json['d1'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d2 = (json['d2'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d3 = (json['d3'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d4 = (json['d4'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d5 = (json['d5'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d6 = (json['d6'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d7 = (json['d7'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d8 = (json['d8'] as Map?)?.cast<String, dynamic>() ?? const {};

    List<T> _parseList<T>(dynamic value, T Function(Map<String, dynamic>) builder) {
      if (value is List) {
        return value
            .whereType<Map>()
            .map((e) => builder(e.cast<String, dynamic>()))
            .toList(growable: false);
      }
      return const [];
    }

    List<String> _parseStrings(dynamic value) {
      if (value is List) {
        return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
      return const [];
    }

    return CapaSections(
      area: (d1['area'] ?? '').toString(),
      date: _parseDate(d1['date']),
      teamLead: (d1['teamLead'] ?? '').toString(),
      product: (d1['product'] ?? '').toString(),
      batch: (d1['batch'] ?? '').toString(),
      problem: (d1['problem'] ?? '').toString(),
      teamMembers: _parseList(d1['teamMembers'], (j) => CapaTeamMember.fromJson(j)),
      immediateActions: _parseList(d2['immediateActions'], (j) => CapaImmediateAction.fromJson(j)),
      immediateDetails: (d2['details'] ?? '').toString(),
      causes: _parseList(d3['causes'], (j) => CapaCauseEntry.fromJson(j)),
      causeSummary: (d3['summary'] ?? '').toString(),
      correctiveActions: _parseList(d4['correctiveActions'], (j) => CapaCorrectiveAction.fromJson(j)),
      d5Description: (d5['description'] ?? '').toString(),
      d5Date: _parseDate(d5['date']),
      d5Effective: d5['effective'] == true || d5['effective'] == 'true' || d5['effective'] == 1,
      d5FollowUp: (d5['followUp'] ?? '').toString(),
      preventiveActions: _parseStrings(d6['preventiveActions']),
      lessons: _parseStrings(d7['lessons']),
      transfer: (d7['transfer'] ?? '').toString(),
      approvals: _parseList(d8['approvals'], (j) => CapaApprovalEntry.fromJson(j)),
      closingNote: (d8['closingNote'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'd1': {
          'area': area,
          'date': date?.millisecondsSinceEpoch,
          'teamLead': teamLead,
          'product': product,
          'batch': batch,
          'problem': problem,
          'teamMembers': teamMembers.map((e) => e.toJson()).toList(),
        },
        'd2': {
          'immediateActions': immediateActions.map((e) => e.toJson()).toList(),
          'details': immediateDetails,
        },
        'd3': {
          'causes': causes.map((e) => e.toJson()).toList(),
          'summary': causeSummary,
        },
        'd4': {
          'correctiveActions': correctiveActions.map((e) => e.toJson()).toList(),
        },
        'd5': {
          'description': d5Description,
          'date': d5Date?.millisecondsSinceEpoch,
          'effective': d5Effective,
          'followUp': d5FollowUp,
        },
        'd6': {
          'preventiveActions': preventiveActions,
        },
        'd7': {
          'lessons': lessons,
          'transfer': transfer,
        },
        'd8': {
          'approvals': approvals.map((e) => e.toJson()).toList(),
          'closingNote': closingNote,
        },
      };

  CapaSections copyWith({
    String? area,
    DateTime? date,
    bool clearDate = false,
    String? teamLead,
    String? product,
    String? batch,
    String? problem,
    List<CapaTeamMember>? teamMembers,
    List<CapaImmediateAction>? immediateActions,
    String? immediateDetails,
    List<CapaCauseEntry>? causes,
    String? causeSummary,
    List<CapaCorrectiveAction>? correctiveActions,
    String? d5Description,
    DateTime? d5Date,
    bool clearD5Date = false,
    bool? d5Effective,
    String? d5FollowUp,
    List<String>? preventiveActions,
    List<String>? lessons,
    String? transfer,
    List<CapaApprovalEntry>? approvals,
    String? closingNote,
  }) =>
      CapaSections(
        area: area ?? this.area,
        date: clearDate ? null : (date ?? this.date),
        teamLead: teamLead ?? this.teamLead,
        product: product ?? this.product,
        batch: batch ?? this.batch,
        problem: problem ?? this.problem,
        teamMembers: teamMembers ?? this.teamMembers,
        immediateActions: immediateActions ?? this.immediateActions,
        immediateDetails: immediateDetails ?? this.immediateDetails,
        causes: causes ?? this.causes,
        causeSummary: causeSummary ?? this.causeSummary,
        correctiveActions: correctiveActions ?? this.correctiveActions,
        d5Description: d5Description ?? this.d5Description,
        d5Date: clearD5Date ? null : (d5Date ?? this.d5Date),
        d5Effective: d5Effective ?? this.d5Effective,
        d5FollowUp: d5FollowUp ?? this.d5FollowUp,
        preventiveActions: preventiveActions ?? this.preventiveActions,
        lessons: lessons ?? this.lessons,
        transfer: transfer ?? this.transfer,
        approvals: approvals ?? this.approvals,
        closingNote: closingNote ?? this.closingNote,
      );
}

class CapaReport {
  final String id;
  final String capaNumber;
  final String title;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String responsibleUserId;
  final String complaintId;
  final CapaSections sections;

  const CapaReport({
    this.id = '',
    this.capaNumber = '',
    this.title = '',
    this.status = 'open',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.responsibleUserId = '',
    this.complaintId = '',
    this.sections = const CapaSections(),
  })  : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory CapaReport.fromJson(Map<String, dynamic> json) => CapaReport(
        id: (json['id'] ?? '').toString(),
        capaNumber: (json['capaNumber'] ?? '').toString(),
        title: (json['title'] ?? json['problem'] ?? '').toString(),
        status: (json['status'] ?? 'open').toString(),
        createdAt: _parseDate(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: _parseDate(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        responsibleUserId: (json['responsibleUserId'] ?? '').toString(),
        complaintId: (json['complaintId'] ?? '').toString(),
        sections: CapaSections.fromJson((json['sections'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'id': id.isEmpty ? null : id,
        'capaNumber': capaNumber.isEmpty ? null : capaNumber,
        'title': title,
        'status': status,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'responsibleUserId': responsibleUserId,
        'complaintId': complaintId,
        'sections': sections.toJson(),
      }..removeWhere((key, value) => value == null);

  CapaReport copyWith({
    String? id,
    String? capaNumber,
    String? title,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? responsibleUserId,
    String? complaintId,
    CapaSections? sections,
  }) =>
      CapaReport(
        id: id ?? this.id,
        capaNumber: capaNumber ?? this.capaNumber,
        title: title ?? this.title,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        responsibleUserId: responsibleUserId ?? this.responsibleUserId,
        complaintId: complaintId ?? this.complaintId,
        sections: sections ?? this.sections,
      );

  String get effectiveNumber => capaNumber.isNotEmpty ? capaNumber : (id.isNotEmpty ? id : '');

  static List<CapaReport> listFromResponse(dynamic json) {
    if (json is List) {
      return json.whereType<Map>().map((e) => CapaReport.fromJson(e.cast<String, dynamic>())).toList();
    }
    if (json is Map && json['list'] is List) {
      return (json['list'] as List)
          .whereType<Map>()
          .map((e) => CapaReport.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }
}

List<T> updateList<T>(List<T> source, int index, T Function(T old) update) {
  if (index < 0 || index >= source.length) return source;
  return source.mapIndexed((i, e) => i == index ? update(e) : e).toList();
}
