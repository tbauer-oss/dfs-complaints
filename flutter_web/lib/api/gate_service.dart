// flutter_web/lib/api/gate_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://dfs-complaints-backend.vercel.app',
);

Future<bool> checkGate(String pwd) async {
  final uri = Uri.parse('$apiBase/api/gate');
  final resp = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'password': pwd}),
  );
  if (resp.statusCode == 200) {
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['ok'] == true;
  }
  if (resp.statusCode == 401) return false; // falsches Passwort
  throw Exception('Gate error ${resp.statusCode}: ${resp.body}');
}
