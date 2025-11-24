class AdminMailLogEntry {
  final String id;
  final String to;
  final String? cc;
  final String? bcc;
  final String subject;
  final String category;
  final String status;
  final String? template;
  final String? error;
  final int attempts;
  final DateTime? createdAt;
  final DateTime? sentAt;
  final DateTime? lastTriedAt;
  final Map<String, dynamic> meta;

  AdminMailLogEntry({
    required this.id,
    required this.to,
    required this.subject,
    required this.category,
    required this.status,
    this.cc,
    this.bcc,
    this.template,
    this.error,
    this.attempts = 0,
    this.createdAt,
    this.sentAt,
    this.lastTriedAt,
    Map<String, dynamic>? meta,
  }) : meta = meta ?? const <String, dynamic>{};

  factory AdminMailLogEntry.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      if (v is num) {
        try {
          return DateTime.fromMillisecondsSinceEpoch(v.toInt());
        } catch (_) {
          return null;
        }
      }
      if (v is String && v.trim().isNotEmpty) {
        return DateTime.tryParse(v.trim());
      }
      return null;
    }

    String pickAddress(dynamic v) {
      if (v is List) {
        final nonEmpty = v.map((e) => e?.toString() ?? '').where((e) => e.trim().isNotEmpty).toList();
        if (nonEmpty.isNotEmpty) return nonEmpty.join(', ');
      }
      return (v ?? '').toString();
    }

    return AdminMailLogEntry(
      id: (json['id'] ?? json['messageId'] ?? '').toString(),
      to: pickAddress(json['to'] ?? json['recipient']),
      cc: pickAddress(json['cc']).trim().isEmpty ? null : pickAddress(json['cc']),
      bcc: pickAddress(json['bcc']).trim().isEmpty ? null : pickAddress(json['bcc']),
      subject: (json['subject'] ?? '').toString(),
      category: (json['category'] ?? json['type'] ?? '').toString(),
      status: (json['status'] ?? json['state'] ?? '').toString(),
      template: (json['template'] ?? json['kind'])?.toString(),
      error: (json['error'] ?? json['lastError'])?.toString(),
      attempts: (json['attempts'] is num) ? (json['attempts'] as num).toInt() : 0,
      createdAt: parseTs(json['createdAt'] ?? json['created']),
      sentAt: parseTs(json['sentAt'] ?? json['deliveredAt'] ?? json['sent']),
      lastTriedAt: parseTs(json['lastTriedAt'] ?? json['lastAttempt']),
      meta: json['meta'] is Map<String, dynamic>
          ? json['meta'] as Map<String, dynamic>
          : (json['meta'] is Map)
              ? Map<String, dynamic>.from(json['meta'] as Map)
              : const <String, dynamic>{},
    );
  }

  String get normalizedStatus {
    final s = status.toLowerCase().trim();
    if (['sent', 'delivered', 'ok', 'success'].contains(s)) return 'sent';
    if (['failed', 'error', 'bounce'].contains(s)) return 'failed';
    if (['queued', 'pending', 'retry', 'scheduled', 'requeued'].contains(s)) return 'queued';
    return s.isEmpty ? 'unknown' : s;
  }

  String get displayCategory {
    if (category.trim().isEmpty) return 'Sonstige';
    switch (category.trim().toLowerCase()) {
      case 'register':
      case 'registration':
        return 'Registrierung';
      case 'support':
        return 'Support';
      case 'complaint-xml':
      case 'xml':
        return 'Complaint-XML';
      case 'decision':
      case 'resolution':
        return 'Entscheidung';
      case 'reset-password':
      case 'reset':
      case 'password':
        return 'Reset-Passwort';
      default:
        return category.trim();
    }
  }
}

class AdminMailLogStats {
  final int total;
  final int sent;
  final int failed;
  final int queued;

  AdminMailLogStats({
    required this.total,
    required this.sent,
    required this.failed,
    required this.queued,
  });

  factory AdminMailLogStats.fromJson(Map<String, dynamic> json) {
    int pick(String k) => (json[k] is num) ? (json[k] as num).toInt() : 0;
    return AdminMailLogStats(
      total: pick('total'),
      sent: pick('sent'),
      failed: pick('failed'),
      queued: pick('queued'),
    );
  }
}

class AdminMailCenterPayload {
  final List<AdminMailLogEntry> items;
  final AdminMailLogStats? stats;

  AdminMailCenterPayload({
    required this.items,
    this.stats,
  });
}
