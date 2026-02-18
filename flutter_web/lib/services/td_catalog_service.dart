import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ProductRow {
  final Map<String, String> values;

  const ProductRow(this.values);

  String operator [](String key) => values[key] ?? '';
}

class TdCatalogLoadException implements Exception {
  final String message;

  const TdCatalogLoadException(this.message);

  @override
  String toString() => message;
}

class TdCatalogCsvLoadResult {
  final List<ProductRow> rows;
  final String strategy;
  final String sourcePath;
  final int bytes;
  final int lineCount;

  const TdCatalogCsvLoadResult({
    required this.rows,
    required this.strategy,
    required this.sourcePath,
    required this.bytes,
    required this.lineCount,
  });
}

class TdCatalogService {
  static const String assetPath = 'assets/data/dfs_products.csv';
  static const List<String> webFallbackPaths = [
    'assets/assets/data/dfs_products.csv',
    'assets/data/dfs_products.csv',
  ];

  TdCatalogCsvLoadResult? _memoryCache;

  Future<List<ProductRow>> loadDfsProductsCsv({bool forceRefresh = false}) async {
    final result = await loadDfsProductsCsvWithDiagnostics(forceRefresh: forceRefresh);
    return result.rows;
  }

  Future<TdCatalogCsvLoadResult> loadDfsProductsCsvWithDiagnostics({bool forceRefresh = false}) async {
    if (!forceRefresh && _memoryCache != null) {
      if (kDebugMode) {
        debugPrint('[td_catalog] strategy=memory source=${_memoryCache!.sourcePath} lines=${_memoryCache!.lineCount} bytes=${_memoryCache!.bytes}');
      }
      return _memoryCache!;
    }

    try {
      final content = await rootBundle.loadString(assetPath);
      final result = _parseCsvContent(content, strategy: 'bundle', sourcePath: assetPath);
      _memoryCache = result;
      _logDebug(result);
      return result;
    } catch (bundleError) {
      if (!kIsWeb) {
        throw TdCatalogLoadException('TD-Katalog konnte nicht aus Bundle geladen werden ($assetPath): $bundleError');
      }

      TdCatalogLoadException? lastError;
      for (final url in webFallbackPaths) {
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode != 200) {
            throw TdCatalogLoadException('TD-Katalog HTTP-Fallback fehlgeschlagen: url=$url status=${response.statusCode}');
          }
          final result = _parseCsvContent(
            response.body,
            strategy: 'http-fallback',
            sourcePath: url,
          );
          _memoryCache = result;
          _logDebug(result);
          return result;
        } catch (error) {
          lastError = error is TdCatalogLoadException
              ? error
              : TdCatalogLoadException('TD-Katalog HTTP-Fallback fehlgeschlagen: url=$url error=$error');
        }
      }

      throw TdCatalogLoadException(
        'TD-Katalog konnte nicht geladen werden. Bundle-Fehler: $bundleError. '
        'Letzter HTTP-Fallback-Fehler: ${lastError?.message ?? 'unbekannt'}.',
      );
    }
  }

  TdCatalogCsvLoadResult _parseCsvContent(
    String content, {
    required String strategy,
    required String sourcePath,
  }) {
    final normalized = content.trimLeft().toLowerCase();
    if (normalized.startsWith('<!doctype') || normalized.startsWith('<html')) {
      throw TdCatalogLoadException('Ungültiger CSV-Inhalt aus $sourcePath (HTML statt CSV).');
    }

    final lines = const LineSplitter().convert(content).where((line) => line.trim().isNotEmpty).toList(growable: false);
    if (lines.isEmpty) {
      return TdCatalogCsvLoadResult(
        rows: const [],
        strategy: strategy,
        sourcePath: sourcePath,
        bytes: utf8.encode(content).length,
        lineCount: 0,
      );
    }

    final header = _parseCsvLine(lines.first).map((cell) => cell.trim()).toList(growable: false);
    final rows = <ProductRow>[];

    for (final line in lines.skip(1)) {
      final cells = _parseCsvLine(line);
      if (cells.isEmpty || cells.every((c) => c.trim().isEmpty)) continue;
      final values = <String, String>{};
      for (var i = 0; i < header.length; i++) {
        if (i >= cells.length) break;
        values[header[i]] = cells[i].trim();
      }
      rows.add(ProductRow(values));
    }

    return TdCatalogCsvLoadResult(
      rows: rows,
      strategy: strategy,
      sourcePath: sourcePath,
      bytes: utf8.encode(content).length,
      lineCount: lines.length,
    );
  }

  void _logDebug(TdCatalogCsvLoadResult result) {
    if (!kDebugMode) return;
    debugPrint('[td_catalog] strategy=${result.strategy} source=${result.sourcePath} lines=${result.lineCount} bytes=${result.bytes} rows=${result.rows.length}');
  }

  List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ';' && !inQuotes) {
        values.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }

    values.add(current.toString());
    return values;
  }
}

final TdCatalogService tdCatalogService = TdCatalogService();
