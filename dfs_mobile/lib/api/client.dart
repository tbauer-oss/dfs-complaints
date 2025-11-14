// lib/api/client.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

// EIN einziger bedingter Import – nur für window.localStorage (Stub auf Mobile)
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;

import 'package:http/http.dart' as http;
import '../models/complaint.dart';

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => 'HTTP $status: $message';
}

String _extractMessage(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map && j['error'] is String) return j['error'] as String;
    if (j is Map && j['message'] is String) return j['message'] as String;
    return body.isNotEmpty ? body : 'Unknown error';
  } catch (_) {
    return body.isNotEmpty ? body : 'Unknown error';
  }
}

bool _ok2xx(int s) => s >= 200 && s < 300;

class ApiClient {
  // ---------- Konfiguration ----------
  static const String _apiBase =
      String.fromEnvironment('API_BASE', defaultValue: '');

  String? token;        // JWT (Kundenportal)
  String? gate;         // optionales Gate-Token
  String? adminSecret;  // für X-Admin-Secret
  String? repToken;     // JWT für Vertreter-Login
  String? pushDeviceToken; // letzter registrierter Push-Token

  // Merker für Vertreter-Login-Flow
  String? _repEmail;    // zuletzt geprüfte/benutzte Vertreter-E-Mail

  // ---------- Session persistieren ----------
  void _saveSession() {
    final ls = kIsWeb ? html.window.localStorage : <String, String>{};

    // Token
    if (token != null) {
      ls['dfs_token'] = token!;
    } else {
      ls.remove('dfs_token');
    }

    // Admin-Secret
    if (adminSecret != null) {
      ls['dfs_admin'] = adminSecret!;
    } else {
      ls.remove('dfs_admin');
    }

    // Gate
    if (gate != null) {
      ls['dfs_gate'] = gate!;
    } else {
      ls.remove('dfs_gate');
    }

    // Rep-Token
    if (repToken != null) {
      ls['dfs_rep_token'] = repToken!;
    } else {
      ls.remove('dfs_rep_token');
    }

    if (pushDeviceToken != null && pushDeviceToken!.isNotEmpty) {
      ls['dfs_push_token'] = pushDeviceToken!;
    } else {
      ls.remove('dfs_push_token');
    }

    // Vertreter-E-Mail (nur als Hilfe für Secret-Login)
    if (_repEmail != null && _repEmail!.isNotEmpty) {
      ls['dfs_rep_email'] = _repEmail!;
    } else {
      ls.remove('dfs_rep_email');
    }
  }

  Future<void> restoreSession() async {
    final ls = kIsWeb ? html.window.localStorage : <String, String>{};
    token       = ls['dfs_token'];
    adminSecret = ls['dfs_admin'];
    gate        = ls['dfs_gate'];
    repToken    = ls['dfs_rep_token'];
    _repEmail   = ls['dfs_rep_email'];
    pushDeviceToken = ls['dfs_push_token'];
  }

  Future<void> logout() async {
    final tok = pushDeviceToken;
    if (tok != null && tok.isNotEmpty) {
      await unregisterPushToken(tok, silent: true);
    }
    token = null;
    adminSecret = null;
    gate = null;
    pushDeviceToken = null;
    _saveSession();
  }

  void setAdminSecret(String? s) {
    adminSecret = (s ?? '').trim().isEmpty ? null : s!.trim();
    _saveSession();
  }

  Map<String, String> _pushAuthHeaders() {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (gate != null && gate!.isNotEmpty) {
      h['X-Gate'] = gate!;
    }
    if (token != null && token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    } else if (repToken != null && repToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $repToken';
      h.putIfAbsent('X-Gate', () => 'rep');
    }
    if (adminSecret != null && adminSecret!.isNotEmpty) {
      h['X-Admin-Secret'] = adminSecret!;
    }
    return h;
  }

  void clearAdminSecret() {
    adminSecret = null;
    _saveSession();
  }

  void clearGate() {
    gate = null;
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

  Map<String, String> _headersJson() => {
        'Content-Type': 'application/json; charset=utf-8',
      };

  Map<String, dynamic>? _appMeta;
  DateTime? _appMetaLoadedAt;

  Map<String, dynamic>? get appMeta => _appMeta;
  String get appVersion => _appMeta?['version']?.toString() ?? '';

  Map<String, String> _adminHeaders({bool auth = false, Map<String, String>? extra}) {
    final h = _headers(auth: auth, extra: extra);
    if (adminSecret != null && adminSecret!.isNotEmpty) {
      h['X-Admin-Secret'] = adminSecret!;
    }
    return h;
  }

  // Header für Vertreter-Endpunkte (erzwingt X-Gate: rep)
  Map<String, String> _repHeaders({Map<String, String>? extra}) {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'X-Gate': 'rep', // <- wichtig
    };
    final tok = repToken ?? '';
    if (tok.isNotEmpty) h['Authorization'] = 'Bearer $tok';
    if (extra != null) h.addAll(extra);
    return h;
  }

  // Versucht, das Rep-Token leise zu erneuern (POST /api/rep/refresh)
  Future<bool> _repTryRefresh() async {
    try {
      final r = await http.post(
        _u('/api/rep/refresh'),
        headers: _repHeaders(),
        body: jsonEncode(const {}),
      );
      if (_ok2xx(r.statusCode)) {
        final body = r.body.trim().isEmpty ? '{}' : r.body;
        final j = jsonDecode(body);
        final tok = (j is Map ? (j['token'] ?? '') : '').toString();
        if (tok.isNotEmpty) {
          repToken = tok;
          _saveSession();
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // Zentrales Fetch für Rep-Endpunkte mit 1x 401-Retry nach Refresh
  Future<http.Response> _repFetch(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    Future<http.Response> _do() {
      final uri = _u(path);
      final h = _repHeaders();
      switch (method) {
        case 'POST':
          return http.post(uri, headers: h, body: jsonEncode(body ?? const {}));
        case 'PUT':
          return http.put(uri, headers: h, body: jsonEncode(body ?? const {}));
        case 'PATCH':
          return http.patch(uri, headers: h, body: jsonEncode(body ?? const {}));
        case 'DELETE':
          return http.delete(uri, headers: h, body: jsonEncode(body ?? const {}));
        default:
          return http.get(uri, headers: h);
      }
    }

    var r = await _do();

    if (r.statusCode == 401) {
      final ok = await _repTryRefresh();
      if (ok) {
        r = await _do();
      }
    }

    final newTok = r.headers['x-rep-token'];
    if (newTok != null && newTok.isNotEmpty && newTok != repToken) {
      repToken = newTok;
      _saveSession();
    }

    return r;
  }

  // ——— Nur für Vertreter-Endpunkte: POST mit Bearer-Token ———
  Future<Map<String, dynamic>> _repPostJson(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      _u(path),
      headers: _repHeaders(),
      body: jsonEncode(body),
    );
    if (!_ok2xx(r.statusCode)) {
      throw 'HTTP ${r.statusCode} ${r.reasonPhrase} — ${r.body}';
    }
    final txt = r.body.trim();
    return txt.isEmpty ? <String, dynamic>{} : jsonDecode(txt);
  }

  Uri _u(String path) {
    final base = baseUrl; // nutzt den sauberen Getter inkl. Mobile-Fallback
    return Uri.parse('$base$path');
  }

  // Öffentlicher Wrapper für Rep-POST (mit X-Gate: rep + Bearer)
  Future<Map<String, dynamic>> repPostJson(String path, Map<String, dynamic> body) {
    return _repPostJson(path, body);
  }

  Future<Map<String, dynamic>?> getAppMeta({bool refresh = false}) async {
    final cacheValid = _appMeta != null && _appMetaLoadedAt != null &&
        DateTime.now().difference(_appMetaLoadedAt!).inMinutes < 5;
    if (!refresh && cacheValid) return _appMeta;

    final r = await http.get(
      _u('/api/meta'),
      headers: {'Content-Type': 'application/json'},
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final j = jsonDecode(r.body);
    if (j is Map<String, dynamic>) {
      _appMeta = j;
      _appMetaLoadedAt = DateTime.now();
    }
    return _appMeta;
  }

  // ---- Basis ----
  String get baseUrl {
    const b = String.fromEnvironment('API_BASE', defaultValue: '');
    if (b.isNotEmpty) return b;

    if (kIsWeb) {
      // Erst localStorage, dann origin
      try {
        final ls = html.window.localStorage['API_BASE'] ?? '';
        if (ls.trim().isNotEmpty) return ls.trim();
      } catch (_) {}
      try {
        return html.window.location.origin;
      } catch (_) {}
    }

    // Mobile/Desktop-Fallback (ohne dart:html)
    if (_apiBase.isNotEmpty) return _apiBase;
    return 'https://dfs-complaints-backend.vercel.app';
  }

  // ---- Generic POST JSON (nur noch über package:http) ----
  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final url = _u(path);
    final r = await http.post(url, headers: _headersJson(), body: jsonEncode(body));

    final status = r.statusCode;
    final text   = r.body;

    if (status != 200 && status != 201) {
      throw 'HTTP $status — $text';
    }
    final t = text.trim();
    return t.isEmpty ? <String, dynamic>{} : (jsonDecode(t) as Map<String, dynamic>);
  }

  // ---- Reps: Entscheidung zu Complaint (mit Bearer-Token) ----
  Future<void> repDecision({
    required String ticket,
    required bool approve,
  }) async {
    final r = await _repFetch(
      '/api/rep/decision',
      method: 'POST',
      body: {
        'ticket': ticket,
        'decision': approve ? 'accepted' : 'rejected',
      },
    );
    if (!_ok2xx(r.statusCode)) {
      throw Exception('POST /api/rep/decision failed: ${r.statusCode} ${r.body}');
    }
  }

  // ✅ Dedizierter Reset-Call – erwartet 204 (ohne Body)
  Future<void> repDecisionReset({required String ticket}) async {
    // Falls repToken leer ist: defensiv aus LocalStorage ziehen
    if (repToken == null || repToken!.isEmpty) {
      if (kIsWeb) {
        try {
          final lsTok = html.window.localStorage['dfs_rep_token'];
          if (lsTok != null && lsTok.isNotEmpty) repToken = lsTok;
        } catch (_) {}
      }
    }

    final r = await http.post(
      _u('/api/rep/decision/reset'),
      headers: _repHeaders(),
      body: jsonEncode({'ticket': ticket}),
    );

    if (r.statusCode == 204) return;               // Erfolg (ohne Body)
    if (_ok2xx(r.statusCode)) return;              // z. B. 200 im Debug-Fall
    throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  // Alternative: Entscheidung leeren (falls /api/rep/decision/reset nicht greift)
  Future<void> repDecisionClear(String ticket) async {
    // sorgt für Bearer + X-Gate: rep und 401->Refresh via _repFetch
    final r = await _repFetch(
      '/api/rep/decision',
      method: 'POST',
      body: {'ticket': ticket, 'decision': ''},
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<void> setAppMeta({
    required String version,
    String? build,
    String? notes,
  }) async {
    final body = jsonEncode({
      'version': version,
      if (build != null) 'build': build,
      if (notes != null) 'notes': notes,
    });

    final headers = {
      'Content-Type': 'application/json',
      if (adminSecret != null && adminSecret!.isNotEmpty) 'X-Admin-Secret': adminSecret!,
    };

    final r = await http.post(
      _u('/api/admin/meta'),
      headers: headers,
      body: body,
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    _appMetaLoadedAt = null; // Cache invalidieren -> neu laden beim nächsten Zugriff
  }

  Future<Map<String, dynamic>> repMe() async {
    final r = await _repFetch('/api/rep/me');
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/me failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<List<String>> repCustomers() async {
    final r = await _repFetch('/api/rep/customers');
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/customers failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is List) return j.whereType<String>().toList(growable: false);
    return const [];
  }

  Future<List<Map<String, dynamic>>> repCustomersDetailed() async {
    final r = await _repFetch('/api/rep/customers?details=1');
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/customers?details=1 failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is List) {
      if (j.isNotEmpty && j.first is String) {
        return j.whereType<String>().map((mail) => <String, dynamic>{
          'email': mail,
          'name': mail,
        }).toList(growable: false);
      }
      return j
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> repComplaints({String status = ''}) async {
    final path = status.isEmpty
        ? '/api/rep/complaints'
        : '/api/rep/complaints?status=$status';
    final r = await _repFetch(path);
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET $path failed: ${r.statusCode} ${r.body}');
    }
    final body = jsonDecode(r.body);
    if (body is List) return body.cast<Map<String, dynamic>>();
    if (body is Map && body['items'] is List) {
      return (body['items'] as List).cast<Map<String, dynamic>>();
    }
    return const [];
  }

  // ---------- NEU: Vertreter – zuweisbare Kunden (free oder all) ----------
  Future<List<Map<String, dynamic>>> repAssignableCustomers({bool all = false}) async {
    final q = all ? '?all=1' : '';
    final r = await _repFetch('/api/rep/assignable-customers$q');
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/assignable-customers failed: ${r.statusCode} ${r.body}');
    }
    final body = r.body.trim();
    if (body.isEmpty) return const [];
    final j = jsonDecode(body);
    if (j is List) {
      return j
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  // ---------- Low-level HTTP (nur package:http) ----------
  Future<http.Response> _get(String path, {bool auth = false, Map<String,String>? extra}) {
    return http.get(_u(path), headers: _headers(auth: auth, extra: extra));
    }

  Future<http.Response> _post(String path, Map body,
      {bool auth = false, Map<String, String>? extraHeaders}) {
    return http.post(
      _u(path),
      headers: _headers(auth: auth, extra: extraHeaders),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _put(String path, Map body, {bool auth = false}) {
    return http.put(
      _u(path),
      headers: _headers(auth: auth),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _patch(String path, Map body, {bool auth = false}) {
    return http.patch(
      _u(path),
      headers: _headers(auth: auth),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _delete(String path, {Map? body, bool auth = false}) {
    return http.delete(
      _u(path),
      headers: _headers(auth: auth),
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<void> registerPushToken(String token, {String? platform, String? locale, String? lang}) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    final headers = _pushAuthHeaders();
    final hasAuth = headers.containsKey('Authorization') || headers.containsKey('X-Admin-Secret');
    if (!hasAuth) {
      pushDeviceToken = trimmed;
      _saveSession();
      return;
    }

    final body = <String, String>{'token': trimmed};
    if (platform != null && platform.trim().isNotEmpty) body['platform'] = platform.trim();
    if (locale != null && locale.trim().isNotEmpty) body['locale'] = locale.trim();
    if (lang != null && lang.trim().isNotEmpty) body['lang'] = lang.trim();

    final res = await http.post(
      _u('/api/push/register'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (!_ok2xx(res.statusCode)) {
      final msg = _extractMessage(res.body);
      throw ApiError(res.statusCode, msg);
    }
    pushDeviceToken = trimmed;
    _saveSession();
  }

  Future<void> unregisterPushToken(String token, {bool silent = false}) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      if (pushDeviceToken != null) {
        pushDeviceToken = null;
        _saveSession();
      }
      return;
    }

    final headers = _pushAuthHeaders();
    final hasAuth = headers.containsKey('Authorization') || headers.containsKey('X-Admin-Secret');
    if (hasAuth) {
      try {
        final res = await http.delete(
          _u('/api/push/register?token=${Uri.encodeComponent(trimmed)}'),
          headers: headers,
        );
        if (!_ok2xx(res.statusCode) && res.statusCode != 204 && res.statusCode != 404) {
          if (!silent) {
            final msg = _extractMessage(res.body);
            throw ApiError(res.statusCode, msg);
          }
        }
      } catch (e) {
        if (!silent) {
          if (e is ApiError) rethrow;
          throw ApiError(0, e.toString());
        }
      }
    }

    if (pushDeviceToken == trimmed) {
      pushDeviceToken = null;
      _saveSession();
    }
  }

  // ---------- Gate ----------
  Future<bool> gateUnlock(String password, {String? email}) async {
    final body = <String, String>{'password': password};
    final em = email?.trim();
    if (em != null && em.isNotEmpty) body['email'] = em;
    final r = await _post('/api/gate', body);
    if (!_ok2xx(r.statusCode)) return false;
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

  Future<String?> gateRequestPassword(String email) async {
    final r = await _post('/api/gate/request', {'email': email.trim()});
    if (_ok2xx(r.statusCode)) return null;
    try {
      final body = r.body;
      if (body.isNotEmpty) return body;
    } catch (_) {}
    return 'gate request failed: ${r.statusCode}';
  }

  // ---------- Auth (Kunden) ----------
  Future<bool> login(String email, String password) async {
    final r = await _post('/api/auth/login', {'email': email, 'password': password});
    if (!_ok2xx(r.statusCode)) return false;
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
    if (_ok2xx(r.statusCode)) return null;
    try {
      final body = r.body;
      if (body.isNotEmpty) return body;
    } catch (_) {}
    return 'register failed: ${r.statusCode}';
  }

  // ---------- Account ----------
  Future<Map<String, dynamic>> accountGet() async {
    final r = await _get('/api/account', auth: true);
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/account failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> accountUpdate(Map<String, dynamic> data) async {
    var r = await _put('/api/account', data, auth: true);
    if (_ok2xx(r.statusCode)) return;

    if (r.statusCode == 405 || r.statusCode == 404) {
      r = await _patch('/api/account', data, auth: true);
      if (_ok2xx(r.statusCode)) return;

      if (r.statusCode == 405 || r.statusCode == 404) {
        r = await _post('/api/account/update', data, auth: true);
        if (_ok2xx(r.statusCode)) return;

        if (r.statusCode == 405 || r.statusCode == 404) {
          r = await _post('/api/account', data, auth: true);
          if (_ok2xx(r.statusCode)) return;
        }
      }
    }

    throw Exception('PUT/PATCH/POST /api/account failed: ${r.statusCode} ${r.body}');
  }

  Future<void> accountDelete(String password) async {
    var r = await _delete('/api/account', body: {'password': password}, auth: true);
    if (_ok2xx(r.statusCode)) {
      await logout();
      return;
    }

    if (r.statusCode == 405 || r.statusCode == 404) {
      r = await _post('/api/account/delete', {'password': password}, auth: true);
      if (_ok2xx(r.statusCode)) {
        await logout();
        return;
      }
    }

    throw Exception('DELETE/POST /api/account failed: ${r.statusCode} ${r.body}');
  }

  Future<void> accountChangePassword(String oldPw, String newPw) async {
    try {
      final r = await _post(
        '/api/account/password',
        {'oldPassword': oldPw, 'newPassword': newPw},
        auth: true,
      );

      if (!_ok2xx(r.statusCode)) {
        final msg = _extractMessage(r.body);
        throw ApiError(r.statusCode, msg);
      }
    } catch (e) {
      if (e is ApiError) rethrow;
      throw ApiError(0, e.toString());
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
    if (!_ok2xx(r.statusCode)) {
      throw Exception('POST /api/support failed: ${r.statusCode} ${r.body}');
    }
  }

    // ---------- Kontakt zum Vertreter (Mail über Backend) ----------
  Future<void> sendRepContact(Map<String, dynamic> data) async {
    // Kunde ist eingeloggt -> Auth: true, damit Bearer-Token mitgesendet wird
    final r = await _post('/api/rep/contact', data, auth: true);
    if (!_ok2xx(r.statusCode)) {
      // Versuch, saubere Fehlermeldung aus dem Body zu ziehen
      final msg = _extractMessage(r.body);
      throw ApiError(r.statusCode, msg);
    }
  }

  // ---------- Complaints ----------
  Future<Map<String, dynamic>?> complaintCreate(
    Map<String, dynamic> data, [
    List<({String name, List<int> bytes, String mime})> files = const [],
  ]) async {
    final encFiles = files
        .map((f) => {
              'name': f.name,
              'mime': f.mime,
              'bytes': base64Encode(f.bytes),
            })
        .toList();

    final r = await _post('/api/complaint/create', {
      'payload': data,
      if (encFiles.isNotEmpty) 'files': encFiles,
    }, auth: true);

    if (!_ok2xx(r.statusCode)) {
      return null;
    }
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> complaintListRaw() async {
    final r = await _get('/api/complaint/mine', auth: true);
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/complaint/mine failed: ${r.statusCode} ${r.body}');
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

  Future<List<Complaint>> complaintList() async {
    final raw = await complaintListRaw();
    return raw.map(Complaint.fromJson).toList(growable: false);
  }

  // ---------- Kundenbereich – Live-Updates ----------
  Future<List<Map<String, dynamic>>> myComplaintsDetailed() async {
    final r = await _get('/api/complaint/list?details=1', auth: true);
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/complaint/list?details=1 failed: ${r.statusCode} ${r.body}');
    }
    final List data = jsonDecode(r.body);
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> myComplaintByTicket(String ticket) async {
    final r = await _get('/api/complaint/get?ticket=$ticket', auth: true);
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/complaint/get failed: ${r.statusCode} ${r.body}');
    }
    return (jsonDecode(r.body) as Map).cast<String, dynamic>();
  }

  // ---------- Admin: Secret prüfen (für Dialog) ----------
  Future<bool> validateAdminSecret(String secret) async {
    if (secret.trim().isEmpty) return false;
    try {
      final r = await _get(
        '/api/admin/pending',
        extra: {'X-Admin-Secret': secret.trim()},
      );
      return _ok2xx(r.statusCode);
    } catch (_) {
      return false;
    }
  }

  // ---------- Vertreter (Kundenbereich) ----------
  Future<MyRep?> getMyRep() async {
    final uri = _u('/api/rep/of-customer');

    final headers = <String, String>{'Content-Type': 'application/json'};
    final tok = token ?? '';
    if (tok.isNotEmpty) {
      headers['Authorization'] = 'Bearer $tok'; // Kunden-JWT!
    }

    final r = await http.get(uri, headers: headers);
    if (r.statusCode == 204) return null;
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final j = jsonDecode(r.body);
    if (j is! Map) return null;

    return MyRep.fromJson(j.cast<String, dynamic>());
  }

  // ---------- Vertreter-API (Rep-Login & -Aktionen) ----------
  Future<bool> repExists(String email) async {
    final e = email.trim().toLowerCase();
    try {
      final r = await _post('/api/rep/exists', {'email': e});
      if (_ok2xx(r.statusCode)) {
        try {
          final j = jsonDecode(r.body);
          final exists = (j is Map && j['exists'] is bool) ? j['exists'] as bool : false;
          if (exists) {
            _repEmail = e;
            _saveSession();
          }
          return exists;
        } catch (_) {}
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<({bool ok, bool mustChange})> repLogin(String email, String password) async {
    try {
      final e = email.trim().toLowerCase();
      final r = await _post('/api/rep/login', {'email': e, 'password': password});
      if (!_ok2xx(r.statusCode)) {
        return (ok: false, mustChange: false);
      }

      final j = jsonDecode(r.body);
      if (j is! Map) return (ok: false, mustChange: false);

      final tok = (j['token'] ?? '').toString();
      final mustChange = (j['mustChangePw'] ?? false) == true;

      if (tok.isEmpty) return (ok: false, mustChange: false);

      repToken = tok;
      _repEmail = e;
      _saveSession();

      return (ok: true, mustChange: mustChange);
    } catch (_) {
      return (ok: false, mustChange: false);
    }
  }

  Future<bool> repLoginWithSecret(String email, String secret) async {
    final sec = secret.trim();
    final mail = email.trim().toLowerCase();
    if (sec.isEmpty || mail.isEmpty) return false;

    try {
      final r = await http.post(
        _u('/api/rep/login'),
        headers: _repHeaders(),
        body: jsonEncode({'email': mail, 'secret': sec}),
      );

      if (_ok2xx(r.statusCode)) {
        try {
          if (r.body.isNotEmpty) {
            final j = jsonDecode(r.body);
            if (j is Map && j['token'] is String) {
              repToken = j['token'] as String;
            }
          }
        } catch (_) {}
        _saveSession();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> repLoginSecret(String secret) {
    final mail = _repEmail ?? '';
    return repLoginWithSecret(mail, secret);
  }

  Future<bool> ensureRepSession() async {
    if (repToken == null || repToken!.isEmpty) return false;
    try {
      final r = await http.get(_u('/api/rep/me'), headers: _repHeaders());
      if (_ok2xx(r.statusCode)) return true;
      repToken = null;
      _saveSession();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> repChangePassword(String newPw) async {
    final r = await http.post(
      _u('/api/rep/password'),
      headers: _repHeaders(),
      body: jsonEncode({'new': newPw}),
    );

    if (r.statusCode == 204) {
      return;
    }
    if (_ok2xx(r.statusCode)) {
      try {
        if (r.body.isNotEmpty) {
          final j = jsonDecode(r.body);
          if (j is Map && j['token'] is String) {
            repToken = j['token'] as String;
            _saveSession();
          }
        }
      } catch (_) {}
      return;
    }

    throw Exception('POST /api/rep/password failed: ${r.statusCode} ${r.body}');
  }

  Future<void> repAssignCustomer(String email) async {
    final r = await http.post(
      _u('/api/rep/customers'),
      headers: _repHeaders(),
      body: jsonEncode({'action': 'assign', 'email': email}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw Exception('POST /api/rep/customers assign failed: ${r.statusCode} ${r.body}');
    }
  }

  Future<void> repUnassignCustomer(String email) async {
    final r = await http.post(
      _u('/api/rep/customers'),
      headers: _repHeaders(),
      body: jsonEncode({'action': 'unassign', 'email': email}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw Exception('POST /api/rep/customers unassign failed: ${r.statusCode} ${r.body}');
    }
  }

  Future<void> repLogout() async {
    repToken = null;
    _saveSession();
  }

  // Ende ApiClient
}

// ===== Modelle =====
class MyRep {
  final String firstName;
  final String lastName;
  final String email;
  final String region;
  const MyRep({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.region,
  });

  String get displayName {
    final fn = firstName.trim();
    final ln = lastName.trim();
    if (fn.isEmpty && ln.isEmpty) return email.trim();
    return [fn, ln].where((s) => s.isNotEmpty).join(' ');
  }

  factory MyRep.fromJson(Map<String, dynamic> j) {
    String pick(List<dynamic> values) {
      for (final v in values) {
        final s = (v ?? '').toString().trim();
        if (s.isNotEmpty) return s;
      }
      return '';
    }

    String first = pick([
      j['firstName'],
      j['firstname'],
      j['first_name'],
    ]);

    String last = pick([
      j['lastName'],
      j['lastname'],
      j['last_name'],
      j['surname'],
    ]);

    final fullName = pick([
      j['name'],
      j['fullName'],
      j['displayName'],
      j['label'],
    ]);

    if (fullName.isNotEmpty) {
      final parts = fullName.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (first.isEmpty && parts.isNotEmpty) {
        first = parts.first;
      }
      if (last.isEmpty && parts.length > 1) {
        last = parts.sublist(1).join(' ');
      }
      if (first.isEmpty && last.isEmpty) {
        first = fullName;
      }
    }

    final email = pick([
      j['email'],
      j['mail'],
      j['emailAddress'],
      j['email_address'],
      j['userEmail'],
    ]).toLowerCase();

    final region = pick([
      j['region'],
      j['area'],
      j['territory'],
      j['regionName'],
      j['regions'],
    ]);

    return MyRep(
      firstName: first,
      lastName: last,
      email: email,
      region: region,
    );
  }
}

class RepMe {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String region;
  final List<String> customers;
  const RepMe({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.region,
    required this.customers,
  });

  factory RepMe.fromJson(Map<String,dynamic> j) => RepMe(
    id:       (j['id']        ?? '').toString(),
    firstName:(j['firstName'] ?? '').toString(),
    lastName: (j['lastName']  ?? '').toString(),
    email:    (j['email']     ?? '').toString(),
    region:   (j['region']    ?? '').toString(),
    customers: (j['customers'] as List? ?? const []).cast<String>(),
  );
}
