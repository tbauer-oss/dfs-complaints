// lib/api/client.dart
import 'dart:convert';
import 'dart:html' as html; // Web: LocalStorage & Window
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
  }

  Future<void> restoreSession() async {
    final ls = html.window.localStorage;
    token       = ls['dfs_token'];
    adminSecret = ls['dfs_admin'];
    gate        = ls['dfs_gate'];
  }

  Future<void> logout() async {
    token = null;
    adminSecret = null;
    gate = null;
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
    if (adminSecret != null && adminSecret!.isNotEmpty) {
      h['X-Admin-Secret'] = adminSecret!;
    }
    return h;
  }

  Uri _u(String path) {
    final base = _apiBase.isEmpty ? '' : _apiBase;
    return Uri.parse('$base$path');
  }

  // ---------- Low-level HTTP ----------
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
    if (r.statusCode == 200 || r.statusCode == 201) {
      return null;
    }
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
    // 1) Primär: PUT /api/account
    var r = await _put('/api/account', data, auth: true);
    if (r.statusCode == 200) return;

    // 2) Fallback: PATCH /api/account (falls PUT nicht erlaubt)
    if (r.statusCode == 405 || r.statusCode == 404) {
      r = await _patch('/api/account', data, auth: true);
      if (r.statusCode == 200) return;

      // 3) Fallback: POST /api/account/update oder POST /api/account
      if (r.statusCode == 405 || r.statusCode == 404) {
        r = await _post('/api/account/update', data, auth: true);
        if (r.statusCode == 200) return;

        if (r.statusCode == 405 || r.statusCode == 404) {
          r = await _post('/api/account', data, auth: true);
          if (r.statusCode == 200) return;
        }
      }
    }

    throw Exception('PUT/PATCH/POST /api/account failed: ${r.statusCode} ${r.body}');
  }

  Future<void> accountDelete(String password) async {
    // 1) Primär: DELETE /api/account (204 = Erfolg)
    var r = await _delete('/api/account', body: {'password': password}, auth: true);
    if (r.statusCode == 200 || r.statusCode == 204) {
      await logout();
      return;
    }

    // 2) Fallback: POST /api/account/delete
    if (r.statusCode == 405 || r.statusCode == 404) {
      r = await _post('/api/account/delete', {'password': password}, auth: true);
      if (r.statusCode == 200 || r.statusCode == 204) {
        await logout();
        return;
      }
    }

    throw Exception('DELETE/POST /api/account failed: ${r.statusCode} ${r.body}');
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

    // 🔧 Richtiger Pfad (Singular + create)
    final r = await _post('/api/complaint/create', {
      'payload': data,
      if (encFiles.isNotEmpty) 'files': encFiles,
    }, auth: true);

    if (r.statusCode != 200 && r.statusCode != 201) {
      return null;
    }
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> complaintListRaw() async {
    // 🔧 Richtiger Pfad (Singular)
    final r = await _get('/api/complaint/mine', auth: true);
    if (r.statusCode != 200) {
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
  /// Liefert die eigenen Reklamationen mit allen Feldern (inkl. status/decision/updatedAt).
  /// Backend: GET /api/complaint/list?details=1  (JWT erforderlich)
  Future<List<Map<String, dynamic>>> myComplaintsDetailed() async {
    final r = await _get('/api/complaint/list?details=1', auth: true);
    if (r.statusCode != 200) {
      throw Exception('GET /api/complaint/list?details=1 failed: ${r.statusCode} ${r.body}');
    }
    final List data = jsonDecode(r.body);
    return data.cast<Map<String, dynamic>>();
  }

  /// Eine eigene Reklamation per Ticket (Validierung gegen User erfolgt im Backend).
  /// Backend: GET /api/complaint/get?ticket=...  (JWT erforderlich)
  Future<Map<String, dynamic>> myComplaintByTicket(String ticket) async {
    final r = await _get('/api/complaint/get?ticket=$ticket', auth: true);
    if (r.statusCode != 200) {
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
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------- Admin: Reklamationen ----------
  /// Offene Reklamationen (oder nach Query) laden – nutzt Admin-Secret Header.
  Future<List<Map<String, dynamic>>> adminComplaintsList({String query = ''}) async {
    final path = query.isEmpty ? '/api/admin/complaints' : '/api/admin/complaints?$query';
    final r = await http.get(_u(path), headers: _adminHeaders());
    if (r.statusCode != 200) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final j = jsonDecode(r.body);
    if (j is List) {
      return j.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(growable: false);
    }
    return const [];
  }

  /// Admin-Update für eine Reklamation.
  /// - `reportLink`: wenn `""` (leerer String) übergeben wird, löscht das Backend den Link.
  /// - Key wird NUR gesendet, wenn Parameter != null (damit keine ungewollten Änderungen passieren).
  Future<Map<String, dynamic>> adminComplaintUpdate({
    required String ticket,
    int? status,
    String? decision,
    String? reportLink, // "" => explizit löschen
  }) async {
    final body = <String, dynamic>{'ticket': ticket};
    if (status != null) body['status'] = status;
    if (decision != null) body['decision'] = decision;
    if (reportLink != null) body['reportLink'] = reportLink; // wichtig: "" wird gesendet

    final r = await http.post(
      _u('/api/admin/complaints'),
      headers: _adminHeaders(),
      body: jsonEncode(body),
    );

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }
}

// ===== Model =====
class MyRep {
  final String firstName;
  final String lastName;
  final String email;
  final String region;
  const MyRep({required this.firstName, required this.lastName, required this.email, required this.region});

  String get displayName {
    final fn = firstName.trim();
    final ln = lastName.trim();
    if (fn.isEmpty && ln.isEmpty) return email.trim();
    return [fn, ln].where((s) => s.isNotEmpty).join(' ');
  }

  factory MyRep.fromJson(Map<String, dynamic> j) => MyRep(
    firstName: (j['firstName'] ?? '').toString(),
    lastName : (j['lastName']  ?? '').toString(),
    email    : (j['email']     ?? '').toString(),
    region   : (j['region']    ?? '').toString(),
  );
}

// ===== ApiClient: Hilfsheader mit JWT =====
extension _AuthHeaders on ApiClient {
  Map<String,String> _jsonAuthHeaders() => {
    'Content-Type': 'application/json; charset=utf-8',
    if (_jwt.isNotEmpty) 'Authorization': 'Bearer $_jwt',
  };
}

// ===== ApiClient: Request-Helper (Web) =====
extension _Http on ApiClient {
  Uri _u(String path, [Map<String, String>? q]) {
    final base = const String.fromEnvironment('API_BASE', defaultValue: '');
    final url  = base.isNotEmpty ? '$base$path' : '${html.window.location.origin}$path';
    final uri  = Uri.parse(url);
    return (q == null || q.isEmpty) ? uri : uri.replace(queryParameters: q);
  }

  Future<html.HttpRequest> _request(String method, String path,
      {Map<String,String>? query, Object? body, bool auth = false}) async {
    final headers = auth ? _jsonAuthHeaders() : {'Content-Type': 'application/json; charset=utf-8'};
    final send = body is String ? body : (body == null ? null : jsonEncode(body));
    try {
      final res = await html.HttpRequest.request(
        _u(path, query).toString(),
        method: method,
        requestHeaders: headers,
        sendData: send,
        withCredentials: true,
      );
      return res;
    } catch (e) {
      // Fehler transparent machen
      if (e is html.ProgressEvent) {
        final t = e.target;
        if (t is html.HttpRequest) {
          throw 'HTTP ${t.status} ${t.statusText} — ${t.responseText ?? ''}';
        }
      }
      rethrow;
    }
  }
}

// ===== ApiClient: getMyRep() =====
extension _RepApi on ApiClient {
  Future<MyRep?> getMyRep() async {
    try {
      final res = await _request('GET', '/api/rep/my', auth: true);
      if (res.status == 204) return null;                       // kein Vertreter
      if ((res.responseText ?? '').trim().isEmpty) return null; // leer
      final Map<String,dynamic> j = jsonDecode(res.responseText!);
      // Minimalvalidierung
      if ((j['email'] ?? '').toString().trim().isEmpty) return null;
      return MyRep.fromJson(j);
    } catch (e) {
      // 401/404 → kein Banner anzeigen, aber für Debug loggen
      // ignore: avoid_print
      print('getMyRep() failed: $e');
      return null;
    }
  }
}
