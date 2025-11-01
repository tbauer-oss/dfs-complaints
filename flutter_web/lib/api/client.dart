// lib/api/client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'config.dart';
import '../models/complaint.dart';

class ApiClient {
  String? token; // JWT
  String? gate;  // Gate-Token (X-Gate)

  Map<String, String> _headers({bool auth = false, Map<String, String>? extra}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      if (gate != null) 'X-Gate': gate!,
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  // ---------- interne Helper (roh/typsicher) ----------
  Future<Map<String, dynamic>> _getJson(String path, {bool auth = false}) async {
    final r = await http.get(Uri.parse('${CFG.apiBase}$path'), headers: _headers(auth: auth));
    if (r.statusCode != 200) {
      throw Exception('GET $path failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is Map<String, dynamic>) return j;
    throw Exception('GET $path did not return an object');
  }

  Future<List<dynamic>> _getJsonList(String path, {bool auth = false}) async {
    final r = await http.get(Uri.parse('${CFG.apiBase}$path'), headers: _headers(auth: auth));
    if (r.statusCode != 200) {
      throw Exception('GET $path failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is List) return j;
    throw Exception('GET $path did not return a list');
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}$path'),
      headers: _headers(auth: auth),
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) {
      throw Exception('POST $path failed: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is Map<String, dynamic>) return j;
    throw Exception('POST $path did not return an object');
  }

  // =========================================================
  // -------------------- Gate & Auth ------------------------
  // =========================================================

  /// Gate freischalten (POST /api/gate) — tolerant auf {ok:true} / {gate:"..."}
  Future<bool> gateUnlock(String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/gate'),
      headers: _headers(),
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode != 200) return false;
    try {
      final j = jsonDecode(r.body);
      if (j is Map<String, dynamic>) {
        if (j['gate'] is String) {
          gate = j['gate'] as String;
          return true;
        }
        if (j['ok'] == true) {
          gate = gate ?? 'ok';
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Login (POST /api/auth/login)
  /// Gibt bewusst den ROHEN http.Response zurück, weil dein auth_page.dart .statusCode/.body erwartet.
  Future<http.Response> login(String email, String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/auth/login'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (r.statusCode == 200) {
      try {
        final j = jsonDecode(r.body);
        final t = (j is Map) ? j['token']?.toString() : null;
        if (t != null && t.isNotEmpty) token = t;
      } catch (_) {}
    }
    return r;
  }

  /// Registrierung (POST /api/auth/register)
  /// Ebenfalls roher http.Response (deine auth_page prüft .statusCode/.body).
  Future<http.Response> register(Map<String, dynamic> data) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/auth/register'),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (r.statusCode == 200) {
      try {
        final j = jsonDecode(r.body);
        final t = (j is Map) ? j['token']?.toString() : null;
        if (t != null && t.isNotEmpty) token = t;
      } catch (_) {}
    }
    return r;
  }

  // =========================================================
  // ---------------- Reklamationen (neu) --------------------
  // =========================================================

  /// Typsicher: Anlegen (POST /api/complaint)
  Future<Complaint> complaintCreate(Map<String, dynamic> payload) async {
    final j = await _postJson('/api/complaint', payload, auth: true);
    return Complaint.fromJson(j as Map<String, dynamic>);
  }

  /// Typsicher: Liste (GET /api/complaint)
  Future<List<Complaint>> complaintList() async {
    final list = await _getJsonList('/api/complaint', auth: true);
    return list.map((e) => Complaint.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Typsicher: Einzelnes Ticket (GET /api/complaint/<ticket>)
  Future<Complaint> complaintGet(String ticket) async {
    final j = await _getJson('/api/complaint/$ticket', auth: true);
    return Complaint.fromJson(j);
  }

  // =========================================================
  // ---- Rückwärtskompatible Wrapper für alte Aufrufe -------
  // =========================================================

  /// ALT: submitComplaint(payload, [legacyArg]) — Map wie früher (inkl. 'data'-Alias)
  Future<Map<String, dynamic>> submitComplaint(Map<String, dynamic> payload, [dynamic _legacy]) async {
    final raw = await _postJson('/api/complaint', payload, auth: true);
    return _cloneWithDataAlias(raw);
  }

  /// ALT: myComplaints() — List<Map> wie früher (inkl. 'data'-Alias)
  Future<List<dynamic>> myComplaints() async {
    final list = await _getJsonList('/api/complaint', auth: true);
    return list.map((e) => _cloneWithDataAlias((e as Map).cast<String, dynamic>())).toList();
  }

  /// 'payload' zusätzlich als 'data' spiegeln, damit altes UI (data.article, …) weiterläuft
  Map<String, dynamic> _cloneWithDataAlias(Map<String, dynamic> src) {
    final out = Map<String, dynamic>.from(src);
    final payload = (src['payload'] is Map) ? (src['payload'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    out['data'] = out['data'] ?? payload;
    return out;
  }

  // =========================================================
  // ---------------------- Account --------------------------
  // =========================================================

  Future<Map<String, dynamic>> accountGet() async {
    return _getJson('/api/account', auth: true);
  }

  Future<Map<String, dynamic>> accountUpdate(Map<String, dynamic> data) async {
    final r = await http.put(
      Uri.parse('${CFG.apiBase}/api/account'),
      headers: _headers(auth: true),
      body: jsonEncode(data),
    );
    if (r.statusCode != 200) {
      throw Exception('account update failed: ${r.statusCode} ${r.body}');
    }
    return (jsonDecode(r.body) as Map).cast<String, dynamic>();
  }

  Future<void> accountChangePassword(String oldPw, String newPw) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/account/password'),
      headers: _headers(auth: true),
      body: jsonEncode({'oldPassword': oldPw, 'newPassword': newPw}),
    );
    if (r.statusCode != 200) {
      throw Exception('password change failed: ${r.statusCode} ${r.body}');
    }
  }

  Future<void> accountDelete(String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/account/delete'),
      headers: _headers(auth: true),
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode != 200) {
      throw Exception('account delete failed: ${r.statusCode} ${r.body}');
    }
  }

  // =========================================================
  // ----------------------- Support -------------------------
  // =========================================================

  Future<void> sendSupport({
    required String category,
    required String message,
    required bool consent,
  }) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/support'),
      headers: _headers(auth: true),
      body: jsonEncode({
        'category': category,
        'message': message,
        'consent': consent,
      }),
    );
    if (r.statusCode != 200) {
      throw Exception('support send failed: ${r.statusCode} ${r.body}');
    }
  }
}
