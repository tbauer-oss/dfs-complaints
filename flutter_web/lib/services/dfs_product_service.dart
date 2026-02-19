import '../models/dfs_product.dart';
import 'td_catalog_service.dart';

class DfsProductService {
  Future<List<DfsProduct>> loadProducts({bool forceRefresh = false}) async {
    final rows = await tdCatalogService.loadProducts(forceRefresh: forceRefresh);
    return rows.map((row) => DfsProduct.fromHeaderMap(row.values)).toList(growable: false);
  }

  List<DfsProduct> parse(String content) {
    throw UnsupportedError('DfsProductService.parse is deprecated. Use TdCatalogService API loading.');
  }

  String exportCsv(List<DfsProduct> products, List<String> columns) {
    final buffer = StringBuffer();
    buffer.writeln(columns.join(';'));

    for (final p in products) {
      final map = p.toHeaderMap();
      final cells = columns.map((c) => _escapeCsv(map[c] ?? ''));
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
