import '../models/dfs_product.dart';
import 'dfs_product_service.dart';
import '../utils/gs1_data_matrix_parser.dart';

class ProductLookup {
  ProductLookup({DfsProductService? service})
      : _service = service ?? DfsProductService();

  final DfsProductService _service;
  List<DfsProduct> _products = const [];
  Map<String, DfsProduct> _index = const {};
  Map<String, DfsProduct> _gtinIndex = const {};

  List<DfsProduct> get products => _products;
  bool get hasProducts => _products.isNotEmpty;

  Future<List<DfsProduct>> loadProducts() async {
    final list = await _service.loadProducts();
    setProducts(list);
    return _products;
  }

  void setProducts(List<DfsProduct> list) {
    _products = List.unmodifiable(list);
    _index = {
      for (final p in _products)
        if (p.articleNumber.trim().isNotEmpty) p.articleNumber.trim(): p,
    };

    final gtinIndex = <String, DfsProduct>{};

    void addGtin(String raw, DfsProduct product) {
      final normalized = Gs1DataMatrixParser.normalizeGtin(raw);
      if (normalized != null) {
        gtinIndex.putIfAbsent(normalized, () => product);

        // Some scanners drop leading zeros on GTIN-14. Index an unpadded
        // variant as well to tolerate both forms.
        final unpadded = normalized.replaceFirst(RegExp('^0+'), '');
        if (unpadded.isNotEmpty) {
          gtinIndex.putIfAbsent(unpadded, () => product);
        }
      }
    }

    for (final p in _products) {
      addGtin(p.udiSingleUnit, p);
      addGtin(p.udiVe, p);
    }

    _gtinIndex = gtinIndex;
  }

  DfsProduct? byArticle(String? articleNumber) {
    final key = (articleNumber ?? '').trim();
    if (key.isEmpty) return null;
    return _index[key];
  }

  DfsProduct? byGtin(String? gtin) {
    final digits = Gs1DataMatrixParser.digitsOnly(gtin);
    if (digits == null || digits.isEmpty) return null;

    final normalized = Gs1DataMatrixParser.normalizeGtin(digits);
    if (normalized != null) {
      final product = _gtinIndex[normalized];
      if (product != null) return product;
    }

    final unpadded = digits.replaceFirst(RegExp('^0+'), '');
    if (unpadded.isNotEmpty) {
      final fallbackNormalized = Gs1DataMatrixParser.normalizeGtin(unpadded);
      if (fallbackNormalized != null) {
        final product = _gtinIndex[fallbackNormalized];
        if (product != null) return product;
      }
      return _gtinIndex[unpadded];
    }

    return null;
  }
}
