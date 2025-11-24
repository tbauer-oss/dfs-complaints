// lib/api/client.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

// EIN einziger bedingter Import – nur für window.localStorage (Stub auf Mobile)
import 'package:dfs_mobile/web_compat/html_stub.dart'
  if (dart.library.html) 'package:dfs_mobile/web_compat/html_web.dart' as html;

import 'package:http/http.dart' as http;
import '../models/complaint.dart';
import '../models/customer_news_entry.dart';

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

String _formatDateOnly(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  final y = normalized.year.toString().padLeft(4, '0');
  final m = normalized.month.toString().padLeft(2, '0');
  final d = normalized.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

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
  bool _persistCustomerSession = true;
  bool _persistRepSession = true;
  bool _persistAdminSession = true;

  Future<void> _saveSession() async {
    final allowPushPersist =
        _persistCustomerSession || _persistRepSession || _persistAdminSession;

    if (kIsWeb) {
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

      if (allowPushPersist && pushDeviceToken != null && pushDeviceToken!.isNotEmpty) {
        ls['dfs_push_token'] = pushDeviceToken!;
      } else {
        ls.remove('dfs_push_token');
      }

      // Vertreter-E-Mail (nur als Hilfe für Secret-Login)
      if (_persistRepSession && _repEmail != null && _repEmail!.isNotEmpty) {
        ls['dfs_rep_email'] = _repEmail!;
      } else {
        ls.remove('dfs_rep_email');
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (_persistCustomerSession && token != null && token!.isNotEmpty) {
      await prefs.setString('dfs_token', token!);
    } else {
      await prefs.remove('dfs_token');
    }

    if (_persistAdminSession && adminSecret != null && adminSecret!.isNotEmpty) {
      await prefs.setString('dfs_admin', adminSecret!);
    } else {
      await prefs.remove('dfs_admin');
    }

    if (_persistCustomerSession && gate != null && gate!.isNotEmpty) {
      await prefs.setString('dfs_gate', gate!);
    } else {
      await prefs.remove('dfs_gate');
    }

    if (_persistRepSession && repToken != null && repToken!.isNotEmpty) {
      await prefs.setString('dfs_rep_token', repToken!);
    } else {
      await prefs.remove('dfs_rep_token');
    }

    if (allowPushPersist && pushDeviceToken != null && pushDeviceToken!.isNotEmpty) {
      await prefs.setString('dfs_push_token', pushDeviceToken!);
    } else {
      await prefs.remove('dfs_push_token');
    }

    if (_persistRepSession && _repEmail != null && _repEmail!.isNotEmpty) {
      await prefs.setString('dfs_rep_email', _repEmail!);
    } else {
      await prefs.remove('dfs_rep_email');
    }
  }

  Future<void> restoreSession() async {
    if (kIsWeb) {
      final ls = html.window.localStorage;
      token       = ls['dfs_token'];
      adminSecret = ls['dfs_admin'];
      gate        = ls['dfs_gate'];
      repToken    = ls['dfs_rep_token'];
      _repEmail   = ls['dfs_rep_email'];
      pushDeviceToken = ls['dfs_push_token'];

      _persistCustomerSession = (token ?? '').isNotEmpty || (gate ?? '').isNotEmpty;
      _persistAdminSession = (adminSecret ?? '').isNotEmpty;
      _persistRepSession = (repToken ?? '').isNotEmpty || (_repEmail ?? '').isNotEmpty;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    token       = prefs.getString('dfs_token');
    adminSecret = prefs.getString('dfs_admin');
    gate        = prefs.getString('dfs_gate');
    repToken    = prefs.getString('dfs_rep_token');
    _repEmail   = prefs.getString('dfs_rep_email');
    pushDeviceToken = prefs.getString('dfs_push_token');

    _persistCustomerSession = (token ?? '').isNotEmpty || (gate ?? '').isNotEmpty;
    _persistAdminSession = (adminSecret ?? '').isNotEmpty;
    _persistRepSession = (repToken ?? '').isNotEmpty || (_repEmail ?? '').isNotEmpty;
  }

  void setCustomerSessionPersistence(bool persist) {
    _persistCustomerSession = persist;
  }

  void setRepSessionPersistence(bool persist) {
    _persistRepSession = persist;
  }

  Future<void> logout() async {
    final tok = pushDeviceToken;
    if (tok != null && tok.isNotEmpty) {
      await unregisterPushToken(tok, silent: true);
    }
    token = null;
    adminSecret = null;
    gate = null;
    _persistCustomerSession = true;
    _persistAdminSession = true;
    _persistRepSession = true;
    pushDeviceToken = null;
    await _saveSession();
  }

  Future<void> setAdminSecret(String? s, {bool persist = true}) async {
    _persistAdminSession = persist && (s ?? '').trim().isNotEmpty;
    adminSecret = (s ?? '').trim().isEmpty ? null : s!.trim();
    await _saveSession();
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

  bool get hasPushAuth {
    final hasToken = (token ?? '').isNotEmpty;
    final hasRepToken = (repToken ?? '').isNotEmpty;
    final hasAdminSecret = (adminSecret ?? '').isNotEmpty;
    return hasToken || hasRepToken || hasAdminSecret;
  }

  Future<void> clearAdminSecret() async {
    adminSecret = null;
    _persistAdminSession = true;
    await _saveSession();
  }
  
  Future<void> clearGate() async {
    gate = null;
    await _saveSession();
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
  List<CustomerNewsEntry>? _newsCache;
  DateTime? _newsLoadedAt;
  static const Duration _newsCacheTtl = Duration(minutes: 1);

  void clearCustomerNewsCache() {
    _newsCache = null;
    _newsLoadedAt = null;
  }

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
          await _saveSession();
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
      await _saveSession();
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
    final decoded = jsonDecode(r.body);
    final List<CustomerNewsEntry> items = [];
    if (decoded is Map<String, dynamic>) {
      final rawList = decoded['items'];
      if (rawList is List) {
        for (final entry in rawList) {
          if (entry is Map<String, dynamic>) {
            items.add(CustomerNewsEntry.fromJson(entry));
          }
        }
      }
    }
    _newsCache = items;
    _newsLoadedAt = DateTime.now();
    return items;
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

  Future<Map<String, dynamic>> setAppMeta({
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

  Future<void> registerPushToken(
    String token, {
    String? platform,
    String? locale,
    String? lang,
    String? appVersion,
    String? appBuild,
    double? lat,
    double? lng,
    String? country,
    String? city,
    String? locationLabel,
  }) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    final headers = _pushAuthHeaders();
    final hasAuth = headers.containsKey('Authorization') || headers.containsKey('X-Admin-Secret');
    if (!hasAuth) {
      pushDeviceToken = trimmed;
      await _saveSession();
      return;
    }

    final body = <String, String>{'token': trimmed};
    if (platform != null && platform.trim().isNotEmpty) body['platform'] = platform.trim();
    if (locale != null && locale.trim().isNotEmpty) body['locale'] = locale.trim();
    if (lang != null && lang.trim().isNotEmpty) body['lang'] = lang.trim();
    if (appVersion != null && appVersion.trim().isNotEmpty) body['appVersion'] = appVersion.trim();
    if (appBuild != null && appBuild.trim().isNotEmpty) body['appBuild'] = appBuild.trim();
    if (lat != null) body['lat'] = lat.toString();
    if (lng != null) body['lng'] = lng.toString();
    if (country != null && country.trim().isNotEmpty) body['country'] = country.trim();
    if (city != null && city.trim().isNotEmpty) body['city'] = city.trim();
    if (locationLabel != null && locationLabel.trim().isNotEmpty) body['location'] = locationLabel.trim();

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
    await _saveSession();
  }

  Future<void> unregisterPushToken(String token, {bool silent = false}) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      if (pushDeviceToken != null) {
        pushDeviceToken = null;
        await _saveSession();
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
      await _saveSession();
    }
  }

  Future<void> _registerCachedPushTokenIfPossible() async {
    final cached = (pushDeviceToken ?? '').trim();
    if (cached.isEmpty) return;
    final headers = _pushAuthHeaders();
    final hasAuth = headers.containsKey('Authorization') || headers.containsKey('X-Admin-Secret');
    if (!hasAuth) return;
    try {
      await registerPushToken(cached);
    } catch (e) {
      debugPrint('[push] cached token registration failed: $e');
    }
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
        await _saveSession();
        return true;
      }
      if (j is Map && j['ok'] == true) {
        gate = 'ok';
        await _saveSession();
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
          await _saveSession();
          await _registerCachedPushTokenIfPossible();
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
      final txt = r.body.trim();
      if (txt.isEmpty) return const <String, dynamic>{};
      final j = jsonDecode(txt);
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
    final body = r.body.trim();
    if (body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return const <String, dynamic>{};
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
            await _saveSession();
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
      await _saveSession();
      await _registerCachedPushTokenIfPossible();

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
        await _saveSession();
        await _registerCachedPushTokenIfPossible();
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
      await _saveSession();
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
            await _saveSession();
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
    await _saveSession();
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
