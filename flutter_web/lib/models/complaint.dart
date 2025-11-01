// lib/models/complaint.dart
class Complaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int status; // 1..6
  final String? decision; // 'accepted' | 'rejected' | null
  final String? reportLink;

  Complaint({
    required this.ticket,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.decision,
    this.reportLink,
  });

  factory Complaint.fromJson(Map<String, dynamic> j) => Complaint(
    ticket: j['ticket'],
    email: j['email'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] ?? 0, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] ?? 0, isUtc: true),
    status: j['status'] ?? 1,
    decision: j['decision'],
    reportLink: j['reportLink'],
  );
}
