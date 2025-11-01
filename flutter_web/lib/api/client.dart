// lib/api/client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'config.dart';
import '../models/complaint.dart';

// Web LocalStorage (sicher in Web, no-op sonst)
String? _lsGet(String key) {
  if (!kIsWeb) return null;
  try {
    // ignore: avoid_web_libraries_in_flutter
    import 'dart:html' as html;
  } catch (_) {}
  return null;
}
void _lsSet(String key, String? value) {
  if (!kIsWeb) return;
  try {
    // ignore: avoid_web_libraries_in_flutter
    import 'dart:html' as html;
  } catch (_) {}
}

class ApiClient {
  String? token;
  String? gate;

  // ===== Persistenz =====
  Future<void> restoreSession() async {
    if (!kIsWeb) return;
    try {
      // ignore: avoid_web_libraries_in_flutter
      import 'dart:html' as html;
    } catch (_) {}
  }

  void _saveToken(String? t) {
    token = t;
    if (!kIsWeb) return;
    try {
      // ignore: avoid_web_libraries_in_flutter
      import 'dart:html' as html;
    } catch (_) {}
  }

  void _saveGate(String? g) {
    gate = g;
    if (!kIsWeb) return;
    try {
      // ignore: avoid_web_libraries_in_flutter
      import 'dart:html' as html;
    } catch (_) {}
  }

  void clearSession() {
    _saveToken(null);
    _saveGate(null);
  }

  Map<String,String> _headers({bool auth=false, Map<String,String>? extra}) {
    final h = <String,String>{
      'Content-Type': 'application/json',
      if (gate != null) 'X-Gate': gate!,
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  // ===== Gate / Auth =====
  Future<bool> gateUnlock(String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/gate'),
      headers: _headers(),
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode != 200) return false;
    final j = jsonDecode(r.body);
    final g = j['gate']?.toString();
    if (g != null && g.isNotEmpty) {
      _saveGate(g);
      return true;
    }
    return j['ok'] == true;
  }

  Future<bool> login(String email, String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/auth/login'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (r.statusCode != 200) return false;
    final j = jsonDecode(r.body);
    final t = j['token']?.toString();
    if (t != null && t.isNotEmpty) {
      _saveToken(t);
      return true;
    }
    return false;
  }

  Future<http.Response> register(Map<String,dynamic> data) async {
    return await http.post(
      Uri.parse('${CFG.apiBase}/api/auth/register'),
      headers: _headers(),
      body: jsonEncode(data),
    );
  }

  // ===== Complaints =====
  Future<Complaint> complaintCreate(Map<String, dynamic> payload) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/complaint'),
      headers: _headers(auth: true),
      body: jsonEncode(payload),
    );
    if (r.statusCode != 200) {
      throw Exception('complaint create failed: ${r.statusCode} ${r.body}');
    }
    return Complaint.fromJson(jsonDecode(r.body));
  }

  Future<List<Complaint>> complaintList() async {
    final r = await http.get(
      Uri.parse('${CFG.apiBase}/api/complaint'),
      headers: _headers(auth: true),
    );
    if (r.statusCode == 401) {
      clearSession();
      throw Exception('complaint list failed: 401 ${r.body}');
    }
    if (r.statusCode != 200) {
      throw Exception('complaint list failed: ${r.statusCode} ${r.body}');
    }
    final List data = jsonDecode(r.body);
    return data.map((e)=>Complaint.fromJson(e as Map<String,dynamic>)).toList();
  }

  // ===== Account =====
  Future<Map<String,dynamic>> accountGet() async {
    final r = await http.get(
      Uri.parse('${CFG.apiBase}/api/account'),
      headers: _headers(auth: true),
    );
    if (r.statusCode == 401) {
      clearSession();
      throw Exception('GET /api/account failed: 401 ${r.body}');
    }
    if (r.statusCode != 200) {
      throw Exception('GET /api/account failed: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String,dynamic>;
  }

  Future<Map<String,dynamic>> accountUpdate(Map<String,dynamic> data) async {
    final r = await http.put(
      Uri.parse('${CFG.apiBase}/api/account'),
      headers: _headers(auth: true),
      body: jsonEncode(data),
    );
    if (r.statusCode != 200) throw Exception('account update failed: ${r.body}');
    return jsonDecode(r.body) as Map<String,dynamic>;
  }

  Future<void> accountChangePassword(String oldPw, String newPw) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/account/password'),
      headers: _headers(auth: true),
      body: jsonEncode({'oldPassword': oldPw, 'newPassword': newPw}),
    );
    if (r.statusCode != 200) throw Exception('password change failed: ${r.body}');
  }

  Future<void> accountDelete(String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/account/delete'),
      headers: _headers(auth: true),
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode != 200) throw Exception('account delete failed: ${r.body}');
    clearSession();
  }

  // ===== Support =====
  Future<void> sendSupport({
    required String category,
    required String message,
    required bool consent,
  }) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/support'),
      headers: _headers(auth: true),
      body: jsonEncode({'category': category, 'message': message, 'consent': consent}),
    );
    if (r.statusCode != 200) throw Exception('support send failed: ${r.body}');
  }
}
