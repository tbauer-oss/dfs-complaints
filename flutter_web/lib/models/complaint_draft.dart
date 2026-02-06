// lib/models/complaint_draft.dart
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const draftListPrefKey = 'dfs_complaint_drafts_v2';
const legacyDraftPrefKey = 'dfs_complaint_draft_v1';

class ComplaintDraft {
  final String id;
  final Map<String, dynamic> data;

  ComplaintDraft({required this.id, required Map<String, dynamic> data})
      : data = Map.unmodifiable(data);

  ComplaintDraft copyWith({Map<String, dynamic>? data}) =>
      ComplaintDraft(id: id, data: data ?? this.data);

  DateTime get updatedAt {
    final raw = data['updatedAt']?.toString();
    if (raw == null || raw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String get article => (data['article'] ?? '').toString();
  String get batch => (data['batch'] ?? '').toString();
  String get description => (data['desc'] ?? '').toString();
  String get segmentKey => (data['segmentKey'] ?? '').toString();

  Map<String, dynamic> toJson() => {'id': id, 'data': data};

  static String newId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(99999).toString().padLeft(5, '0');
    return 'draft-$now-$rand';
  }

  static ComplaintDraft fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString();
    final raw = j['data'];
    final map = <String, dynamic>{};
    if (raw is Map) {
      raw.forEach((key, value) => map['$key'] = value);
    }
    return ComplaintDraft(id: id.isEmpty ? newId() : id, data: map);
  }

  static ComplaintDraft fromLegacy(Map<String, dynamic> data) =>
      ComplaintDraft(id: newId(), data: data);
}

class ComplaintDraftStore {
  Future<List<ComplaintDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(draftListPrefKey);
    if (raw == null || raw.isEmpty) return <ComplaintDraft>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ComplaintDraft>[];
      final list = <ComplaintDraft>[];
      for (final entry in decoded) {
        if (entry is Map) {
          list.add(ComplaintDraft.fromJson(entry.cast<String, dynamic>()));
        }
      }
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return <ComplaintDraft>[];
    }
  }

  Future<void> save(ComplaintDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadAll();
    final idx = existing.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      existing[idx] = draft;
    } else {
      existing.add(draft);
    }
    final payload = existing.map((d) => d.toJson()).toList(growable: false);
    await prefs.setString(draftListPrefKey, jsonEncode(payload));
    await prefs.remove(legacyDraftPrefKey);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadAll();
    existing.removeWhere((d) => d.id == id);
    final payload = existing.map((d) => d.toJson()).toList(growable: false);
    await prefs.setString(draftListPrefKey, jsonEncode(payload));
  }

  Future<ComplaintDraft?> findById(String id) async {
    final drafts = await loadAll();
    try {
      return drafts.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<ComplaintDraft?> latest() async {
    final drafts = await loadAll();
    if (drafts.isEmpty) return null;
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts.first;
  }

  Future<ComplaintDraft?> migrateLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(legacyDraftPrefKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = <String, dynamic>{};
      decoded.forEach((key, value) => map['$key'] = value);
      final draft = ComplaintDraft.fromLegacy(map);
      await save(draft);
      await prefs.remove(legacyDraftPrefKey);
      return draft;
    } catch (_) {
      return null;
    }
  }
}
