// lib/api/client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiClient {
  String? token;
  String? gate;

  Map<String, String> _headers({bool auth = false, Map<String, String>? extra}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      if (gate != null) 'X-Gate': gate!,
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  Future<bool> gateUnlock(String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/gate'),
      headers: _headers(),
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode != 200) return false;

    // tolerant auf {ok:true} oder {gate:"..."}
    try {
      final j = jsonDecode(r.body);
      if (j is Map<String, dynamic>) {
        if (j['gate'] is String) gate = j['gate'] as String;
        if (j['ok'] == true || gate != null) return true;
      }
    } catch (_) {}
    return true;
  }

  /// Registrierung: Sprache wird explizit übergeben (Header + Body)
  Future<http.Response> register(
    Map<String, dynamic> body, {
    String? lang,
  }) {
    final uri = Uri.parse('${CFG.apiBase}/api/auth/register');

    // Header inkl. Sprache
    final headers = _headers(extra: {
      if (lang != null) 'X-DFS-Lang': lang,
      if (lang != null) 'Accept-Language': lang,
    });

    // Body inkl. Sprache
    final payload = {
      ...body,
      if (lang != null) 'lang': lang,
    };

    return http.post(uri, headers: headers, body: jsonEncode(payload));
  }

  Future<bool> login(String email, String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/auth/login'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body);
      token = j['token'];
      return true;
    }
    return false;
  }

  Future<List<dynamic>> myComplaints() async {
    final r = await http.get(
      Uri.parse('${CFG.apiBase}/api/complaint/mine'),
      headers: _headers(auth: true),
    );
    if (r.statusCode == 200) return jsonDecode(r.body) as List;
    return [];
  }

  Future<Map<String, dynamic>?> submitComplaint(
    Map<String, String> fields,
    List<({String name, List<int> bytes, String mime})> files,
  ) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${CFG.apiBase}/api/complaint/create'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields['fields'] = jsonEncode(fields);
    for (final f in files) {
      req.files.add(
        http.MultipartFile.fromBytes('images', f.bytes, filename: f.name),
      );
    }
    final res = await req.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode == 200) {
      return jsonDecode(body) as Map<String, dynamic>;
    }
    return null;
  }
}
