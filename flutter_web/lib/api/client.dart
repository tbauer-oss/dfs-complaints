// lib/api/client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import '../models/complaint.dart';

class ApiClient {
  String? token;
  String? gate;

  Map<String, String> _headers({bool auth = false, Map<String, String>? extra}) {
    final h = {
      'Content-Type': 'application/json',
      if (gate != null) 'X-Gate': gate!,
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  // --- bestehende gateUnlock etc. bleiben ---

  // ========================
  // Reklamation: Anlegen (POST /api/complaint)
  // ========================
  Future<Complaint> complaintCreate(Map<String, dynamic> payload) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/complaint'),
      headers: _headers(auth: true),
      body: jsonEncode(payload),
    );
    if (r.statusCode != 200) {
      throw Exception('complaint create failed: ${r.body}');
    }
    return Complaint.fromJson(jsonDecode(r.body));
    // erwartet: ein Complaint-Objekt (inkl. ticket, status usw.)
  }

  // ========================
  // Reklamation: Liste (GET /api/complaint)
  // ========================
  Future<List<Complaint>> complaintList() async {
    final r = await http.get(
      Uri.parse('${CFG.apiBase}/api/complaint'),
      headers: _headers(auth: true),
    );
    if (r.statusCode != 200) {
      throw Exception('complaint list failed: ${r.body}');
    }
    final List data = jsonDecode(r.body);
    return data.map((e) => Complaint.fromJson(e)).toList();
  }

  // ========================
  // Reklamation: Einzelnes Ticket (GET /api/complaint/<ticket>)
  // (nur falls du im Frontend eine Detailseite brauchst)
  // ========================
  Future<Complaint> complaintGet(String ticket) async {
    final r = await http.get(
      Uri.parse('${CFG.apiBase}/api/complaint/$ticket'),
      headers: _headers(auth: true),
    );
    if (r.statusCode != 200) {
      throw Exception('complaint get failed: ${r.body}');
    }
    return Complaint.fromJson(jsonDecode(r.body));
  }

  // ========================
  // Account lesen (GET /api/account)
  // ========================
  Future<Map<String, dynamic>> accountGet() async {
    final r = await http.get(
      Uri.parse('${CFG.apiBase}/api/account'),
      headers: _headers(auth: true),
    );
    if (r.statusCode != 200) throw Exception('account get failed: ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ========================
  // Account aktualisieren (PUT /api/account)
  // ========================
  Future<Map<String, dynamic>> accountUpdate(Map<String, dynamic> data) async {
    final r = await http.put(
      Uri.parse('${CFG.apiBase}/api/account'),
      headers: _headers(auth: true),
      body: jsonEncode(data),
    );
    if (r.statusCode != 200) throw Exception('account update failed: ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ========================
  // Passwort ändern (POST /api/account/password)
  // ========================
  Future<void> accountChangePassword(String oldPw, String newPw) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/account/password'),
      headers: _headers(auth: true),
      body: jsonEncode({'oldPassword': oldPw, 'newPassword': newPw}),
    );
    if (r.statusCode != 200) throw Exception('password change failed: ${r.body}');
  }

  // ========================
  // Account löschen (POST /api/account/delete)
  // ========================
  Future<void> accountDelete(String password) async {
    final r = await http.post(
      Uri.parse('${CFG.apiBase}/api/account/delete'),
      headers: _headers(auth: true),
      body: jsonEncode({'password': password}),
    );
    if (r.statusCode != 200) throw Exception('account delete failed: ${r.body}');
  }

  // ========================
  // DFS Support (POST /api/support)
  // ========================
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
    if (r.statusCode != 200) throw Exception('support send failed: ${r.body}');
  }
}
