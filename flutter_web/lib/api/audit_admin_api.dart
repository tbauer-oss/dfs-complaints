import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/audit.dart';
import '../models/portal_user.dart';
import 'client.dart';
import 'config.dart';

class AuditAdminApi {
  AuditAdminApi(this._client);

  final ApiClient _client;

  String get baseUrl => CFG.apiBase;

  Map<String, String> _headersJson({bool includeContentType = true}) => {
        if (includeContentType) 'Content-Type': 'application/json; charset=utf-8',
        if ((_client.portalToken ?? '').isNotEmpty) 'Authorization': 'Bearer ${_client.portalToken}',
      };

  Uri _u(String path, [Map<String, String>? q]) {
    final uri = Uri.parse('$baseUrl$path');
    return (q == null || q.isEmpty) ? uri : uri.replace(queryParameters: q);
  }

  Future<Map<String, dynamic>> _decode(http.Response r) async {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final parsed = _parseErrorBody(r.body);
      throw ApiError(r.statusCode, parsed['message'] as String, (parsed['details'] as List).cast<String>());
    }
    if (r.body.isEmpty) return {};
    return (jsonDecode(r.body) as Map).cast<String, dynamic>();
  }

  Map<String, dynamic> _parseErrorBody(String body) {
    List<String> _details(dynamic raw) {
      if (raw is List) {
        return raw
            .where((element) => element != null)
            .map((element) {
              if (element is String) return element;
              if (element is Map) {
                final field = element['field']?.toString() ?? '';
                final issue = element['issue']?.toString() ?? '';
                final msg = element['message']?.toString() ?? '';
                final combined = msg.isNotEmpty ? msg : (issue.isNotEmpty ? issue : element.toString());
                return field.isNotEmpty ? '$field: $combined' : combined;
              }
              return element.toString();
            })
            .toList();
      }
      return const <String>[];
    }

    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final msg = (j['error']?.toString() ?? j['message']?.toString() ?? '').trim();
        return {
          'message': msg.isNotEmpty ? msg : (body.isNotEmpty ? body : 'Unknown error'),
          'details': _details(j['details']),
        };
      }
    } catch (_) {}
    return {'message': body.isNotEmpty ? body : 'Unknown error', 'details': const <String>[]};
  }

  // Audits ------------------------------------------------------------
  Future<List<Audit>> listAudits({
    int? year,
    String? quarter,
    String? status,
    String? orgUnit,
    String? leadAuditorId,
    DateTime? from,
    DateTime? to,
  }) async {
    // Filters are intentionally ignored in V2; the endpoint returns the canonical list.
    final r = await http.get(_u('/api/internal-audits'), headers: _headersJson(includeContentType: false));
    final decoded = await _decode(r);
    final list = decoded['audits'] ?? decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Audit.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Future<Audit> getAudit(String id) async {
    final r = await http.get(_u('/api/internal-audits/$id'), headers: _headersJson(includeContentType: false));
    final decoded = await _decode(r);
    final data = decoded['audit'] as Map?;
    return Audit.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  Future<Audit> createAudit(Audit audit) async {
    final r = await http.post(
      _u('/api/internal-audits'),
      headers: _headersJson(),
      body: jsonEncode(_auditPayload(audit)),
    );
    final decoded = await _decode(r);
    final data = decoded['audit'] as Map?;
    return Audit.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  Future<Audit> updateAudit(Audit audit) async {
    final uri = audit.id.isEmpty ? _u('/api/internal-audits') : _u('/api/internal-audits/${audit.id}');
    final r = await http.patch(
      uri,
      headers: _headersJson(),
      body: jsonEncode(_auditPayload(audit)),
    );
    final decoded = await _decode(r);
    final data = decoded['audit'] as Map?;
    return Audit.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  Future<List<AuditPlanEntry>> loadAuditPlan(String auditId) async {
    final r = await http.get(
      _u('/api/internal-audits/$auditId/plan'),
      headers: _headersJson(includeContentType: false),
    );
    final decoded = await _decode(r);
    final planObj = decoded['plan'];
    final list = decoded['planEntries'] ?? (planObj is Map ? planObj['planEntries'] : null) ?? planObj;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => AuditPlanEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Future<List<AuditPlanEntry>> saveAuditPlan(String auditId, List<AuditPlanEntry> plan) async {
    final r = await http.put(
      _u('/api/internal-audits/$auditId/plan'),
      headers: _headersJson(),
      body: jsonEncode({
        'planEntries': plan.map((p) => p.toJson()).toList(),
      }),
    );
    final decoded = await _decode(r);
    final planObj = decoded['plan'];
    final list = decoded['planEntries'] ?? (planObj is Map ? planObj['planEntries'] : null) ?? planObj;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => AuditPlanEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Future<void> deleteAudit(String id) async {
    final uri = id.isEmpty ? _u('/api/internal-audits') : _u('/api/internal-audits/$id');
    await _decode(await http.delete(uri, headers: _headersJson()));
  }

  // Auditoren ---------------------------------------------------------
  Future<List<Auditor>> listAuditors() async {
    final r = await http.get(_u('/api/internal-auditors'), headers: _headersJson());
    final decoded = await _decode(r);
    final list = decoded['auditors'] ?? decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Auditor.fromJson({
                ...e.cast<String, dynamic>(),
                if (e['status'] == null && e['active'] != null) 'status': e['active'] == true ? 'active' : 'inactive',
              }))
          .toList();
    }
    return const [];
  }

  Future<Auditor> saveAuditor(Auditor auditor) async {
    final r = await http.post(
      _u('/api/internal-auditors'),
      headers: _headersJson(),
      body: jsonEncode({
        'id': auditor.id.isEmpty ? null : auditor.id,
        'userId': auditor.userId,
        'name': auditor.name,
        'email': auditor.email,
        'orgUnit': auditor.orgUnit,
        'role': auditor.role,
        'status': auditor.status,
        'active': auditor.status != 'inactive',
        'trainingType': auditor.trainingType,
        'restrictedProcessOwners': auditor.restrictedProcessOwners,
        'restrictedOrgUnits': auditor.restrictedOrgUnits,
        'internalAuditorTrainingDate': auditor.internalAuditorTrainingDate?.toIso8601String(),
        'trainingDate': auditor.trainingDate?.toIso8601String(),
        'experienceYears': auditor.experienceYears,
        'standardsKnowledge': auditor.standardsKnowledge,
        'requalificationDueDate': auditor.requalificationDueDate?.toIso8601String(),
        'qualificationOverride': auditor.qualificationOverride,
        'evidenceAttachments': auditor.evidenceAttachments.map((e) => e.toJson()).toList(),
        'coAuditCount': auditor.coAuditCount,
        'leadAuditCount': auditor.leadAuditCount,
      }),
    );
    final decoded = await _decode(r);
    final data = decoded['auditor'] as Map?;
    return Auditor.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  Future<void> deleteAuditor(String id) async {
    await _decode(await http.delete(_u('/api/internal-auditors/$id'), headers: _headersJson()));
  }

  Future<List<PortalUserSummary>> listDfsEmployees() async {
    final users = await _client.fetchPortalUsers();
    return users
        .where((u) {
          final status = u.portalStatus.toLowerCase();
          if (status != 'active') return false;
          final role = u.role.toLowerCase();
          if (role.contains('customer')) return false;
          return true;
        })
        .toList(growable: false);
  }

  // Findings ----------------------------------------------------------
  Future<List<AuditFinding>> listFindings(String auditId) async {
    final r = await http.get(_u('/api/admin/audit-findings', {'auditId': auditId}), headers: _headersJson());
    final decoded = await _decode(r);
    final list = decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => AuditFinding.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Future<AuditFinding> saveFinding(AuditFinding finding) async {
    final r = await http.post(
      _u('/api/admin/audit-findings'),
      headers: _headersJson(),
      body: jsonEncode({
        'id': finding.id.isEmpty ? null : finding.id,
        'auditId': finding.auditId,
        'type': finding.type,
        'description': finding.description,
        'requirementRef': finding.requirementRef,
        'evidenceText': finding.evidenceText,
        'linkedComplaintIds': finding.linkedComplaintIds,
        'linkedCapaIds': finding.linkedCapaIds,
        'ownerOrgUnit': finding.ownerOrgUnit,
        'processOwner': finding.processOwner,
        'createdInMeeting': finding.createdInMeeting,
        'status': finding.status,
      }),
    );
    final decoded = await _decode(r);
    final data = decoded['finding'] as Map?;
    return AuditFinding.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  // Actions -----------------------------------------------------------
  Future<List<AuditAction>> listActions(String auditId) async {
    final r = await http.get(_u('/api/admin/audit-actions', {'auditId': auditId}), headers: _headersJson());
    final decoded = await _decode(r);
    final list = decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => AuditAction.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Future<AuditAction> saveAction(AuditAction action) async {
    final r = await http.post(
      _u('/api/admin/audit-actions'),
      headers: _headersJson(),
      body: jsonEncode({
        'id': action.id.isEmpty ? null : action.id,
        'auditId': action.auditId,
        'findingId': action.findingId,
        'actionType': action.actionType,
        'description': action.description,
        'responsibleUserId': action.responsibleUserId,
        'responsibleOrgUnit': action.responsibleOrgUnit,
        'dueDate': action.dueDate?.toIso8601String(),
        'completedAt': action.completedAt?.toIso8601String(),
        'effectivenessCheckRequired': action.effectivenessCheckRequired,
        'effectivenessCheckMethod': action.effectivenessCheckMethod,
        'effectivenessCheckedAt': action.effectivenessCheckedAt?.toIso8601String(),
        'effectivenessResult': action.effectivenessResult,
        'escalationLevel': action.escalationLevel,
        'escalationReason': action.escalationReason,
        'status': action.status,
      }),
    );
    final decoded = await _decode(r);
    final data = decoded['action'] as Map?;
    return AuditAction.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  // Programme ---------------------------------------------------------
  Future<List<AuditProgram>> listPrograms({int? year}) async {
    final r = await http.get(
      _u('/api/admin/audit-programs', {
        if (year != null) 'year': year.toString(),
      }),
      headers: _headersJson(),
    );
    final decoded = await _decode(r);
    final list = decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => AuditProgram.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  // Annual Reports ----------------------------------------------------
  Future<AuditAnnualReport> generateAnnualReport(int year) async {
    final r = await http.post(
      _u('/api/admin/audit-annual-reports'),
      headers: _headersJson(),
      body: jsonEncode({'year': year}),
    );
    final decoded = await _decode(r);
    final data = decoded['report'] as Map?;
    return AuditAnnualReport.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  Future<List<AuditAnnualReport>> listAnnualReports(int year) async {
    final r = await http.get(_u('/api/admin/audit-annual-reports', {'year': '$year'}), headers: _headersJson());
    final decoded = await _decode(r);
    final list = decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => AuditAnnualReport.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  // Audit Log ---------------------------------------------------------
  Future<List<AuditHistoryEntry>> listHistory({String? auditId, String? entityType}) async {
    final r = await http.get(
      _u('/api/admin/audit-log', {
        if (auditId != null) 'auditId': auditId,
        if (entityType != null) 'entityType': entityType,
      }),
      headers: _headersJson(),
    );
    final decoded = await _decode(r);
    final list = decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => AuditHistoryEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> _auditPayload(Audit audit) {
    final plannedDate = audit.plannedStart ?? audit.plannedEnd ?? audit.actualStart ?? audit.actualEnd;
    return {
      if (audit.id.isNotEmpty) 'id': audit.id,
      'auditNumber': audit.auditNumber,
      'title': audit.title,
      'status': audit.status,
      if (plannedDate != null) 'date': plannedDate.toIso8601String(),
      if (audit.leadAuditorId != null) 'leadAuditorId': audit.leadAuditorId,
      if (audit.coAuditorId != null) 'coAuditorId': audit.coAuditorId,
    };
  }
}
