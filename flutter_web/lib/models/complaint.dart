// lib/models/complaint.dart
class Complaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int status;                 // 1..6
  final String? decision;           // 'accepted' | 'rejected' | null
  final String? reportLink;         // URL zum Bericht (optional)
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

  /// Robuste Timestamp-PARSER (int ms oder ISO-String)
  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    }
    if (v is String && v.trim().isNotEmpty) {
      // Fallback: ISO-String
      try {
        return DateTime.parse(v).toUtc();
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

  static int _parseInt(dynamic v, {int def = 0}) {
    if (v is int) return v;
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null) return n;
    }
    return def;
  }

  factory Complaint.fromJson(Map<String, dynamic> j) {
    return Complaint(
      ticket: (j['ticket'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      createdAt: _parseDate(j['createdAt']),
      updatedAt: _parseDate(j['updatedAt']),
      status: _parseInt(j['status'], def: 1),
      decision: j['decision']?.toString(),
      reportLink: j['reportLink']?.toString(),
      payload: (j['payload'] is Map)
          ? (j['payload'] as Map).cast<String, dynamic>()
          : null,
    );
  }
}
