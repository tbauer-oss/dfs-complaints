import 'dart:async';
import 'dart:html' as html;
import 'dart:math';

import '../models/internal_error_model.dart';

class InternalErrorService {
  InternalErrorService._();

  static final InternalErrorService instance = InternalErrorService._();

  static const String _storageKey = 'dfs_internal_errors_v1';
  static const String _sequencePrefix = 'dfs_internal_errors_seq_';

  // TODO: replace localStorage persistence with API/DB-backed storage for multi-user consistency.

  Future<void> _mutex = Future.value();
  List<InternalError> _cache = [];
  bool _loaded = false;

  Future<List<InternalError>> fetchAll() async {
    await _ensureLoaded();
    return List.unmodifiable(_cache);
  }

  Future<InternalError> create(InternalError draft, {String? createdBy}) {
    return _enqueue(() async {
      await _ensureLoaded();
      final createdAt = draft.createdAt;
      final year = createdAt.year;
      final sequence = _nextSequence(year);
      final code = _buildErrorCode(year, sequence);
      final updated = draft
          .copyWith(
            id: _newId(),
            year: year,
            sequence: sequence,
            errorCode: code,
            createdBy: createdBy ?? draft.createdBy,
          )
          .recalcDerived();
      _cache = [updated, ..._cache];
      _persist();
      return updated;
    });
  }

  Future<InternalError> update(InternalError entry) {
    return _enqueue(() async {
      await _ensureLoaded();
      final index = _cache.indexWhere((e) => e.id == entry.id);
      if (index == -1) {
        throw StateError('Internal error not found');
      }
      final recalculated = entry.recalcDerived();
      _cache = [..._cache]..[index] = recalculated;
      _persist();
      return recalculated;
    });
  }

  Future<void> delete(String id) {
    return _enqueue(() async {
      await _ensureLoaded();
      _cache = _cache.where((e) => e.id != id).toList();
      _persist();
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = html.window.localStorage[_storageKey];
    if (raw != null && raw.isNotEmpty) {
      _cache = InternalError.decodeList(raw);
      _cache.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    _loaded = true;
  }

  void _persist() {
    html.window.localStorage[_storageKey] = InternalError.encodeList(_cache);
  }

  int _nextSequence(int year) {
    final key = '$_sequencePrefix$year';
    final stored = int.tryParse(html.window.localStorage[key] ?? '') ?? 0;
    final maxCurrent = _cache.where((e) => e.year == year).map((e) => e.sequence).fold(0, max);
    var next = max(maxCurrent, stored) + 1;
    var code = _buildErrorCode(year, next);
    while (_cache.any((e) => e.errorCode == code)) {
      next += 1;
      code = _buildErrorCode(year, next);
    }
    html.window.localStorage[key] = next.toString();
    return next;
  }

  String _buildErrorCode(int year, int sequence) {
    final yy = (year % 100).toString().padLeft(2, '0');
    final seq = sequence.toString().padLeft(4, '0');
    return 'F$yy-$seq';
  }

  String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(9999).toString().padLeft(4, '0');
    return '$now-$rand';
  }

  Future<T> _enqueue<T>(FutureOr<T> Function() action) {
    final completer = Completer<T>();
    _mutex = _mutex.then((_) async {
      final result = await action();
      completer.complete(result);
    }).catchError((error, stack) {
      completer.completeError(error, stack);
    });
    return completer.future;
  }
}
