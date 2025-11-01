// lib/models/complaint.dart
class Complaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int status;              // 1..6
  final String? decision;        // 'accepted' | 'rejected' | null
  final String? reportLink;

  // Optional: Rohdaten der Meldung, falls vom Backend mitgeliefert (payload/data)
  // -> Hilfreich für Anzeige z. B. des Artikels in der Liste
  final Map<String, dynamic>? payload;

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

  // ---- Helpers -------------------------------------------------------------

  /// Versucht robust, Timestamps aus int, String (ISO/epoch), DateTime zu lesen.
  static DateTime _toDateTime(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (v is DateTime) return v.toUtc();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null) return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Stellt sicher, dass `status` ein int ist.
  static int _toInt(dynamic v, [int fallback = 1]) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// Liefert – falls vorhanden – einen Artikeltext aus payload/data.
  String get articleLabel {
    final p = payload;
    if (p == null) return '';
    final a = p['article'] ?? p['Artikel'];
    return (a ?? '').toString();
  }

  int get createdMs => createdAt.millisecondsSinceEpoch;
  int get updatedMs => updatedAt.millisecondsSinceEpoch;

  // ---- JSON I/O ------------------------------------------------------------

  factory Complaint.fromJson(Map<String, dynamic> j) {
    // payload/data tolerant abgreifen
    Map<String, dynamic>? _payload;
    final rawPayload = j['payload'] ?? j['data'];
    if (rawPayload is Map) _payload = rawPayload.cast<String, dynamic>();

    return Complaint(
      ticket: (j['ticket'] ?? '').toString(),
      email: (j['email']  ?? '').toString(),
      createdAt: _toDateTime(j['createdAt']),
      updatedAt: _toDateTime(j['updatedAt']),
      status: _toInt(j['status'], 1),
      decision: j['decision']?.toString(),
      reportLink: j['reportLink']?.toString(),
      payload: _payload,
    );
  }

  Map<String, dynamic> toJson() => {
    'ticket': ticket,
    'email': email,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'status': status,
    'decision': decision,
    'reportLink': reportLink,
    if (payload != null) 'payload': payload,
  };

  // ---- Convenience ---------------------------------------------------------

  Complaint copyWith({
    String? ticket,
    String? email,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? status,
    String? decision,
    String? reportLink,
    Map<String, dynamic>? payload,
  }) {
    return Complaint(
      ticket: ticket ?? this.ticket,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      decision: decision ?? this.decision,
      reportLink: reportLink ?? this.reportLink,
      payload: payload ?? this.payload,
    );
  }

  @override
  String toString() =>
      'Complaint(ticket=$ticket, email=$email, status=$status, decision=$decision)';

  @override
  bool operator ==(Object other) =>// lib/models/complaint.dart
class Complaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int status;              // 1..6
  final String? decision;        // 'accepted' | 'rejected' | null
  final String? reportLink;
  final Map<String, dynamic>? payload; // optional

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

  static DateTime _toDateTime(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (v is DateTime) return v.toUtc();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null) return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static int _toInt(dynamic v, [int fb = 1]) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fb;
    return fb;
  }

  String get articleLabel {
    final p = payload;
    if (p == null) return '';
    final a = p['article'] ?? p['Artikel'];
    return (a ?? '').toString();
  }

  factory Complaint.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? p;
    final rawP = j['payload'] ?? j['data'];
    if (rawP is Map) p = rawP.cast<String, dynamic>();
    return Complaint(
      ticket: (j['ticket'] ?? '').toString(),
      email: (j['email']  ?? '').toString(),
      createdAt: _toDateTime(j['createdAt']),
      updatedAt: _toDateTime(j['updatedAt']),
      status: _toInt(j['status'], 1),
      decision: j['decision']?.toString(),
      reportLink: j['reportLink']?.toString(),
      payload: p,
    );
  }

  Map<String, dynamic> toJson() => {
    'ticket': ticket,
    'email': email,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'status': status,
    'decision': decision,
    'reportLink': reportLink,
    if (payload != null) 'payload': payload,
  };
}

      identical(this, other) ||
      other is Complaint &&
          runtimeType == other.runtimeType &&
          ticket == other.ticket &&
          email == other.email &&
          status == other.status &&
          decision == other.decision &&
          reportLink == other.reportLink &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      ticket.hashCode ^
      email.hashCode ^
      status.hashCode ^
      (decision?.hashCode ?? 0) ^
      (reportLink?.hashCode ?? 0) ^
      createdAt.hashCode ^
      updatedAt.hashCode;
}
