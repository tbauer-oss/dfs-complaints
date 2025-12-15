import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/audit.dart';
import 'client.dart';

class AuditAdminApi {
  AuditAdminApi(this._client);

  final ApiClient _client;

  String get _secret => _client.adminSecret ?? '';

  String get baseUrl {
    const b = String.fromEnvironment('API_BASE', defaultValue: '');
    if (b.isNotEmpty) return b;
    if (kIsWeb) {
      try {
        return Uri.base.origin;
      } catch (_) {}
    }
    return 'https://dfs-complaints-backend.vercel.app';
  }

  Map<String, String> _headersJson() => {
        'Content-Type': 'application/json; charset=utf-8',
        if (_secret.isNotEmpty) 'X-Admin-Secret': _secret,
        if ((_client.portalToken ?? '').isNotEmpty) 'Authorization': 'Bearer ${_client.portalToken}',
      };

  Uri _u(String path, [Map<String, String>? q]) {
    final uri = Uri.parse('$baseUrl$path');
    return (q == null || q.isEmpty) ? uri : uri.replace(queryParameters: q);
  }

  Future<Map<String, dynamic>> _decode(http.Response r) async {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiError(r.statusCode, _extractErrorMessage(r.body));
    }
    if (r.body.isEmpty) return {};
    return (jsonDecode(r.body) as Map).cast<String, dynamic>();
  }

  String _formatDateOnly(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final y = normalized.year.toString().padLeft(4, '0');
    final m = normalized.month.toString().padLeft(2, '0');
    final d = normalized.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _extractErrorMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
      if (j is Map && j['message'] is String) return j['message'] as String;
      return body.isNotEmpty ? body : 'Unknown error';
    } catch (_) {
      return body.isNotEmpty ? body : 'Unknown error';
    }
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
    String? fmt(DateTime? d) => d == null ? null : _formatDateOnly(d);
    final q = {
      if (year != null) 'year': year.toString(),
      if (quarter != null && quarter.isNotEmpty) 'quarter': quarter,
      if (status != null && status.isNotEmpty) 'status': status,
      if (orgUnit != null && orgUnit.isNotEmpty) 'orgUnit': orgUnit,
      if (leadAuditorId != null && leadAuditorId.isNotEmpty) 'leadAuditorId': leadAuditorId,
      if (from != null) 'from': fmt(from)!,
      if (to != null) 'to': fmt(to)!,
    };
    final r = await http.get(_u('/api/admin/audits', q), headers: _headersJson());
    final decoded = await _decode(r);
    final list = decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Audit.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Future<Audit> createAudit(Audit audit) async {
    final r = await http.post(
      _u('/api/admin/audits'),
      headers: _headersJson(),
      body: jsonEncode(audit.toJson()),
    );
    final decoded = await _decode(r);
    final data = decoded['audit'] as Map?;
    return Audit.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  Future<Audit> updateAudit(Audit audit) async {
    final r = await http.patch(
      _u('/api/admin/audits'),
      headers: _headersJson(),
      body: jsonEncode(audit.toJson()),
    );
    final decoded = await _decode(r);
    final data = decoded['audit'] as Map?;
    return Audit.fromJson((data ?? decoded).cast<String, dynamic>());
  }

  Future<void> deleteAudit(String id) async {
    await http.delete(_u('/api/admin/audits', {'id': id}), headers: _headersJson());
  }

  // Auditoren ---------------------------------------------------------
  Future<List<Auditor>> listAuditors() async {
    final r = await http.get(_u('/api/admin/auditors'), headers: _headersJson());
    final decoded = await _decode(r);
    final list = decoded['list'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Auditor.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Future<Auditor> saveAuditor(Auditor auditor) async {
    final r = await http.post(
      _u('/api/admin/auditors'),
      headers: _headersJson(),
      body: jsonEncode({
        'id': auditor.id.isEmpty ? null : auditor.id,
        'name': auditor.name,
        'email': auditor.email,
        'orgUnit': auditor.orgUnit,
        'role': auditor.role,
        'status': auditor.status,
        'restrictedProcessOwners': auditor.restrictedProcessOwners,
        'restrictedOrgUnits': auditor.restrictedOrgUnits,
        'internalAuditorTrainingDate': auditor.internalAuditorTrainingDate?.toIso8601String(),
        'trainingType': auditor.trainingType,
        'trainingDate': auditor.trainingDate?.toIso8601String(),
        'coAuditCount': auditor.coAuditCount,
        'leadAuditCount': auditor.leadAuditCount,
        'experienceYears': auditor.experienceYears,
        'standardsIso13485': auditor.standardsIso13485,
        'standardsMdr': auditor.standardsMdr,
        'standardsIso19011': auditor.standardsIso19011,
        'lastRequalificationDate': auditor.lastRequalificationDate?.toIso8601String(),
        'requalificationDueDate': auditor.requalificationDueDate?.toIso8601String(),
        'evidenceAttachments': auditor.evidenceAttachments,
      }),
    );
    final decoded = await _decode(r);
    final data = decoded['auditor'] as Map?;
    return Auditor.fromJson((data ?? decoded).cast<String, dynamic>());
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
}
