// lib/api/client.dart
import 'dart:convert';
import 'dart:html' as html; // Web: LocalStorage & Window
import 'package:http/http.dart' as http;

import '../models/complaint.dart';

class ApiClient {
  // ---------- Konfiguration ----------
  static const String _apiBase =
      String.fromEnvironment('API_BASE', defaultValue: '');

  String? token;        // JWT
  String? gate;         // optionales Gate-Token
  String? adminSecret;  // für X-Admin-Secret

  // ---------- Session persistieren ----------
  void _saveSession() {
    final ls = html.window.localStorage;

    // Token
    if (token != null && token!.isNotEmpty) {
      ls['dfs_token'] = token!;
    } else {
      ls.remove('dfs_token');
    }

    // Admin-Secret
    if (adminSecret != null && adminSecret!.isNotEmpty) {
      ls['dfs_admin'] = adminSecret!;
    } else {
      ls.remove('dfs_admin');
    }

    // Gate
    if (gate != null && gate!.isNotEmpty) {
      ls['dfs_gate'] = gate!;
    } else {
      ls.remove('dfs_gate');
    }
  }

  Future<void> restoreSession() async {
    final ls = html.window.localStorage;
    token       = ls['dfs_token'];
    adminSecret = ls['dfs_admin'];
    gate        = ls['dfs_gate'];
  }

  void logout() {
    token = null;
    _saveSession();
  }

  void setAdminSecret(String? s) {
    adminSecret = (s ?? '').trim().isEmpty ? null : s!.trim();
    _saveSession();
  }

  void clearAdminSecret() {
    adminSecret = null;
    _saveSession();
  }

  // ---------- Header-Helfer ----------
  Map<String, String> _headers({bool auth = false, Map<String, String>? extra}) {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      if (gate != null) 'X-Gate': gate!,
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  Map<String, String> _adminHeaders({bool auth = false, Map<String, String>? extra}) {
    final h = _headers(auth: auth, extra: extra);
    if (adminSecret != null) h['X-Admin-Secret'] = adminSecret!;
    return h;
  }

  Uri _u(String path) {
    final base = _apiBase.isEmpty ? '' : _apiBase;
    return Uri.parse('$base$path');
  }

  // ---------- Low-level HTTP ----------
  Future<http.Response> _get(String path, {bool auth = false, bool admin = false}) {
    final headers = admin ? _adminHeaders(auth: auth) : _headers(auth: auth);
    return http.get(_u(path), headers: headers);
  }

  Future<http.Response> _post(String path, Map body,
      {bool auth = false, bool admin = false, Map<String, String>? extraHeaders}) {
    final headers = admin
        ? _adminHeaders(auth: auth, extra: extraHeaders)
        : _headers(auth: auth, extra: extraHeaders);
    return http.post(_u(path), headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> _put(String path, Map body, {bool auth = false, bool admin = false}) {
    final headers = admin ? _adminHeaders(auth: auth) : _headers(auth: auth);
    return http.put(_u(path), headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> _delete(String path, {Map? body, bool auth = false, bool admin = false}) {
    final headers = admin ? _adminHeaders(auth: auth) : _headers(auth: auth);
    return http.delete(_u(path), headers: headers, body: body == null ? null : jsonEncode(body));
  }

  // ---------- Gate ----------
  Future<bool> gateUnlock(String password) async {
    final r = await _post('/api/gate', {'password': password});
    if (r.statusCode != 200) return false;
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['gate'] is String) {
        gate = j['gate'] as String;
        _saveSession();
        return true;
      }
      if (j is Map && j['ok'] == true) {
        gate = 'ok';
        _saveSession();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---------- Auth ----------
  Future<bool> login(String email, String password) async {
    final r = await _post('/api/auth/login', {'email': email, 'password': password});
    if (r.statusCode != 200) return false;
    final j = jsonDecode(r.body);
    if (j is Map && j['token'] is String) {
      token = j['token'] as String;
      _saveSession();
      return true;
    }
    return false;
  }

  /// Registrierung: `null` = Erfolg, sonst Fehlermeldung
  Future<String?> register(Map<String, dynamic> data) async {
    final r = await _post('/api/auth/register', data);
    if (r.statusCode == 200 || r.statusCode == 201) return null;

    // Body (falls vorhanden) als Fehlertext durchreichen
    try {
      final body = r.body;
      if (body.isNotEmpty) return body;
    } catch (_) {}
    return 'register failed: ${r.statusCode}';
  }

  // ---------- Account ----------
  Future<Map<String, dynamic>> accountGet() async {
    final r = await _get('/api/account', auth: true);
    if (r.statusCode != 200) {
      throw Exception('GET /api/account failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> accountUpdate(Map<String, dynamic> data) async {
    final r = await _put('/api/account', data, auth: true);
    if (r.statusCode != 200) {
      throw Exception('PUT /api/account failed: ${r.statusCode} ${r.body}');
    }
  }

  Future<void> accountDelete(String password) async {
    final r = await _delete('/api/account', body: {'password': password}, auth: true);
    if (r.statusCode != 200) {
      throw Exception('DELETE /api/account failed: ${r.statusCode} ${r.body}');
    }
    logout();
  }

  Future<void> accountChangePassword(String oldPw, String newPw) async {
    final r = await _post('/api/account/password', {'old': oldPw, 'new': newPw}, auth: true);
    if (r.statusCode != 200) {
      throw Exception('POST /api/account/password failed: ${r.statusCode} ${r.body}');
    }
  }

  // ---------- Support ----------
  Future<void> sendSupport({
    required String category,
    required String message,
    required bool consent,
  }) async {
    final r = await _post('/api/support', {
      'category': category,
      'message': message,
      'consent': consent,
    }, auth: true);
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception('POST /api/support failed: ${r.statusCode} ${r.body}');
    }
  }

  // ---------- Complaints ----------
  // Optionaler 2. Positions-Parameter 'files' (List von Records {name, bytes, mime})
  Future<Map<String, dynamic>?> complaintCreate(
    Map<String, dynamic> data, [
    List<({String name, List<int> bytes, String mime})> files = const [],
  ]) async {
    // Dateien base64-kodieren
    final encFiles = files
        .map((f) => {
              'name': f.name,
              'mime': f.mime,
              'bytes': base64Encode(f.bytes),
            })
        .toList();

    final r = await _post('/api/complaints', {
      'payload': data,
      if (encFiles.isNotEmpty) 'files': encFiles,
    }, auth: true);

    if (r.statusCode != 200 && r.statusCode != 201) return null;
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// Rohdaten
  Future<List<Map<String, dynamic>>> complaintListRaw() async {
    final r = await _get('/api/complaints', auth: true);
    if (r.statusCode != 200) {
      throw Exception('GET /api/complaints failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is List) {
      return j
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  /// Typisierte Liste
  Future<List<Complaint>> complaintList() async {
    final raw = await complaintListRaw();
    return raw.map(Complaint.fromJson).toList(growable: false);
  }
  Future<bool> validateAdminSecret(String secret) async {
    if (secret.trim().isEmpty) return false;
    try {
      // leichter Health-Check über Pending-Endpoint
      final r = await http.get(
        _u('/api/admin/pending'),
        headers: _headers(extra: {'X-Admin-Secret': secret}),
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
