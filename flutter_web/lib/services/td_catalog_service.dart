import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import '../api/config.dart';

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

class TdCatalogService {
  static const String endpoint = '/api/td/catalog';
  List<ProductRow>? _memoryCache;

  String _resolveApiBase() {
    const defined = String.fromEnvironment('API_BASE', defaultValue: '');
    if (defined.isNotEmpty) return defined;
    try {
      final stored = html.window.localStorage['API_BASE'] ?? '';
      if (stored.trim().isNotEmpty) return stored.trim();
    } catch (_) {}
    return CFG.apiBase;
  }

  Future<List<ProductRow>> loadProducts({bool forceRefresh = false}) async {
    if (!forceRefresh && _memoryCache != null) {
      return _memoryCache!;
    }

    final base = _resolveApiBase().replaceAll(RegExp(r'/+$'), '');
    final response = await http.get(Uri.parse('$base$endpoint'));
    if (response.statusCode != 200) {
      throw TdCatalogLoadException('TD catalog request failed: ${response.statusCode}');
    }

    final decoded = response.body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const TdCatalogLoadException('TD catalog response is not a JSON object');
    }

    final items = (decoded['items'] as List?) ?? const [];
    final rows = items.whereType<Map>().map((item) {
      final row = item.cast<String, dynamic>();
      return ProductRow({
        'td_number_and_name': (row['title'] ?? '').toString(),
        'product_group': (row['product_group'] ?? '').toString(),
        'risk_class': (row['risk_class'] ?? '').toString(),
      });
    }).toList(growable: false);

    _memoryCache = rows;
    return rows;
  }
}

final TdCatalogService tdCatalogService = TdCatalogService();
