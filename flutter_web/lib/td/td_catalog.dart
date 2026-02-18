import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/td.dart';

class TdCatalogResult {
  final List<TdFile> items;
  final String source;

  const TdCatalogResult({required this.items, required this.source});
}

class TdCatalogBuilder {
  static const String _assetPath = 'assets/data/dfs_products.csv';
  static const String _storageKey = 'tdCatalogV1';
  static const Duration _ttl = Duration(hours: 24);

  static DateTime? _memoryLoadedAt;
  static List<TdFile>? _memoryCache;

  static Future<TdCatalogResult> loadCatalog() async {
    final now = DateTime.now();
    if (_memoryCache != null && _memoryLoadedAt != null && now.difference(_memoryLoadedAt!) < _ttl) {
      return TdCatalogResult(items: _memoryCache!, source: 'memory');
    }

    final storage = _fromLocalStorage(now);
    if (storage != null) {
      _memoryCache = storage;
      _memoryLoadedAt = now;
      return TdCatalogResult(items: storage, source: 'localStorage');
    }

    final csv = await loadDfsProductsCsv();
    final built = _buildFromCsv(csv);
    _memoryCache = built;
    _memoryLoadedAt = now;
    _saveToLocalStorage(now, built);
    return TdCatalogResult(items: built, source: 'csv');
  }

  static Future<String> loadDfsProductsCsv() {
    return rootBundle.loadString(_assetPath);
  }

  static List<TdFile> _buildFromCsv(String csv) {
    final lines = const LineSplitter().convert(csv).where((e) => e.trim().isNotEmpty).toList(growable: false);
    if (lines.length < 2) return const [];

    final header = _parseCsvLine(lines.first);
    final tdIndex = header.indexOf('td_number_and_name');
    final productGroupIndex = header.indexOf('product_group');

    final Map<String, _TdBucket> buckets = <String, _TdBucket>{};

    for (final line in lines.skip(1)) {
      final row = _parseCsvLine(line);
      final tdLabel = tdIndex >= 0 && tdIndex < row.length ? row[tdIndex].trim() : '';
      final productGroup = productGroupIndex >= 0 && productGroupIndex < row.length ? row[productGroupIndex].trim() : '';
      final key = _extractTdKey(tdLabel);
      if (key == null && !_mapsToTdModule(productGroup)) continue;
      if (key == null) continue;

      final bucket = buckets.putIfAbsent(key, () => _TdBucket(key: key, tdLabel: tdLabel, productGroup: productGroup));
      bucket.absorb(tdLabel, productGroup);
    }

    final entries = buckets.values.toList()
      ..sort((a, b) => _tdOrder(a.key).compareTo(_tdOrder(b.key)));

    return entries
        .map(
          (bucket) => TdFile(
            id: bucket.key,
            code: bucket.key,
            title: bucket.title,
            lifecycleState: 'Development',
            productGroup: bucket.productGroup.isNotEmpty ? bucket.productGroup : null,
            classification: null,
            rule: null,
            status: 'Draft',
            summary: const TdSummary(
              complianceScore: 0,
              readinessStatus: 'Yellow',
              overdueReviews: 0,
              openCapaCount: 0,
              reasons: <String>[],
            ),
          ),
        )
        .toList(growable: false);
  }

  static bool _mapsToTdModule(String productGroup) {
    final normalized = productGroup.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('dental') || normalized.contains('rot') || normalized.contains('fräser') || normalized.contains('polier');
  }

  static String? _extractTdKey(String raw) {
    if (raw.isEmpty) return null;
    final match = RegExp(r'(MDR-TD\s*\d+)', caseSensitive: false).firstMatch(raw);
    if (match == null) return null;
    return match.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  static int _tdOrder(String key) {
    final match = RegExp(r'MDR-TD(\d+)').firstMatch(key);
    return int.tryParse(match?.group(1) ?? '') ?? 9999;
  }

  static List<String> _parseCsvLine(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ';' && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(char);
      }
    }
    out.add(buf.toString());
    return out;
  }

  static List<TdFile>? _fromLocalStorage(DateTime now) {
    if (!kIsWeb) return null;
    try {
      final raw = html.window.localStorage[_storageKey];
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final loadedAt = DateTime.tryParse(decoded['loadedAt']?.toString() ?? '');
      if (loadedAt == null || now.difference(loadedAt) >= _ttl) return null;
      final items = (decoded['items'] as List?)
              ?.whereType<Map>()
              .map((e) => TdFile.fromJson(e.cast<String, dynamic>()))
              .toList(growable: false) ??
          const <TdFile>[];
      return items;
    } catch (_) {
      return null;
    }
  }

  static void _saveToLocalStorage(DateTime now, List<TdFile> items) {
    if (!kIsWeb) return;
    try {
      html.window.localStorage[_storageKey] = jsonEncode({
        'loadedAt': now.toIso8601String(),
        'items': items
            .map(
              (e) => {
                'id': e.id,
                'code': e.code,
                'title': e.title,
                'lifecycleState': e.lifecycleState,
                'productGroup': e.productGroup,
                'classification': e.classification,
                'rule': e.rule,
                'status': e.status,
                'summary': {
                  'complianceScore': e.summary.complianceScore,
                  'readinessStatus': e.summary.readinessStatus,
                  'overdueReviews': e.summary.overdueReviews,
                  'openCapaCount': e.summary.openCapaCount,
                  'reasons': e.summary.reasons,
                },
              },
            )
            .toList(growable: false),
      });
    } catch (_) {}
  }
}

class _TdBucket {
  final String key;
  String tdLabel;
  String productGroup;

  _TdBucket({required this.key, required this.tdLabel, required this.productGroup});

  String get title {
    if (tdLabel.trim().isNotEmpty) return tdLabel.trim();
    return key;
  }

  void absorb(String nextLabel, String nextGroup) {
    if (tdLabel.trim().isEmpty && nextLabel.trim().isNotEmpty) {
      tdLabel = nextLabel;
    }
    if (productGroup.trim().isEmpty && nextGroup.trim().isNotEmpty) {
      productGroup = nextGroup;
    }
  }
}
