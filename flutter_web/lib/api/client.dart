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

bool _ok2xx(int s) => s >= 200 && s < 300;

class ApiClient {
  // ---------- Konfiguration ----------
  static const String _apiBase =
      String.fromEnvironment('API_BASE', defaultValue: '');

  String? token;        // JWT (Kundenportal)
  String? gate;         // optionales Gate-Token
  String? adminSecret;  // für X-Admin-Secret
  String? repToken;     // JWT für Vertreter-Login

  // Merker für Vertreter-Login-Flow
  String? _repEmail;    // zuletzt geprüfte/benutzte Vertreter-E-Mail

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

    // Rep-Token
    if (repToken != null) {
      ls['dfs_rep_token'] = repToken!;
    } else {
      ls.remove('dfs_rep_token');
    }

    // Vertreter-E-Mail (nur als Hilfe für Secret-Login, kein Sicherheitskritikum)
    if (_repEmail != null && _repEmail!.isNotEmpty) {
      ls['dfs_rep_email'] = _repEmail!;
    } else {
      ls.remove('dfs_rep_email');
    }
  }

  Future<void> restoreSession() async {
    final ls = html.window.localStorage;
    token       = ls['dfs_token'];
    adminSecret = ls['dfs_admin'];
    gate        = ls['dfs_gate'];
    repToken    = ls['dfs_rep_token'];
    _repEmail   = ls['dfs_rep_email'];
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

  Map<String, String> _repHeaders({Map<String, String>? extra}) {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      if (gate != null) 'X-Gate': gate!,
      if (repToken != null && repToken!.isNotEmpty) 'Authorization': 'Bearer $repToken',
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  Uri _u(String path) {
    // Wenn API_BASE leer ist (z. B. Preview/Local), nimm die aktuelle Origin
    final base = _apiBase.isNotEmpty ? _apiBase : html.window.location.origin;
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
    // 1) Primär: PUT /api/account
    var r = await _put('/api/account', data, auth: true);
    if (_ok2xx(r.statusCode)) return;

    // 2) Fallback: PATCH /api/account (falls PUT nicht erlaubt)
    if (r.statusCode == 405 || r.statusCode == 404) {
      r = await _patch('/api/account', data, auth: true);
      if (_ok2xx(r.statusCode)) return;

      // 3) Fallback: POST /api/account/update oder POST /api/account
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
    // 1) Primär: DELETE /api/account (204 = Erfolg)
    var r = await _delete('/api/account', body: {'password': password}, auth: true);
    if (_ok2xx(r.statusCode)) {
      await logout();
      return;
    }

    // 2) Fallback: POST /api/account/delete
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

    // Richtiger Pfad (Singular + create)
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
    // Richtiger Pfad (Singular)
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
  /// Liefert den zugewiesenen Vertreter für den eingeloggten Kunden.
  /// Backend: GET /api/rep/my  (JWT erforderlich)
  Future<MyRep?> getMyRep() async {
    try {
      final r = await _get('/api/rep/my', auth: true);
      if (r.statusCode == 204) return null;          // kein Vertreter
      if (!_ok2xx(r.statusCode)) return null;         // still schlucken, Banner dann nicht anzeigen
      final body = r.body.trim();
      if (body.isEmpty) return null;

      final j = jsonDecode(body);
      if (j is Map) {
        final m = j.cast<String, dynamic>();
        if ((m['email'] ?? '').toString().trim().isEmpty) return null; // Minimalvalidierung
        return MyRep.fromJson(m);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------- Vertreter-API (Rep-Login & -Aktionen) ----------

  /// Prüft, ob ein Vertreter (aktiv) existiert.
  /// Erwartet: 200 { exists: true|false } – alles andere wird als false interpretiert.
  Future<bool> repExists(String email) async {
    final e = email.trim().toLowerCase();
    try {
      final r = await _post('/api/rep/exists', {'email': e});
      if (_ok2xx(r.statusCode)) {
        try {
          final j = jsonDecode(r.body);
          final exists = (j is Map && j['exists'] is bool) ? j['exists'] as bool : false;
          if (exists) {
            _repEmail = e; // <— Merken, damit Secret-Login die E-Mail mitsenden kann
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

  /// Bestehender Flow (E-Mail + Passwort).
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

  // ---- Vertreter-Login über Secret + E-Mail (Einmalpasswort)
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

  /// Alias: verwendet die zuletzt gespeicherte Vertreter-E-Mail.
  Future<bool> repLoginSecret(String secret) {
    final mail = _repEmail ?? '';
    return repLoginWithSecret(mail, secret);
  }

  /// Prüft das repToken einmalig gegen /api/rep/me.
  /// Bei 401 wird das Token entfernt (verhindert den 401-Loop nach Reload).
  Future<bool> ensureRepSession() async {
    if (repToken == null || repToken!.isEmpty) return false;
    try {
      final r = await http.get(_u('/api/rep/me'), headers: _repHeaders());
      if (_ok2xx(r.statusCode)) return true;
      // Token ungültig -> räumen
      repToken = null;
      _saveSession();
      return false;
    } catch (_) {
      // Netzwerkfehler o.ä.: Session behalten, aber false zurückgeben
      return false;
    }
  }
  
  /// Passwort ändern (Vertreter). Akzeptiert:
  /// - 204 (kein Body) ODER
  /// - 200 { token: '...' } -> Token wird aktualisiert.
  Future<void> repChangePassword(String newPw) async {
    final r = await http.post(
      _u('/api/rep/password'),
      headers: _repHeaders(),
      body: jsonEncode({'new': newPw}),
    );

    if (r.statusCode == 204) {
      // ok ohne Body
      return;
    }
    if (_ok2xx(r.statusCode)) {
      // evtl. neues Token returned
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

  Future<Map<String, dynamic>> repMe() async {
    final r = await http.get(_u('/api/rep/me'), headers: _repHeaders());
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/me failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<List<String>> repCustomers() async {
    final r = await http.get(_u('/api/rep/customers'), headers: _repHeaders());
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/customers failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is List) return j.whereType<String>().toList(growable: false);
    return const [];
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

  Future<List<Map<String, dynamic>>> repComplaints() async {
    final r = await http.get(_u('/api/rep/complaints'), headers: _repHeaders());
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/complaints failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is List) {
      return j.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(growable: false);
    }
    return const [];
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

  factory MyRep.fromJson(Map<String, dynamic> j) => MyRep(
        firstName: (j['firstName'] ?? '').toString(),
        lastName : (j['lastName']  ?? '').toString(),
        email    : (j['email']     ?? '').toString(),
        region   : (j['region']    ?? '').toString(),
      );
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
