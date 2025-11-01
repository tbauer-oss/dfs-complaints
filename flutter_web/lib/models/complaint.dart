// lib/models/complaint.dart

class Complaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// 1 = gesendet, 2 = in Bearbeitung, 3 = Rückfrage,
  /// 4 = Entscheidung (accepted/rejected), 5 = Nacharbeit, 6 = abgeschlossen
  final int status;
  /// 'accepted' | 'rejected' | null
  final String? decision;
  /// Link zum Reklamationsbericht (optional)
  final String? reportLink;
  /// Original-Client-Payload (z. B. article/Artikel, batch, …)
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

  factory Complaint.fromJson(Map<String, dynamic> j) {
    DateTime _ts(dynamic v) {
      if (v == null) {
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      if (v is int) {
        return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
      }
      if (v is String) {
        final asInt = int.tryParse(v);
        if (asInt != null) {
          return DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true);
        }
        return DateTime.tryParse(v)?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final Map<String, dynamic>? pl =
        (j['payload'] is Map) ? (j['payload'] as Map).cast<String, dynamic>() : null;

    return Complaint(
      ticket: (j['ticket'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      createdAt: _ts(j['createdAt']),
      updatedAt: _ts(j['updatedAt']),
      status: j['status'] is int ? j['status'] as int
            : int.tryParse('${j['status'] ?? 1}') ?? 1,
      decision: j['decision']?.toString(),
      reportLink: j['reportLink']?.toString(),
      payload: pl,
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

  // Bequeme Helfer – nützlich falls irgendwo Millisekunden erwartet werden
  int get createdAtMs => createdAt.millisecondsSinceEpoch;
  int get updatedAtMs => updatedAt.millisecondsSinceEpoch;

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
  String toString() => 'Complaint(ticket: $ticket, status: $status)';
}
