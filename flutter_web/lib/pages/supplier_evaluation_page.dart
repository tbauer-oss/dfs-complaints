import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/client.dart';
import '../models/supplier_evaluation.dart';
import '../utils/app_error_mapper.dart';

class SupplierEvaluationPage extends StatefulWidget {
  final ApiClient api;
  final bool canWrite;
  final bool isQm;
  const SupplierEvaluationPage({super.key, required this.api, required this.canWrite, required this.isQm});

  @override
  State<SupplierEvaluationPage> createState() => _SupplierEvaluationPageState();
}

class _SupplierEvaluationPageState extends State<SupplierEvaluationPage> {
  bool _loading = true;
  String? _error;
  List<Supplier> _suppliers = const [];
  List<SupplierPerformanceEntry> _entries = const [];
  List<SupplierAnnualEvaluation> _evaluations = const [];
  List<SupplierEscalation> _escalations = const [];
  SupplierEvaluationConfig? _config;
  String? _supplierFilter;

  final _dateFmt = DateFormat('dd.MM.yyyy');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.adminSuppliers(),
        widget.api.adminSupplierPerformance(),
        widget.api.adminSupplierEvaluations(),
        widget.api.adminSupplierEscalations(),
        widget.api.adminSupplierEvalConfig(),
      ]);
      setState(() {
        _suppliers = results[0] as List<Supplier>;
        _entries = results[1] as List<SupplierPerformanceEntry>;
        _evaluations = results[2] as List<SupplierAnnualEvaluation>;
        _escalations = results[3] as List<SupplierEscalation>;
        _config = results[4] as SupplierEvaluationConfig;
        _loading = false;
      });
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      setState(() {
        _error = mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim();
        _loading = false;
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  SupplierEvaluationConfig _copyConfig(
    SupplierEvaluationConfig base, {
    List<dynamic>? categories,
    Map<String, dynamic>? thresholds,
    Map<String, dynamic>? trend,
    Map<String, dynamic>? annualWindow,
    Map<String, dynamic>? approval,
    Map<String, dynamic>? editRules,
    Map<String, dynamic>? notifications,
    int? updatedAt,
    String? updatedBy,
    List<dynamic>? history,
  }) {
    return SupplierEvaluationConfig(
      id: base.id,
      version: base.version,
      categories: categories ?? base.categories,
      thresholds: thresholds ?? base.thresholds,
      trend: trend ?? base.trend,
      annualWindow: annualWindow ?? base.annualWindow,
      approval: approval ?? base.approval,
      editRules: editRules ?? base.editRules,
      notifications: notifications ?? base.notifications,
      updatedAt: updatedAt ?? base.updatedAt,
      updatedBy: updatedBy ?? base.updatedBy,
      history: history ?? base.history,
    );
  }

  String _supplierName(String id) {
    final supplier = _suppliers.firstWhere((s) => s.id == id, orElse: () => Supplier.fromJson({}));
    return supplier.name.isNotEmpty ? supplier.name : id;
  }

  Future<void> _createSupplier() async {
    final nameCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String status = 'zugelassen';
    bool critical = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lieferant anlegen'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name / Firma *')),
                TextField(controller: numberCtrl, decoration: const InputDecoration(labelText: 'Lieferanten-Nr.')),
                TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Kategorie / Warengruppe')),
                TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Kontaktname')),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Kontakt E-Mail')),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Kontakt Telefon')),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'zugelassen', child: Text('zugelassen')),
                    DropdownMenuItem(value: 'gesperrt', child: Text('gesperrt')),
                    DropdownMenuItem(value: 'in bewertung', child: Text('in Bewertung')),
                  ],
                  onChanged: (value) => status = value ?? status,
                ),
                SwitchListTile.adaptive(
                  value: critical,
                  onChanged: (value) => critical = value,
                  title: const Text('Kritischer Lieferant'),
                ),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notizen')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
          ],
        );
      },
    );

    if (result != true) return;
    if (nameCtrl.text.trim().isEmpty) {
      _showSnack('Bitte einen Lieferantennamen angeben.');
      return;
    }

    try {
      final created = await widget.api.adminCreateSupplier(
        Supplier(
          id: '',
          supplierNumber: numberCtrl.text.trim(),
          name: nameCtrl.text.trim(),
          address: '',
          contactName: contactCtrl.text.trim(),
          contactEmail: emailCtrl.text.trim(),
          contactPhone: phoneCtrl.text.trim(),
          category: categoryCtrl.text.trim(),
          critical: critical,
          status: status,
          notes: notesCtrl.text.trim(),
          blockedReason: '',
          blockedAt: null,
          blockedBy: '',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          createdBy: '',
          updatedBy: '',
          history: const [],
        ),
      );
      setState(() => _suppliers = [created, ..._suppliers]);
      _showSnack('Lieferant gespeichert.');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _createPerformanceEntry() async {
    if (_suppliers.isEmpty) {
      _showSnack('Bitte zuerst einen Lieferanten anlegen.');
      return;
    }
    final descCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String supplierId = _suppliers.first.id;
    String type = _config?.categories.isNotEmpty == true
        ? (_config!.categories.first['name'] ?? '').toString()
        : 'Liefertermin/Termintreue';
    String rating = _config?.categories.isNotEmpty == true
        ? (_config!.categories.first['scale'] as List?)?.first?.toString() ?? '3'
        : '3';
    bool includeInAnnual = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<dynamic> scaleForType(String type) {
              final categories = _config?.categories ?? const [];
              final match = categories.firstWhere(
                (cat) => cat['name']?.toString() == type,
                orElse: () => categories.isNotEmpty ? categories.first : {},
              );
              return (match['scale'] as List?) ?? const [];
            }

            final ratingOptions = scaleForType(type);
            if (!ratingOptions.any((value) => value.toString() == rating)) {
              rating = ratingOptions.isNotEmpty ? ratingOptions.first.toString() : rating;
            }

            return AlertDialog(
              title: const Text('Performance-Eintrag erfassen'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: supplierId,
                      decoration: const InputDecoration(labelText: 'Lieferant'),
                      items: _suppliers
                          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                          .toList(),
                      onChanged: (value) => setModalState(() => supplierId = value ?? supplierId),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Datum: ${_dateFmt.format(selectedDate)}'),
                      trailing: const Icon(Icons.date_range_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                    ),
                    TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Kurzbeschreibung *')),
                    TextField(controller: refCtrl, decoration: const InputDecoration(labelText: 'Bezug (Bestellung/Lieferschein)')),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(labelText: 'Typ'),
                      items: (_config?.categories ?? const [])
                          .map((cat) => DropdownMenuItem(value: cat['name'].toString(), child: Text(cat['name'].toString())))
                          .toList(),
                      onChanged: (value) => setModalState(() => type = value ?? type),
                    ),
                    DropdownButtonFormField<String>(
                      value: rating,
                      decoration: const InputDecoration(labelText: 'Bewertung'),
                      items: ratingOptions
                          .map((value) => DropdownMenuItem(value: value.toString(), child: Text(value.toString())))
                          .toList(),
                      onChanged: (value) => setModalState(() => rating = value ?? rating),
                    ),
                    SwitchListTile.adaptive(
                      value: includeInAnnual,
                      onChanged: (value) => setModalState(() => includeInAnnual = value),
                      title: const Text('In Jahresbewertung berücksichtigen'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;
    if (descCtrl.text.trim().isEmpty) {
      _showSnack('Bitte eine Kurzbeschreibung angeben.');
      return;
    }

    try {
      final created = await widget.api.adminCreateSupplierPerformance(
        SupplierPerformanceEntry(
          id: '',
          supplierId: supplierId,
          date: selectedDate.millisecondsSinceEpoch,
          type: type,
          rating: rating,
          description: descCtrl.text.trim(),
          reference: refCtrl.text.trim(),
          attachments: const [],
          includeInAnnual: includeInAnnual,
          status: 'open',
          cancelReason: '',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          createdBy: '',
          updatedBy: '',
          history: const [],
        ),
      );
      setState(() => _entries = [created, ..._entries]);
      _showSnack('Eintrag gespeichert.');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _createAnnualEvaluation() async {
    if (_suppliers.isEmpty) {
      _showSnack('Bitte zuerst einen Lieferanten anlegen.');
      return;
    }
    String supplierId = _suppliers.first.id;
    final yearCtrl = TextEditingController(text: DateTime.now().year.toString());
    DateTime periodFrom = DateTime(DateTime.now().year - 1, 1, 1);
    DateTime periodTo = DateTime(DateTime.now().year - 1, 12, 31);
    String decision = 'weiterhin zugelassen';
    final reasonCtrl = TextEditingController();
    final commentEkCtrl = TextEditingController();
    final commentQmCtrl = TextEditingController();
    String status = 'draft';
    final approvedByCtrl = TextEditingController();
    final reviewedByCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Jahresbewertung starten'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: supplierId,
                  decoration: const InputDecoration(labelText: 'Lieferant'),
                  items: _suppliers
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (value) => supplierId = value ?? supplierId,
                ),
                TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: 'Bewertungsjahr')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Zeitraum von: ${_dateFmt.format(periodFrom)}'),
                  trailing: const Icon(Icons.date_range_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: periodFrom,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      periodFrom = picked;
                      (context as Element).markNeedsBuild();
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Zeitraum bis: ${_dateFmt.format(periodTo)}'),
                  trailing: const Icon(Icons.date_range_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: periodTo,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      periodTo = picked;
                      (context as Element).markNeedsBuild();
                    }
                  },
                ),
                DropdownButtonFormField<String>(
                  value: decision,
                  decoration: const InputDecoration(labelText: 'Entscheidung'),
                  items: const [
                    DropdownMenuItem(value: 'weiterhin zugelassen', child: Text('weiterhin zugelassen')),
                    DropdownMenuItem(value: 'zugelassen mit Auflagen', child: Text('zugelassen mit Auflagen')),
                    DropdownMenuItem(value: 'in Beobachtung', child: Text('in Beobachtung')),
                    DropdownMenuItem(value: 'sperren / re-qualifikation', child: Text('sperren / Re-Qualifikation erforderlich')),
                  ],
                  onChanged: (value) => decision = value ?? decision,
                ),
                TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Begründung')),
                TextField(controller: commentEkCtrl, decoration: const InputDecoration(labelText: 'Kommentar EK')),
                TextField(controller: commentQmCtrl, decoration: const InputDecoration(labelText: 'Kommentar QM')),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Entwurf')),
                    DropdownMenuItem(value: 'final', child: Text('Final')),
                  ],
                  onChanged: (value) => status = value ?? status,
                ),
                TextField(controller: reviewedByCtrl, decoration: const InputDecoration(labelText: 'geprüft von')),
                TextField(controller: approvedByCtrl, decoration: const InputDecoration(labelText: 'freigegeben von')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Starten')),
          ],
        );
      },
    );

    if (result != true) return;
    if (decision.toLowerCase().contains('sperr') && reasonCtrl.text.trim().isEmpty) {
      _showSnack('Bitte eine Begründung zur Sperrung angeben.');
      return;
    }
    if (status == 'final' && approvedByCtrl.text.trim().isEmpty) {
      _showSnack('Bitte die Freigabe dokumentieren.');
      return;
    }

    try {
      final created = await widget.api.adminCreateSupplierEvaluation(
        SupplierAnnualEvaluation(
          id: '',
          evalYear: int.tryParse(yearCtrl.text.trim()) ?? DateTime.now().year,
          periodFrom: periodFrom.millisecondsSinceEpoch,
          periodTo: periodTo.millisecondsSinceEpoch,
          supplierId: supplierId,
          aggregates: const {},
          commentEk: commentEkCtrl.text.trim(),
          commentQm: commentQmCtrl.text.trim(),
          decision: decision,
          decisionReason: reasonCtrl.text.trim(),
          status: status,
          configVersion: _config?.version ?? 1,
          configSnapshot: const {},
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          createdBy: '',
          updatedBy: '',
          reviewedBy: reviewedByCtrl.text.trim(),
          approvedBy: approvedByCtrl.text.trim(),
          history: const [],
        ),
      );
      setState(() => _evaluations = [created, ..._evaluations]);
      _showSnack('Jahresbewertung erstellt.');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _createEscalation() async {
    if (_suppliers.isEmpty) {
      _showSnack('Bitte zuerst einen Lieferanten anlegen.');
      return;
    }
    String supplierId = _suppliers.first.id;
    String trigger = 'einzelereignis';
    String severity = 'mittel';
    String status = 'offen';
    final reasonCtrl = TextEditingController();
    final ownerCtrl = TextEditingController();
    DateTime? dueDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eskalation anlegen'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: supplierId,
                  decoration: const InputDecoration(labelText: 'Lieferant'),
                  items: _suppliers
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (value) => supplierId = value ?? supplierId,
                ),
                DropdownButtonFormField<String>(
                  value: trigger,
                  decoration: const InputDecoration(labelText: 'Trigger'),
                  items: const [
                    DropdownMenuItem(value: 'trend', child: Text('Trend (automatisch)')),
                    DropdownMenuItem(value: 'jahresbewertung', child: Text('Jahresbewertung')),
                    DropdownMenuItem(value: 'einzelereignis', child: Text('Einzelereignis')),
                  ],
                  onChanged: (value) => trigger = value ?? trigger,
                ),
                TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Grund *')),
                DropdownButtonFormField<String>(
                  value: severity,
                  decoration: const InputDecoration(labelText: 'Schweregrad'),
                  items: const [
                    DropdownMenuItem(value: 'niedrig', child: Text('niedrig')),
                    DropdownMenuItem(value: 'mittel', child: Text('mittel')),
                    DropdownMenuItem(value: 'hoch', child: Text('hoch')),
                  ],
                  onChanged: (value) => severity = value ?? severity,
                ),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'offen', child: Text('offen')),
                    DropdownMenuItem(value: 'in bearbeitung', child: Text('in Bearbeitung')),
                    DropdownMenuItem(value: 'abgeschlossen', child: Text('abgeschlossen')),
                  ],
                  onChanged: (value) => status = value ?? status,
                ),
                TextField(controller: ownerCtrl, decoration: const InputDecoration(labelText: 'Owner')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dueDate == null ? 'Fälligkeitsdatum: —' : 'Fälligkeitsdatum: ${_dateFmt.format(dueDate!)}'),
                  trailing: const Icon(Icons.date_range_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dueDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      dueDate = picked;
                      (context as Element).markNeedsBuild();
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Anlegen')),
          ],
        );
      },
    );

    if (result != true) return;
    if (reasonCtrl.text.trim().isEmpty) {
      _showSnack('Bitte einen Grund angeben.');
      return;
    }

    try {
      final created = await widget.api.adminCreateSupplierEscalation(
        SupplierEscalation(
          id: '',
          supplierId: supplierId,
          trigger: trigger,
          reason: reasonCtrl.text.trim(),
          severity: severity,
          status: status,
          owner: ownerCtrl.text.trim(),
          dueDate: dueDate?.millisecondsSinceEpoch,
          links: const {},
          actions: '',
          effectiveness: '',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          createdBy: '',
          updatedBy: '',
          history: const [],
        ),
      );
      setState(() => _escalations = [created, ..._escalations]);
      _showSnack('Eskalation angelegt.');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _downloadReportPdf() async {
    try {
      final bytes = await widget.api.adminSupplierReportPdf();
      _downloadBytes(bytes, 'lieferantenbewertung.pdf', 'application/pdf');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _downloadReportCsv() async {
    try {
      final csv = await widget.api.adminSupplierReportCsv();
      _downloadBytes(Uint8List.fromList(csv.codeUnits), 'lieferantenbewertung.csv', 'text/csv');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  void _downloadBytes(Uint8List bytes, String filename, String mime) {
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)..download = filename;
    anchor.click();
    html.Url.revokeObjectUrl(url);
  }

  Widget _buildSuppliersTab() {
    return ListView(
      children: [
        if (widget.canWrite)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _createSupplier,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Lieferant anlegen'),
            ),
          ),
        if (_suppliers.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Keine Lieferanten vorhanden.'),
          ),
        ..._suppliers.map((s) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              title: Text(s.name),
              subtitle: Text('${s.status} • ${s.category.isEmpty ? 'ohne Kategorie' : s.category}'),
              trailing: s.critical ? const Icon(Icons.warning_amber_outlined, color: Colors.orange) : null,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPerformanceTab() {
    final entries = _supplierFilter == null
        ? _entries
        : _entries.where((e) => e.supplierId == _supplierFilter).toList();
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _supplierFilter,
                  decoration: const InputDecoration(labelText: 'Lieferant filtern'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Alle Lieferanten')),
                    ..._suppliers.map((s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (value) => setState(() => _supplierFilter = value),
                ),
              ),
              const SizedBox(width: 12),
              if (widget.canWrite)
                ElevatedButton.icon(
                  onPressed: _createPerformanceEntry,
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Eintrag erfassen'),
                ),
            ],
          ),
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Keine Performance-Einträge vorhanden.'),
          ),
        ...entries.map((e) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              title: Text('${_supplierName(e.supplierId)} • ${e.type}'),
              subtitle: Text('${_dateFmt.format(DateTime.fromMillisecondsSinceEpoch(e.date))} • ${e.description}'),
              trailing: Chip(label: Text(e.rating)),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEvaluationTab() {
    return ListView(
      children: [
        if (widget.canWrite)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _createAnnualEvaluation,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Jahresbewertung starten'),
            ),
          ),
        if (_evaluations.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Keine Jahresbewertungen vorhanden.'),
          ),
        ..._evaluations.map((e) {
          final score = e.aggregates['totalScore']?.toString() ?? '—';
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              title: Text('${_supplierName(e.supplierId)} • ${e.evalYear}'),
              subtitle: Text('${e.decision} • Score ${score}'),
              trailing: Text(e.status),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEscalationsTab() {
    return ListView(
      children: [
        if (widget.canWrite)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _createEscalation,
              icon: const Icon(Icons.report_outlined),
              label: const Text('Eskalation anlegen'),
            ),
          ),
        if (_escalations.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Keine Eskalationen vorhanden.'),
          ),
        ..._escalations.map((e) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              title: Text('${_supplierName(e.supplierId)} • ${e.trigger}'),
              subtitle: Text(e.reason),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(e.severity),
                  Text(e.status),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildReportsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF-Export Jahresbewertungen'),
            subtitle: const Text('Pro Lieferant inklusive Score-Übersicht'),
            onTap: _downloadReportPdf,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('CSV-Export Managementübersicht'),
            subtitle: const Text('Gesamtübersicht für Managementreview'),
            onTap: _downloadReportCsv,
          ),
        ),
      ],
    );
  }

  Future<void> _editCategory({
    required SupplierEvaluationConfig config,
    Map<String, dynamic>? category,
  }) async {
    final nameCtrl = TextEditingController(text: category?['name']?.toString() ?? '');
    final weightCtrl = TextEditingController(text: category?['weight']?.toString() ?? '');
    final scaleCtrl = TextEditingController(
      text: (category?['scale'] as List?)?.map((e) => e.toString()).join(', ') ?? '',
    );
    final scoreMapCtrl = TextEditingController(
      text: (category?['scoreMap'] as Map?)?.entries.map((e) => '${e.key}=${e.value}').join(', ') ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(category == null ? 'Kategorie hinzufügen' : 'Kategorie bearbeiten'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name *')),
                TextField(controller: weightCtrl, decoration: const InputDecoration(labelText: 'Gewichtung (%)')),
                TextField(controller: scaleCtrl, decoration: const InputDecoration(labelText: 'Skala (z. B. 1,2,3,4,5)')),
                TextField(
                  controller: scoreMapCtrl,
                  decoration: const InputDecoration(labelText: 'Score-Mapping (z. B. 1=1, 2=2)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Übernehmen')),
          ],
        );
      },
    );

    if (result != true) return;
    if (nameCtrl.text.trim().isEmpty) {
      _showSnack('Bitte einen Kategorienamen angeben.');
      return;
    }

    final scale = scaleCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final scoreMap = <String, num>{};
    for (final pair in scoreMapCtrl.text.split(',')) {
      final parts = pair.split('=').map((e) => e.trim()).toList();
      if (parts.length != 2) continue;
      final value = num.tryParse(parts[1]);
      if (value == null) continue;
      scoreMap[parts[0]] = value;
    }

    final updatedCategory = {
      'name': nameCtrl.text.trim(),
      'weight': num.tryParse(weightCtrl.text.trim()) ?? 0,
      'scale': scale,
      'scoreMap': scoreMap,
    };
    final categories = [...config.categories.map((e) => Map<String, dynamic>.from(e as Map))];
    if (category == null) {
      categories.add(updatedCategory);
    } else {
      final index = categories.indexWhere((c) => c['name'] == category['name']);
      if (index >= 0) {
        categories[index] = updatedCategory;
      } else {
        categories.add(updatedCategory);
      }
    }

    setState(() => _config = _copyConfig(config, categories: categories));
  }

  Widget _buildConfigTab() {
    if (!widget.isQm) {
      return const Center(child: Text('Nur QM/Superuser können die Konfiguration bearbeiten.'));
    }
    final config = _config;
    if (config == null) {
      return const Center(child: Text('Konfiguration wird geladen...'));
    }

    final thresholdGreen = TextEditingController(text: config.thresholds['green']?.toString() ?? '');
    final thresholdYellow = TextEditingController(text: config.thresholds['yellow']?.toString() ?? '');
    final thresholdRed = TextEditingController(text: config.thresholds['red']?.toString() ?? '');
    final escalationScore = TextEditingController(text: config.thresholds['escalationScore']?.toString() ?? '');
    final trendWindow = TextEditingController(text: config.trend['windowDays']?.toString() ?? '');
    final trendMin = TextEditingController(text: config.trend['minEntries']?.toString() ?? '');
    final editDays = TextEditingController(text: config.editRules['entryEditDays']?.toString() ?? '');
    final emailsCtrl = TextEditingController(text: (config.notifications['emails'] as List?)?.join(', ') ?? '');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Config-Version: ${config.version}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const Text('Schwellenwerte'),
        Row(
          children: [
            Expanded(child: TextField(controller: thresholdGreen, decoration: const InputDecoration(labelText: 'Grün'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: thresholdYellow, decoration: const InputDecoration(labelText: 'Gelb'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: thresholdRed, decoration: const InputDecoration(labelText: 'Rot'))),
          ],
        ),
        TextField(controller: escalationScore, decoration: const InputDecoration(labelText: 'Eskalation ab (Score)')),
        const SizedBox(height: 12),
        const Text('Trendlogik'),
        Row(
          children: [
            Expanded(child: TextField(controller: trendWindow, decoration: const InputDecoration(labelText: 'Fenster (Tage)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: trendMin, decoration: const InputDecoration(labelText: 'Minimum Entries'))),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Bearbeitung'),
        TextField(controller: editDays, decoration: const InputDecoration(labelText: 'Editierbar ohne Begründung (Tage)')),
        const SizedBox(height: 12),
        const Text('Benachrichtigungen'),
        TextField(controller: emailsCtrl, decoration: const InputDecoration(labelText: 'E-Mail Empfänger (kommagetrennt)')),
        const SizedBox(height: 12),
        const Text('Bewertungskategorien'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _editCategory(config: config),
            icon: const Icon(Icons.add_outlined),
            label: const Text('Kategorie hinzufügen'),
          ),
        ),
        ...config.categories.map((cat) {
          return Card(
            child: ListTile(
              title: Text(cat['name']?.toString() ?? ''),
              subtitle: Text('Gewichtung: ${cat['weight'] ?? ''}'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Bearbeiten',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editCategory(config: config, category: Map<String, dynamic>.from(cat as Map)),
                  ),
                  IconButton(
                    tooltip: 'Entfernen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      final categories = [...config.categories];
                      categories.remove(cat);
                      setState(() => _config = _copyConfig(config, categories: categories));
                    },
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () async {
            try {
              final updated = await widget.api.adminUpdateSupplierEvalConfig(
                SupplierEvaluationConfig(
                  id: config.id,
                  version: config.version,
                  categories: config.categories,
                  thresholds: {
                    'green': num.tryParse(thresholdGreen.text) ?? config.thresholds['green'],
                    'yellow': num.tryParse(thresholdYellow.text) ?? config.thresholds['yellow'],
                    'red': num.tryParse(thresholdRed.text) ?? config.thresholds['red'],
                    'escalationScore': num.tryParse(escalationScore.text) ?? config.thresholds['escalationScore'],
                  },
                  trend: {
                    'windowDays': num.tryParse(trendWindow.text) ?? config.trend['windowDays'],
                    'minEntries': num.tryParse(trendMin.text) ?? config.trend['minEntries'],
                  },
                  annualWindow: config.annualWindow,
                  approval: config.approval,
                  editRules: {
                    'entryEditDays': num.tryParse(editDays.text) ?? config.editRules['entryEditDays'],
                  },
                  notifications: {
                    ...config.notifications,
                    'emails': emailsCtrl.text
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                  },
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                  updatedBy: '',
                  history: config.history,
                ),
              );
              setState(() => _config = updated);
              _showSnack('Konfiguration gespeichert.');
            } catch (err) {
              final mapped = AppErrorMapper.map(err);
              _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
            }
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Konfiguration speichern'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Lieferanten'),
              Tab(text: 'Laufende Erfassung'),
              Tab(text: 'Jahresbewertung'),
              Tab(text: 'Eskalationen & Maßnahmen'),
              Tab(text: 'Reports & Export'),
              Tab(text: 'Konfiguration'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSuppliersTab(),
                _buildPerformanceTab(),
                _buildEvaluationTab(),
                _buildEscalationsTab(),
                _buildReportsTab(),
                _buildConfigTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
