import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/client.dart';
import '../models/supplier_evaluation.dart';
import '../utils/app_error_mapper.dart';
import '../utils/email_validation.dart';

class SupplierEvaluationPage extends StatefulWidget {
  final ApiClient api;
  final bool canWrite;
  final bool isQm;
  final bool canManageLookups;
  const SupplierEvaluationPage({
    super.key,
    required this.api,
    required this.canWrite,
    required this.isQm,
    required this.canManageLookups,
  });

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
  SupplierLookups _supplierLookups = SupplierLookups.empty();
  String? _supplierFilter;
  String? _selectedSupplierId;
  bool _savingSupplier = false;
  bool _formDirty = false;
  bool _emailTouched = false;
  bool _emailValidationRequested = false;

  final _supplierFormKey = GlobalKey<FormState>();
  final _emailFieldKey = GlobalKey();
  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _phoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _blockedReasonCtrl = TextEditingController();

  String _status = 'zugelassen';
  String _category = '';
  String _country = '';
  bool _critical = false;

  final _dateFmt = DateFormat('dd.MM.yyyy');
  static const String _addLookupValue = '__add__';

  List<String> get _statusOptions =>
      _supplierLookups.statuses.isNotEmpty ? _supplierLookups.statuses : const ['zugelassen', 'in bewertung', 'gesperrt'];

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(() {
      if (!_emailFocusNode.hasFocus && !_emailTouched) {
        setState(() => _emailTouched = true);
      }
    });
    _loadAll();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _addressCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _emailFocusNode.dispose();
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    _notesCtrl.dispose();
    _blockedReasonCtrl.dispose();
    super.dispose();
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
        widget.api.adminSupplierLookups(),
      ]);
      setState(() {
        _suppliers = results[0] as List<Supplier>;
        _entries = results[1] as List<SupplierPerformanceEntry>;
        _evaluations = results[2] as List<SupplierAnnualEvaluation>;
        _escalations = results[3] as List<SupplierEscalation>;
        _config = results[4] as SupplierEvaluationConfig;
        _supplierLookups = results[5] as SupplierLookups;
        _loading = false;
      });
      if (_selectedSupplierId != null) {
        final selected = _suppliers.firstWhere(
          (s) => s.id == _selectedSupplierId,
          orElse: () => Supplier.fromJson({}),
        );
        if (selected.id.isNotEmpty) {
          _selectSupplier(selected);
        } else {
          _startNewSupplier();
        }
      } else if (_suppliers.isNotEmpty) {
        _selectSupplier(_suppliers.first);
      } else {
        _startNewSupplier();
      }
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

  void _startNewSupplier() {
    setState(() {
      _selectedSupplierId = null;
      _formDirty = false;
      _nameCtrl.text = '';
      _numberCtrl.text = '';
      _addressCtrl.text = '';
      _contactCtrl.text = '';
      _emailCtrl.text = '';
      _phoneCtrl.text = '';
      _websiteCtrl.text = '';
      _notesCtrl.text = '';
      _blockedReasonCtrl.text = '';
      _status = _statusOptions.contains('zugelassen') ? 'zugelassen' : _statusOptions.first;
      _category = '';
      _country = '';
      _critical = false;
      _emailTouched = false;
      _emailValidationRequested = false;
    });
  }

  void _selectSupplier(Supplier supplier) {
    setState(() {
      _selectedSupplierId = supplier.id;
      _formDirty = false;
      _nameCtrl.text = supplier.name;
      _numberCtrl.text = supplier.supplierNumber;
      _addressCtrl.text = supplier.address;
      _contactCtrl.text = supplier.contactName;
      _emailCtrl.text = supplier.contactEmail;
      _phoneCtrl.text = supplier.contactPhone;
      _websiteCtrl.text = supplier.website;
      _notesCtrl.text = supplier.notes;
      _blockedReasonCtrl.text = supplier.blockedReason;
      _status = _statusOptions.contains(supplier.status)
          ? supplier.status
          : (_statusOptions.isNotEmpty ? _statusOptions.first : supplier.status);
      _category = supplier.category;
      _country = supplier.country;
      _critical = supplier.critical;
      _emailTouched = false;
      _emailValidationRequested = false;
    });
  }

  void _markSupplierDirty() {
    setState(() => _formDirty = true);
  }

  bool _supplierFormValid() {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_status.trim().isEmpty) return false;
    if (_status == 'gesperrt' && _blockedReasonCtrl.text.trim().isEmpty) return false;
    return true;
  }

  String _normalizedEmail(String value) => normalizeEmail(value);

  bool _isValidEmail(String value) => isValidEmail(value);

  void _onEmailChanged(String value) {
    final normalized = _normalizedEmail(value);
    if (normalized != value) {
      _emailCtrl.value = _emailCtrl.value.copyWith(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    setState(() {
      _emailTouched = true;
      _formDirty = true;
    });
  }

  Future<void> _focusEmailIfInvalid() async {
    final normalized = _normalizedEmail(_emailCtrl.text);
    if (normalized.isEmpty || _isValidEmail(normalized)) return;
    _emailFocusNode.requestFocus();
    final context = _emailFieldKey.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1,
      );
    }
    _showSnack('Bitte gültige E-Mail eingeben.');
  }

  Supplier? _currentSupplier() {
    if (_selectedSupplierId == null) return null;
    return _suppliers.firstWhere(
      (s) => s.id == _selectedSupplierId,
      orElse: () => Supplier.fromJson({}),
    );
  }

  Future<void> _saveSupplier() async {
    if (!widget.canWrite) return;
    final form = _supplierFormKey.currentState;
    setState(() => _emailValidationRequested = true);
    final normalizedEmail = _normalizedEmail(_emailCtrl.text);
    if (normalizedEmail != _emailCtrl.text) {
      _emailCtrl.value = _emailCtrl.value.copyWith(
        text: normalizedEmail,
        selection: TextSelection.collapsed(offset: normalizedEmail.length),
      );
    }
    if (form == null || !form.validate()) {
      await _focusEmailIfInvalid();
      return;
    }
    if (normalizedEmail.isNotEmpty && !_isValidEmail(normalizedEmail)) {
      await _focusEmailIfInvalid();
      return;
    }
    if (!_supplierFormValid()) return;

    setState(() => _savingSupplier = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _currentSupplier();
    final isEdit = existing != null && existing.id.isNotEmpty;
    final blockedAt = _status == 'gesperrt'
        ? (existing?.blockedAt ?? now)
        : null;

    final payload = Supplier(
      id: isEdit ? existing!.id : '',
      supplierNumber: _numberCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      contactName: _contactCtrl.text.trim(),
      contactEmail: normalizedEmail,
      contactPhone: _phoneCtrl.text.trim(),
      website: _websiteCtrl.text.trim(),
      country: _country.trim(),
      category: _category.trim(),
      critical: _critical,
      status: _status.trim(),
      notes: _notesCtrl.text.trim(),
      blockedReason: _status == 'gesperrt' ? _blockedReasonCtrl.text.trim() : '',
      blockedAt: blockedAt,
      blockedBy: existing?.blockedBy ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      createdBy: existing?.createdBy ?? '',
      updatedBy: existing?.updatedBy ?? '',
      history: existing?.history ?? const [],
    );

    try {
      final saved = isEdit
          ? await widget.api.adminUpdateSupplier(payload)
          : await widget.api.adminCreateSupplier(payload);
      setState(() {
        _suppliers = [
          saved,
          ..._suppliers.where((s) => s.id != saved.id),
        ];
        _selectedSupplierId = saved.id;
        _formDirty = false;
      });
      _showSnack('Lieferant gespeichert.');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    } finally {
      if (mounted) {
        setState(() => _savingSupplier = false);
      }
    }
  }

  Future<void> _confirmDeleteSupplier(Supplier supplier) async {
    if (!widget.canWrite) return;
    var isDeleting = false;
    String? dialogError;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Lieferant löschen?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dieser Vorgang kann nicht rückgängig gemacht werden.'),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(dialogError!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(context, false),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () {
                          setDialogState(() => isDeleting = true);
                          widget.api.adminDeleteSupplier(supplier.id).then((_) {
                            Navigator.pop(context, 'deleted');
                          }).catchError((err) {
                            if (err is ApiError && (err.status == 409 || err.status == 403)) {
                              Navigator.pop(context, 'blocked');
                              return;
                            }
                            final mapped = AppErrorMapper.map(err);
                            setDialogState(() {
                              dialogError = mapped.message.isEmpty
                                  ? mapped.title
                                  : '${mapped.title} ${mapped.message}'.trim();
                              isDeleting = false;
                            });
                          });
                        },
                  child: isDeleting
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Löschen'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == 'deleted') {
      setState(() {
        _suppliers = _suppliers.where((s) => s.id != supplier.id).toList();
        if (_selectedSupplierId == supplier.id) {
          _selectedSupplierId = null;
          _startNewSupplier();
        }
        if (_supplierFilter == supplier.id) {
          _supplierFilter = null;
        }
      });
      _showSnack('Lieferant gelöscht.');
    } else if (result == 'blocked') {
      // Delete Constraint Handling: verständliche Meldung und Sperr-Alternative.
      await _offerBlockInstead(supplier);
    }
  }

  Future<void> _offerBlockInstead(Supplier supplier) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lieferant kann nicht gelöscht werden'),
          content: const Text(
            'Lieferant kann nicht gelöscht werden, da bereits Bewertungen/Eskalationen existieren.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('OK')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Stattdessen sperren'),
            ),
          ],
        );
      },
    );
    if (result != true) return;
    await _blockSupplier(supplier);
  }

  Future<void> _blockSupplier(Supplier supplier) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lieferant sperren'),
          content: TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(labelText: 'Sperrgrund *'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sperren')),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (reasonCtrl.text.trim().isEmpty) {
      _showSnack('Bitte einen Sperrgrund angeben.');
      return;
    }
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = await widget.api.adminUpdateSupplier(
        supplier.copyWith(
          status: 'gesperrt',
          blockedReason: reasonCtrl.text.trim(),
          blockedAt: now,
          updatedAt: now,
        ),
      );
      setState(() {
        _suppliers = [updated, ..._suppliers.where((s) => s.id != updated.id)];
        _selectSupplier(updated);
      });
      _showSnack('Lieferant gesperrt.');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _addLookupOption({
    required String label,
    required String currentValue,
    required List<String> values,
    required void Function(String) onSelected,
    required SupplierLookups Function(String) buildUpdatedLookups,
  }) async {
    final ctrl = TextEditingController(text: currentValue);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$label hinzufügen'),
          content: TextField(
            controller: ctrl,
            decoration: InputDecoration(labelText: '$label *'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final value = ctrl.text.trim();
    if (value.isEmpty) {
      _showSnack('Bitte einen Wert angeben.');
      return;
    }
    if (values.contains(value)) {
      onSelected(value);
      _markSupplierDirty();
      return;
    }
    if (!widget.canManageLookups) {
      _showSnack('Sie haben keine Berechtigung, neue Optionen anzulegen.');
      return;
    }
    try {
      final saved = await widget.api.adminUpdateSupplierLookups(buildUpdatedLookups(value));
      setState(() {
        _supplierLookups = saved;
        onSelected(value);
        _formDirty = true;
      });
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

  Widget _buildSectionCard({required String title, required String description, required Widget child}) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierListTile(Supplier supplier) {
    final isSelected = supplier.id == _selectedSupplierId;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: isSelected ? 2 : 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        selected: isSelected,
        onTap: () => _selectSupplier(supplier),
        title: Text(supplier.name),
        subtitle: Text(
          '${supplier.status} • ${supplier.category.isEmpty ? 'ohne Kategorie' : supplier.category}',
        ),
        trailing: Wrap(
          spacing: 6,
          children: [
            if (supplier.critical)
              const Icon(Icons.warning_amber_outlined, color: Colors.orange),
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _selectSupplier(supplier),
            ),
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              color: Colors.redAccent,
              onPressed: () => _confirmDeleteSupplier(supplier),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuppliersTab() {
    final selected = _currentSupplier();
    final isEditing = selected != null && selected.id.isNotEmpty;
    final canSave = widget.canWrite && _supplierFormValid() && !_savingSupplier;

    Widget buildListPane(bool isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Lieferanten', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (widget.canWrite)
                  ElevatedButton.icon(
                    onPressed: _startNewSupplier,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Neuer Lieferant'),
                  ),
              ],
            ),
          ),
          if (_suppliers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Noch keine Lieferanten angelegt. Jetzt starten…'),
                      const SizedBox(height: 12),
                      if (widget.canWrite)
                        ElevatedButton.icon(
                          onPressed: _startNewSupplier,
                          icon: const Icon(Icons.add_outlined),
                          label: const Text('Lieferant anlegen'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_suppliers.isNotEmpty)
            if (isWide)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _suppliers.length,
                  itemBuilder: (context, index) => _buildSupplierListTile(_suppliers[index]),
                ),
              )
            else
              ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _suppliers.length,
                itemBuilder: (context, index) => _buildSupplierListTile(_suppliers[index]),
              ),
        ],
      );
    }

    Widget formContent = Form(
      key: _supplierFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isEditing ? 'Lieferant bearbeiten' : 'Neuen Lieferanten anlegen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (isEditing)
                Text(
                  _selectedSupplierId ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Stammdaten',
            description: 'Basisangaben zur Identifikation und Zuordnung des Lieferanten.',
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name / Firma *'),
                  onChanged: (_) => _markSupplierDirty(),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _numberCtrl,
                  decoration: const InputDecoration(labelText: 'Lieferanten-Nr.'),
                  onChanged: (_) => _markSupplierDirty(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _websiteCtrl,
                  decoration: const InputDecoration(labelText: 'Website'),
                  onChanged: (_) => _markSupplierDirty(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Adresse'),
                  onChanged: (_) => _markSupplierDirty(),
                ),
              ],
            ),
          ),
          _buildSectionCard(
            title: 'Kontakt',
            description: 'Ansprechpartner und Kommunikationswege.',
            child: Column(
              children: [
                TextFormField(
                  controller: _contactCtrl,
                  decoration: const InputDecoration(labelText: 'Ansprechpartner'),
                  onChanged: (_) => _markSupplierDirty(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: _emailFieldKey,
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                  keyboardType: TextInputType.emailAddress,
                  focusNode: _emailFocusNode,
                  onChanged: _onEmailChanged,
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    if (!_emailTouched && !_emailValidationRequested) return null;
                    final normalized = _normalizedEmail(value);
                    if (normalized.isEmpty) return null;
                    return _isValidEmail(normalized) ? null : 'Ungültige E-Mail';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                  onChanged: (_) => _markSupplierDirty(),
                ),
              ],
            ),
          ),
          _buildSectionCard(
            title: 'Klassifizierung & Status',
            description: 'Bewertung, Status und Risikoeinschätzung des Lieferanten.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _statusOptions.contains(_status) ? _status : _statusOptions.first,
                  decoration: const InputDecoration(labelText: 'Status *'),
                  items: _statusOptions
                      .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _status = value;
                      _formDirty = true;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _category.isEmpty ? null : _category,
                  decoration: const InputDecoration(labelText: 'Kategorie / Warengruppe'),
                  items: [
                    ..._supplierLookups.categories.map(
                      (value) => DropdownMenuItem(value: value, child: Text(value)),
                    ),
                    if (widget.canManageLookups)
                      const DropdownMenuItem(
                        value: _addLookupValue,
                        child: Text('+ Option hinzufügen…'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    if (value == _addLookupValue) {
                      _addLookupOption(
                        label: 'Kategorie',
                        currentValue: _category,
                        values: _supplierLookups.categories,
                        onSelected: (newValue) => setState(() => _category = newValue),
                        buildUpdatedLookups: (value) => SupplierLookups(
                          categories: [..._supplierLookups.categories, value].where((e) => e.isNotEmpty).toList(),
                          countries: _supplierLookups.countries,
                          statuses: _supplierLookups.statuses,
                          updatedAt: _supplierLookups.updatedAt,
                          updatedBy: _supplierLookups.updatedBy,
                          history: _supplierLookups.history,
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _category = value;
                      _formDirty = true;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _country.isEmpty ? null : _country,
                  decoration: const InputDecoration(labelText: 'Land'),
                  items: [
                    ..._supplierLookups.countries.map(
                      (value) => DropdownMenuItem(value: value, child: Text(value)),
                    ),
                    if (widget.canManageLookups)
                      const DropdownMenuItem(
                        value: _addLookupValue,
                        child: Text('+ Option hinzufügen…'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    if (value == _addLookupValue) {
                      _addLookupOption(
                        label: 'Land',
                        currentValue: _country,
                        values: _supplierLookups.countries,
                        onSelected: (newValue) => setState(() => _country = newValue),
                        buildUpdatedLookups: (value) => SupplierLookups(
                          categories: _supplierLookups.categories,
                          countries: [..._supplierLookups.countries, value].where((e) => e.isNotEmpty).toList(),
                          statuses: _supplierLookups.statuses,
                          updatedAt: _supplierLookups.updatedAt,
                          updatedBy: _supplierLookups.updatedBy,
                          history: _supplierLookups.history,
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _country = value;
                      _formDirty = true;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Switch.adaptive(
                      value: _critical,
                      onChanged: (value) {
                        // Toggle Fix: lokal gebundener State sorgt für sofortige UI-Aktualisierung.
                        setState(() {
                          _critical = value;
                          _formDirty = true;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    Text('Kritisch: ${_critical ? 'Ja' : 'Nein'}'),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Kritisch = sicherheitsrelevanter Einfluss / VWB',
                      child: const Icon(Icons.info_outline, size: 18),
                    ),
                  ],
                ),
                if (_status == 'gesperrt') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _blockedReasonCtrl,
                    decoration: const InputDecoration(labelText: 'Sperrgrund *'),
                    onChanged: (_) => _markSupplierDirty(),
                    validator: (value) {
                      if (_status != 'gesperrt') return null;
                      return (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null;
                    },
                  ),
                ],
              ],
            ),
          ),
          _buildSectionCard(
            title: 'Notizen & Anhänge',
            description: 'Zusätzliche Hinweise oder Dokumente (optional).',
            child: TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notizen'),
              maxLines: 3,
              onChanged: (_) => _markSupplierDirty(),
            ),
          ),
          Row(
            children: [
              ElevatedButton(
                onPressed: canSave ? _saveSupplier : null,
                child: _savingSupplier
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Speichern'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () {
                  if (isEditing) {
                    final supplier = _currentSupplier();
                    if (supplier != null && supplier.id.isNotEmpty) {
                      _selectSupplier(supplier);
                    }
                  } else {
                    _startNewSupplier();
                  }
                },
                child: const Text('Abbrechen'),
              ),
              if (isEditing && _formDirty) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    final supplier = _currentSupplier();
                    if (supplier != null && supplier.id.isNotEmpty) {
                      _selectSupplier(supplier);
                    }
                  },
                  child: const Text('Änderungen verwerfen'),
                ),
              ],
              const Spacer(),
              if (isEditing)
                TextButton.icon(
                  onPressed: () => _confirmDeleteSupplier(selected!),
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  label: const Text('Löschen'),
                ),
            ],
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1050;
        if (isWide) {
          return Row(
            children: [
              Expanded(flex: 4, child: buildListPane(true)),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: formContent,
                ),
              ),
            ],
          );
        }
        return ListView(
          children: [
            buildListPane(false),
            const Divider(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: formContent,
            ),
            const SizedBox(height: 24),
          ],
        );
      },
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
