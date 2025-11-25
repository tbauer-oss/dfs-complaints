// lib/api/client.dart
import 'dart:convert';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import '../models/complaint.dart';
import '../models/catalog_link.dart';
import '../models/customer_news_entry.dart';
import '../models/faq.dart';
import 'config.dart';

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => 'HTTP $status: $message';
}

class LoginResult {
  final bool ok;
  final bool revoked;
  final String? message;
  final int? statusCode;

  const LoginResult({
    required this.ok,
    this.revoked = false,
    this.message,
    this.statusCode,
  });

  factory LoginResult.success() => const LoginResult(ok: true);

  factory LoginResult.failure({
    bool revoked = false,
    String? message,
    int? statusCode,
  }) =>
      LoginResult(
        ok: false,
        revoked: revoked,
        message: message,
        statusCode: statusCode,
      );
}

class SimpleResult {
  final bool ok;
  final String? message;
  final int statusCode;

  const SimpleResult({
    required this.ok,
    this.message,
    required this.statusCode,
  });

  factory SimpleResult.success() => const SimpleResult(ok: true, statusCode: 200);
  factory SimpleResult.failure(int statusCode, String? message) =>
      SimpleResult(ok: false, statusCode: statusCode, message: message);
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

String _resolveApiBase() {
  const defined = String.fromEnvironment('API_BASE', defaultValue: '');
  if (defined.isNotEmpty) return defined;

  try {
    final stored = html.window.localStorage['API_BASE'] ?? '';
    if (stored.trim().isNotEmpty) return stored.trim();
  } catch (_) {}

  try {
    final origin = html.window.location.origin;
    final lower = origin.toLowerCase();
    final isLocal = lower.contains('localhost') ||
        lower.contains('127.0.0.1') ||
        lower.contains('0.0.0.0') ||
        lower.contains('://192.168.') ||
        lower.contains('://10.') ||
        lower.contains('://172.');
    if (isLocal && origin.isNotEmpty) return origin;
  } catch (_) {}

  return CFG.apiBase;
}

class ApiClient {
  // ---------- Konfiguration ----------
  static final String _apiBase = _resolveApiBase();

  String? token;        // JWT (Kundenportal)
  String? gate;         // optionales Gate-Token
  String? adminSecret;  // für X-Admin-Secret
  String? repToken;     // JWT für Vertreter-Login

  // Merker für Vertreter-Login-Flow
  String? _repEmail;    // zuletzt geprüfte/benutzte Vertreter-E-Mail

  bool _persistCustomerSession = true;
  bool _persistRepSession = true;
  bool _persistAdminSession = true;

  // ---------- Session persistieren ----------
  void _saveSession() {
    final ls = html.window.localStorage;

    // Token
    if (_persistCustomerSession && token != null) {
      ls['dfs_token'] = token!;
    } else {
      ls.remove('dfs_token');
    }

    // Admin-Secret
    if (_persistAdminSession && adminSecret != null) {
      ls['dfs_admin'] = adminSecret!;
    } else {
      ls.remove('dfs_admin');
    }

    // Gate
    if (_persistCustomerSession && gate != null) {
      ls['dfs_gate'] = gate!;
    } else {
      ls.remove('dfs_gate');
    }

    // Rep-Token
    if (_persistRepSession && repToken != null) {
      ls['dfs_rep_token'] = repToken!;
    } else {
      ls.remove('dfs_rep_token');
    }

    // Vertreter-E-Mail (nur als Hilfe für Secret-Login, kein Sicherheitskritikum)
    if (_persistRepSession && _repEmail != null && _repEmail!.isNotEmpty) {
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

    _persistCustomerSession = (token ?? '').isNotEmpty || (gate ?? '').isNotEmpty;
    _persistAdminSession = (adminSecret ?? '').isNotEmpty;
    _persistRepSession = (repToken ?? '').isNotEmpty || (_repEmail ?? '').isNotEmpty;
  }

  Future<void> logout() async {
    token = null;
    adminSecret = null;
    gate = null;
    _saveSession();
  }

  void setCustomerSessionPersistence(bool persist) {
    _persistCustomerSession = persist;
  }

  void setRepSessionPersistence(bool persist) {
    _persistRepSession = persist;
  }

  void setAdminSecret(String? s, {bool persist = true}) {
    _persistAdminSession = persist && (s ?? '').trim().isNotEmpty;
    adminSecret = (s ?? '').trim().isEmpty ? null : s!.trim();
    _saveSession();
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
  
  Map<String, dynamic>? _appMeta;
  DateTime? _appMetaLoadedAt;
  List<CustomerNewsEntry>? _newsCache;
  DateTime? _newsLoadedAt;
  static const Duration _newsCacheTtl = Duration(minutes: 1);
  FaqData? _faqCache;
  DateTime? _faqLoadedAt;
  static const Duration _faqCacheTtl = Duration(minutes: 1);

  void _invalidateNewsCache() {
    _newsCache = null;
    _newsLoadedAt = null;
  }

  void clearCustomerNewsCache() => _invalidateNewsCache();

  Map<String, dynamic>? get appMeta => _appMeta;
  String get appVersion => _appMeta?['version']?.toString() ?? '';

  Map<String, String> _adminHeaders({bool auth = false, Map<String, String>? extra}) {
    final h = _headers(auth: auth, extra: extra);
    if (adminSecret != null && adminSecret!.isNotEmpty) {
      h['X-Admin-Secret'] = adminSecret!;
    }
    return h;
  }

  String _formatDateOnly(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
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

  Future<Map<String, String>> fetchCatalogConfig() async {
    final res = await get('/api/catalogs/config'); // Pfad anpassen falls nötig
    final m = <String, String>{};
    if (res is Map) {
      for (final k in ['lab_default', 'lab_esfr', 'dent_default', 'dent_esfr']) {
        final v = res[k];
        if (v is String && v.trim().isNotEmpty) m[k] = v.trim();
      }
    }
    return m;
  }

  Future<void> updateCatalogConfig(Map<String, String> cfg) async {
    // nur erlaubte Keys schicken
    final body = <String, String>{};
    for (final k in ['lab_default', 'lab_esfr', 'dent_default', 'dent_esfr']) {
      final v = cfg[k];
      if (v != null) body[k] = v;
    }
    await put('/api/catalogs/config', body: body);
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
    final base = _apiBase.isNotEmpty ? _apiBase : html.window.location.origin;
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

    final base = _apiBase.isEmpty ? '' : _apiBase;
    final uri = Uri.parse('$base/api/meta');
    final r = await http.get(uri, headers: {'Content-Type': 'application/json'});
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

  Future<List<CustomerNewsEntry>> fetchCustomerNews({bool refresh = false}) async {
    final cacheValid =
        _newsCache != null && _newsLoadedAt != null &&
        DateTime.now().difference(_newsLoadedAt!) < _newsCacheTtl;
    if (!refresh && cacheValid) return _newsCache!;

    final r = await http.get(
      _u('/api/news'),
      headers: {'Content-Type': 'application/json'},
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    dynamic decoded = jsonDecode(r.body);
    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      decoded = decoded['items'];
    }
    final List<CustomerNewsEntry> items = [];
    if (decoded is List) {
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          items.add(CustomerNewsEntry.fromJson(entry));
        }
      }
    }
    _newsCache = items;
    _newsLoadedAt = DateTime.now();
    return items;
  }

  Future<FaqData> fetchFaq({bool refresh = false}) async {
    final cacheValid = _faqCache != null &&
        _faqLoadedAt != null &&
        DateTime.now().difference(_faqLoadedAt!) < _faqCacheTtl;
    if (!refresh && cacheValid) return _faqCache!;

    final res = await http.get(
      _u('/api/faq'),
      headers: {'Content-Type': 'application/json'},
    );

    if (!_ok2xx(res.statusCode)) {
      throw ApiError(res.statusCode, _extractMessage(res.body));
    }

    final body = res.body.trim();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    final data =
        decoded is Map<String, dynamic> ? FaqData.fromJson(decoded) : const FaqData(categories: [], entries: []);

    _faqCache = data;
    _faqLoadedAt = DateTime.now();
    return data;
  }

  // ---- Basis ----
  String get baseUrl {
    const b = String.fromEnvironment('API_BASE', defaultValue: '');
    if (b.isNotEmpty) return b;
    return html.window.location.origin;
  }

  Map<String, String> _headersJson() => {
    'Content-Type': 'application/json; charset=utf-8',
  };

  Future<html.HttpRequest> _request(
    String method,
    String path, {
    Object? body,
  }) async {
    try {
      final res = await html.HttpRequest.request(
        _u(path).toString(),
        method: method,
        requestHeaders: _headersJson(),
        sendData: body == null ? null : jsonEncode(body),
        withCredentials: true,
      );
      return res;
    } catch (e) {
      if (e is html.ProgressEvent) {
        final t = e.target;
        if (t is html.HttpRequest) {
          final st = t.status;
          final txt = t.responseText ?? '';
          final stx = t.statusText ?? '';
          throw 'HTTP $st $stx — ${txt.isEmpty ? "Request fehlgeschlagen" : txt}';
        }
      }
      throw e.toString();
    }
  }

  // ---- Generic POST JSON ----
  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final r = await _request('POST', path, body: body);
    if (r.status != 200 && r.status != 201) {
      throw 'HTTP ${r.status} ${r.statusText} — ${r.responseText ?? ''}';
    }
    final txt = r.responseText ?? '{}';
    return txt.trim().isEmpty ? <String, dynamic>{} : jsonDecode(txt);
  }

  // --- NEU: generische JSON-Wrapper passend zu postJson(...) ---
  Future<T> getJson<T>(String path) async {
    // Falls du bereits eine private Helper-Methode wie _json(method, path, body)
    // verwendest, kannst du hier darauf delegieren:
    try {
      // bevorzugt: gleiche Pipeline wie bei postJson (Auth-Header, Gate, Retry etc.)
      final dyn = this as dynamic;
      if (dyn._json != null) {
        return await dyn._json('GET', path, null) as T;
      }
    } catch (_) {}
    // Fallback: vorhandene low-level GET-Funktion nutzen (falls vorhanden)
    try {
      final dyn = this as dynamic;
      if (dyn.get != null) {
      final res = await dyn.get(path);
        return res as T;
      }
    } catch (_) {}
    throw StateError('getJson($path) ist nicht implementiert.');
  }

  Future<T> putJson<T>(String path, Object? body) async {
    // bevorzugt: gleiche Pipeline wie bei postJson
    try {
      final dyn = this as dynamic;
      if (dyn._json != null) {
        return await dyn._json('PUT', path, body) as T;
      }
    } catch (_) {}
    // Fallback: vorhandene low-level PUT-Funktion nutzen (falls vorhanden)
    try {
      final dyn = this as dynamic;
      if (dyn.put != null) {
        final res = await dyn.put(path, body: body);
        return res as T;
      }
    } catch (_) {}
    // Letzter Fallback: wenn postJson existiert UND Server PUT=POST akzeptiert (nicht schön, aber stabil)
    try {
      final dyn = this as dynamic;
      if (dyn.postJson != null) {
        final res = await dyn.postJson(path, body);
        return res as T;
      }
    } catch (_) {}
    throw StateError('putJson($path, ...) ist nicht implementiert.');
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
      final lsTok = html.window.localStorage['dfs_rep_token'];
      if (lsTok != null && lsTok.isNotEmpty) repToken = lsTok;
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

  Future<Map<String, dynamic>> setAppMeta({
    required String version,
    String? build,
    String? notes,
    bool? testMode,
    String? testEmail,
    List<String>? testPushTokens,
  }) async {
    final base = _apiBase.isEmpty ? '' : _apiBase;
    final uri = Uri.parse('$base/api/admin/meta');
    final body = jsonEncode({
      'version': version,
      if (build != null) 'build': build,
      if (notes != null) 'notes': notes,
      if (testMode != null) 'testMode': testMode,
      if (testEmail != null) 'testEmail': testEmail,
      if (testPushTokens != null) 'testPushTokens': testPushTokens,
    });

    final headers = {
      'Content-Type': 'application/json',
      if (adminSecret != null && adminSecret!.isNotEmpty) 'X-Admin-Secret': adminSecret!,
    };

    final r = await http.post(uri, headers: headers, body: body);
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }

    // Die API liefert die frisch gespeicherten Metadaten zurück – direkt
    // übernehmen, damit nach dem Speichern kein zweiter Fetch nötig ist.
    Map<String, dynamic> saved = {};
    try {
      final decoded = jsonDecode(r.body);
      if (decoded is Map && decoded['meta'] is Map<String, dynamic>) {
        saved = Map<String, dynamic>.from(decoded['meta'] as Map);
      }
    } catch (_) {}

    if (saved.isNotEmpty) {
      _appMeta = saved;
      _appMetaLoadedAt = DateTime.now();
      return saved;
    }

    _appMetaLoadedAt = null; // Cache invalidieren -> neu laden beim nächsten Zugriff
    return await getAppMeta(refresh: true) ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> repMe() async {
    final r = await _repFetch('/api/rep/me');
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/me failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    return (j is Map) ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<RepMe> repUpdateProfile({
    String? firstName,
    String? lastName,
    String? region,
    String? lang,
    String? country,
    String? countryCode,
  }) async {
    final body = <String, dynamic>{};
    if (firstName != null) body['firstName'] = firstName;
    if (lastName != null) body['lastName'] = lastName;
    if (region != null) body['region'] = region;
    if (lang != null) body['lang'] = lang;
    if (country != null) body['country'] = country;
    if (countryCode != null) body['countryCode'] = countryCode;

    final r = await _repFetch(
      '/api/rep/update',
      method: 'PUT',
      body: body,
    );
    if (!_ok2xx(r.statusCode)) {
      throw Exception('PUT /api/rep/update failed: ${r.statusCode} ${r.body}');
    }

    final raw = r.body.trim().isEmpty ? '{}' : r.body;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      if (decoded['rep'] is Map) {
        return RepMe.fromJson((decoded['rep'] as Map).cast<String, dynamic>());
      }
      return RepMe.fromJson(decoded);
    }
    if (decoded is Map) {
      return RepMe.fromJson(decoded.cast<String, dynamic>());
    }
    throw Exception('invalid response for /api/rep/update');
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

  Future<String> repUpdateCustomerNote({
    required String email,
    required String note,
  }) async {
    final target = Uri.encodeComponent(email.trim().toLowerCase());
    final r = await _repFetch(
      '/api/customers/$target',
      method: 'PATCH',
      body: {'repNote': note},
    );
    if (!_ok2xx(r.statusCode)) {
      throw Exception('PATCH /api/customers/$target failed: ${r.statusCode} ${r.body}');
    }
    final body = r.body.trim();
    if (body.isEmpty) return note;
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final map = decoded.cast<String, dynamic>();
      final value = map['repNote'];
      if (value is String) return value;
    }
    return note;
  }

  Future<dynamic> get(String path, {bool auth = false, Map<String, String>? extra}) async {
    final r = await _get(path, auth: auth, extra: extra);
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final body = r.body.trim();
    if (body.isEmpty) return null;
    return jsonDecode(body);
  }

  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    Map<String, String>? extra,
  }) async {
    final r = await http.put(
      _u(path),
      headers: _headers(auth: auth, extra: extra),
      body: jsonEncode(body ?? const <String, dynamic>{}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final text = r.body.trim();
    if (text.isEmpty) return null;
    return jsonDecode(text);
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
  Future<bool> gateUnlock(String password, {String? email, String? company}) async {
    final body = <String, String>{'password': password};
    final em = email?.trim();
    if (em != null && em.isNotEmpty) body['email'] = em;
    final co = company?.trim();
    if (co != null && co.isNotEmpty) body['company'] = co;
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

  Future<String?> gateRequestPassword(String email, {String? company}) async {
    final body = <String, String>{'email': email.trim()};
    final co = company?.trim();
    if (co != null && co.isNotEmpty) body['company'] = co;
    final r = await _post('/api/gate/request', body);
    if (_ok2xx(r.statusCode)) return null;
    try {
      final body = r.body;
      if (body.isNotEmpty) return body;
    } catch (_) {}
    return 'gate request failed: ${r.statusCode}';
  }

  // ---------- Auth (Kunden) ----------
  Future<LoginResult> login(String email, String password) async {
    try {
      final r = await _post('/api/auth/login', {'email': email, 'password': password});
      final status = r.statusCode;
      if (_ok2xx(status)) {
        final j = jsonDecode(r.body);
        if (j is Map && j['token'] is String) {
          token = j['token'] as String;
          _saveSession();
          return LoginResult.success();
        }
        return LoginResult.failure(message: 'unexpected response', statusCode: status);
      }

      final msg = _extractMessage(r.body);
      final revoked = status == 403 && msg.toLowerCase().contains('revoked');
      return LoginResult.failure(revoked: revoked, message: msg, statusCode: status);
    } catch (e) {
      return LoginResult.failure(message: e.toString());
    }
  }

  Future<SimpleResult> requestPasswordReset(String email) async {
    try {
      final r = await _post('/api/auth/reset-request', {'email': email.trim()});
      if (_ok2xx(r.statusCode)) {
        return SimpleResult(ok: true, statusCode: r.statusCode);
      }
      return SimpleResult.failure(r.statusCode, _extractMessage(r.body));
    } catch (e) {
      return SimpleResult.failure(500, e.toString());
    }
  }

  Future<SimpleResult> completePasswordReset(
    String email,
    String tempPassword,
    String newPassword,
  ) async {
    try {
      final r = await _post('/api/auth/reset-complete', {
        'email': email.trim(),
        'tempPassword': tempPassword,
        'newPassword': newPassword,
      });
      if (_ok2xx(r.statusCode)) {
        return SimpleResult(ok: true, statusCode: r.statusCode);
      }
      return SimpleResult.failure(r.statusCode, _extractMessage(r.body));
    } catch (e) {
      return SimpleResult.failure(500, e.toString());
    }
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

  Future<Map<String, dynamic>> accountExport() async {
    try {
      final r = await _get('/api/account_export', auth: true);
      if (!_ok2xx(r.statusCode)) {
        final msg = _extractMessage(r.body);
        throw ApiError(r.statusCode, msg);
      }
      final body = r.body.trim();
      if (body.isEmpty) return const <String, dynamic>{};
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) return j;
      if (j is Map) return j.cast<String, dynamic>();
      return const <String, dynamic>{};
    } catch (e) {
      if (e is ApiError) rethrow;
      throw ApiError(0, e.toString());
    }
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

  Future<void> sendRepContact(Map<String, dynamic> data) async {
    final r = await _post('/api/rep/contact', data, auth: true);
    if (!_ok2xx(r.statusCode)) {
      final msg = _extractMessage(r.body);
      throw ApiError(r.statusCode, msg);
    }
  }

  Future<void> repContactQM({
    required String subject,
    required String message,
  }) async {
    final r = await http.post(
      _u('/api/rep/contact-qm'),
      headers: _repHeaders(),
      body: jsonEncode({
        'subject': subject,
        'message': message,
      }),
    );

    if (!_ok2xx(r.statusCode)) {
      final msg = _extractMessage(r.body);
      throw ApiError(r.statusCode, msg);
    }
  }

  // ---------- Complaints ----------
  Future<Map<String, dynamic>?> complaintCreate(
    Map<String, dynamic> data, [
    List<({String name, List<int> bytes, String mime, String? preview})> files = const [],
  ]) async {
    final encFiles = files
        .map((f) => {
              'name': f.name,
              'mime': f.mime,
              'bytes': base64Encode(f.bytes),
              if ((f.preview ?? '').isNotEmpty) 'preview': f.preview,
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

  Future<Map<String, dynamic>> complaintUploadFiles(
    String ticket,
    List<({String name, List<int> bytes, String mime, String? preview})> files,
  ) async {
    if (ticket.trim().isEmpty) {
      throw ArgumentError('ticket required');
    }
    if (files.isEmpty) {
      return const <String, dynamic>{};
    }

    final encFiles = files
        .map((f) => {
              'name': f.name,
              'mime': f.mime,
              'bytes': base64Encode(f.bytes),
              if ((f.preview ?? '').isNotEmpty) 'preview': f.preview,
            })
        .toList(growable: false);

    final r = await _post('/api/complaint/$ticket', {
      'files': encFiles,
    }, auth: true);

    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }

    final body = r.body.trim().isEmpty ? '{}' : r.body;
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  Future<void> complaintContact({
    required String ticket,
    required String subject,
    required String message,
  }) async {
    final r = await _post(
      '/api/complaint/contact',
      {'ticket': ticket, 'subject': subject, 'message': message},
      auth: true,
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
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

  Future<Map<String, dynamic>> adminStats({DateTime? from, DateTime? to}) async {
    final params = <String, String>{};
    if (from != null) params['from'] = _formatDateOnly(from);
    if (to != null) params['to'] = _formatDateOnly(to);
    var path = '/api/admin/stats';
    if (params.isNotEmpty) {
      final query = params.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      path = '$path?$query';
    }
    final r = await http.get(_u(path), headers: _adminHeaders());
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final txt = r.body.trim();
    if (txt.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(txt);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> adminActivity({required String email, String kind = 'auto'}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return null;
    final params = <String, String>{'email': trimmed};
    final k = kind.trim().toLowerCase();
    if (k == 'customer' || k == 'rep') params['kind'] = k;
    final query = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final r = await http.get(_u('/api/admin/activity?$query'), headers: _adminHeaders());
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    if (r.body.trim().isEmpty) return null;
    final decoded = jsonDecode(r.body);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }

  Future<Map<String, Map<String, String>>> translateFaqDraft({
    required String sourceLang,
    required List<String> targetLangs,
    String? question,
    String? answer,
  }) async {
    final payload = <String, dynamic>{
      'sourceLang': sourceLang,
      'targets': targetLangs,
    };
    if (question != null && question.trim().isNotEmpty) payload['question'] = question.trim();
    if (answer != null && answer.trim().isNotEmpty) payload['answer'] = answer.trim();

    final r = await http.post(
      _u('/api/admin/translate'),
      headers: _adminHeaders(),
      body: jsonEncode(payload),
    );

    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }

    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final translations = <String, Map<String, String>>{};
    if (decoded is Map && decoded['translations'] is Map) {
      (decoded['translations'] as Map).forEach((key, value) {
        if (value is Map) {
          translations[key.toString()] = value.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
        }
      });
    }
    return translations;
  }

  // ---------- Vertreter (Kundenbereich) ----------
  Future<MyRep?> getMyRep() async {
    final base = _apiBase.isEmpty
        ? (html.window.localStorage['API_BASE'] ?? '')
        : _apiBase;

    // NEU: Kunden-Endpoint
    final url = '$base/api/rep/of-customer';

    final headers = <String, String>{ 'Content-Type': 'application/json' };
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token'; // Kunden-JWT!
    }

    final r = await http.get(Uri.parse(url), headers: headers);
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

  Future<void> repChangePassword(String newPw, {String? oldPw}) async {
    final r = await http.post(
      _u('/api/rep/password'),
      headers: _repHeaders(),
      body: jsonEncode({
        'new': newPw,
        if (oldPw != null && oldPw.isNotEmpty) ...{
          'old': oldPw,
          'current_password': oldPw,
        },
      }),
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

  Future<Map<String, dynamic>> repCreateCustomer(Map<String, dynamic> data) async {
    final r = await _repFetch(
      '/api/rep/customers',
      method: 'POST',
      body: {'action': 'create', ...data},
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final txt = r.body.trim();
    if (txt.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(txt);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{};
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
  
  // === Kataloge: GET ===
  Future<List<CatalogLink>> fetchCatalogLinks() async {
    final res = await get('/api/catalogs'); // passe Pfad ggf. an
    // Erwartet: { "items": [ {label, url, locales:[...]} ] }
    final items = (res['items'] as List?) ?? const [];
    return items.map((e) => CatalogLink.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  // === Kataloge: PUT (ersetzt Liste vollständig) ===
  Future<void> updateCatalogLinks(List<CatalogLink> links) async {
    await put('/api/catalogs', body: {
      'items': links.map((e) => e.toJson()).toList(),
    });
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
  final String country;
  final String countryCode;
  final String lang;
  final List<String> customers;
  const RepMe({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.region,
    required this.country,
    required this.countryCode,
    required this.lang,
    required this.customers,
  });

  factory RepMe.fromJson(Map<String,dynamic> j) => RepMe(
    id:       (j['id']        ?? '').toString(),
    firstName:(j['firstName'] ?? '').toString(),
    lastName: (j['lastName']  ?? '').toString(),
    email:    (j['email']     ?? '').toString(),
    region:   (j['region']    ?? '').toString(),
    country:  (j['country']   ?? '').toString(),
    countryCode: (j['countryCode'] ?? '').toString(),
    lang:     (j['lang']      ?? '').toString(),
    customers: (j['customers'] as List? ?? const []).cast<String>(),
  );
}
