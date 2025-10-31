// lib/api/admin_service.dart (oder dein Pfad)
import 'dart:convert';
import 'package:http/http.dart' as http;

class AdminService {
  final String baseUrl;
  final String adminSecret;
  AdminService(this.baseUrl, this.adminSecret);

  Map<String,String> _hdr() => {
    'Content-Type':'application/json',
    'X-Admin-Secret': adminSecret,
  };

  dynamic _safeJson(String? s) {
    if (s == null || s.isEmpty) return null;
    try { return jsonDecode(s); } catch (_) { return null; }
  }

  Future<bool> approve(String email) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/admin/pending'),
      headers: _hdr(),
      body: jsonEncode({'action':'approve','email': email}),
    );
    if (r.statusCode == 200 || r.statusCode == 204) {
      _safeJson(r.body); // optional verwenden, aber nicht erzwingen
      return true;
    }
    // optional: Logging der Fehlermeldung aus dem Backend
    _safeJson(r.body);
    return false;
  }

  Future<bool> decline(String email) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/admin/pending'),
      headers: _hdr(),
      body: jsonEncode({'action':'decline','email': email}),
    );
    return (r.statusCode == 200 || r.statusCode == 204);
  }

  Future<List<dynamic>> listPending() async {
    final r = await http.get(Uri.parse('$baseUrl/api/admin/pending'), headers: _hdr());
    final j = _safeJson(r.body);
    return (r.statusCode == 200 && j is List) ? j : <dynamic>[];
  }

  Future<List<dynamic>> listUsers() async {
    final r = await http.get(Uri.parse('$baseUrl/api/admin/users'), headers: _hdr());
    final j = _safeJson(r.body);
    return (r.statusCode == 200 && j is List) ? j : <dynamic>[];
  }
}
