import 'package:flutter/material.dart';

import '../models/dfs_product.dart';
import '../services/dfs_product_service.dart';
import '../l10n/app_localizations.dart';

class RepProductListPage extends StatefulWidget {
  final List<String> articleNumbers;
  final String? productGroup;
  final String? title;

  const RepProductListPage({
    super.key,
    required this.articleNumbers,
    this.productGroup,
    this.title,
  });

  @override
  State<RepProductListPage> createState() => _RepProductListPageState();
}

class _RepProductListPageState extends State<RepProductListPage> {
  final _service = DfsProductService();
  List<DfsProduct> _items = const [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final products = await _service.loadProducts();
      setState(() {
        _items = products;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DfsProduct> _filtered() {
    List<DfsProduct> list = _items;
    if (widget.articleNumbers.isNotEmpty) {
      final target = widget.articleNumbers.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      list = list.where((p) => target.contains(p.articleNumber)).toList();
    } else if ((widget.productGroup ?? '').trim().isNotEmpty) {
      final group = widget.productGroup!.trim().toLowerCase();
      list = list
          .where((p) => p.productGroup.trim().toLowerCase() == group)
          .toList(growable: false);
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list.where((p) {
        return p.articleNumber.toLowerCase().contains(q) ||
            p.productName.toLowerCase().contains(q) ||
            p.productGroup.toLowerCase().contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final list = _filtered();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? t.repEarlyWarningProductsTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: t.repEarlyWarningSearchLabel,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : list.isEmpty
                          ? Center(child: Text(t.repEarlyWarningProductsEmpty))
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final isNarrow = constraints.maxWidth < 700;
                                return ListView.separated(
                                  itemCount: list.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) {
                                    final p = list[i];
                                    return Card(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    p.productName.isNotEmpty ? p.productName : p.articleNumber,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                if (p.productGroup.isNotEmpty)
                                                  Chip(
                                                    label: Text(p.productGroup),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 6,
                                              children: [
                                                _InfoPill(label: t.repEarlyWarningArticleLabel, value: p.articleNumber),
                                                if (p.isoCode.isNotEmpty)
                                                  _InfoPill(label: 'ISO', value: p.isoCode),
                                                if (p.packagingUnitVe.isNotEmpty)
                                                  _InfoPill(
                                                    label: t.repEarlyWarningPackaging,
                                                    value: p.packagingUnitVe,
                                                  ),
                                              ],
                                            ),
                                            if (!isNarrow) const SizedBox(height: 4),
                                            if (p.material.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 8),
                                                child: Text(
                                                  p.material,
                                                  style: Theme.of(context).textTheme.bodySmall,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(value),
        ],
      ),
    );
  }
}
