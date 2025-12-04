// lib/models/complaint.dart
class Complaint {
  final String ticket;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int status;
  final String? decision;
  final String? reportLink;
  final Map<String, String>? reportLinks; // neue Mehrsprachigkeit für Reports
  final Map<String, String>? externalReportLinks;
  final Map<String, String>? internalReportLinks;
  final String? qmCustomerSummary;
  final List<String> internalDepartments; // betroffene interne Abteilungen
  final String? internalEvaluationTextDe; // interne Bewertung (Deutsch)
  final String? internalEvaluationCause; // vermutete Ursache
  final Map<String, String>? internalEvaluationTranslations; // gespeicherte Übersetzungen
  final Map<String, dynamic>? payload;

  // ⬇️ NEU: interne Reklamationsnummer
  final String? internalNo;
  final List<ComplaintUpload> uploads;

  Complaint({
    required this.ticket,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.decision,
    this.reportLink,
    this.reportLinks,
    this.externalReportLinks,
    this.internalReportLinks,
    this.qmCustomerSummary,
    List<String>? internalDepartments,
    this.internalEvaluationTextDe,
    this.internalEvaluationCause,
    this.internalEvaluationTranslations,
    this.payload,
    this.internalNo, // ⬅️ NEU
    List<ComplaintUpload>? uploads,
  })  : internalDepartments = List.unmodifiable(internalDepartments ?? const <String>[]),
        uploads = List.unmodifiable(uploads ?? const <ComplaintUpload>[]);

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

  static List<ComplaintUpload> _parseUploads(dynamic value) {
    if (value is List) {
      final out = <ComplaintUpload>[];
      for (final entry in value) {
        if (entry is Map) {
          try {
            out.add(ComplaintUpload.fromJson(entry.cast<String, dynamic>()));
          } catch (_) {
            out.add(ComplaintUpload.fromJson(_coerceMap(entry)));
          }
        }
      }
      return List.unmodifiable(out);
    }
    return const <ComplaintUpload>[];
  }

  static Map<String, dynamic> _coerceMap(dynamic value) {
    final map = <String, dynamic>{};
    if (value is Map) {
      value.forEach((key, v) => map['$key'] = v);
    }
    return map;
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
      reportLinks: (j['reportLinks'] is Map)
          ? Map<String, String>.from((j['reportLinks'] as Map).map((k, v) => MapEntry('$k', v.toString())))
          : null,
      externalReportLinks: (j['externalReportLinks'] is Map)
          ? Map<String, String>.from((j['externalReportLinks'] as Map).map((k, v) => MapEntry('$k', v.toString())))
          : null,
      internalReportLinks: (j['internalReportLinks'] is Map)
          ? Map<String, String>.from((j['internalReportLinks'] as Map).map((k, v) => MapEntry('$k', v.toString())))
          : null,
      qmCustomerSummary: (j['qmCustomerSummary'] ?? j['qmCustomerSummary_de'])?.toString(),
      internalDepartments: _parseStringList(j['internalDepartments']),
      internalEvaluationTextDe: (j['internalEvaluationText_de'] ?? j['internalEvaluationTextDe'])
              ?.toString()
              .trim()
              .isEmpty ==
          true
          ? null
          : (j['internalEvaluationText_de'] ?? j['internalEvaluationTextDe'])?.toString(),
      internalEvaluationCause: (j['internalEvaluationCause'] ?? '').toString().trim().isEmpty
          ? null
          : j['internalEvaluationCause']?.toString(),
      internalEvaluationTranslations: (j['internalEvaluationTranslations'] is Map)
          ? Map<String, String>.from(
              (j['internalEvaluationTranslations'] as Map).map((k, v) => MapEntry('$k', v.toString())),
            )
          : null,
      payload: _parsePayload(j['payload']),
      internalNo: _parseInternal(j), // ⬅️ NEU
      uploads: _parseUploads(j['uploads']),
    );
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList(growable: false);
    }
    return const <String>[];
  }
}

class ComplaintUpload {
  final String name;
  final String mime;
  final int size;
  final DateTime? uploadedAt;
  final String? preview;
  final String? url;
  final String? downloadUrl;
  final String? blobPath;

  ComplaintUpload({
    required this.name,
    required this.mime,
    required this.size,
    required this.uploadedAt,
    this.preview,
    this.url,
    this.downloadUrl,
    this.blobPath,
  });

  bool get isImage => mime.toLowerCase().startsWith('image/');
  bool get hasPreview => isImage && ((preview ?? '').isNotEmpty || (imageUrl ?? '').isNotEmpty);
  String? get imageUrl {
    if (!isImage) return null;
    final candidate = (downloadUrl ?? url ?? '').trim();
    return candidate.isEmpty ? null : candidate;
  }

  static int _parseSize(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final n = int.tryParse(value.trim());
      if (n != null) return n;
    }
    return 0;
  }

  static DateTime? _parseUploadedAt(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      if (value <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is num) {
      final ms = value.toInt();
      if (ms <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final numeric = int.tryParse(trimmed);
      if (numeric != null) {
        if (numeric <= 0) return null;
        return DateTime.fromMillisecondsSinceEpoch(numeric, isUtc: true);
      }
      try {
        return DateTime.parse(trimmed).toUtc();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  factory ComplaintUpload.fromJson(Map<String, dynamic> json) {
    String? _preview(dynamic value) {
      if (value == null) return null;
      final s = value.toString().trim();
      return s.isEmpty ? null : s;
    }
    String? _url(dynamic value) {
      if (value == null) return null;
      final s = value.toString().trim();
      if (s.isEmpty) return null;
      if (!s.startsWith('http://') && !s.startsWith('https://')) return null;
      return s;
    }

    return ComplaintUpload(
      name: (json['name'] ?? '').toString(),
      mime: (json['mime'] ?? 'application/octet-stream').toString(),
      size: _parseSize(json['size']),
      uploadedAt: _parseUploadedAt(json['uploadedAt']),
      preview: _preview(json['preview']),
      url: _url(json['url'] ?? json['previewUrl']),
      downloadUrl: _url(json['downloadUrl'] ?? json['downloadURL']),
      blobPath: (json['blobPath'] ?? json['pathname'] ?? '').toString().trim().isEmpty
          ? null
          : (json['blobPath'] ?? json['pathname']).toString().trim(),
    );
  }
}
