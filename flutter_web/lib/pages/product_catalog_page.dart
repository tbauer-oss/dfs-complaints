import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/dfs_product.dart';
import '../services/dfs_product_service.dart';

class ProductCatalogPage extends StatefulWidget {
  final List<DfsProduct> products;
  final bool loading;
  final String? error;
  final Future<void> Function()? onReload;
  final ValueChanged<List<DfsProduct>> onProductsChanged;

  const ProductCatalogPage({
    super.key,
    required this.products,
    required this.onProductsChanged,
    this.loading = false,
    this.error,
    this.onReload,
  });

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage> {
  final _service = DfsProductService();
  late List<DfsProduct> _items;
  final Map<String, TextEditingController> _filterCtrls = {};
  String _globalSearch = '';
  int _rowsPerPage = 10;
  bool _showFilters = true;
  final _tableScrollController = ScrollController();
  final _verticalTableScrollController = ScrollController();

  static const _tdNumberAndNameOptions = [
    'MDR-TD1 - rot. Dentalinstrumente',
    'MDR-TD2 - Knochenfräser',
    'MDR-TD3 - Dentalpolierer',
    'TD4 - PreciCut',
    'TD5 - Dentallegierungen',
    'SET',
  ];

  static const _scrollDragDevices = <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  static const _dropdownKeys = <String>{
    'td_number_and_name',
    'basic_udi_di',
    'product_group',
    'risk_class',
    'classification_rule',
    'mdr_code',
    'gmdn',
    'umdns_code',
    'emdn',
    'dmids_no',
    'certification_no',
    'material',
  };

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.products);
    for (final key in DfsProduct.fieldOrder) {
      _filterCtrls[key] = TextEditingController();
      _filterCtrls[key]!.addListener(() => setState(() {}));
    }
  }

  @override
  void didUpdateWidget(covariant ProductCatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.products != widget.products) {
      setState(() => _items = List.of(widget.products));
    }
  }

  @override
  void dispose() {
    _tableScrollController.dispose();
    _verticalTableScrollController.dispose();
    for (final ctrl in _filterCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  List<DfsProduct> _applyFilters() {
    final filters = _filterCtrls.map((key, ctrl) => MapEntry(key, ctrl.text.trim().toLowerCase()));
    final search = _globalSearch.trim().toLowerCase();

    return _items.where((p) {
      final map = p.toHeaderMap();

      if (search.isNotEmpty && !map.values.any((v) => v.toLowerCase().contains(search))) {
        return false;
      }

      for (final entry in filters.entries) {
        final filter = entry.value;
        if (filter.isEmpty) continue;
        if (!(map[entry.key]?.toLowerCase().contains(filter) ?? false)) return false;
      }

      return true;
    }).toList();
  }

  Iterable<String> _optionsFor(String key) {
    if (key == 'td_number_and_name') {
      return _tdNumberAndNameOptions;
    }

    final values = _items
        .map((p) =>
            p.fieldValue(key).replaceAll('\n', ' ').replaceAll(RegExp(' +'), ' ').trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  Future<void> _openEditor({DfsProduct? product}) async {
    final isEdit = product != null;
    final controllers = <String, TextEditingController>{};

    for (final key in DfsProduct.fieldOrder) {
      final initial = product?.fieldValue(key) ?? '';
      controllers[key] = TextEditingController(text: initial);
    }

    Future<void> disposeControllers() async {
      for (final c in controllers.values) {
        c.dispose();
      }
    }

    final result = await showDialog<DfsProduct>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Artikel bearbeiten' : 'Neuen Artikel anlegen'),
        content: SizedBox(
          width: 780,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: DfsProduct.fieldOrder.map((key) {
                    final label = DfsProduct.fieldLabels[key] ?? key;
                    final controller = controllers[key]!;
                    final options = _dropdownKeys.contains(key) ? _optionsFor(key) : const <String>[];

                    if (_dropdownKeys.contains(key)) {
                      return SizedBox(
                        width: 360,
                        child: DropdownMenu<String>(
                          controller: controller,
                          label: Text(label),
                          dropdownMenuEntries:
                              options.map((v) => DropdownMenuEntry<String>(value: v, label: v)).toList(),
                          enableFilter: true,
                          requestFocusOnTap: true,
                          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
                        ),
                      );
                    }

                    return SizedBox(
                      width: 360,
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: label,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              final map = controllers.map((key, ctrl) => MapEntry(key, ctrl.text.trim()));
              final updated = DfsProduct.fromHeaderMap(map);
              Navigator.pop(ctx, updated);
            },
            child: Text(isEdit ? 'Speichern' : 'Anlegen'),
          ),
        ],
      ),
    );

    await disposeControllers();

    if (result == null) return;

    setState(() {
      if (isEdit) {
        final idx = _items.indexWhere((p) => p.articleNumber == product!.articleNumber);
        if (idx >= 0) {
          _items[idx] = result;
        }
      } else {
        _items.add(result);
      }
    });

    widget.onProductsChanged(_items);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? 'Artikel aktualisiert.' : 'Artikel hinzugefügt.')),
      );
    }
  }

  Future<void> _deleteProduct(DfsProduct product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Artikel löschen'),
        content: Text('Soll ${product.articleNumber} wirklich entfernt werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _items.removeWhere((p) => p.articleNumber == product.articleNumber));
    widget.onProductsChanged(_items);
  }

  Future<void> _export(List<DfsProduct> source) async {
    final selected = Set<String>.from(DfsProduct.fieldOrder);
    final confirmed = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Export konfigurieren'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ...DfsProduct.fieldOrder.map((key) => CheckboxListTile(
                          value: selected.contains(key),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                selected.add(key);
                              } else {
                                selected.remove(key);
                              }
                            });
                          },
                          title: Text(DfsProduct.fieldLabels[key] ?? key),
                        )),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Spalten auswählen oder alle übernehmen.',
                        style: Theme.of(ctx)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
              FilledButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected),
                child: const Text('Export starten'),
              ),
            ],
          );
        });
      },
    );

    if (confirmed == null || confirmed.isEmpty) return;

    final columns = DfsProduct.fieldOrder.where((c) => confirmed.contains(c)).toList();
    final csv = _service.exportCsv(source, columns);
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'artikelliste.csv')
      ..click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _applyFilters();
    final dataSource = _ProductDataSource(
      products: filtered,
      onEdit: _openEditor,
      onDelete: _deleteProduct,
    );

    var rowsPerPage = _rowsPerPage;
    if (filtered.isNotEmpty) {
      rowsPerPage = math.min(rowsPerPage, filtered.length);
    }
    final effectiveRowsPerPage = rowsPerPage.clamp(1, math.max(1, rowsPerPage)).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.inventory_2_outlined),
            const SizedBox(width: 8),
            Text('Artikelliste', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Suchen (alle Felder)',
                ),
                onChanged: (v) => setState(() => _globalSearch = v),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Neu laden',
              icon: widget.loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: widget.onReload,
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Artikel hinzufügen'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: filtered.isEmpty ? null : () => _export(filtered),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Exportieren'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.filter_alt_outlined),
                    const SizedBox(width: 8),
                    Text('Filter', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() => _showFilters = !_showFilters),
                      icon: Icon(_showFilters ? Icons.expand_less : Icons.expand_more),
                      label: Text(_showFilters ? 'Einklappen' : 'Ausklappen'),
                    ),
                  ],
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: !_showFilters
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 760;
                              final fieldWidth = isCompact
                                  ? math.max(160.0, constraints.maxWidth / 2 - 12)
                                  : 200.0;

                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: DfsProduct.fieldOrder.map((key) {
                                  final label = DfsProduct.fieldLabels[key] ?? key;
                                  final ctrl = _filterCtrls[key]!;
                                  final options =
                                      _dropdownKeys.contains(key) ? _optionsFor(key) : const <String>[];

                                  final baseDecoration = InputDecoration(
                                    labelText: label,
                                    labelStyle: Theme.of(context).textTheme.bodySmall,
                                    floatingLabelStyle: Theme.of(context).textTheme.bodySmall,
                                    prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    border: const OutlineInputBorder(),
                                  );

                                  if (_dropdownKeys.contains(key)) {
                                    return SizedBox(
                                      width: fieldWidth,
                                      child: DropdownMenu<String>(
                                        controller: ctrl,
                                        label: Text(label, style: Theme.of(context).textTheme.bodySmall),
                                        enableFilter: true,
                                        enableSearch: true,
                                        textStyle: Theme.of(context).textTheme.bodySmall,
                                        leadingIcon: const Icon(Icons.filter_alt_outlined, size: 18),
                                        dropdownMenuEntries: options
                                            .map((v) => DropdownMenuEntry<String>(value: v, label: v))
                                            .toList(),
                                        inputDecorationTheme: InputDecorationTheme(
                                          isDense: true,
                                          contentPadding: baseDecoration.contentPadding,
                                          border: baseDecoration.border as OutlineInputBorder?,
                                          labelStyle: baseDecoration.labelStyle,
                                          floatingLabelStyle: baseDecoration.floatingLabelStyle,
                                        ),
                                      ),
                                    );
                                  }

                                  return SizedBox(
                                    width: fieldWidth,
                                    child: TextField(
                                      controller: ctrl,
                                      style: Theme.of(context).textTheme.bodySmall,
                                      decoration: baseDecoration,
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Scrollbar(
                          controller: _tableScrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          interactive: true,
                          child: ScrollConfiguration(
                            behavior: const MaterialScrollBehavior()
                                .copyWith(dragDevices: _scrollDragDevices),
                            child: SingleChildScrollView(
                              controller: _tableScrollController,
                              scrollDirection: Axis.horizontal,
                              child: Scrollbar(
                                controller: _verticalTableScrollController,
                                thumbVisibility: true,
                                trackVisibility: true,
                                interactive: true,
                                notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
                                child: ScrollConfiguration(
                                  behavior: const MaterialScrollBehavior()
                                      .copyWith(dragDevices: _scrollDragDevices),
                                  child: SingleChildScrollView(
                                    controller: _verticalTableScrollController,
                                    scrollDirection: Axis.vertical,
                                    child: ConstrainedBox(
                                      constraints:
                                          BoxConstraints(minWidth: math.max(constraints.maxWidth, 1200)),
                                      child: PaginatedDataTable(
                                        header: Row(
                                          children: [
                                            Text('${filtered.length} von ${_items.length} Artikeln',
                                                style: Theme.of(context).textTheme.titleMedium),
                                            const Spacer(),
                                            if (widget.loading)
                                              const Padding(
                                                padding: EdgeInsets.only(right: 8),
                                                child: SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(strokeWidth: 2)),
                                              ),
                                          ],
                                        ),
                                        columns: [
                                          ...DfsProduct.fieldOrder
                                              .map((key) =>
                                                  DataColumn(label: Text(DfsProduct.fieldLabels[key] ?? key))),
                                          const DataColumn(label: Text('Aktionen')),
                                    ],
                                    source: dataSource,
                                    rowsPerPage: effectiveRowsPerPage,
                                    availableRowsPerPage: const [10, 20, 50],
                                    onRowsPerPageChanged: (value) {
                                      if (value != null) {
                                        setState(() => _rowsPerPage = value);
                                      }
                                    },
                                    showFirstLastButtons: true,
                                    horizontalMargin: 12,
                                    columnSpacing: 28,
                                    showCheckboxColumn: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductDataSource extends DataTableSource {
  final List<DfsProduct> products;
  final Future<void> Function({DfsProduct? product}) onEdit;
  final Future<void> Function(DfsProduct product) onDelete;

  _ProductDataSource({required this.products, required this.onEdit, required this.onDelete});

  @override
  DataRow? getRow(int index) {
    if (index >= products.length) return null;
    final product = products[index];
    final map = product.toHeaderMap();
    return DataRow.byIndex(
      index: index,
      cells: [
        ...DfsProduct.fieldOrder.map((k) => DataCell(Text(map[k] ?? ''))),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Bearbeiten',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => onEdit(product: product),
              ),
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(product),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => products.length;

  @override
  int get selectedRowCount => 0;
}
