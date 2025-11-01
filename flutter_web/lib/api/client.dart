import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'config.dart';

// Nur für Flutter Web verfügbar
// (Du baust Web, daher ist das ok. Für Mobile würde man mit conditional imports arbeiten.)
import 'dart:html' as html;

class ApiClient {
  String? token; // JWT
  String? gate;  // Gate-Token

  ApiClient() {
    // Beim App-Start ggf. aus localStorage wiederherstellen
    if (kIsWeb) {
      token = html.window.localStorage['dfs_token'];
      gate  = html.window.localStorage['dfs_gate'];
    }
  }

  // ---------- Storage Helpers ----------
  void _persistAuth() {
    if (!kIsWeb) return;
    if (token != null) {
      html.window.localStorage['dfs_token'] = token!;
    } else {
      html.window.localStorage.remove('dfs_token');
    }
    if (gate != null) {
      html.window.localStorage['dfs_gate'] = gate!;
    } else {
      html.window.localStorage.remove('dfs_gate');
    }
  }

  void logout() {
    token = null;
    _persistAuth();
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

  // ---------- Gate ----------
  Future<bool> gateUnlock(String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/gate'),
      headers: _headers(),
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode != 200) return false;
    try {
      final j = jsonDecode(r.body);
      // akzeptiert {ok:true} oder {gate:"..."}
      if (j is Map<String,dynamic>) {
        if (j['gate'] is String) {
          gate = j['gate'] as String;
          _persistAuth();
          return true;
        }
        if (j['ok'] == true) {
          // optional: Gate aus Header übernehmen?
          final g = r.headers['x-gate'];
          if (g != null && g.isNotEmpty) {
            gate = g;
            _persistAuth();
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // ---------- Auth ----------
  Future<bool> login(String email, String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/auth/login'),
      headers: _headers(),
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body);
      token = (j['token'] ?? '').toString();
      _persistAuth();
      return token != null && token!.isNotEmpty;
    }
    return false;
  }

  /// Gibt die http.Response zurück, damit der Aufrufer Statuscodes unterscheiden kann (200/409/400…)
  Future<http.Response> register(Map<String,dynamic> data) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/auth/register'),
      headers: _headers(),
      body: jsonEncode(data),
    );
    return r;
  }

  // ---------- Complaints (Kunden-Endpunkte) ----------
  Future<Map<String,dynamic>> complaintCreate(Map<String, dynamic> payload,
      List<({String name, List<int> bytes, String mime})> files) async {
    // Dein Backend nimmt JSON + (optional) Dateien im Array (Base64).
    final body = {
      'payload': payload,
      if (files.isNotEmpty)
        'files': files.map((f) => {
          'name': f.name,
          'mime': f.mime,
          'data': base64Encode(f.bytes),
        }).toList(),
    };

    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/complaint'),
      headers: _headers(auth: true),
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) {
      if (r.statusCode == 401) throw Exception('unauthorized');
      throw Exception('complaint create failed: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String,dynamic>;
  }

  Future<List<Map<String,dynamic>>> complaintListRaw() async {
    final r = await http.get(
      Uri.parse('${CFG.apiBase}/api/complaint'),
      headers: _headers(auth: true),
    );
    if (r.statusCode != 200) {
      if (r.statusCode == 401) throw Exception('unauthorized');
      throw Exception('complaint list failed: ${r.statusCode} ${r.body}');
    }
    final List data = jsonDecode(r.body);
    return data.cast<Map>().map((e)=>e.cast<String,dynamic>()).toList();
  }
}
