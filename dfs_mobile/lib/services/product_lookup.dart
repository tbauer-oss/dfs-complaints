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
      if (normalized != null && !gtinIndex.containsKey(normalized)) {
        gtinIndex[normalized] = product;
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
    final key = Gs1DataMatrixParser.normalizeGtin(gtin);
    if (key == null) return null;
    return _gtinIndex[key];
  }
}
