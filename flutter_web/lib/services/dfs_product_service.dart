import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

import '../models/dfs_product.dart';

class DfsProductService {
  static const assetPath = 'lib/data/dfs_products.csv';

  Future<List<DfsProduct>> loadProducts() async {
    final csv = await rootBundle.loadString(assetPath);
    return parse(csv);
  }

  List<DfsProduct> parse(String content) {
    final lines = const LineSplitter().convert(content).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const [];

    final headers = _splitCsvLine(lines.first).map((h) => h.trim()).toList();
    final products = <DfsProduct>[];

    for (final line in lines.skip(1)) {
      final cells = _splitCsvLine(line);
      if (cells.isEmpty || cells.every((c) => c.trim().isEmpty)) continue;

      final map = <String, String>{};
      for (var i = 0; i < headers.length; i++) {
        if (i >= cells.length) break;
        map[headers[i]] = cells[i];
      }
      products.add(DfsProduct.fromHeaderMap(map));
    }

    return products;
  }

  List<String> _splitCsvLine(String line) {
    final values = <String>[];
    final current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      final isQuote = char == '"';
      final isDelimiter = char == ';';

      if (isQuote) {
        final isEscapedQuote = inQuotes && i + 1 < line.length && line[i + 1] == '"';
        if (isEscapedQuote) {
          current.write('"');
          i++; // Skip the escaped quote
          continue;
        }
        inQuotes = !inQuotes;
        continue;
      }

      if (isDelimiter && !inQuotes) {
        values.add(current.toString());
        current.clear();
        continue;
      }

      current.write(char);
    }

    values.add(current.toString());
    return values;
  }

  String exportCsv(List<DfsProduct> products, List<String> columns) {
    final buffer = StringBuffer();
    buffer.writeln(columns.join(';'));

    for (final p in products) {
      final map = p.toHeaderMap();
      final cells = columns.map((c) => _escapeCsv(map[c] ?? '')); // ensure order
      buffer.writeln(cells.join(';'));
    }

    return buffer.toString();
  }

  String _escapeCsv(String value) {
    final needsQuotes = value.contains(';') || value.contains('"') || value.contains('\n');
    if (!needsQuotes) return value;
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
