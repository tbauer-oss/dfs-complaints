// lib/models/complaint.dart
class Complaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int status;
  final String? decision;
  final String? reportLink;
  final Map<String, dynamic>? payload;

  // ⬇️ NEU: interne Reklamationsnummer
  final String? internalNo;

  Complaint({
    required this.ticket,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.decision,
    this.reportLink,
    this.payload,
    this.internalNo, // ⬅️ NEU
  });

  String get articleLabel {
    final p = payload;
    if (p == null) return '';
    final a = p['article'] ?? p['Artikel'];
    return (a ?? '').toString();
  }

  // ⬇️ Helper zum robusten Lesen der internen Nummer (mehrere mögliche Keys)
  static String? _parseInternal(dynamic j) {
    // Top-Level Varianten
    final top =
        (j is Map && j['internalNo'] != null) ? j['internalNo'] :
        (j is Map && j['internalId'] != null) ? j['internalId'] :
        (j is Map && j['internal']   != null) ? j['internal']   : null;
    if (top != null) {
      final s = top.toString().trim();
      if (s.isNotEmpty) return s;
    }
    // Falls in payload mitgegeben
    try {
      final p = (j is Map && j['payload'] is Map)
          ? (j['payload'] as Map).cast<String, dynamic>()
          : const <String,dynamic>{};
      final pay = p['internalNo'] ?? p['internalId'] ?? p['internal'];
      if (pay != null) {
        final s = pay.toString().trim();
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return null;
  }

  // ---------- bestehende Parser-Helper ----------
  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    if (v is String && v.trim().isNotEmpty) {
      final s = v.trim();
      final n = int.tryParse(s);
      if (n != null) {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      }
      try {
        return DateTime.parse(s).toUtc();
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static int _parseInt(dynamic v, {int def = 1}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v.trim());
      if (n != null) return n;
    }
    return def;
  }

  static String? _parseDecision(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'accepted' || s == 'rejected') return s;
    return null;
  }

  static Map<String, dynamic>? _parsePayload(dynamic v) {
    if (v is Map) {
      try {
        return v.cast<String, dynamic>();
      } catch (_) {
        final out = <String, dynamic>{};
        v.forEach((key, value) => out['$key'] = value);
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
      internalNo: _parseInternal(j), // ⬅️ NEU
    );
  }
}
