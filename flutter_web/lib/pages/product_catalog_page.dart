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
  final _globalSearchCtrl = TextEditingController();
  String _globalSearch = '';
  int _rowsPerPage = 10;
  int _currentPage = 0;
  static const _rowsPerPageOptions = [10, 20, 50, 100];
  bool _showFilters = false;
  final _tableScrollController = ScrollController();
  final _verticalTableScrollController = ScrollController();
  final Set<String> _hiddenColumns = <String>{};

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
      _filterCtrls[key]!.addListener(() => setState(() => _currentPage = 0));
    }
  }

  @override
  void didUpdateWidget(covariant ProductCatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.products != widget.products) {
      setState(() {
        _items = List.of(widget.products);
        _currentPage = 0;
      });
    }
  }

  @override
  void dispose() {
    _tableScrollController.dispose();
    _verticalTableScrollController.dispose();
    for (final ctrl in _filterCtrls.values) {
      ctrl.dispose();
    }
    _globalSearchCtrl.dispose();
    super.dispose();
  }

  void _resetFilters() {
    setState(() {
      _globalSearchCtrl.clear();
      _globalSearch = '';
      _currentPage = 0;
      for (final ctrl in _filterCtrls.values) {
        ctrl.clear();
      }
    });
  }

  Future<void> _openColumnPicker() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        final tempHidden = Set<String>.from(_hiddenColumns);

        void showMustKeepOneMessage() {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mindestens eine Spalte muss sichtbar bleiben.')),
          );
        }

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            int visibleCount() => DfsProduct.fieldOrder.length - tempHidden.length;

            void toggle(String key, bool visible) {
              if (!visible && visibleCount() <= 1) {
                showMustKeepOneMessage();
                return;
              }

              setStateDialog(() {
                if (visible) {
                  tempHidden.remove(key);
                } else {
                  tempHidden.add(key);
                }
              });
            }

            return AlertDialog(
              title: const Text('Spalten ein-/ausblenden'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setStateDialog(() => tempHidden.clear()),
                            icon: const Icon(Icons.select_all),
                            label: const Text('Alle anzeigen'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () {
                              if (DfsProduct.fieldOrder.length == 1) {
                                return;
                              }
                              setStateDialog(() {
                                tempHidden
                                  ..clear()
                                  ..addAll(DfsProduct.fieldOrder.skip(1));
                              });
                            },
                            icon: const Icon(Icons.indeterminate_check_box_outlined),
                            label: const Text('Alle außer erster ausblenden'),
                          ),
                        ],
                      ),
                      const Divider(),
                      ...DfsProduct.fieldOrder.map((key) {
                        final label = DfsProduct.fieldLabels[key] ?? key;
                        final visible = !tempHidden.contains(key);
                        return CheckboxListTile(
                          dense: true,
                          title: Text(label),
                          value: visible,
                          onChanged: (val) {
                            if (val == null) return;
                            toggle(key, val);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    if (tempHidden.length == DfsProduct.fieldOrder.length) {
                      showMustKeepOneMessage();
                      return;
                    }
                    Navigator.pop(ctx, tempHidden);
                  },
                  child: const Text('Übernehmen'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() {
      _hiddenColumns
        ..clear()
        ..addAll(result);
    });
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

    final filteredLength = filtered.length;
    final totalPages = filteredLength == 0 ? 1 : (filteredLength / _rowsPerPage).ceil();
    final currentPage = filteredLength == 0
        ? 0
        : _currentPage.clamp(0, math.max(0, totalPages - 1)).toInt();
    final pageItems = filtered.skip(currentPage * _rowsPerPage).take(_rowsPerPage).toList();
    final startIndex = filteredLength == 0 ? 0 : currentPage * _rowsPerPage + 1;
    final endIndex = filteredLength == 0
        ? 0
        : math.min(filteredLength, currentPage * _rowsPerPage + pageItems.length);
    final visibleFields =
        DfsProduct.fieldOrder.where((key) => !_hiddenColumns.contains(key)).toList();

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
                controller: _globalSearchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Suchen (alle Felder)',
                ),
                onChanged: (v) => setState(() {
                  _globalSearch = v;
                  _currentPage = 0;
                }),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _openColumnPicker,
              icon: const Icon(Icons.view_column_outlined),
              label: const Text('Spalten'),
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
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Zurücksetzen'),
                    ),
                    const SizedBox(width: 6),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      Text('$startIndex–$endIndex von ${filtered.length} Artikeln',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (widget.loading)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final estimatedWidth = visibleFields.length * 180.0 + 170.0;
                      final minWidth = math.max(constraints.maxWidth, estimatedWidth);

                      return Scrollbar(
                        controller: _tableScrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        interactive: true,
                        child: ScrollConfiguration(
                          behavior:
                              const MaterialScrollBehavior().copyWith(dragDevices: _scrollDragDevices),
                          child: SingleChildScrollView(
                            controller: _tableScrollController,
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: minWidth),
                              child: Column(
                                children: [
                                  _buildStickyHeader(visibleFields, minWidth),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: Scrollbar(
                                      controller: _verticalTableScrollController,
                                      thumbVisibility: true,
                                      trackVisibility: true,
                                      interactive: true,
                                      notificationPredicate: (notif) =>
                                          notif.metrics.axis == Axis.vertical,
                                      child: ScrollConfiguration(
                                        behavior: const MaterialScrollBehavior()
                                            .copyWith(dragDevices: _scrollDragDevices),
                                        child: SingleChildScrollView(
                                          controller: _verticalTableScrollController,
                                          scrollDirection: Axis.vertical,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(minWidth: minWidth),
                                            child: _buildDataTableBody(
                                              pageItems,
                                              visibleFields,
                                              minWidth,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    border: Border(
                      top: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: _buildPagination(
                    totalPages: totalPages,
                    currentPage: currentPage,
                    totalItems: filteredLength,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Map<int, TableColumnWidth> _columnWidths(int visibleFieldCount, double tableWidth) {
    const actionWidth = 170.0;
    final available = math.max(tableWidth - actionWidth, visibleFieldCount * 120.0);
    final cellWidth = available / visibleFieldCount;

    final widths = <int, TableColumnWidth>{};
    for (var i = 0; i < visibleFieldCount; i++) {
      widths[i] = FixedColumnWidth(cellWidth);
    }
    widths[visibleFieldCount] = const FixedColumnWidth(actionWidth);
    return widths;
  }

  Widget _buildStickyHeader(List<String> visibleFields, double tableWidth) {
    final widths = _columnWidths(visibleFields.length, tableWidth);
    return Container(
      height: 56,
      color: Theme.of(context).colorScheme.surfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Table(
        columnWidths: widths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              ...visibleFields.map(
                (key) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    DfsProduct.fieldLabels[key] ?? key,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Aktionen', style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataTableBody(
    List<DfsProduct> items,
    List<String> visibleFields,
    double tableWidth,
  ) {
    final widths = _columnWidths(visibleFields.length, tableWidth);

    TableRow buildRow(DfsProduct product) {
      final map = product.toHeaderMap();
      return TableRow(
        children: [
          ...visibleFields.map((key) {
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5)),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(map[key] ?? ''),
            );
          }),
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5)),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Bearbeiten',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openEditor(product: product),
                ),
                IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteProduct(product),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Table(
      columnWidths: widths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: items.map(buildRow).toList(),
    );
  }

  Widget _buildPagination({
    required int totalPages,
    required int currentPage,
    required int totalItems,
  }) {
    if (totalItems == 0) {
      return const SizedBox.shrink();
    }

    List<Widget> buildPageButtons() {
      const maxButtons = 9;
      int start = math.max(0, currentPage - 4);
      int end = math.min(totalPages - 1, start + maxButtons - 1);
      start = math.max(0, end - maxButtons + 1);

      final buttons = <Widget>[];

      void addPageButton(int page) {
        final isActive = page == currentPage;
        buttons.add(OutlinedButton(
          style: isActive
              ? OutlinedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
              : null,
          onPressed: isActive
              ? null
              : () => setState(() {
                    _currentPage = page;
                  }),
          child: Text('${page + 1}'),
        ));
      }

      addPageButton(0);
      if (start > 1) {
        buttons.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('…'),
        ));
      }

      for (var i = start; i <= end; i++) {
        if (i == 0 || i == totalPages - 1) continue;
        addPageButton(i);
      }

      if (end < totalPages - 2) {
        buttons.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('…'),
        ));
      }

      if (totalPages > 1) {
        addPageButton(totalPages - 1);
      }

      return buttons;
    }

    return Row(
      children: [
        DropdownButton<int>(
          value: _rowsPerPage,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _rowsPerPage = value;
                _currentPage = 0;
              });
            }
          },
          items: _rowsPerPageOptions
              .map((v) => DropdownMenuItem<int>(
                    value: v,
                    child: Text('$v pro Seite'),
                  ))
              .toList(),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Zurück',
          icon: const Icon(Icons.chevron_left),
          onPressed: currentPage > 0
              ? () => setState(() {
                    _currentPage = currentPage - 1;
                  })
              : null,
        ),
        Wrap(
          spacing: 4,
          children: buildPageButtons(),
        ),
        IconButton(
          tooltip: 'Weiter',
          icon: const Icon(Icons.chevron_right),
          onPressed: currentPage < totalPages - 1
              ? () => setState(() {
                    _currentPage = currentPage + 1;
                  })
              : null,
        ),
      ],
    );
  }
}
