// lib/models/complaint.dart
class Complaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int status;                  // 1..6
  final String? decision;            // 'accepted' | 'rejected' | null
  final String? reportLink;          // URL zum Bericht (optional)
  final Map<String, dynamic>? payload; // optionaler Nutzinhalt (z.B. article)

  Complaint({
    required this.ticket,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.decision,
    this.reportLink,
    this.payload,
  });

  /// Bequemer Anzeigename des Artikels (falls vom Backend mitgeschickt).
  /// Sucht zuerst 'article', dann deutsch 'Artikel'.
  String get articleLabel {
    final p = payload;
    if (p == null) return '';
    final a = p['article'] ?? p['Artikel'];
    return (a ?? '').toString();
  }

  // ---------- Parser-Helper ----------

  /// Robuste Timestamp-PARSER (int ms, int-String, oder ISO-String)
  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    // int (ms since epoch)
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    // int als String
    if (v is String && v.trim().isNotEmpty) {
      final s = v.trim();
      final n = int.tryParse(s);
      if (n != null) {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      }
      // ISO String
      try {
        return DateTime.parse(s).toUtc();
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Status 1..6 (akzeptiert Zahl oder Zahl-String; sonst Default)
  static int _parseInt(dynamic v, {int def = 1}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v.trim());
      if (n != null) return n;
    }
    return def;
  }

  /// Normalisiert decision auf 'accepted' | 'rejected' | null
  static String? _parseDecision(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'accepted' || s == 'rejected') return s;
    return null; // Unbekannte Werte ignorieren
  }

  /// Payload sicher zu Map<String,dynamic> casten
  static Map<String, dynamic>? _parsePayload(dynamic v) {
    if (v is Map) {
      try {
        return v.cast<String, dynamic>();
      } catch (_) {
        // Fallback: harte Kopie in Map<String,dynamic>
        final out = <String, dynamic>{};
        v.forEach((key, value) {
          out['$key'] = value;
        });
        return out;
      }
    }
    return null;
  }

  factory Complaint.fromJson(Map<String, dynamic> j) {
    return Complaint(
      ticket: (j['ticket'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      createdAt: _parseDate(j['createdAt']),
      updatedAt: _parseDate(j['updatedAt']),
      status: _parseInt(j['status'], def: 1),
      decision: _parseDecision(j['decision']),
      reportLink: (j['reportLink']?.toString().trim().isEmpty ?? true)
          ? null
          : j['reportLink']!.toString().trim(),
      payload: _parsePayload(j['payload']),
    );
  }
}
