import '../models/dfs_product.dart';
import 'dfs_product_service.dart';

class ProductLookup {
  ProductLookup({DfsProductService? service})
      : _service = service ?? DfsProductService();

  final DfsProductService _service;
  List<DfsProduct> _products = const [];
  Map<String, DfsProduct> _gtinIndex = const {};
  Map<String, DfsProduct> _index = const {};

  List<DfsProduct> get products => _products;
  bool get hasProducts => _products.isNotEmpty;

  Future<List<DfsProduct>> loadProducts() async {
    final list = await _service.loadProducts();
    setProducts(list);
    return _products;
  }

  void setProducts(List<DfsProduct> list) {
    _products = List.unmodifiable(list);
    String normalize(String value) =>
        value.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toLowerCase();

    _index = {
      for (final p in _products)
        if (p.articleNumber.trim().isNotEmpty) p.articleNumber.trim(): p,
    };

    _gtinIndex = {
      for (final p in _products)
        for (final id in [
          p.basicUdiDi,
          p.udiSingleUnit,
          p.udiVe,
          p.articleNumber,
        ])
          if (normalize(id).isNotEmpty) normalize(id): p,
    };
  }

  DfsProduct? byArticle(String? articleNumber) {
    final key = (articleNumber ?? '').trim();
    if (key.isEmpty) return null;
    return _index[key];
  }

  DfsProduct? byGtin(String? gtin) {
    final key = (gtin ?? '').replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toLowerCase();
    if (key.isEmpty) return null;
    return _gtinIndex[key];
  }
}
