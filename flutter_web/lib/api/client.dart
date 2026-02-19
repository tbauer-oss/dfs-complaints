// lib/api/client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/complaint.dart';
import '../models/catalog_link.dart';
import '../models/customer_news_entry.dart';
import '../models/faq.dart';
import '../models/wiki_article.dart';
import '../models/wiki_category.dart';
import '../models/wiki_overview.dart';
import '../models/rep_download_item.dart';
import '../models/download_category.dart';
import '../models/admin_rep_summary.dart';
import '../models/capa_report.dart';
import '../models/change_management.dart';
import '../models/portal_user.dart';
import '../models/fmea.dart';
import '../models/supplier_evaluation.dart';
import '../models/training.dart';
import '../models/training_signature.dart';
import '../models/gspr.dart';
import '../models/td.dart';
import 'config.dart';

class ApiError implements Exception {
  final int status;
  final String message;
  final List<String> details;
  ApiError(this.status, this.message, [List<String>? details])
      : details = List.unmodifiable(details ?? const []);
  @override
  String toString() =>
      details.isNotEmpty ? 'HTTP $status: $message (${details.join('; ')})' : 'HTTP $status: $message';
}

class LoginResult {
  final bool ok;
  final bool revoked;
  final String? message;
  final int? statusCode;
  final String? errorCode;

  const LoginResult({
    required this.ok,
    this.revoked = false,
    this.message,
    this.statusCode,
    this.errorCode,
  });

  factory LoginResult.success() => const LoginResult(ok: true);

  factory LoginResult.failure({
    bool revoked = false,
    String? message,
    int? statusCode,
    String? errorCode,
  }) =>
      LoginResult(
        ok: false,
        revoked: revoked,
        message: message,
        statusCode: statusCode,
        errorCode: errorCode,
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

  String? token;            // JWT (Kundenportal)
  String? gate;             // optionales Gate-Token
  String? adminSecret;      // für X-Admin-Secret (Legacy)
  String? repToken;         // JWT für Vertreter-Login
  String? portalToken;      // JWT für DFS Portal
  Map<String, dynamic>? portalProfile; // Rolle & Status fürs DFS Portal

  // Merker für Vertreter-Login-Flow
  String? _repEmail;    // zuletzt geprüfte/benutzte Vertreter-E-Mail

  bool _persistCustomerSession = true;
  bool _persistRepSession = true;
  bool _persistAdminSession = true;
  bool _persistPortalSession = true;

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

    // DFS Portal Session
    if (_persistPortalSession && portalToken != null) {
      ls['dfs_portal_token'] = portalToken!;
      if (portalProfile != null) {
        ls['dfs_portal_profile'] = jsonEncode(portalProfile);
      }
    } else {
      ls.remove('dfs_portal_token');
      ls.remove('dfs_portal_profile');
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
    portalToken = ls['dfs_portal_token'];
    final storedProfile = ls['dfs_portal_profile'];
    if (storedProfile != null && storedProfile.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedProfile);
        if (decoded is Map) portalProfile = decoded.cast<String, dynamic>();
      } catch (_) {}
    }

    _persistCustomerSession = (token ?? '').isNotEmpty || (gate ?? '').isNotEmpty;
    _persistAdminSession = (adminSecret ?? '').isNotEmpty;
    _persistPortalSession = (portalToken ?? '').isNotEmpty;
    _persistRepSession = (repToken ?? '').isNotEmpty || (_repEmail ?? '').isNotEmpty;
  }

  Future<void> logout() async {
    token = null;
    adminSecret = null;
    gate = null;
    portalToken = null;
    portalProfile = null;
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

  void setPortalSession({
    required String token,
    required Map<String, dynamic> profile,
    bool persist = true,
  }) {
    portalToken = token.trim();
    portalProfile = profile;
    _persistPortalSession = persist && portalToken!.isNotEmpty;
    _saveSession();
  }

  void clearPortalSession() {
    portalToken = null;
    portalProfile = null;
    _persistPortalSession = false;
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
      if (auth && token != null && token!.isNotEmpty)
        'Authorization': 'Bearer $token'
      else if (auth && (token == null || token!.isEmpty) && portalToken != null && portalToken!.isNotEmpty)
        'Authorization': 'Bearer $portalToken',
      };
    if (extra != null) h.addAll(extra);
    return h;
  }
  
  Map<String, dynamic>? _appMeta;
  DateTime? _appMetaLoadedAt;
  List<CustomerNewsEntry>? _newsCache;
  DateTime? _newsLoadedAt;
  static const Duration _newsCacheTtl = Duration(minutes: 1);
  List<CustomerNewsEntry>? _portalNewsCache;
  DateTime? _portalNewsLoadedAt;
  static const Duration _portalNewsCacheTtl = Duration(minutes: 1);
  FaqData? _faqCache;
  DateTime? _faqLoadedAt;
  static const Duration _faqCacheTtl = Duration(minutes: 1);

  void _invalidateNewsCache() {
    _newsCache = null;
    _newsLoadedAt = null;
  }

  void clearCustomerNewsCache() => _invalidateNewsCache();
  void clearPortalNewsCache() {
    _portalNewsCache = null;
    _portalNewsLoadedAt = null;
  }

  void clearAllNewsCaches() {
    clearCustomerNewsCache();
    clearPortalNewsCache();
  }

  Map<String, dynamic>? get appMeta => _appMeta;
  String get appVersion => _appMeta?['version']?.toString() ?? '';

  Map<String, String> _adminHeaders({bool auth = false, Map<String, String>? extra, String? path}) {
    final h = _headers(auth: false, extra: extra);
    String? authSource;
    if (auth) {
      if (portalToken != null && portalToken!.isNotEmpty) {
        h['Authorization'] = 'Bearer $portalToken';
        authSource = 'portal';
      } else if (adminSecret != null && adminSecret!.isNotEmpty) {
        h['X-Admin-Secret'] = adminSecret!; // Legacy Fallback
        authSource = 'admin-secret';
      } else if (repToken != null && repToken!.isNotEmpty) {
        h['Authorization'] = 'Bearer $repToken';
        authSource = 'rep';
      } else if (token != null && token!.isNotEmpty) {
        h['Authorization'] = 'Bearer $token';
        authSource = 'customer';
      }
    }
    if (kDebugMode && path != null) {
      final lower = path.toLowerCase();
      if (lower.startsWith('/api/admin') || lower.startsWith('/api/chat')) {
        debugPrint('API auth [$path]: ${authSource ?? 'none'}');
      }
    }
    return h;
  }

  void _logSupplierRequest(String method, String endpoint, String supplierId, int statusCode) {
    if (kDebugMode) {
      debugPrint('Supplier API: $method $endpoint (supplierId: $supplierId) -> $statusCode');
    }
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

  /// Öffentlicher Helfer zum Bauen einer URI mit Query-Parametern.
  Uri buildUri(String path, {Map<String, dynamic>? query}) {
    final uri = _u(path);
    if (query == null || query.isEmpty) return uri;
    final qp = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      qp[key] = value.toString();
    });
    return uri.replace(queryParameters: qp);
  }

  /// Auth-Header für DFS-Portal-Aufrufe (inkl. JWT / Admin-Secret Fallback).
  Map<String, String> portalHeaders() => _adminHeaders(auth: true);
  Map<String, String> portalHeadersFor(String path) => _adminHeaders(auth: true, path: path);

  void assertSuccess(http.Response response) {
    if (_ok2xx(response.statusCode)) return;
    throw ApiError(response.statusCode, _extractMessage(response.body));
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

  Future<List<CustomerNewsEntry>> fetchPortalNews({bool refresh = false}) async {
    final cacheValid =
        _portalNewsCache != null && _portalNewsLoadedAt != null &&
        DateTime.now().difference(_portalNewsLoadedAt!) < _portalNewsCacheTtl;
    if (!refresh && cacheValid) return _portalNewsCache!;

    final headers = {
      'Content-Type': 'application/json',
      if (portalToken != null && portalToken!.isNotEmpty) 'Authorization': 'Bearer ${portalToken!}',
    };

    final r = await http.get(
      _u('/api/portal/news'),
      headers: headers,
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
    _portalNewsCache = items;
    _portalNewsLoadedAt = DateTime.now();
    return items;
  }

  Future<void> acknowledgePortalNews(String id) async {
    final headers = {
      'Content-Type': 'application/json',
      if (portalToken != null && portalToken!.isNotEmpty) 'Authorization': 'Bearer ${portalToken!}',
    };

    final r = await http.post(
      _u('/api/portal/news/ack'),
      headers: headers,
      body: jsonEncode({'id': id}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    clearPortalNewsCache();
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
    try {
      final ls = html.window.localStorage['API_BASE'] ?? '';
      if (ls.trim().isNotEmpty) return ls.trim();
    } catch (_) {}
    final origin = html.window.location.origin;
    if (origin == 'https://dfs-complaints-web.vercel.app') {
      return 'https://dfs-complaints-backend.vercel.app';
    }
    return origin;
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

  Future<html.HttpRequest> _requestWithProgress(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    void Function(int sent, int total)? onProgress,
  }) async {
    final payload = body == null ? null : jsonEncode(body);
    try {
      final req = html.HttpRequest();
      req
        ..open(method, _u(path).toString())
        ..withCredentials = true;
      (headers ?? _headersJson()).forEach(req.setRequestHeader);
      if (onProgress != null) {
        final totalBytes = payload == null ? 0 : utf8.encode(payload).length;
        req.upload.onProgress.listen((event) {
          final total = event.total ?? 0;
          final loaded = event.loaded ?? 0;
          onProgress(loaded, total > 0 ? total : totalBytes);
        });
      }
      final completer = Completer<html.HttpRequest>();
      req.onLoad.listen((_) => completer.complete(req));
      req.onError.listen((event) => completer.completeError(event));
      req.send(payload);
      return await completer.future;
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
    final uri = _u('/api/admin/meta');
    final body = jsonEncode({
      'version': version,
      if (build != null) 'build': build,
      if (notes != null) 'notes': notes,
      if (testMode != null) 'testMode': testMode,
      if (testEmail != null) 'testEmail': testEmail,
      if (testPushTokens != null) 'testPushTokens': testPushTokens,
    });

    final r = await http.post(
      uri,
      headers: _adminHeaders(auth: true),
      body: body,
    );
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

  Future<List<RepDownloadItem>> repDownloads() async {
    final r = await _repFetch('/api/rep/downloads');
    if (!_ok2xx(r.statusCode)) {
      throw Exception('GET /api/rep/downloads failed: ${r.statusCode} ${r.body}');
    }
    final body = r.body.trim();
    if (body.isEmpty) return const <RepDownloadItem>[];
    final decoded = jsonDecode(body);
    final list = decoded is Map && decoded['items'] is List
        ? decoded['items'] as List
        : decoded is List
            ? decoded
            : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => RepDownloadItem.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> repMarkDownloadSeen(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    try {
      await _repFetch(
        '/api/rep/downloads/seen',
        method: 'POST',
        body: {'id': trimmed},
      );
    } catch (_) {}
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
    final gateToken = gate?.trim();
    final r = await _post(
      '/api/auth/register',
      data,
      extraHeaders: gateToken == null || gateToken.isEmpty ? null : {'X-Gate': gateToken},
    );
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
    String? repEmail,
    String? repFirstName,
    String? repLastName,
    String? repRegion,
  }) async {
    final payload = <String, dynamic>{
      'subject': subject,
      'message': message,
    };

    void addIfPresent(String key, String? value) {
      final v = value?.trim() ?? '';
      if (v.isNotEmpty) payload[key] = v;
    }

    addIfPresent('email', repEmail);
    addIfPresent('firstName', repFirstName);
    addIfPresent('lastName', repLastName);
    addIfPresent('region', repRegion);

    final r = await http.post(
      _u('/api/rep/contact-qm'),
      headers: _repHeaders(),
      body: jsonEncode(payload),
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

  Future<Map<String, dynamic>> updateComplaintDetails({
    required String ticket,
    required Map<String, String> payload,
  }) async {
    final r = await http.post(
      _u('/api/admin/complaints'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({
        'ticket': ticket,
        'payload': payload,
      }),
    );

    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }

    final decoded = (r.body.trim().isEmpty) ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw ApiError(500, 'Ungültige Antwort für Reklamations-Update');
  }

  Future<List<Complaint>> adminComplaints({bool details = false, bool openOnly = false}) async {
    final params = <String, String>{};
    if (details) params['details'] = '1';
    if (openOnly) params['open'] = '1';
    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final r = await http.get(
      _u('/api/admin/complaints$query'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <dynamic>[] : jsonDecode(r.body);
    final list = decoded is List
        ? decoded
        : decoded is Map && decoded['items'] is List
            ? decoded['items'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => Complaint.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
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

  // ---------- DFS Portal Login (E-Mail + Passwort) ----------
  Future<LoginResult> portalLogin({
    required String email,
    required String password,
    bool persist = true,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final body = {'email': normalizedEmail, 'password': password};
    try {
      final r = await http.post(
        _u('/api/portal/login'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(body),
      );
      if (!_ok2xx(r.statusCode)) {
        String? code;
        try {
          final decoded = jsonDecode(r.body);
          if (decoded is Map && decoded['code'] is String) {
            code = decoded['code'] as String;
          }
        } catch (_) {}
        return LoginResult.failure(
          statusCode: r.statusCode,
          message: _extractMessage(r.body),
          errorCode: code,
        );
      }

      final decoded = jsonDecode(r.body);
      if (decoded is Map) {
        final tok = (decoded['token'] ?? '').toString();
        final profile = (decoded['profile'] is Map)
            ? (decoded['profile'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        final backendTourSeen = decoded['tourSeen'] == true || profile['tourSeen'] == true;
        profile['tourSeen'] = backendTourSeen;
        if (tok.isNotEmpty) {
          setPortalSession(token: tok, profile: profile, persist: persist);
          return LoginResult.success();
        }
      }
    } catch (_) {}
    return LoginResult.failure(statusCode: 0, message: 'Login fehlgeschlagen');
  }


  Future<SimpleResult> markPortalTourSeen({bool seen = true}) async {
    try {
      final r = await _post('/api/portal/tour/seen', {'seen': seen}, auth: true);
      if (_ok2xx(r.statusCode)) {
        if (portalProfile != null) {
          portalProfile = {...portalProfile!, 'tourSeen': seen};
          _saveSession();
        }
        return SimpleResult(ok: true, statusCode: r.statusCode);
      }
      return SimpleResult.failure(r.statusCode, _extractMessage(r.body));
    } catch (e) {
      return SimpleResult.failure(500, e.toString());
    }
  }

  Future<Map<String, dynamic>?> refreshPortalProfile() async {
    if (portalToken == null || portalToken!.isEmpty) return null;
    final r = await _get('/api/me/permissions', auth: true);
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map) return null;
    final profileRaw = decoded['profile'];
    if (profileRaw is! Map) return null;
    final profile = profileRaw.cast<String, dynamic>();
    final enriched = <String, dynamic>{...profile};
    if (decoded['permissions'] is Map) {
      enriched['permissions'] = (decoded['permissions'] as Map).cast<String, dynamic>();
    }
    if (decoded['tileGrants'] is List) {
      enriched['tileGrants'] = (decoded['tileGrants'] as List).whereType<String>().toList();
    }
    portalProfile = enriched;
    _saveSession();
    return portalProfile;
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
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final txt = r.body.trim();
    if (txt.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(txt);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> adminCapaDashboard() async {
    final r = await http.get(_u('/api/capa/dashboard'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final txt = r.body.trim();
    if (txt.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(txt);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> adminTrainingDashboardMetrics() async {
    final r = await http.get(_u('/api/training/dashboard-metrics'), headers: _adminHeaders(auth: true));
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
    final r = await http.get(_u('/api/admin/activity?$query'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    if (r.body.trim().isEmpty) return null;
    final decoded = jsonDecode(r.body);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }

  Future<List<RepDownloadItem>> adminDownloads() async {
    const path = '/api/admin/downloads';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['items'] is List
        ? decoded['items'] as List
        : decoded is List
            ? decoded
            : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => RepDownloadItem.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<CustomerNewsEntry>> adminFetchCustomerNewsEntries() async {
    const path = '/api/news';
    final r = await http.get(
      buildUri(path, query: const {'includeDrafts': '1'}),
      headers: _adminHeaders(auth: true, path: path),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final txt = r.body.trim();
    dynamic data = txt.isEmpty ? const {} : jsonDecode(txt);
    if (data is Map && data['items'] is List) {
      data = data['items'];
    }
    final list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map((e) => CustomerNewsEntry.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<CustomerNewsEntry>> adminFetchPortalNewsEntries() async {
    const path = '/api/portal/admin/news';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final txt = r.body.trim();
    dynamic data = txt.isEmpty ? const {} : jsonDecode(txt);
    if (data is Map && data['items'] is List) {
      data = data['items'];
    }
    final list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map((e) => CustomerNewsEntry.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<RepDownloadItem> adminSaveDownload({
    String? id,
    required String title,
    String? description,
    String? category,
    String? badge,
    String? language,
    bool? active,
    Map<String, dynamic>? file,
    List<String>? allowedRepresentatives,
    void Function(int sent, int total)? onProgress,
  }) async {
    final body = <String, dynamic>{
      if (id != null) 'id': id,
      'title': title,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (badge != null) 'badge': badge,
      if (language != null) 'language': language,
      if (active != null) 'active': active,
      if (file != null) 'files': [file],
      if (allowedRepresentatives != null) 'allowedRepresentatives': allowedRepresentatives,
    };
    if (onProgress != null) {
      final res = await _requestWithProgress(
        'POST',
        '/api/admin/downloads',
        body: body,
        headers: _adminHeaders(auth: true, path: '/api/admin/downloads'),
        onProgress: onProgress,
      );
      final status = res.status ?? 0;
      if (status != 200 && status != 201) {
        throw ApiError(status, _extractMessage(res.responseText ?? ''));
      }
      final decoded = jsonDecode(res.responseText ?? '{}');
      if (decoded is Map) return RepDownloadItem.fromJson(decoded.cast<String, dynamic>());
      throw ApiError(status, 'invalid response for admin download save');
    }
    final r = await http.post(
      _u('/api/admin/downloads'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(body),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map) return RepDownloadItem.fromJson(decoded.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'invalid response for admin download save');
  }

  Future<List<AdminRepSummary>> adminRepSummaries() async {
    final r = await http.get(_u('/api/admin/reps'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <dynamic>[] : jsonDecode(r.body);
    final list = decoded is List ? decoded : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => AdminRepSummary.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> adminDeleteDownload(String id) async {
    final r = await http.delete(
      _u('/api/admin/downloads'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'id': id}),
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<DownloadCategory>> adminDownloadCategories() async {
    final r = await http.get(_u('/api/admin/download-categories'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['items'] is List ? decoded['items'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => DownloadCategory.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<DownloadCategory>> adminAddDownloadCategory(String name) async {
    final r = await http.post(
      _u('/api/admin/download-categories'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'name': name}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['items'] is List ? decoded['items'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => DownloadCategory.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<CapaReport>> adminCapas() async {
    const path = '/api/admin/capas';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map && decoded['list'] is List) {
      return (decoded['list'] as List)
          .whereType<Map>()
          .map((e) => CapaReport.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    if (decoded is List) {
      return decoded.whereType<Map>().map((e) => CapaReport.fromJson(e.cast<String, dynamic>())).toList();
    }
    return const [];
  }

  Future<List<PortalUserSummary>> fetchPortalUsers() async {
    final r = await http.get(_u('/api/portal/users'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => PortalUserSummary.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }
    throw ApiError(r.statusCode, 'Ungültige Antwort für Portal-User');
  }

  Future<List<PortalUserSummary>> adminStaffUsers({bool includeInactive = false}) async {
    final r = await http.get(
      _u('/api/admin/users?scope=staff&includeInactive=${includeInactive ? 'true' : 'false'}'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['users'] is List ? decoded['users'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => PortalUserSummary.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<CapaReport> adminSaveCapa(CapaReport report) async {
    final r = await http.post(
      _u('/api/admin/capas'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(report.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map && decoded['report'] is Map) {
      return CapaReport.fromJson((decoded['report'] as Map).cast<String, dynamic>());
    }
    if (decoded is Map) return CapaReport.fromJson(decoded.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'invalid response for CAPA save');
  }

  Future<CapaReport> adminUpdateCapa(CapaReport report) async {
    final payload = report.toJson();
    final r = await http.patch(
      _u('/api/admin/capas'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(payload),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map && decoded['report'] is Map) {
      return CapaReport.fromJson((decoded['report'] as Map).cast<String, dynamic>());
    }
    if (decoded is Map) return CapaReport.fromJson(decoded.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'invalid response for CAPA update');
  }

  Future<void> adminDeleteCapa(String id) async {
    final path = Uri(path: '/api/admin/capas', queryParameters: {'id': id}).toString();
    final r = await http.delete(
      _u(path),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<Uint8List> adminCapaPdf({required String id, String lang = 'de'}) async {
    final query = Uri(queryParameters: {'id': id, 'lang': lang}).query;
    final path = '/api/admin/capa-pdf${query.isEmpty ? '' : '?$query'}';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    return r.bodyBytes;
  }

  // ---------- Admin: Change Management ----------
  Future<List<ChangeManagementRecord>> adminChanges() async {
    final r = await http.get(_u('/api/admin/changes'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['list'] is List
        ? decoded['list'] as List
        : decoded is List
            ? decoded
            : <dynamic>[];
    final records = list
        .whereType<Map>()
        .map((e) => ChangeManagementRecord.fromJson(e.cast<String, dynamic>()))
        .toList();
    records.sort((a, b) => (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return records;
  }

  Future<Map<String, dynamic>> adminChangeSummary() async {
    final r = await http.get(_u('/api/admin/changes?summary=1'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map && decoded['summary'] is Map) {
      return (decoded['summary'] as Map).cast<String, dynamic>();
    }
    return const {};
  }

  Future<ChangeManagementRecord> adminSaveChange(ChangeManagementRecord record) async {
    final r = await http.post(
      _u('/api/admin/changes'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(record.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map && decoded['record'] is Map) {
      return ChangeManagementRecord.fromJson((decoded['record'] as Map).cast<String, dynamic>());
    }
    if (decoded is Map) return ChangeManagementRecord.fromJson(decoded.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'invalid response for change save');
  }

  Future<ChangeManagementRecord> adminUpdateChange(ChangeManagementRecord record) async {
    final r = await http.patch(
      _u('/api/admin/changes'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(record.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map && decoded['record'] is Map) {
      return ChangeManagementRecord.fromJson((decoded['record'] as Map).cast<String, dynamic>());
    }
    if (decoded is Map) return ChangeManagementRecord.fromJson(decoded.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'invalid response for change update');
  }

  Future<ChangeManagementRecord> adminChange(String idOrNumber) async {
    final r = await http.get(_u('/api/admin/changes?id=$idOrNumber'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map && decoded['record'] is Map) {
      return ChangeManagementRecord.fromJson((decoded['record'] as Map).cast<String, dynamic>());
    }
    if (decoded is Map) return ChangeManagementRecord.fromJson(decoded.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'invalid response for change lookup');
  }

  Future<void> adminDeleteChange(String id) async {
    final r = await http.delete(
      _u('/api/admin/changes?id=$id'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  // ---------- Admin: FMEA (Liste & Risiken) ----------
  Future<List<FmeaRecord>> adminFmeas() async {
    final r = await http.get(_u('/api/admin/fmeas'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['list'] is List
        ? decoded['list'] as List
        : decoded is List
            ? decoded
            : <dynamic>[];
    final records = list
        .whereType<Map>()
        .map((e) => FmeaRecord.fromJson(e.cast<String, dynamic>()))
        .toList();
    records.sort(FmeaRecord.sortByUpdatedDesc());
    return records;
  }

  Future<FmeaRecord> adminFetchFmea(String id) async {
    final uri = Uri(path: '/api/admin/fmeas', queryParameters: {'id': id}).toString();
    final r = await http.get(_u(uri), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['fmea'] is Map ? decoded['fmea'] as Map : decoded;
    if (map is Map) return FmeaRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige FMEA-Antwort');
  }

  Future<FmeaRecord> adminCreateFmea(FmeaRecord fmea) async {
    final r = await http.post(
      _u('/api/admin/fmeas'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(fmea.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['fmea'] is Map ? decoded['fmea'] as Map : decoded;
    if (map is Map) return FmeaRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige FMEA-Antwort');
  }

  Future<FmeaRecord> adminUpdateFmea(FmeaRecord fmea) async {
    final r = await http.patch(
      _u('/api/admin/fmeas'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(fmea.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['fmea'] is Map ? decoded['fmea'] as Map : decoded;
    if (map is Map) return FmeaRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige FMEA-Antwort');
  }

  Future<void> adminDeleteFmea(String id) async {
    final path = Uri(path: '/api/admin/fmeas', queryParameters: {'id': id}).toString();
    final r = await http.delete(
      _u(path),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<FmeaRiskEntry> adminAddFmeaRisk({required String fmeaId, required FmeaRiskEntry risk}) async {
    final r = await http.post(
      _u('/api/admin/fmea-risks'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'fmeaId': fmeaId, 'risk': risk.toJson()}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['risk'] is Map ? decoded['risk'] as Map : decoded;
    if (map is Map) return FmeaRiskEntry.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige FMEA-Risiko-Antwort');
  }

  Future<List<Map<String, dynamic>>> adminFmeaLinks() async {
    final r = await http.get(_u('/api/admin/fmea-links'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map && decoded['links'] is List) {
      return (decoded['links'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  Future<Uint8List> adminFmeaPdf(String id) async {
    final path = Uri(path: '/api/admin/fmea-export', queryParameters: {'id': id, 'format': 'pdf'}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    return r.bodyBytes;
  }

  Future<String> adminFmeaCsv(String id) async {
    final path = Uri(path: '/api/admin/fmea-export', queryParameters: {'id': id, 'format': 'csv'}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    return r.body;
  }

  Future<List<Supplier>> adminSuppliers() async {
    final r = await http.get(_u('/api/admin/suppliers'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map && decoded['list'] is List) {
      return (decoded['list'] as List)
          .whereType<Map>()
          .map((e) => Supplier.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return const [];
  }

  Future<SupplierLookups> adminSupplierLookups() async {
    final r = await http.get(_u('/api/admin/supplier-lookups'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['lookups'] is Map ? decoded['lookups'] as Map : decoded;
    if (map is Map) return SupplierLookups.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Lookup-Antwort');
  }

  Future<SupplierLookups> adminUpdateSupplierLookups(SupplierLookups lookups) async {
    final r = await http.patch(
      _u('/api/admin/supplier-lookups'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(lookups.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['lookups'] is Map ? decoded['lookups'] as Map : decoded;
    if (map is Map) return SupplierLookups.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Lookup-Antwort');
  }

  Future<Supplier> adminCreateSupplier(Supplier supplier) async {
    final r = await http.post(
      _u('/api/admin/suppliers'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(supplier.toJson()),
    );
    _logSupplierRequest('POST', '/api/admin/suppliers', supplier.id, r.statusCode);
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['supplier'] is Map ? decoded['supplier'] as Map : decoded;
    if (map is Map) return Supplier.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Lieferanten-Antwort');
  }

  Future<Supplier> adminUpdateSupplier(Supplier supplier, {String? changeReason}) async {
    final payload = supplier.toJson();
    if (changeReason != null && changeReason.trim().isNotEmpty) payload['changeReason'] = changeReason.trim();
    final path = Uri(path: '/api/admin/suppliers', queryParameters: {'id': supplier.id}).toString();
    final r = await http.patch(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(payload),
    );
    _logSupplierRequest('PATCH', '/api/admin/suppliers', supplier.id, r.statusCode);
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['supplier'] is Map ? decoded['supplier'] as Map : decoded;
    if (map is Map) return Supplier.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Lieferanten-Antwort');
  }

  Future<Supplier?> adminDeleteSupplier(String id) async {
    final path = Uri(path: '/api/admin/suppliers', queryParameters: {'id': id}).toString();
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true));
    _logSupplierRequest('DELETE', '/api/admin/suppliers', id, r.statusCode);
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['supplier'] is Map ? decoded['supplier'] as Map : null;
    if (map != null) {
      return Supplier.fromJson(map.cast<String, dynamic>());
    }
    return null;
  }

  Future<List<SupplierPerformanceEntry>> adminSupplierPerformance({String? supplierId, bool includeDeleted = false}) async {
    final queryParameters = <String, String>{
      if (supplierId != null) 'supplierId': supplierId,
      if (includeDeleted) 'includeDeleted': 'true',
    };
    final path = Uri(path: '/api/admin/supplier-performance', queryParameters: queryParameters).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map && decoded['list'] is List) {
      return (decoded['list'] as List)
          .whereType<Map>()
          .map((e) => SupplierPerformanceEntry.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return const [];
  }

  Future<SupplierPerformanceEntry> adminCreateSupplierPerformance(SupplierPerformanceEntry entry) async {
    final r = await http.post(
      _u('/api/admin/supplier-performance'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(entry.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['entry'] is Map ? decoded['entry'] as Map : decoded;
    if (map is Map) return SupplierPerformanceEntry.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Performance-Antwort');
  }

  Future<SupplierPerformanceEntry> adminUpdateSupplierPerformance(SupplierPerformanceEntry entry, {String? changeReason}) async {
    final payload = entry.toJson();
    if (changeReason != null && changeReason.trim().isNotEmpty) payload['changeReason'] = changeReason.trim();
    final path = Uri(path: '/api/admin/supplier-performance', queryParameters: {'id': entry.id}).toString();
    final r = await http.patch(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(payload),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['entry'] is Map ? decoded['entry'] as Map : decoded;
    if (map is Map) return SupplierPerformanceEntry.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Performance-Antwort');
  }

  Future<void> adminDeleteSupplierPerformance(String id, {String? deleteReason}) async {
    final path = Uri(path: '/api/admin/supplier-performance', queryParameters: {'id': id}).toString();
    final r = await http.delete(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: deleteReason != null ? jsonEncode({'deleteReason': deleteReason}) : null,
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<SupplierAnnualEvaluation>> adminSupplierEvaluations({String? supplierId}) async {
    final path = Uri(path: '/api/admin/supplier-evaluations', queryParameters: supplierId != null ? {'supplierId': supplierId} : {}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    if (decoded is Map && decoded['list'] is List) {
      return (decoded['list'] as List)
          .whereType<Map>()
          .map((e) => SupplierAnnualEvaluation.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return const [];
  }

  Future<List<ApprovedSupplier>> adminApprovedSuppliers({int? year}) async {
    final path = Uri(
      path: '/api/admin/approved-suppliers',
      queryParameters: year != null ? {'year': year.toString()} : {},
    ).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    if (decoded is Map && decoded['list'] is List) {
      return (decoded['list'] as List)
          .whereType<Map>()
          .map((e) => ApprovedSupplier.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return const [];
  }

  Future<ApprovedSupplier> adminRecomputeApprovedSupplier({
    required String supplierId,
    required int year,
    String? adminNote,
    bool reviewedByPurchasing = false,
  }) async {
    final payload = jsonEncode({
      'supplierId': supplierId,
      'year': year,
      if (adminNote != null) 'adminNote': adminNote,
      if (reviewedByPurchasing) 'reviewedByPurchasing': true,
    });
    final r = await http.post(
      _u('/api/admin/approved-suppliers/recompute'),
      headers: _adminHeaders(auth: true),
      body: payload,
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final supplier = decoded is Map ? decoded['supplier'] : null;
    if (supplier is Map) return ApprovedSupplier.fromJson(supplier.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Zulassungsliste-Antwort');
  }

  Future<SupplierAnnualEvaluation> adminCreateSupplierEvaluation(SupplierAnnualEvaluation evaluation) async {
    final r = await http.post(
      _u('/api/admin/supplier-evaluations'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(evaluation.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['evaluation'] is Map ? decoded['evaluation'] as Map : decoded;
    if (map is Map) return SupplierAnnualEvaluation.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Bewertungs-Antwort');
  }

  Future<SupplierAnnualEvaluation> adminUpdateSupplierEvaluation(SupplierAnnualEvaluation evaluation, {String? changeReason}) async {
    final payload = evaluation.toJson();
    if (changeReason != null && changeReason.trim().isNotEmpty) payload['changeReason'] = changeReason.trim();
    final path = Uri(path: '/api/admin/supplier-evaluations', queryParameters: {'id': evaluation.id}).toString();
    final r = await http.patch(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(payload),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['evaluation'] is Map ? decoded['evaluation'] as Map : decoded;
    if (map is Map) return SupplierAnnualEvaluation.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Bewertungs-Antwort');
  }

  Future<void> adminDeleteSupplierEvaluation(String id, {String? cancelReason}) async {
    final path = Uri(path: '/api/admin/supplier-evaluations', queryParameters: {'id': id}).toString();
    final r = await http.delete(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: cancelReason != null ? jsonEncode({'cancelReason': cancelReason}) : null,
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<SupplierEscalation>> adminSupplierEscalations({String? supplierId}) async {
    final path = Uri(path: '/api/admin/supplier-escalations', queryParameters: supplierId != null ? {'supplierId': supplierId} : {}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    if (decoded is Map && decoded['list'] is List) {
      return (decoded['list'] as List)
          .whereType<Map>()
          .map((e) => SupplierEscalation.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return const [];
  }

  Future<SupplierEscalation> adminCreateSupplierEscalation(SupplierEscalation escalation) async {
    final r = await http.post(
      _u('/api/admin/supplier-escalations'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(escalation.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['escalation'] is Map ? decoded['escalation'] as Map : decoded;
    if (map is Map) return SupplierEscalation.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Eskalations-Antwort');
  }

  Future<SupplierEscalation> adminUpdateSupplierEscalation(SupplierEscalation escalation, {String? changeReason}) async {
    final payload = escalation.toJson();
    if (changeReason != null && changeReason.trim().isNotEmpty) payload['changeReason'] = changeReason.trim();
    final path = Uri(path: '/api/admin/supplier-escalations', queryParameters: {'id': escalation.id}).toString();
    final r = await http.patch(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(payload),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['escalation'] is Map ? decoded['escalation'] as Map : decoded;
    if (map is Map) return SupplierEscalation.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Eskalations-Antwort');
  }

  Future<void> adminDeleteSupplierEscalation(String id) async {
    final path = Uri(path: '/api/admin/supplier-escalations', queryParameters: {'id': id}).toString();
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<SupplierEvaluationConfig> adminSupplierEvalConfig() async {
    final r = await http.get(_u('/api/admin/supplier-config'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['config'] is Map ? decoded['config'] as Map : decoded;
    if (map is Map) return SupplierEvaluationConfig.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Konfigurations-Antwort');
  }

  Future<SupplierEvaluationConfig> adminUpdateSupplierEvalConfig(SupplierEvaluationConfig config) async {
    final r = await http.patch(
      _u('/api/admin/supplier-config'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(config.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['config'] is Map ? decoded['config'] as Map : decoded;
    if (map is Map) return SupplierEvaluationConfig.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Konfigurations-Antwort');
  }

  Future<SupplierLetterLayoutConfig> adminSupplierReportLayout() async {
    final path = Uri(path: '/api/admin/supplier-report-layout', queryParameters: {'type': 'letter'}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['layout'] is Map ? decoded['layout'] as Map : decoded;
    if (map is Map) return SupplierLetterLayoutConfig.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Layout-Antwort');
  }

  Future<SupplierLetterLayoutConfig> adminUpdateSupplierReportLayout(SupplierLetterLayoutConfig layout) async {
    final path = Uri(path: '/api/admin/supplier-report-layout', queryParameters: {'type': 'letter'}).toString();
    final payload = {
      'version': layout.version,
      'type': 'letter',
      'page': {
        'marginTopMm': layout.page['marginTopMm'],
        'marginRightMm': layout.page['marginRightMm'],
        'marginBottomMm': layout.page['marginBottomMm'],
        'marginLeftMm': layout.page['marginLeftMm'],
      },
      'blocks': {
        'logoWidthMm': layout.header['logoWidthMm'],
        'headerTopMm': layout.header['headerTopMm'],
        'recipientTopMm': layout.recipientBlock['topMm'],
        'recipientLeftMm': layout.recipientBlock['leftMm'],
        'dateTopMm': layout.dateBlock['topMm'],
        'dateRightMm': layout.dateBlock['rightMm'],
        'subjectTopMm': layout.titleBlock['topMm'],
        'bodyTopMm': layout.bodyStartMm,
        'signature': {
          'enabled': layout.signature.enabled,
          'startY': layout.signature.startY,
          'compact': layout.signature.compact,
          'showName': layout.signature.showName,
          'showRole': layout.signature.showRole,
          'showEmail': layout.signature.showEmail,
          'showLegalFooter': layout.signature.showLegalFooter,
          'senderName': layout.signature.senderName,
        },
      },
    };
    final encodedPayload = jsonEncode(payload);
    if (encodedPayload.length > 100000) {
      throw 'Layout payload too large — contains unexpected data';
    }
    final r = await http.post(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: encodedPayload,
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final map = decoded is Map && decoded['layout'] is Map ? decoded['layout'] as Map : decoded;
    if (map is Map) return SupplierLetterLayoutConfig.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Layout-Antwort');
  }

  Future<Uint8List> adminSupplierReportPdf({
    String? supplierId,
    int? year,
    String type = 'internal',
    bool preview = false,
    SupplierLetterLayoutConfig? layoutConfig,
  }) async {
    final queryParameters = {
      'format': 'pdf',
      if (supplierId != null) 'supplierId': supplierId,
      if (year != null) 'year': year.toString(),
      if (type.isNotEmpty) 'type': type,
      if (preview) 'preview': 'true',
    };
    final path = Uri(path: '/api/admin/supplier-reports', queryParameters: queryParameters).toString();
    final r = preview
        ? await http.post(
            _u(path),
            headers: _adminHeaders(auth: true),
            body: jsonEncode(<String, dynamic>{
              if (layoutConfig != null)
                'layout': {
                  'page': layoutConfig.page,
                  'header': layoutConfig.header,
                  'recipientBlock': layoutConfig.recipientBlock,
                  'dateBlock': layoutConfig.dateBlock,
                  'titleBlock': layoutConfig.titleBlock,
                  'bodyStartMm': layoutConfig.bodyStartMm,
                  'signature': layoutConfig.signature.toJson(),
                },
            }),
          )
        : await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    return r.bodyBytes;
  }

  Future<String> adminSupplierReportCsv() async {
    final path = Uri(path: '/api/admin/supplier-reports', queryParameters: {'format': 'csv'}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    return r.body;
  }

  Future<FmeaRiskEntry> adminUpdateFmeaRisk({
    required String fmeaId,
    required String riskId,
    required FmeaRiskEntry risk,
  }) async {
    final r = await http.patch(
      _u('/api/admin/fmea-risks'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'fmeaId': fmeaId, 'riskId': riskId, 'risk': risk.toJson()}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['risk'] is Map ? decoded['risk'] as Map : decoded;
    if (map is Map) return FmeaRiskEntry.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige FMEA-Risiko-Antwort');
  }

  Future<void> adminDeleteFmeaRisk({required String fmeaId, required String riskId}) async {
    final r = await http.delete(
      _u('/api/admin/fmea-risks'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'fmeaId': fmeaId, 'riskId': riskId}),
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<GsprTdOption>> gsprTdOptions() async {
    final r = await http.get(_u('/api/gspr/td-options'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['options'] is List
        ? decoded['options'] as List
        : decoded is List
            ? decoded
            : <dynamic>[];
    return list
        .whereType<Map>()
        .map((entry) => GsprTdOption.fromJson(entry.cast<String, dynamic>()))
        .toList();
  }


  Future<GsprSourceSyncResult> gsprSyncSource({String? tdKey}) async {
    final body = <String, dynamic>{};
    if ((tdKey ?? '').trim().isNotEmpty) body['tdKey'] = tdKey!.trim();
    final r = await http.post(
      _u('/api/gspr/sync'),
      headers: _adminHeaders(auth: true),
      body: body.isEmpty ? null : jsonEncode(body),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map) {
      return GsprSourceSyncResult.fromJson(decoded.cast<String, dynamic>());
    }
    throw ApiError(r.statusCode, 'Ungültige GSPR-Sync-Antwort');
  }

  Future<GsprSummary> gsprSummary({required String tdId}) async {
    final path = Uri(path: '/api/gspr/summary', queryParameters: {'tdId': tdId}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map) {
      return GsprSummary.fromJson(decoded.cast<String, dynamic>());
    }
    throw ApiError(r.statusCode, 'Ungültige GSPR-Zusammenfassung');
  }

  Future<GsprChapterResponse> gsprChapter({required String tdId, required String chapter}) async {
    final path = Uri(
      path: '/api/gspr/chapter',
      queryParameters: {'tdId': tdId, 'chapter': chapter},
    ).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map) {
      return GsprChapterResponse.fromJson(decoded.cast<String, dynamic>(), tdId: tdId);
    }
    throw ApiError(r.statusCode, 'Ungültige GSPR-Kapitel-Antwort');
  }

  Future<GsprAnalysisResponse> gsprAnalysis({
    required String tdId,
    String? chapter,
    List<GsprAssessmentStatus> statuses = const [],
    bool onlyOpen = false,
    bool onlyOverdue = false,
    bool onlyDueSoon = false,
    bool onlyMissingEvidence = false,
    String owner = '',
    String search = '',
    int dueSoonDays = 14,
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String, String>{
      'tdId': tdId,
      'page': page.toString(),
      'pageSize': pageSize.toString(),
      'dueSoonDays': dueSoonDays.toString(),
    };
    if (chapter != null && chapter.isNotEmpty) params['chapter'] = chapter;
    if (statuses.isNotEmpty) {
      params['status'] = statuses.map(gsprAssessmentStatusToString).join(',');
    }
    if (onlyOpen) params['openOnly'] = 'true';
    if (onlyOverdue) params['overdueOnly'] = 'true';
    if (onlyDueSoon) params['dueSoonOnly'] = 'true';
    if (onlyMissingEvidence) params['missingEvidenceOnly'] = 'true';
    if (owner.trim().isNotEmpty) params['owner'] = owner.trim();
    if (search.trim().isNotEmpty) params['search'] = search.trim();

    final path = Uri(path: '/api/gspr/analysis', queryParameters: params).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map) {
      return GsprAnalysisResponse.fromJson(decoded.cast<String, dynamic>());
    }
    throw ApiError(r.statusCode, 'Ungültige GSPR-Analyse-Antwort');
  }

  Future<GsprAssessment> updateGsprAssessment(GsprAssessment assessment) async {
    final r = await http.put(
      _u('/api/gspr/assessment/${assessment.id}'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(assessment.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['assessment'] is Map ? decoded['assessment'] as Map : decoded;
    return GsprAssessment.fromJson(map.cast<String, dynamic>());
  }

  Future<void> submitGsprTd(String tdId) async {
    final r = await http.post(
      _u('/api/gspr/td/$tdId/submit'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<void> approveGsprTd(String tdId) async {
    final r = await http.post(
      _u('/api/gspr/td/$tdId/approve'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<GsprAssessment> newGsprAssessmentVersion(String assessmentId) async {
    final r = await http.post(
      _u('/api/gspr/assessment/$assessmentId/new-version'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final map = decoded is Map && decoded['assessment'] is Map ? decoded['assessment'] as Map : decoded;
    return GsprAssessment.fromJson(map.cast<String, dynamic>());
  }

  Future<List<DownloadCategory>> adminDeleteDownloadCategory(String name, {bool force = false}) async {
    final r = await http.delete(
      _u('/api/admin/download-categories'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'name': name, 'force': force}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['items'] is List ? decoded['items'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => DownloadCategory.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  // ---------- Admin: Schulungswesen ----------
  Future<List<TrainingNeed>> adminTrainingNeeds({int? year}) async {
    final path = year == null ? '/api/admin/training-needs' : '/api/admin/training-needs?year=$year';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['list'] is List ? decoded['list'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => TrainingNeed.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<TrainingNeedSubmitResult> adminCreateTrainingNeed(TrainingNeed need) async {
    final r = await http.post(
      _u('/api/admin/training-needs'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(need.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['need'] is Map ? decoded['need'] as Map : decoded;
    if (map is Map) {
      final warning = decoded is Map ? decoded['warning']?.toString() : null;
      return TrainingNeedSubmitResult(need: TrainingNeed.fromJson(map.cast<String, dynamic>()), warning: warning);
    }
    throw ApiError(r.statusCode, 'Ungültige Schulungsbedarf-Antwort');
  }

  Future<TrainingNeed> adminUpdateTrainingNeed(TrainingNeed need) async {
    final r = await http.patch(
      _u('/api/admin/training-needs'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(need.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['need'] is Map ? decoded['need'] as Map : decoded;
    if (map is Map) return TrainingNeed.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Schulungsbedarf-Antwort');
  }

  Future<void> adminDeleteTrainingNeed(String id, {bool deleteInstances = false}) async {
    final params = deleteInstances ? {'deleteInstances': 'true'} : null;
    final path = Uri(path: '/api/training/needs/$id', queryParameters: params).toString();
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<TrainingProgram>> trainingNeedIntegrationSuggestions(String needId) async {
    final r = await http.get(
      _u('/api/training/needs/$needId/integration-suggestions'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['list'] is List ? decoded['list'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => TrainingProgram.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Map<String, dynamic>> integrateTrainingNeed(
    String needId, {
    required String mode,
    String? programEntryId,
    Map<String, dynamic>? programDraft,
    bool markNeedDone = false,
    bool mergeParticipants = false,
    bool mergeBudget = false,
    bool linkNeed = true,
  }) async {
    final payload = {
      'mode': mode,
      'programEntryId': programEntryId,
      'programDraft': programDraft,
      'markNeedDone': markNeedDone,
      'mergeParticipants': mergeParticipants,
      'mergeBudget': mergeBudget,
      'linkNeed': linkNeed,
    };
    final r = await http.post(
      _u('/api/training/needs/$needId/integrate'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(payload),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> integrateTrainingNeedsBulk({
    required List<String> needIds,
    required String bulkMode,
    Map<String, dynamic>? programDraft,
    bool markNeedsDone = false,
    bool linkNeed = true,
  }) async {
    final payload = {
      'needIds': needIds,
      'bulkMode': bulkMode,
      'programDraft': programDraft,
      'markNeedsDone': markNeedsDone,
      'linkNeed': linkNeed,
    };
    final r = await http.post(
      _u('/api/training/needs/integrate-bulk'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(payload),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> removeTrainingProgramNeedLink({required String programEntryId, required String trainingNeedId}) async {
    final r = await http.delete(
      _u('/api/training/program/need-link'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'programEntryId': programEntryId, 'trainingNeedId': trainingNeedId}),
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<TrainingProgram>> adminTrainingPrograms({int? year}) async {
    final path = year == null ? '/api/admin/training-programs' : '/api/admin/training-programs?year=$year';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['list'] is List ? decoded['list'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => TrainingProgram.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<TrainingProgram> adminCreateTrainingProgram(TrainingProgram program) async {
    final r = await http.post(
      _u('/api/admin/training-programs'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(program.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['program'] is Map ? decoded['program'] as Map : decoded;
    if (map is Map) return TrainingProgram.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Schulungsprogramm-Antwort');
  }

  Future<TrainingProgram> adminUpdateTrainingProgram(TrainingProgram program) async {
    final r = await http.patch(
      _u('/api/admin/training-programs'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(program.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['program'] is Map ? decoded['program'] as Map : decoded;
    if (map is Map) return TrainingProgram.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Schulungsprogramm-Antwort');
  }

  Future<void> adminDeleteTrainingProgram(String id) async {
    final path = Uri(path: '/api/training/program/$id').toString();
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<TrainingRecord>> adminTrainings({int? year, bool includeDeleted = false}) async {
    final params = <String, String>{};
    if (year != null) params['year'] = '$year';
    if (includeDeleted) params['includeDeleted'] = 'true';
    final path = Uri(path: '/api/admin/trainings', queryParameters: params.isEmpty ? null : params).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    final list = decoded is Map && decoded['list'] is List ? decoded['list'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => TrainingRecord.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<TrainingRecord> adminTrainingById(String trainingId) async {
    final path = Uri(path: '/api/admin/trainings', queryParameters: {'id': trainingId}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['record'] is Map ? decoded['record'] as Map : decoded;
    if (map is Map) return TrainingRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Trainings-Antwort');
  }

  Future<Map<String, dynamic>> adminTrainingSummary({int? year}) async {
    final params = <String, String>{'summary': '1'};
    if (year != null) params['year'] = '$year';
    final path = Uri(path: '/api/admin/trainings', queryParameters: params).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map && decoded['summary'] is Map) {
      return (decoded['summary'] as Map).cast<String, dynamic>();
    }
    return const {};
  }

  Future<TrainingRecord> adminCreateTraining(TrainingRecord record) async {
    final r = await http.post(
      _u('/api/admin/trainings'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(record.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['record'] is Map ? decoded['record'] as Map : decoded;
    if (map is Map) return TrainingRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Schulungs-Antwort');
  }

  Future<TrainingRecord> adminUpdateTraining(TrainingRecord record) async {
    final r = await http.patch(
      _u('/api/admin/trainings'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(record.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['record'] is Map ? decoded['record'] as Map : decoded;
    if (map is Map) return TrainingRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Schulungs-Antwort');
  }

  Future<void> adminDeleteTraining(String id, {bool deleteInstances = false}) async {
    final params = deleteInstances ? {'deleteInstances': 'true'} : null;
    final path = Uri(path: '/api/training/sessions/$id', queryParameters: params).toString();
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<TrainingQuestionnaireTemplate>> adminTrainingTemplates() async {
    final r = await http.get(_u('/api/admin/training-questionnaire-templates'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    final list = decoded is Map && decoded['list'] is List ? decoded['list'] as List : <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => TrainingQuestionnaireTemplate.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<TrainingQuestionnaireTemplate> adminCreateTrainingTemplate(TrainingQuestionnaireTemplate template) async {
    final r = await http.post(
      _u('/api/admin/training-questionnaire-templates'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(template.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['template'] is Map ? decoded['template'] as Map : decoded;
    if (map is Map) return TrainingQuestionnaireTemplate.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Template-Antwort');
  }

  Future<TrainingQuestionnaireTemplate> adminUpdateTrainingTemplate(TrainingQuestionnaireTemplate template) async {
    final r = await http.patch(
      _u('/api/admin/training-questionnaire-templates'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(template.toJson()),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['template'] is Map ? decoded['template'] as Map : decoded;
    if (map is Map) return TrainingQuestionnaireTemplate.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Template-Antwort');
  }

  Future<TrainingQuestionnaireTemplate> adminDuplicateTrainingTemplate(String id) async {
    final path = Uri(path: '/api/questionnaires/templates/$id/duplicate').toString();
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['template'] is Map ? decoded['template'] as Map : decoded;
    if (map is Map) return TrainingQuestionnaireTemplate.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Template-Antwort');
  }

  Future<List<Map<String, dynamic>>> myQuestionnaires() async {
    final r = await http.get(_u('/api/questionnaires/my'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    if (decoded is Map && decoded['list'] is List) {
      return (decoded['list'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> questionnaireAssignment(String id) async {
    final path = Uri(path: '/api/questionnaires/assignments/$id').toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw ApiError(r.statusCode, 'Ungültige Fragebogen-Antwort');
  }

  Future<Map<String, dynamic>> questionnaireSubmit(String id, List<Map<String, dynamic>> answers) async {
    final path = Uri(path: '/api/questionnaires/assignments/$id/submit').toString();
    final r = await http.post(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'answers': answers}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw ApiError(r.statusCode, 'Ungültige Fragebogen-Antwort');
  }

  Future<Map<String, dynamic>> questionnaireTrainingResults(String trainingId) async {
    final path = Uri(path: '/api/questionnaires/training/$trainingId/results').toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw ApiError(r.statusCode, 'Ungültige Ergebnis-Antwort');
  }

  Future<void> adminDeleteTrainingTemplate(String id) async {
    final path = Uri(path: '/api/training/templates/$id').toString();
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<void> adminPurgeTraining(String scope) async {
    final r = await http.post(
      _u('/api/admin/training/purge'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'scope': scope, 'confirm': 'LOESCHEN'}),
    );
    if (!_ok2xx(r.statusCode) && r.statusCode != 204) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<Map<String, dynamic>>> adminTrainingQuestionnaires({String? trainingId}) async {
    final path = Uri(
      path: '/api/admin/training-questionnaires',
      queryParameters: trainingId == null ? null : {'trainingId': trainingId},
    ).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isNotEmpty ? jsonDecode(r.body) : <String, dynamic>{};
    if (decoded is Map && decoded['list'] is List) {
      return (decoded['list'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  Future<Uint8List> adminTrainingPdf(String id) async {
    final path = Uri(path: '/api/admin/training-pdf', queryParameters: {'id': id}).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    return r.bodyBytes;
  }

  Future<Uint8List> adminTrainingProgramPdf(
    int year, {
    String? department,
    String? status,
    String? format,
    String? search,
    String? sort,
  }) async {
    final params = <String, String>{'year': '$year'};
    if (department != null && department.trim().isNotEmpty) params['department'] = department.trim();
    if (status != null && status.trim().isNotEmpty) params['status'] = status.trim();
    if (format != null && format.trim().isNotEmpty) params['format'] = format.trim();
    if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
    if (sort != null && sort.trim().isNotEmpty) params['sort'] = sort.trim();
    final path = Uri(path: '/api/training/program/pdf', queryParameters: params).toString();
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    return r.bodyBytes;
  }

  Future<Map<String, dynamic>> trainingWkReminders() async {
    final r = await http.get(_u('/api/training/wk/reminders'), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return const {};
  }

  Future<TrainingRecord> trainingSignParticipant({
    required String trainingId,
    required String participantId,
    required String signatureBase64,
    String? note,
  }) async {
    final path = Uri(path: '/api/training/sessions/$trainingId/participants/$participantId/sign').toString();
    final r = await http.post(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'signatureBase64': signatureBase64, 'note': note}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['record'] is Map ? decoded['record'] as Map : decoded;
    if (map is Map) return TrainingRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Unterschrift-Antwort');
  }

  Future<TrainingSignatureTokenResponse> trainingIssueSignatureToken({
    required String trainingId,
    required String participantId,
  }) async {
    final path = Uri(path: '/api/training/sessions/$trainingId/participants/$participantId/signature-token').toString();
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map) return TrainingSignatureTokenResponse.fromJson(decoded.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Token-Antwort');
  }

  Future<TrainingRecord> trainingResetParticipantSignature({
    required String trainingId,
    required String participantId,
    required String reason,
  }) async {
    final path = Uri(path: '/api/training/sessions/$trainingId/participants/$participantId/sign').toString();
    final r = await http.post(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'action': 'reset', 'reason': reason}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['record'] is Map ? decoded['record'] as Map : decoded;
    if (map is Map) return TrainingRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Reset-Antwort');
  }

  Future<TrainingRecord> trainingOverrideParticipantSignature({
    required String trainingId,
    required String participantId,
    required String reason,
  }) async {
    final path = Uri(path: '/api/training/sessions/$trainingId/participants/$participantId/sign').toString();
    final r = await http.post(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'action': 'override', 'reason': reason}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['record'] is Map ? decoded['record'] as Map : decoded;
    if (map is Map) return TrainingRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Override-Antwort');
  }

  Future<TrainingSignContext> publicTrainingSignContext(String token) async {
    final path = Uri(path: '/api/public/training/sign-context', queryParameters: {'t': token}).toString();
    final r = await http.get(_u(path));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map) return TrainingSignContext.fromJson(decoded.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige Signatur-Antwort');
  }

  Future<void> publicSubmitTrainingSignature({
    required String token,
    required String signatureBase64,
    required bool confirmationChecked,
  }) async {
    final r = await http.post(
      _u('/api/public/training/submit-signature'),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'token': token,
        'signatureBase64Png': signatureBase64,
        'confirmationChecked': confirmationChecked,
      }),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<TrainingRecord> trainingConfigureWk({
    required String trainingId,
    required String wkMethod,
    required int wkDelayDays,
    String? wkResponsibleId,
    String? wkQuestionnaireTemplateId,
    List<String>? wkTargetParticipantIds,
    int? wkThresholdPercent,
  }) async {
    final path = Uri(path: '/api/training/sessions/$trainingId/wk/configure').toString();
    final payload = {
      'wkMethod': wkMethod,
      'wkDelayDays': wkDelayDays,
      'wkResponsibleId': wkResponsibleId,
      'wkQuestionnaireTemplateId': wkQuestionnaireTemplateId,
      'wkTargetParticipantIds': wkTargetParticipantIds ?? const [],
      'wkThresholdPercent': wkThresholdPercent,
    };
    final r = await http.post(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode(payload),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['record'] is Map ? decoded['record'] as Map : decoded;
    if (map is Map) return TrainingRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige WK-Antwort');
  }

  Future<TrainingRecord> trainingCompleteWk({
    required String trainingId,
    required String result,
    String? notes,
    DateTime? performedAt,
    bool override = false,
    String? reason,
  }) async {
    final path = Uri(path: '/api/training/sessions/$trainingId/wk/complete').toString();
    final r = await http.post(
      _u(path),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({
        'result': result,
        'notes': notes,
        'performedAt': performedAt?.millisecondsSinceEpoch,
        'override': override,
        'reason': reason,
      }),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final map = decoded is Map && decoded['record'] is Map ? decoded['record'] as Map : decoded;
    if (map is Map) return TrainingRecord.fromJson(map.cast<String, dynamic>());
    throw ApiError(r.statusCode, 'Ungültige WK-Abschluss-Antwort');
  }

  Future<Map<String, Map<String, String>>> translateFaqDraft({
    String? sourceLang,
    required List<String> targetLangs,
    String? question,
    String? answer,
  }) async {
    final payload = <String, dynamic>{
      'targets': targetLangs,
    };
    if (sourceLang != null && sourceLang.trim().isNotEmpty) {
      payload['sourceLang'] = sourceLang.trim();
    }
    if (question != null && question.trim().isNotEmpty) payload['question'] = question.trim();
    if (answer != null && answer.trim().isNotEmpty) payload['answer'] = answer.trim();

    final r = await http.post(
      _u('/api/admin/translate'),
      headers: _adminHeaders(auth: true),
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

  // ---------- Vertreter-Wiki ----------
  Future<List<WikiArticle>> fetchWikiArticles({
    String? category,
    String? productGroup,
    String? type,
    String? search,
    String? lang,
  }) async {
    final params = <String, String>{};
    if (category != null && category.isNotEmpty) params['category'] = category;
    if (productGroup != null && productGroup.isNotEmpty) {
      params['productGroup'] = productGroup;
    }
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (lang != null && lang.isNotEmpty) params['lang'] = lang;
    final query = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final url = query.isEmpty ? '/api/wiki' : '/api/wiki?$query';

    final r = await http.get(_u(url));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final list = decoded is List
        ? decoded
        : decoded is Map && decoded['articles'] is List
            ? decoded['articles'] as List
            : decoded is Map && decoded['items'] is List
                ? decoded['items'] as List
                : const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => WikiArticle.fromJson(e))
        .toList();
  }

  Future<WikiOverview> fetchWikiOverview({
    String? category,
    String? productGroup,
    String? type,
    String? search,
    String? lang,
  }) async {
    final params = <String, String>{};
    if (category != null && category.isNotEmpty) params['category'] = category;
    if (productGroup != null && productGroup.isNotEmpty) params['productGroup'] = productGroup;
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (lang != null && lang.isNotEmpty) params['lang'] = lang;
    final query = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final url = query.isEmpty ? '/api/wiki' : '/api/wiki?$query';

    final r = await http.get(_u(url));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final articleList = decoded is List
        ? decoded
        : decoded is Map && decoded['articles'] is List
            ? decoded['articles'] as List
            : decoded is Map && decoded['items'] is List
                ? decoded['items'] as List
                : const [];
    final categoryList = decoded is Map && decoded['categories'] is List
        ? decoded['categories'] as List
        : const [];
    return WikiOverview(
      categories: categoryList
          .whereType<Map<String, dynamic>>()
          .map((e) => WikiCategory.fromJson(e))
          .toList(),
      articles: articleList
          .whereType<Map<String, dynamic>>()
          .map((e) => WikiArticle.fromJson(e))
          .toList(),
    );
  }

  Future<WikiArticle> fetchWikiArticle(String id, {String? lang}) async {
    final suffix = (lang != null && lang.isNotEmpty)
        ? '?lang=${Uri.encodeQueryComponent(lang)}'
        : '';
    final safeId = Uri.encodeComponent(id);
    final r = await http.get(_u('/api/wiki/$safeId$suffix'));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map<String, dynamic>) return WikiArticle.fromJson(decoded);
    throw ApiError(500, 'Ungültige Antwort für Wiki-Artikel');
  }

  Future<List<WikiCategory>> adminFetchWikiCategories({String? status}) async {
    final query = (status != null && status.isNotEmpty)
        ? '?status=${Uri.encodeQueryComponent(status)}'
        : '';
    final r = await http.get(
      _u('/api/wiki/admin/categories$query'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final list = decoded is List
        ? decoded
        : decoded is Map && decoded['articles'] is List
            ? decoded['articles'] as List
            : decoded is Map && decoded['items'] is List
                ? decoded['items'] as List
                : const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => WikiCategory.fromJson(e))
        .toList();
  }

  Future<WikiCategory> adminSaveWikiCategory(Map<String, dynamic> data,
      {String? id}) async {
    final path = id == null
        ? '/api/wiki/admin/categories'
        : '/api/wiki/admin/categories/$id';
    final r = await (id == null
        ? http.post(_u(path), headers: _adminHeaders(auth: true), body: jsonEncode(data))
        : http.put(_u(path), headers: _adminHeaders(auth: true), body: jsonEncode(data)));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map<String, dynamic>) return WikiCategory.fromJson(decoded);
    throw ApiError(500, 'Ungültige Antwort für Kategorie');
  }

  Future<WikiCategory> adminToggleWikiCategory(String id, bool isActive) async {
    final safeId = Uri.encodeComponent(id);
    final r = await http.patch(
      _u('/api/wiki/admin/categories/$safeId'),
      headers: _adminHeaders(auth: true),
      body: jsonEncode({'isActive': isActive}),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map<String, dynamic>) return WikiCategory.fromJson(decoded);
    throw ApiError(500, 'Ungültige Antwort für Kategorie-Status');
  }

  Future<void> adminDeleteWikiCategory(String id) async {
    final r = await http.delete(
      _u('/api/wiki/admin/categories/$id'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<List<WikiArticle>> adminFetchWikiArticles({
    String? category,
    String? productGroup,
    String? type,
    String? status,
    String? search,
  }) async {
    final params = <String, String>{};
    if (category != null && category.isNotEmpty) params['category'] = category;
    if (productGroup != null && productGroup.isNotEmpty) {
      params['productGroup'] = productGroup;
    }
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final query = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final url = query.isEmpty ? '/api/wiki/admin/articles' : '/api/wiki/admin/articles?$query';
    final r = await http.get(_u(url), headers: _adminHeaders(auth: true, path: url));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    final list = decoded is List
        ? decoded
        : decoded is Map && decoded['articles'] is List
            ? decoded['articles'] as List
            : decoded is Map && decoded['items'] is List
                ? decoded['items'] as List
                : const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => WikiArticle.fromJson(e))
        .toList();
  }

  Future<List<WikiArticle>> adminWikiArticles({String? status}) async {
    return adminFetchWikiArticles(status: status);
  }

  Future<WikiArticle> adminSaveWikiArticle(Map<String, dynamic> data,
      {String? id}) async {
    final path = id == null
        ? '/api/wiki/admin/articles'
        : '/api/wiki/admin/articles/$id';
    final r = await (id == null
        ? http.post(_u(path), headers: _adminHeaders(auth: true), body: jsonEncode(data))
        : http.put(_u(path), headers: _adminHeaders(auth: true), body: jsonEncode(data)));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = jsonDecode(r.body);
    if (decoded is Map<String, dynamic>) return WikiArticle.fromJson(decoded);
    throw ApiError(500, 'Ungültige Antwort für Artikel');
  }

  Future<void> adminDeleteWikiArticle(String id) async {
    final r = await http.delete(
      _u('/api/wiki/admin/articles/$id'),
      headers: _adminHeaders(auth: true),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
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


  Future<TdCatalogResponse> getTdCatalog() async {
    return fetchTdCatalog();
  }

  Future<TdCatalogResponse> fetchTdCatalog() async {
    const path = '/api/td/catalog';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is! Map) throw ApiError(500, 'Ungültige Antwort für TD-Katalog');
    final body = decoded.cast<String, dynamic>();
    if (body['ok'] == false) {
      return const TdCatalogResponse(items: <TdFile>[], meta: <String, dynamic>{}, source: 'api-unavailable');
    }
    final items = (body['items'] as List?) ?? const [];
    final meta = (body['meta'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return TdCatalogResponse(
      items: items.whereType<Map>().map((e) {
        final row = e.cast<String, dynamic>();
        return TdFile(
          id: (row['td_key'] ?? row['tdKey'] ?? row['id'] ?? '').toString(),
          code: (row['td_key'] ?? row['tdKey'] ?? row['code'] ?? '').toString(),
          title: (row['title'] ?? row['td_key'] ?? row['tdKey'] ?? '').toString(),
          lifecycleState: 'Development',
          productGroup: (row['productFamily'] ?? row['product_group'])?.toString(),
          classification: (row['risk_class'] ?? row['riskClass'] ?? row['mdr_classification'])?.toString(),
          rule: (row['mdr_rule'] ?? row['rule'])?.toString(),
          status: 'Draft',
          summary: const TdSummary(
            complianceScore: 0,
            readinessStatus: 'Yellow',
            overdueReviews: 0,
            openCapaCount: 0,
            reasons: <String>[],
          ),
        );
      }).toList(growable: false),
      meta: meta,
      source: 'api',
    );
  }

  Future<List<TdFile>> fetchTdFiles() async {
    return fetchTdSummary();
  }

  Future<List<TdFile>> fetchTdSummary({Duration? timeout, bool optional = false, bool v2 = false}) async {
    final primaryPath = v2 ? '/api/td/summary?v=2' : '/api/td/summary';
    try {
      var request = http.get(_u(primaryPath), headers: _adminHeaders(auth: true, path: '/api/td/summary'));
      if (timeout != null) {
        request = request.timeout(timeout);
      }
      var r = await request;
      if (!_ok2xx(r.statusCode) && r.statusCode == 404) {
        const fallbackPath = '/api/tdk/summary';
        request = http.get(_u(fallbackPath), headers: _adminHeaders(auth: true, path: fallbackPath));
        if (timeout != null) {
          request = request.timeout(timeout);
        }
        r = await request;
      }
      if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
      final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);

      List<dynamic> items;
      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map) {
        final body = decoded.cast<String, dynamic>();
        if (body['ok'] == false) {
          return const <TdFile>[];
        }
        if (body['items'] is List) {
          items = body['items'] as List;
        } else if (body['data'] is List) {
          items = body['data'] as List;
        } else {
          debugPrint('[td] Unsupported summary response shape: keys=${body.keys.toList()}');
          throw ApiError(500, 'Ungültiges TD-Summary-Format');
        }
      } else {
        debugPrint('[td] Unsupported summary response type: ${decoded.runtimeType}');
        throw ApiError(500, 'Ungültiges TD-Summary-Format');
      }

      return items.whereType<Map>().map((e) => TdFile.fromJson(e.cast<String, dynamic>())).toList(growable: false);
    } catch (_) {
      if (!optional) rethrow;
      return const <TdFile>[];
    }
  }

  Future<List<TdFile>> fetchTdListFallback({Duration? timeout}) async {
    const path = '/api/td';
    var request = http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (timeout != null) {
      request = request.timeout(timeout);
    }
    final r = await request;
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is! Map) throw ApiError(500, 'Ungültige Antwort für TD-Liste');
    final body = decoded.cast<String, dynamic>();
    final items = (body['items'] as List?) ?? const [];
    return items.whereType<Map>().map((e) => TdFile.fromJson(e.cast<String, dynamic>())).toList(growable: false);
  }



  Future<Map<String, dynamic>> fetchTdOverview(String tdKey) async {
    final primaryPath = '/api/td/$tdKey/overview';
    var r = await http.get(_u(primaryPath), headers: _adminHeaders(auth: true, path: primaryPath));
    if (!_ok2xx(r.statusCode) && r.statusCode == 404) {
      final fallbackPath = '/api/tdk/$tdKey/overview';
      r = await http.get(_u(fallbackPath), headers: _adminHeaders(auth: true, path: fallbackPath));
    }
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> fetchTdSectionByTd(String tdKey, String sectionId) async {
    final path = '/api/tdk/$tdKey/section/$sectionId';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return (body['item'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> fetchTdDetail(String id) async {
    final path = '/api/td/$id';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<TdFile> createTdFile({
    required String code,
    required String title,
    String? productGroup,
    String? classification,
    String? rule,
    TdApplicabilityProfile? applicabilityProfile,
  }) async {
    const path = '/api/td';
    final r = await http.post(
      _u(path),
      headers: _adminHeaders(auth: true, path: path),
      body: jsonEncode({
        'code': code,
        'title': title,
        'productGroup': productGroup,
        'classification': classification,
        'rule': rule,
        if (applicabilityProfile != null) 'applicabilityProfile': applicabilityProfile.toJson(),
      }),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return TdFile.fromJson((body['item'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{});
  }

  Future<TdFile> patchTdFile(String id, Map<String, dynamic> patch) async {
    final path = '/api/td/$id';
    final r = await http.patch(
      _u(path),
      headers: _adminHeaders(auth: true, path: path),
      body: jsonEncode(patch),
    );
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return TdFile.fromJson((body['item'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{});
  }



  Future<TdApplicabilityBundle> fetchTdApplicability(String tdId) async {
    final path = '/api/td/$tdId/applicability';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return TdApplicabilityBundle.fromJson(body);
  }

  Future<TdApplicabilityBundle> saveTdApplicabilityProfile(String tdId, TdApplicabilityProfile profile) async {
    final path = '/api/td/$tdId/applicability';
    final r = await http.put(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode({'profile': profile.toJson()}));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return TdApplicabilityBundle.fromJson(body);
  }

  Future<TdApplicabilityBundle> regenerateTdApplicability(String tdId) async {
    final path = '/api/td/$tdId/applicability/regenerate';
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(const {}));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return TdApplicabilityBundle.fromJson(body);
  }

  Future<TdApplicabilityBundle> upsertTdApplicabilityOverride(String tdId, Map<String, dynamic> payload) async {
    final path = '/api/td/$tdId/applicability';
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(payload));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return TdApplicabilityBundle.fromJson(body);
  }

  Future<List<TdSection>> fetchTdSections(String tdId) async {
    final page = await fetchTdSectionsPaged(tdId, limit: 50, cursor: 0);
    return page.$1;
  }

  Future<(List<TdSection>, int?)> fetchTdSectionsPaged(String tdId, {int limit = 50, int cursor = 0}) async {
    final path = '/api/td/$tdId/sections';
    final qp = '?limit=$limit&cursor=$cursor';
    final r = await http.get(_u('$path$qp'), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    final items = (body['items'] as List?) ?? const [];
    final sections = items.whereType<Map>().map((e) => TdSection.fromJson(e.cast<String, dynamic>())).toList(growable: false);
    final page = (body['page'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final nextCursor = (page['nextCursor'] as num?)?.toInt();
    return (sections, nextCursor);
  }

  Future<Map<String, dynamic>> fetchTdSectionDetail(String sectionId) async {
    final path = '/api/td/sections/$sectionId';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return (body['item'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  }

  Future<void> patchTdSection(String sectionId, Map<String, dynamic> patch) async {
    final path = '/api/td/sections/$sectionId';
    final r = await http.patch(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(patch));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<void> putTdSectionContent(String sectionId, {required String summaryMarkdown, required Map<String, dynamic> contentJson}) async {
    final path = '/api/td/sections/$sectionId/content';
    final r = await http.put(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode({'summaryMarkdown': summaryMarkdown, 'contentJson': contentJson}));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<List<TdArtifactLink>> fetchTdLinks(String tdId, {String? sectionId}) async {
    final qp = sectionId == null ? '' : '?sectionId=${Uri.encodeQueryComponent(sectionId)}';
    final path = '/api/td/$tdId/links$qp';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: '/api/td/$tdId/links'));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    final items = (body['items'] as List?) ?? const [];
    return items.whereType<Map>().map((e) => TdArtifactLink.fromJson(e.cast<String, dynamic>())).toList(growable: false);
  }

  Future<void> createTdLink(String tdId, Map<String, dynamic> payload) async {
    final path = '/api/td/$tdId/links';
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(payload));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<void> deleteTdLink(String linkId) async {
    final path = '/api/td/links/$linkId';
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<Map<String, dynamic>> fetchTdReadiness(String tdId) async {
    final primaryPath = '/api/td/$tdId/readiness';
    final primary = await http.get(_u(primaryPath), headers: _adminHeaders(auth: true, path: primaryPath));
    if (_ok2xx(primary.statusCode)) {
      final decoded = primary.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(primary.body);
      return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    }

    if (primary.statusCode != 404) {
      throw ApiError(primary.statusCode, _extractMessage(primary.body));
    }

    final fallbackPath = '/api/td/readiness?tdId=${Uri.encodeQueryComponent(tdId)}';
    final fallback = await http.get(_u(fallbackPath), headers: _adminHeaders(auth: true, path: '/api/td/readiness'));
    if (!_ok2xx(fallback.statusCode)) throw ApiError(fallback.statusCode, _extractMessage(fallback.body));
    final decoded = fallback.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(fallback.body);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }


  Future<List<TdQueryAnswer>> fetchTdQueries(String tdId, {String? sectionId}) async {
    final qp = sectionId == null ? '' : '?sectionId=${Uri.encodeQueryComponent(sectionId)}';
    final path = '/api/td/$tdId/queries$qp';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: '/api/td/$tdId/queries'));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    final items = (body['items'] as List?) ?? const [];
    return items.whereType<Map>().map((e) => TdQueryAnswer.fromJson(e.cast<String, dynamic>())).toList(growable: false);
  }

  Future<void> bootstrapTdQueries(String tdId) async {
    final path = '/api/td/$tdId/queries/bootstrap';
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(const {}));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<Map<String, dynamic>> fetchTdStartupBootstrap(String tdId) async {
    final path = '/api/td/$tdId/queries/bootstrap';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> updateTdQuery(String answerId, Map<String, dynamic> payload) async {
    final path = '/api/td/queries/$answerId';
    final r = await http.put(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(payload));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<void> createTdQueryLink(String answerId, Map<String, dynamic> payload) async {
    final path = '/api/td/queries/$answerId/links';
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(payload));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<void> deleteTdQueryLink(String linkId) async {
    final path = '/api/td/queries/links/$linkId';
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<List<TdChangeRequest>> fetchTdChanges(String tdId) async {
    final path = '/api/td/$tdId/changes';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    final items = (body['items'] as List?) ?? const [];
    return items.whereType<Map>().map((e) => TdChangeRequest.fromJson(e.cast<String, dynamic>())).toList(growable: false);
  }

  Future<void> createTdChange(String tdId, Map<String, dynamic> payload) async {
    final path = '/api/td/$tdId/changes';
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(payload));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<TdChangeRequest> fetchTdChange(String changeId) async {
    final path = '/api/td/changes/$changeId';
    final r = await http.get(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    final body = decoded is Map ? decoded.cast<String, dynamic>() : const <String, dynamic>{};
    return TdChangeRequest.fromJson((body['item'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{});
  }

  Future<void> patchTdChange(String changeId, Map<String, dynamic> payload) async {
    final path = '/api/td/changes/$changeId';
    final r = await http.patch(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(payload));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<void> deleteTdChange(String changeId) async {
    final path = '/api/td/changes/$changeId';
    final r = await http.delete(_u(path), headers: _adminHeaders(auth: true, path: path));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<void> patchTdImpact(String impactId, {required String status}) async {
    final path = '/api/td/impacts/$impactId';
    final r = await http.patch(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode({'status': status}));
    if (!_ok2xx(r.statusCode)) throw ApiError(r.statusCode, _extractMessage(r.body));
  }

  Future<void> runTdImpactAnalyzer(String changeId) async {
    final path = '/api/td/changes/$changeId/analyze';
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(const {}));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
  }

  Future<Map<String, dynamic>> exportTdNbPackage(String tdId) async {
    final path = '/api/td/$tdId/export/nb-package';
    final r = await http.post(_u(path), headers: _adminHeaders(auth: true, path: path), body: jsonEncode(const {}));
    if (!_ok2xx(r.statusCode)) {
      throw ApiError(r.statusCode, _extractMessage(r.body));
    }
    final decoded = r.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
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
