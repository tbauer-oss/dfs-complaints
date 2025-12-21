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
  String? _performanceStatusFilter;
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
  String _correspondenceLanguage = 'DE';
  bool _showDeletedEntries = false;
  String? _annualSupplierId;
  int _annualYear = DateTime.now().year;

  final _dateFmt = DateFormat('dd.MM.yyyy');
  final _scoreFmt = NumberFormat('0.00', 'de_DE');
  static const String _addLookupValue = '__add__';
  static const List<Map<String, dynamic>> _performanceCategories = [
    {
      'key': 'communication',
      'labelDe': 'Zusammenarbeit / Kommunikation',
      'labelEn': 'Collaboration / communication',
      'weight': 0.10,
      'allowNa': true,
    },
    {
      'key': 'quality',
      'labelDe': 'Produktqualität',
      'labelEn': 'Product quality',
      'weight': 0.30,
      'allowNa': true,
    },
    {
      'key': 'delivery',
      'labelDe': 'Einhaltung der Lieferfrist',
      'labelEn': 'On-time delivery',
      'weight': 0.15,
      'allowNa': true,
    },
    {
      'key': 'price',
      'labelDe': 'Preis / Rechnungsstellung korrekt (vs. Auftragsbestätigung/Angebot)',
      'labelEn': 'Price / invoice correctness (vs. order confirmation/offer)',
      'weight': 0.15,
      'allowNa': true,
    },
    {
      'key': 'quantity',
      'labelDe': 'Richtige Mengen / richtige Produkte (Fehl-/Falschlieferungen)',
      'labelEn': 'Correct quantity / products (wrong/short deliveries)',
      'weight': 0.20,
      'allowNa': true,
    },
    {
      'key': 'backorders',
      'labelDe': 'Nachlieferungen (Teillieferungen / Backorders)',
      'labelEn': 'Backorders (partial deliveries)',
      'weight': 0.10,
      'allowNa': true,
    },
  ];
  static const String _auditNoteDe =
      'Die Lieferantenbewertung ist Bestandteil des Lieferantenmanagements nach DIN EN ISO 13485 (Beschaffung und Lieferantensteuerung). Ziel ist eine nachvollziehbare, objektivierte und wiederholbare Beurteilung anhand definierter Kriterien. Die Notenvergabe erfolgt anhand der unten beschriebenen Stufenbeschreibung und dient als dokumentierter Nachweis der Überwachung sowie als Grundlage für Eskalationen und Maßnahmen.';
  static const String _auditNoteEn =
      'Supplier performance evaluation is part of supplier control according to ISO 13485 (purchasing and supplier management). The purpose is a traceable, objective and repeatable assessment using defined criteria. The grading scale below provides documented evidence of monitoring and supports escalation and corrective actions where needed.';
  static const List<Map<String, String>> _ratingScale = [
    {
      'grade': '1',
      'de': 'Sehr gut: Anforderungen werden vollständig und dauerhaft erfüllt, keine Abweichungen.',
      'en': 'Excellent: Requirements fully and consistently met; no deviations.',
    },
    {
      'grade': '2',
      'de': 'Gut: Anforderungen werden überwiegend erfüllt, nur geringe/vereinzelte Abweichungen ohne relevante Auswirkung.',
      'en': 'Good: Requirements mostly met; minor/isolated deviations without relevant impact.',
    },
    {
      'grade': '3',
      'de': 'Befriedigend: Erkennbare Abweichungen; Aufwand zur Steuerung/Korrektur vorhanden, Liefer-/Prozessabläufe teilweise beeinträchtigt.',
      'en': 'Satisfactory: Noticeable deviations; corrective steering effort required; partial impact on operations.',
    },
    {
      'grade': '4',
      'de': 'Ausreichend: Wiederkehrende oder relevante Abweichungen; erhöhte Steuerung erforderlich; Risiko für Termine/Qualität/Compliance erkennbar.',
      'en': 'Adequate: Recurrent or relevant deviations; increased control needed; risk to delivery/quality/compliance.',
    },
    {
      'grade': '5',
      'de': 'Mangelhaft: Häufige oder schwerwiegende Abweichungen; Lieferfähigkeit/Qualität/Compliance unzuverlässig; Maßnahmen/Eskalation zwingend.',
      'en': 'Poor: Frequent or severe deviations; unreliable performance; escalation/actions mandatory.',
    },
    {
      'grade': '6',
      'de': 'Ungenügend: Anforderungen werden nicht erfüllt; gravierende Abweichungen oder fehlende Kooperation; Lieferant kritisch, Sperrung/Abkündigung prüfen.',
      'en': 'Unsatisfactory: Requirements not met; severe deviations or lack of cooperation; supplier critical, blocking/discontinuation to be considered.',
    },
  ];
  static const Map<String, Map<String, dynamic>> _criterionDefinitions = {
    'communication': {
      'titleDe': 'Zusammenarbeit / Kommunikation',
      'titleEn': 'Collaboration / communication',
      'linesDe': [
        '1: Reagiert proaktiv, zeitnah und vollständig; keine Erinnerung erforderlich (oder N/A falls keine Anfrage nötig war).',
        '2: Reagiert zeitnah, gelegentlich 1 Nachfrage; Kommunikation ausreichend klar.',
        '3: Reagiert verzögert; wiederholt Nachfragen nötig; Abstimmungen verursachen Mehraufwand.',
        '4: Häufige Verzögerungen; unklare/inkonsistente Antworten; Abläufe beeinträchtigt.',
        '5: Sehr schlechte Erreichbarkeit; Rückmeldungen spät oder unvollständig; Eskalation erforderlich.',
        '6: Keine bzw. verweigerte Kommunikation trotz mehrfacher Kontaktversuche.',
      ],
      'linesEn': [
        '1: Responds proactively, promptly, and completely; no reminder required (or N/A if no inquiry was needed).',
        '2: Responds promptly, occasional single follow-up; communication sufficiently clear.',
        '3: Responds with delays; repeated follow-ups needed; coordination causes extra effort.',
        '4: Frequent delays; unclear/inconsistent answers; workflows impacted.',
        '5: Very poor availability; responses late or incomplete; escalation required.',
        '6: No or refused communication despite repeated contact attempts.',
      ],
    },
    'quality': {
      'titleDe': 'Produktqualität',
      'titleEn': 'Product quality',
      'linesDe': [
        '1: Keine qualitätsrelevanten Beanstandungen im Bewertungszeitraum.',
        '2: Vereinzelte geringfügige Beanstandungen ohne systematische Ursache, gut beherrscht.',
        '3: Wiederkehrende Beanstandungen oder relevante Abweichungen; Nacharbeit/Sortierung erforderlich.',
        '4: Häufige Abweichungen; deutliche Auswirkungen auf Produktion/Wareneingang; Ursachenklärung notwendig.',
        '5: Schwerwiegende Mängel oder hohe Fehlerquote; Lieferant verursacht erhebliche Störungen; Maßnahmen zwingend.',
        '6: Kritische/inakzeptable Qualität; Lieferungen nicht verwendbar; Sperrung/Abkündigung prüfen.',
      ],
      'linesEn': [
        '1: No quality-related complaints in the assessment period.',
        '2: Isolated minor complaints without systematic cause, well controlled.',
        '3: Recurring complaints or relevant deviations; rework/sorting required.',
        '4: Frequent deviations; clear impact on production/goods receipt; root cause analysis needed.',
        '5: Severe defects or high error rate; supplier causes major disruptions; actions mandatory.',
        '6: Critical/unacceptable quality; deliveries unusable; consider blocking/discontinuation.',
      ],
    },
    'delivery': {
      'titleDe': 'Einhaltung der Lieferfrist',
      'titleEn': 'On-time delivery',
      'linesDe': [
        '1: Termine werden zuverlässig eingehalten.',
        '2: Seltene Verzögerungen; frühzeitige Information; geringe Auswirkung.',
        '3: Wiederholte Verzögerungen; spürbare Auswirkungen auf Planung/Produktion.',
        '4: Häufige Verzögerungen; Information verspätet; Termintreue unzuverlässig.',
        '5: Regelmäßige erhebliche Lieferverzüge; Eskalation/Alternativen erforderlich.',
        '6: Liefertermine werden systematisch nicht eingehalten; Versorgungssicherheit nicht gegeben.',
      ],
      'linesEn': [
        '1: Dates are reliably met.',
        '2: Rare delays; early information; minor impact.',
        '3: Repeated delays; noticeable impact on planning/production.',
        '4: Frequent delays; late information; reliability is poor.',
        '5: Regular significant delays; escalation/alternatives required.',
        '6: Delivery dates are systematically not met; supply security not ensured.',
      ],
    },
    'price': {
      'titleDe': 'Preis / Rechnungsstellung korrekt',
      'titleEn': 'Price / invoice correctness',
      'linesDe': [
        '1: Rechnungen stets korrekt und vertragskonform (Preis, Menge, Konditionen, Referenzen).',
        '2: Einzelne formale Fehler ohne finanzielle Auswirkung; schnell korrigiert.',
        '3: Wiederkehrende Fehler; Korrekturaufwand/Abstimmung notwendig.',
        '4: Häufige Preis-/Positionsabweichungen; verzögerte Korrekturen; Risiko für falsche Zahlungen.',
        '5: Schwerwiegende/regelmäßige Abrechnungsfehler; Eskalation erforderlich.',
        '6: Preis-/Rechnungsstellung nicht vertragskonform; Korrektur verweigert oder nicht nachvollziehbar.',
      ],
      'linesEn': [
        '1: Invoices always correct and contract-compliant (price, quantity, terms, references).',
        '2: Isolated formal errors without financial impact; corrected quickly.',
        '3: Recurring errors; correction/coordination effort required.',
        '4: Frequent price/line deviations; delayed corrections; risk of incorrect payments.',
        '5: Severe/regular billing errors; escalation required.',
        '6: Price/invoicing not contract-compliant; correction refused or not traceable.',
      ],
    },
    'quantity': {
      'titleDe': 'Richtige Mengen / richtige Produkte',
      'titleEn': 'Correct quantity / products',
      'linesDe': [
        '1: Lieferungen vollständig und korrekt (Artikel, Menge, Identifikation).',
        '2: Vereinzelte Abweichungen ohne relevante Auswirkung; unkomplizierte Korrektur.',
        '3: Wiederkehrende Mengen-/Artikelfehler; Mehraufwand im Wareneingang/Produktion.',
        '4: Häufige Fehl-/Falschlieferungen; deutliche Prozessstörungen.',
        '5: Schwerwiegende Fehl-/Falschlieferungen; Lieferzuverlässigkeit kritisch; Maßnahmen zwingend.',
        '6: Systematische Falschlieferungen/Identifikationsfehler; Versorgung und Rückverfolgbarkeit gefährdet.',
      ],
      'linesEn': [
        '1: Deliveries complete and correct (items, quantities, identification).',
        '2: Isolated deviations without relevant impact; easy correction.',
        '3: Recurring quantity/item errors; extra effort in goods receipt/production.',
        '4: Frequent missing/wrong deliveries; significant process disruptions.',
        '5: Severe missing/wrong deliveries; reliability critical; actions mandatory.',
        '6: Systematic wrong deliveries/identification errors; supply and traceability at risk.',
      ],
    },
    'backorders': {
      'titleDe': 'Nachlieferungen (Teillieferungen / Backorders)',
      'titleEn': 'Backorders / partial deliveries',
      'linesDe': [
        '1: Bestellungen werden vollständig geliefert; keine Nachlieferungen erforderlich.',
        '2: Gelegentliche Teillieferungen ohne Beeinträchtigung; transparent kommuniziert.',
        '3: Regelmäßige Nachlieferungen; Planungsaufwand entsteht.',
        '4: Häufige Teillieferungen; Planung und Verfügbarkeit beeinträchtigt.',
        '5: Umfangreiche/regelmäßige Nachlieferungen; Eskalation/Alternativen erforderlich.',
        '6: Systematisch unvollständige Lieferungen; Versorgungssicherheit nicht gegeben.',
      ],
      'linesEn': [
        '1: Orders delivered in full; no backorders required.',
        '2: Occasional partial deliveries without impact; transparently communicated.',
        '3: Regular backorders; planning effort arises.',
        '4: Frequent partial deliveries; planning and availability impacted.',
        '5: Extensive/regular backorders; escalation/alternatives required.',
        '6: Systematically incomplete deliveries; supply security not ensured.',
      ],
    },
  };

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
        widget.api.adminSupplierPerformance(includeDeleted: true),
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
      _correspondenceLanguage = 'DE';
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
      _correspondenceLanguage = supplier.correspondenceLanguage.isNotEmpty ? supplier.correspondenceLanguage : 'DE';
      _emailTouched = false;
      _emailValidationRequested = false;
      _annualSupplierId = supplier.id;
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
      correspondenceLanguage: _correspondenceLanguage,
      status: _status.trim(),
      notes: _notesCtrl.text.trim(),
      blockedReason: _status == 'gesperrt' ? _blockedReasonCtrl.text.trim() : '',
      blockedAt: blockedAt,
      blockedBy: existing?.blockedBy ?? '',
      archivedAt: existing?.archivedAt,
      archivedBy: existing?.archivedBy ?? '',
      archivedReason: existing?.archivedReason ?? '',
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
        _annualSupplierId = saved.id;
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
    final result = await showDialog<Object?>(
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
                  const SizedBox(height: 8),
                  const Text('Falls bereits Bewertungen/Eskalationen existieren, wird der Lieferant archiviert.'),
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
                          widget.api.adminDeleteSupplier(supplier.id).then((archivedSupplier) {
                            Navigator.pop(context, archivedSupplier ?? 'deleted');
                          }).catchError((err) {
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
    if (result is Supplier) {
      setState(() {
        _suppliers = [result, ..._suppliers.where((s) => s.id != result.id)];
        if (_selectedSupplierId == result.id) {
          _selectSupplier(result);
        }
      });
      _showSnack('Lieferant archiviert (verknüpfte Daten vorhanden).');
      return;
    }
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

  Map<String, int?> _defaultRatings() {
    return {
      for (final category in _performanceCategories) category['key'] as String: null,
    };
  }

  Map<String, bool> _defaultRatingsNa() {
    return {
      for (final category in _performanceCategories) category['key'] as String: false,
    };
  }

  int _ratedCount(Map<String, int?> ratings, {Map<String, bool>? ratingsNa}) {
    int count = 0;
    for (final category in _performanceCategories) {
      final key = category['key'] as String;
      if (ratingsNa?[key] == true) {
        count += 1;
        continue;
      }
      if (ratings[key] != null) count += 1;
    }
    return count;
  }

  bool _isPerformanceComplete(Map<String, int?> ratings, {Map<String, bool>? ratingsNa}) {
    for (final category in _performanceCategories) {
      final key = category['key'] as String;
      if (ratingsNa?[key] == true) {
        continue;
      }
      if (ratings[key] == null) return false;
    }
    return true;
  }

  double? _computeEntryScore(Map<String, int?> ratings, {Map<String, bool>? ratingsNa}) {
    double total = 0;
    double weightTotal = 0;
    for (final category in _performanceCategories) {
      final key = category['key'] as String;
      final weight = category['weight'] as double;
      if (ratingsNa?[key] == true) {
        continue;
      }
      final value = ratings[key];
      if (value == null) return null;
      total += value * weight;
      weightTotal += weight;
    }
    if (weightTotal == 0) return null;
    return double.parse((total / weightTotal).toStringAsFixed(2));
  }

  String _formatScore(double? grade) => grade == null ? '—' : _scoreFmt.format(grade);

  String _computePerformanceStatus(Map<String, int?> ratings, {Map<String, bool>? ratingsNa}) {
    final count = _ratedCount(ratings, ratingsNa: ratingsNa);
    if (count == 0) return 'OFFEN';
    if (_isPerformanceComplete(ratings, ratingsNa: ratingsNa)) return 'ABGESCHLOSSEN';
    return 'IN_BEARBEITUNG';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ABGESCHLOSSEN':
        return Colors.green;
      case 'IN_BEARBEITUNG':
        return Colors.orange;
      case 'GELÖSCHT':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Color _classificationColor(String classification) {
    switch (classification) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.lightGreen;
      case 'C':
        return Colors.orange;
      case 'D':
        return Colors.deepOrange;
      case 'E':
      case 'F':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Map<String, dynamic> _currentStatusSummary(String supplierId) {
    final year = DateTime.now().year;
    final annualEntries = _entriesForAnnual(supplierId, year);
    final summary = _computeAnnualSummary(annualEntries, log: false);
    final includedCount = summary['includedCount'] as int? ?? 0;
    final average = summary['average'] as double?;
    if (includedCount == 0 || average == null) {
      return {
        'status': '—',
        'average': null,
        'includedCount': 0,
        'year': year,
        'hasData': false,
      };
    }
    String status;
    if (average <= 1.80) {
      status = 'A';
    } else if (average <= 2.60) {
      status = 'B';
    } else if (average <= 3.40) {
      status = 'C';
    } else {
      status = 'D';
    }
    return {
      'status': status,
      'average': average,
      'includedCount': includedCount,
      'year': year,
      'hasData': true,
    };
  }

  String _currentStatusLabel(String status) {
    switch (status) {
      case 'A':
        return 'A – sehr gut (zugelassen)';
      case 'B':
        return 'B – gut (zugelassen)';
      case 'C':
        return 'C – befriedigend (zugelassen)';
      case 'D':
        return 'D – kritisch (Beobachtung/Eskalation)';
      default:
        return '—';
    }
  }

  Widget _buildCurrentStatusBadge(String status) {
    final color = status == '—' ? Colors.grey : _classificationColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(status == '—' ? 0.15 : 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  void _jumpToAnnualDetails(String supplierId) {
    setState(() => _annualSupplierId = supplierId);
    final controller = DefaultTabController.of(context);
    if (controller != null) {
      controller.animateTo(2);
    }
  }

  String _referenceLabel(String type) => type == 'BESTELLUNG' ? 'Bestellnummer' : 'Lieferscheinnummer';

  String _referencePlaceholder(String type) => type == 'BESTELLUNG' ? 'z. B. PO-4711' : 'z. B. LS-2025-12345';

  bool get _isEnglish => _correspondenceLanguage == 'EN';

  String _t(String de, String en) => _isEnglish ? en : de;

  String _categoryLabel(Map<String, dynamic> category) =>
      _isEnglish ? category['labelEn'] as String : category['labelDe'] as String;

  String _ratingScaleTooltip() => _t(
        'Notensystem 1–6: 1=Sehr gut, 2=Gut, 3=Befriedigend, 4=Ausreichend, 5=Mangelhaft, 6=Ungenügend.',
        'Rating scale 1–6: 1=Excellent, 2=Good, 3=Satisfactory, 4=Adequate, 5=Poor, 6=Unsatisfactory.',
      );

  List<Map<String, String>> _splitGradeLines(List<String> lines) {
    return lines.map((line) {
      final parts = line.split(':');
      if (parts.length < 2) {
        return {'grade': '', 'text': line.trim()};
      }
      return {
        'grade': parts.first.trim(),
        'text': parts.sublist(1).join(':').trim(),
      };
    }).toList();
  }

  Widget _buildRatingScaleTable() {
    final textTheme = Theme.of(context).textTheme;
    final rows = _ratingScale
        .map(
          (row) => TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(row['grade']!, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(_isEnglish ? row['en']! : row['de']!, style: textTheme.bodySmall),
              ),
            ],
          ),
        )
        .toList();
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(28),
        1: FlexColumnWidth(),
      },
      children: [
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_t('Note', 'Grade'), style: textTheme.labelSmall),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_t('Bedeutung', 'Meaning'), style: textTheme.labelSmall),
            ),
          ],
        ),
        ...rows,
      ],
    );
  }

  Widget _buildCriterionDefinitionTable(String key) {
    final definition = _criterionDefinitions[key] ?? {};
    final lines = (_isEnglish ? definition['linesEn'] : definition['linesDe']) as List<dynamic>? ?? const [];
    final rows = _splitGradeLines(lines.cast<String>());
    final textTheme = Theme.of(context).textTheme;
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(28),
        1: FlexColumnWidth(),
      },
      children: [
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_t('Note', 'Grade'), style: textTheme.labelSmall),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_t('Beschreibung', 'Description'), style: textTheme.labelSmall),
            ),
          ],
        ),
        ...rows.map(
          (row) => TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(row['grade'] ?? '', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(row['text'] ?? '', style: textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatingSystemHelpEntry() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('Bewertungssystem', 'Rating system'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  _t(
                    'Audit-Hinweis: ISO 13485-konforme Lieferantenbewertung mit dokumentierter Nachvollziehbarkeit.',
                    'Audit note: ISO 13485-aligned supplier evaluation with documented traceability.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showRatingSystemModal,
            child: Text(_t('Details', 'Details')),
          ),
        ],
      ),
    );
  }

  Future<void> _showRatingSystemModal() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(_t('Notensystem 1–6', 'Rating scale 1–6'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_t('Audit-Hinweis', 'Audit note'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(_t(_auditNoteDe, _auditNoteEn), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                _buildRatingScaleTable(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCriterionExplanation(String key) async {
    if (!mounted) return;
    final definition = _criterionDefinitions[key] ?? {};
    final title = _isEnglish ? definition['titleEn'] : definition['titleDe'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(title?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildCriterionDefinitionTable(key),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatReference(SupplierPerformanceEntry entry) {
    final label = entry.referenceType == 'BESTELLUNG' ? 'Bestellung' : 'Lieferschein';
    return entry.referenceNumber.isNotEmpty ? '$label ${entry.referenceNumber}' : label;
  }

  Future<void> _openPerformanceEntryDialog({SupplierPerformanceEntry? entry}) async {
    if (_suppliers.isEmpty) {
      _showSnack('Bitte zuerst einen Lieferanten anlegen.');
      return;
    }
    final isEditing = entry != null;
    final descCtrl = TextEditingController(text: entry?.description ?? '');
    final refCtrl = TextEditingController(text: entry?.referenceNumber ?? '');
    final quickChips = [
      const {'label': 'Routinebewertung', 'text': 'Routinebewertung'},
      const {'label': 'Verspätete Lieferung', 'text': 'Verspätete Lieferung'},
      const {'label': 'Qualitätsabweichung', 'text': 'Qualitätsabweichung festgestellt'},
      const {'label': 'Dokumentation unvollständig', 'text': 'Dokumentation unvollständig'},
      const {'label': 'Erstlieferung', 'text': 'Erstlieferung'},
    ];
    String? lastChipText;
    DateTime selectedDate =
        entry != null ? DateTime.fromMillisecondsSinceEpoch(entry.date) : DateTime.now();
    String supplierId = entry?.supplierId ?? _suppliers.first.id;
    String referenceType = entry?.referenceType.isNotEmpty == true ? entry!.referenceType : 'LIEFERSCHEIN';
    bool includeInAnnual = entry?.includeInAnnual ?? true;
    final ratings = Map<String, int?>.from(entry?.ratings ?? _defaultRatings());
    final ratingsNa = Map<String, bool>.from(entry?.ratingsNa ?? _defaultRatingsNa());

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final status = _computePerformanceStatus(ratings, ratingsNa: ratingsNa);
            final progressText =
                '${_ratedCount(ratings, ratingsNa: ratingsNa)}/${_performanceCategories.length} bewertet';
            final gradePreview = _computeEntryScore(ratings, ratingsNa: ratingsNa);
            return AlertDialog(
              title: Text(isEditing ? 'Performance-Fall bearbeiten' : 'Performance-Fall erfassen'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRatingSystemHelpEntry(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          avatar: Icon(
                            status == 'ABGESCHLOSSEN' ? Icons.check_circle : Icons.timelapse_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: Text(status),
                          backgroundColor: _statusColor(status),
                          labelStyle: const TextStyle(color: Colors.white),
                        ),
                        Text(progressText, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sie können Einträge jederzeit nachträglich ergänzen oder korrigieren. Sobald alle Kriterien bewertet sind, wird der Fall automatisch abgeschlossen.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (gradePreview != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Chip(
                          label: Text('Ø-Score: ${_formatScore(gradePreview)} (1=best, 6=schlecht)'),
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        ),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: supplierId,
                      decoration: const InputDecoration(labelText: 'Lieferant'),
                      items: _suppliers
                          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                          .toList(),
                      onChanged: (value) {
                        final nextId = value ?? supplierId;
                        final nextSupplier = _suppliers.firstWhere(
                          (s) => s.id == nextId,
                          orElse: () => _suppliers.first,
                        );
                        setModalState(() => supplierId = nextId);
                        setState(() {
                          _correspondenceLanguage =
                              nextSupplier.correspondenceLanguage.isNotEmpty ? nextSupplier.correspondenceLanguage : _correspondenceLanguage;
                        });
                      },
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
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Kurzbeschreibung *'),
                      onChanged: (value) {
                        if (lastChipText != null && value.trim() != lastChipText) {
                          lastChipText = null;
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Schnellauswahl (optional)', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Klicken Sie auf einen Vorschlag, um die Kurzbeschreibung schnell zu füllen.',
                          child: Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickChips.map((chip) {
                        return ActionChip(
                          label: Text(chip['label']!),
                          backgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
                          labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          onPressed: () {
                            final chipText = chip['text']!;
                            final currentText = descCtrl.text;
                            final trimmed = currentText.trim();
                            if (trimmed.isEmpty || (lastChipText != null && trimmed == lastChipText)) {
                              lastChipText = chipText;
                              descCtrl.value = descCtrl.value.copyWith(
                                text: chipText,
                                selection: TextSelection.collapsed(offset: chipText.length),
                              );
                              return;
                            }
                            final baseText = currentText.trimRight();
                            final separator = baseText.isEmpty ? '' : ' – ';
                            final newText = '$baseText$separator$chipText';
                            lastChipText = null;
                            descCtrl.value = descCtrl.value.copyWith(
                              text: newText,
                              selection: TextSelection.collapsed(offset: newText.length),
                            );
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text('Bezug *', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ToggleButtons(
                      isSelected: [referenceType == 'LIEFERSCHEIN', referenceType == 'BESTELLUNG'],
                      onPressed: (index) {
                        setModalState(() => referenceType = index == 0 ? 'LIEFERSCHEIN' : 'BESTELLUNG');
                      },
                      borderRadius: BorderRadius.circular(8),
                      children: const [
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Lieferschein')),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Bestellung')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: refCtrl,
                      decoration: InputDecoration(
                        labelText: _referenceLabel(referenceType),
                        hintText: _referencePlaceholder(referenceType),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Tooltip(
                                  message: _ratingScaleTooltip(),
                                  child: Text(
                                    _t('Bewertung (alle Kriterien)', 'Rating (all criteria)'),
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.info_outline, size: 18),
                                  tooltip: _t('Notensystem 1–6', 'Rating scale 1–6'),
                                  onPressed: _showRatingSystemModal,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._performanceCategories.map((category) {
                              final key = category['key'] as String;
                              final selected = ratings[key];
                              final allowNa = category['allowNa'] == true;
                              final isNa = ratingsNa[key] == true;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(child: Text(_categoryLabel(category))),
                                          IconButton(
                                            icon: const Icon(Icons.help_outline, size: 18),
                                            tooltip: _t('Notendefinitionen', 'Grade definitions'),
                                            onPressed: () => _showCriterionExplanation(key),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        for (final value in [1, 2, 3, 4, 5, 6])
                                          ChoiceChip(
                                            label: Text(value.toString()),
                                            selected: selected == value,
                                            onSelected: isNa
                                                ? null
                                                : (_) => setModalState(() {
                                                      ratings[key] = value;
                                                      ratingsNa[key] = false;
                                                    }),
                                          ),
                                        if (allowNa)
                                          ChoiceChip(
                                            label: const Text('N/A'),
                                            selected: isNa,
                                            onSelected: (_) => setModalState(() {
                                              ratingsNa[key] = true;
                                              ratings[key] = null;
                                            }),
                                          ),
                                        ChoiceChip(
                                          label: Text(_t('zurücksetzen', 'reset')),
                                          selected: selected == null && !isNa,
                                          onSelected: (_) => setModalState(() {
                                            ratings[key] = null;
                                            ratingsNa[key] = false;
                                          }),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                            Text(
                              _t(
                                'Bewerten Sie jede Kategorie anhand der Stufenbeschreibung. Wenn eine Kategorie im Zeitraum nicht anwendbar war, wählen Sie \'N/A\' (ohne Einfluss auf den Durchschnitt).',
                                'Rate each category using the grade descriptions. If a category was not applicable during the period, choose \'N/A\' (excluded from average).',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      value: includeInAnnual,
                      onChanged: (value) => setModalState(() => includeInAnnual = value),
                      title: const Text('In Jahresbewertung berücksichtigen'),
                    ),
                    if (_computePerformanceStatus(ratings, ratingsNa: ratingsNa) != 'ABGESCHLOSSEN')
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Text(
                          'Der Eintrag wird erst berücksichtigt, wenn alle Kriterien bewertet sind.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                if (isEditing)
                  TextButton(
                    onPressed: () => setModalState(() {
                      ratings.updateAll((key, value) => null);
                      ratingsNa.updateAll((key, value) => false);
                    }),
                    child: const Text('Bewertungen zurücksetzen'),
                  ),
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;
    final description = descCtrl.text.replaceAll('\u00A0', ' ').trim();
    final referenceNumber = refCtrl.text.replaceAll('\u00A0', ' ').trim();
    if (description.isEmpty) {
      _showSnack('Bitte eine Kurzbeschreibung angeben.');
      return;
    }
    if (referenceNumber.isEmpty) {
      _showSnack('Bitte eine Bezugsnummer angeben.');
      return;
    }

    final payload = SupplierPerformanceEntry(
      id: entry?.id ?? '',
      supplierId: supplierId,
      date: selectedDate.millisecondsSinceEpoch,
      description: description,
      referenceType: referenceType,
      referenceNumber: referenceNumber,
      ratings: ratings,
      ratingsNa: ratingsNa,
      communicationNa: ratingsNa['communication'] == true,
      ratingSchemaVersion: 3,
      attachments: entry?.attachments ?? const [],
      includeInAnnual: includeInAnnual,
      status: _computePerformanceStatus(ratings, ratingsNa: ratingsNa),
      cancelReason: entry?.cancelReason ?? '',
      computedGrade: _computeEntryScore(ratings, ratingsNa: ratingsNa),
      computedScore: _computeEntryScore(ratings, ratingsNa: ratingsNa),
      computedAt: DateTime.now().millisecondsSinceEpoch,
      deletedAt: entry?.deletedAt,
      deletedBy: entry?.deletedBy ?? '',
      deletedReason: entry?.deletedReason ?? '',
      createdAt: entry?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      createdBy: entry?.createdBy ?? '',
      updatedBy: '',
      history: entry?.history ?? const [],
    );

    try {
      if (isEditing) {
        final updated = await widget.api.adminUpdateSupplierPerformance(payload);
        setState(() {
          _entries = _entries.map((e) => e.id == updated.id ? updated : e).toList();
        });
        _showSnack('Eintrag aktualisiert.');
      } else {
        final created = await widget.api.adminCreateSupplierPerformance(payload);
        setState(() => _entries = [created, ..._entries]);
        _showSnack('Eintrag gespeichert.');
      }
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _reloadPerformanceEntries({bool includeDeleted = false}) async {
    try {
      final refreshed = await widget.api.adminSupplierPerformance(includeDeleted: true);
      setState(() => _entries = refreshed);
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _confirmDeletePerformanceEntry(SupplierPerformanceEntry entry) async {
    if (!widget.canWrite) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eintrag wirklich löschen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_supplierName(entry.supplierId)} • ${_formatReference(entry)}'),
              const SizedBox(height: 8),
              Text(entry.description),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Löschbegründung *'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (reasonCtrl.text.trim().isEmpty) {
      _showSnack('Bitte eine Löschbegründung angeben.');
      return;
    }
    try {
      await widget.api.adminDeleteSupplierPerformance(entry.id, deleteReason: reasonCtrl.text.trim());
      await _reloadPerformanceEntries(includeDeleted: _showDeletedEntries);
      _showSnack('Eintrag gelöscht.');
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
    String supplierId = _annualSupplierId ?? _suppliers.first.id;
    final yearCtrl = TextEditingController(text: _annualYear.toString());
    String status = 'draft';

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
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Entwurf')),
                    DropdownMenuItem(value: 'final', child: Text('Final')),
                  ],
                  onChanged: (value) => status = value ?? status,
                ),
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
    final evalYear = int.tryParse(yearCtrl.text.trim()) ?? DateTime.now().year;
    final duplicate = _evaluations.any(
      (evaluation) =>
          evaluation.supplierId == supplierId &&
          evaluation.evalYear == evalYear &&
          evaluation.archivedAt == null,
    );
    if (duplicate) {
      _showSnack('Für dieses Jahr existiert bereits eine Bewertung. Bitte bereinigen oder aktualisieren.');
      return;
    }
    final summary = _computeAnnualSummary(_entriesForAnnual(supplierId, evalYear));
    final decision = (summary['decision'] as String?)?.isNotEmpty == true
        ? summary['decision'] as String
        : 'weiterhin zugelassen';
    final periodFrom = DateTime(evalYear, 1, 1).millisecondsSinceEpoch;
    final periodTo = DateTime(evalYear, 12, 31).millisecondsSinceEpoch;

    try {
      final created = await widget.api.adminCreateSupplierEvaluation(
        SupplierAnnualEvaluation(
          id: '',
          evalYear: evalYear,
          periodFrom: periodFrom,
          periodTo: periodTo,
          supplierId: supplierId,
          aggregates: const {},
          commentEk: '',
          commentQm: '',
          decision: decision,
          decisionReason: '',
          status: status,
          configVersion: _config?.version ?? 1,
          configSnapshot: const {},
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          createdBy: '',
          updatedBy: '',
          reviewedBy: '',
          approvedBy: '',
          archivedAt: null,
          archivedBy: '',
          archivedReason: '',
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
      final bytes = await widget.api.adminSupplierReportPdf(type: 'summary');
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

  Future<void> _downloadAnnualPdf({required String type}) async {
    final supplierId = _annualSupplierId ?? _selectedSupplierId;
    if (supplierId == null) {
      _showSnack('Bitte zuerst einen Lieferanten auswählen.');
      return;
    }
    try {
      final bytes = await widget.api.adminSupplierReportPdf(
        supplierId: supplierId,
        year: _annualYear,
        type: type,
      );
      final filename = type == 'letter'
          ? 'lieferantenbrief_${_annualYear}.pdf'
          : 'lieferantenbewertung_${_annualYear}.pdf';
      _downloadBytes(bytes, filename, 'application/pdf');
    } catch (err) {
      final mapped = AppErrorMapper.map(err);
      _showSnack(mapped.message.isEmpty ? mapped.title : '${mapped.title} ${mapped.message}'.trim());
    }
  }

  Future<void> _openEvaluationCleanupDialog(String supplierId, int year) async {
    final duplicates = _evaluations.where((e) => e.supplierId == supplierId && e.evalYear == year && e.archivedAt == null).toList();
    if (duplicates.length <= 1) return;
    String? primaryId = duplicates.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Entwürfe bereinigen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bitte Hauptentwurf auswählen. Alle anderen werden archiviert.'),
                  const SizedBox(height: 12),
                  ...duplicates.map(
                    (entry) => RadioListTile<String>(
                      title: Text('Entwurf ${entry.id} (${entry.status})'),
                      value: entry.id,
                      groupValue: primaryId,
                      onChanged: (value) => setDialogState(() => primaryId = value),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archivieren')),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || primaryId == null) return;
    try {
      final updates = duplicates.where((entry) => entry.id != primaryId).map((entry) {
        final now = DateTime.now().millisecondsSinceEpoch;
        return widget.api.adminUpdateSupplierEvaluation(
          entry.copyWith(
            archivedAt: now,
            archivedBy: 'ui',
            archivedReason: 'Zusammengeführt',
            updatedAt: now,
          ),
        );
      });
      await Future.wait(updates);
      await _loadAll();
      _showSnack('Entwürfe archiviert.');
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

  List<SupplierPerformanceEntry> _entriesForAnnual(String supplierId, int year) {
    return _entries.where((entry) {
      if (entry.supplierId != supplierId) return false;
      if (entry.deletedAt != null) return false;
      final entryYear = DateTime.fromMillisecondsSinceEpoch(entry.date).year;
      return entryYear == year;
    }).toList();
  }

  Map<String, dynamic> _computeAnnualSummary(List<SupplierPerformanceEntry> entries, {bool log = true}) {
    final included = entries.where(
      (entry) =>
          entry.includeInAnnual &&
          _computePerformanceStatus(entry.ratings, ratingsNa: entry.ratingsNa) == 'ABGESCHLOSSEN',
    );
    final grades = included
        .map((entry) => _computeEntryScore(entry.ratings, ratingsNa: entry.ratingsNa))
        .whereType<double>()
        .toList();
    final average = grades.isEmpty ? null : grades.reduce((a, b) => a + b) / grades.length;
    String classification;
    if (average == null) {
      classification = '';
    } else if (average <= 1.80) {
      classification = 'A';
    } else if (average <= 2.60) {
      classification = 'B';
    } else if (average <= 3.40) {
      classification = 'C';
    } else if (average <= 4.20) {
      classification = 'D';
    } else if (average <= 5.00) {
      classification = 'E';
    } else {
      classification = 'F';
    }
    String decision;
    if (classification == 'A' || classification == 'B' || classification == 'C') {
      decision = 'weiterhin zugelassen';
    } else if (classification == 'D') {
      decision = 'in Beobachtung';
    } else if (classification == 'E' || classification == 'F') {
      decision = 'gesperrt / nicht zugelassen';
    } else {
      decision = '';
    }
    final criterionAverages = _performanceCategories.map((category) {
      final key = category['key'] as String;
      final label = _categoryLabel(category);
      final values = included
          .where((entry) => entry.ratingsNa[key] != true)
          .map((entry) => entry.ratings[key])
          .whereType<int>()
          .toList();
      final avg = values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
      return {
        'key': key,
        'label': label,
        'average': avg == null ? null : double.parse(avg.toStringAsFixed(2)),
      };
    }).toList();
    final topDrivers = [...criterionAverages]
      ..removeWhere((item) => item['average'] == null)
      ..sort((a, b) => (b['average'] as double).compareTo(a['average'] as double));
    final worstDrivers = topDrivers.take(2).toList();
    if (log) {
      debugPrint(
        '[supplier-evaluation] annual summary recomputed: included=${included.length}, avg=${average?.toStringAsFixed(2) ?? '—'}',
      );
    }
    final includedList = included.toList();
    final openEntries = entries.where((entry) {
      final complete = _computePerformanceStatus(entry.ratings, ratingsNa: entry.ratingsNa) == 'ABGESCHLOSSEN';
      return !entry.includeInAnnual || !complete;
    }).toList();
    return {
      'includedEntries': includedList,
      'average': average == null ? null : double.parse(average.toStringAsFixed(2)),
      'classification': classification,
      'decision': decision,
      'criterionAverages': criterionAverages,
      'topDrivers': worstDrivers,
      'totalEntries': entries.length,
      'includedCount': includedList.length,
      'openCount': openEntries.length,
    };
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
    final statusSummary = _currentStatusSummary(supplier.id);
    final status = statusSummary['status'] as String;
    final average = statusSummary['average'] as double?;
    final year = statusSummary['year'] as int;
    final hasData = statusSummary['hasData'] as bool;
    final statusSubtext =
        hasData ? 'Ø ${_formatScore(average)} ($year)' : 'Noch keine Bewertung vorhanden';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: isSelected ? 2 : 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        selected: isSelected,
        onTap: () => _selectSupplier(supplier),
        title: Row(
          children: [
            Expanded(child: Text(supplier.name)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildCurrentStatusBadge(status),
                const SizedBox(height: 4),
                Text(statusSubtext, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
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
          if (isEditing && selected != null && selected.id.isNotEmpty) ...[
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final statusSummary = _currentStatusSummary(selected.id);
                final status = statusSummary['status'] as String;
                final average = statusSummary['average'] as double?;
                final includedCount = statusSummary['includedCount'] as int;
                final year = statusSummary['year'] as int;
                final hasData = statusSummary['hasData'] as bool;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildCurrentStatusBadge(status),
                        Text(
                          hasData ? _currentStatusLabel(status) : 'Status: —',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text('Ø Score: ${_formatScore(average)} ($year)'),
                        Text('$includedCount Fälle berücksichtigt'),
                        TextButton(
                          onPressed: () => _jumpToAnnualDetails(selected.id),
                          child: const Text('Details'),
                        ),
                      ],
                    ),
                    if (!hasData)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Noch keine Bewertung vorhanden',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
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
                  value: _correspondenceLanguage,
                  decoration: const InputDecoration(labelText: 'Korrespondenzsprache'),
                  items: const [
                    DropdownMenuItem(value: 'DE', child: Text('Deutsch')),
                    DropdownMenuItem(value: 'EN', child: Text('Englisch')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _correspondenceLanguage = value ?? 'DE';
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
    final filteredBySupplier =
        _supplierFilter == null ? _entries : _entries.where((e) => e.supplierId == _supplierFilter).toList();
    final filteredByDeleted =
        _showDeletedEntries ? filteredBySupplier : filteredBySupplier.where((e) => e.deletedAt == null).toList();
    final entries = _performanceStatusFilter == null
        ? filteredByDeleted
        : filteredByDeleted
            .where(
              (e) => _computePerformanceStatus(e.ratings, ratingsNa: e.ratingsNa) == _performanceStatusFilter,
            )
            .toList();
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
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _performanceStatusFilter,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('Alle Status')),
                    DropdownMenuItem<String?>(value: 'OFFEN', child: Text('Offen')),
                    DropdownMenuItem<String?>(value: 'IN_BEARBEITUNG', child: Text('In Bearbeitung')),
                    DropdownMenuItem<String?>(value: 'ABGESCHLOSSEN', child: Text('Abgeschlossen')),
                  ],
                  onChanged: (value) => setState(() => _performanceStatusFilter = value),
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  Switch.adaptive(
                    value: _showDeletedEntries,
                    onChanged: (value) async {
                      setState(() => _showDeletedEntries = value);
                      await _reloadPerformanceEntries(includeDeleted: value);
                    },
                  ),
                  const SizedBox(width: 6),
                  const Text('Gelöschte anzeigen'),
                ],
              ),
              const SizedBox(width: 12),
              if (widget.canWrite)
                ElevatedButton.icon(
                  onPressed: () => _openPerformanceEntryDialog(),
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Performance-Fall erfassen'),
                ),
            ],
          ),
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Keine Performance-Einträge vorhanden.'),
          ),
        ...entries.map((entry) {
          final status = entry.deletedAt != null
              ? 'GELÖSCHT'
              : _computePerformanceStatus(entry.ratings, ratingsNa: entry.ratingsNa);
          final progress =
              '${_ratedCount(entry.ratings, ratingsNa: entry.ratingsNa)}/${_performanceCategories.length} bewertet';
          final grade = _computeEntryScore(entry.ratings, ratingsNa: entry.ratingsNa);
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: status == 'ABGESCHLOSSEN'
                  ? BorderSide(color: Colors.green.withOpacity(0.4), width: 1)
                  : BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.canWrite && entry.deletedAt == null ? () => _openPerformanceEntryDialog(entry: entry) : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_dateFmt.format(DateTime.fromMillisecondsSinceEpoch(entry.date)),
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(entry.description, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_supplierName(entry.supplierId), style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(_formatReference(entry), style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Chip(
                            label: Text(status),
                            backgroundColor: _statusColor(status),
                            labelStyle: const TextStyle(color: Colors.white),
                          ),
                          Text(progress, style: Theme.of(context).textTheme.bodySmall),
                          Text('Score: ${_formatScore(grade)}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(entry.includeInAnnual ? 'Jahresbewertung: Ja' : 'Jahresbewertung: Nein',
                              style: Theme.of(context).textTheme.bodySmall),
                          if (widget.canWrite)
                            TextButton.icon(
                              onPressed: () => _openPerformanceEntryDialog(entry: entry),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Bearbeiten'),
                            ),
                          if (widget.canWrite && entry.deletedAt == null)
                            TextButton.icon(
                              onPressed: () => _confirmDeletePerformanceEntry(entry),
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              label: const Text('Löschen'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEvaluationTab() {
    if (_suppliers.isEmpty) {
      return const Center(child: Text('Bitte zuerst einen Lieferanten anlegen.'));
    }
    final supplierId = _annualSupplierId ?? _selectedSupplierId ?? _suppliers.first.id;
    final supplier = _suppliers.firstWhere((s) => s.id == supplierId, orElse: () => _suppliers.first);
    final entriesForSupplier = _entries.where((entry) => entry.supplierId == supplierId && entry.deletedAt == null).toList();
    final years = entriesForSupplier
        .map((entry) => DateTime.fromMillisecondsSinceEpoch(entry.date).year)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }
    final selectedYear = years.contains(_annualYear) ? _annualYear : years.first;
    if (selectedYear != _annualYear) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _annualYear = selectedYear);
      });
    }
    final annualEntries = _entriesForAnnual(supplierId, selectedYear);
    final summary = _computeAnnualSummary(annualEntries);
    final included = summary['includedEntries'] as List<SupplierPerformanceEntry>;
    final avg = summary['average'] as double?;
    final classification = summary['classification'] as String;
    final decision = summary['decision'] as String;
    final criterionAverages = summary['criterionAverages'] as List<dynamic>;
    final topDrivers = summary['topDrivers'] as List<dynamic>;
    final totalEntries = (summary['totalEntries'] as int? ?? annualEntries.length);
    final openCount = summary['openCount'] as int? ?? 0;
    final deletedCount = _entries.where((entry) {
      if (entry.supplierId != supplierId) return false;
      final entryYear = DateTime.fromMillisecondsSinceEpoch(entry.date).year;
      return entryYear == selectedYear && entry.deletedAt != null;
    }).length;
    final totalWithDeleted = totalEntries + deletedCount;
    final duplicates = _evaluations.where((e) => e.supplierId == supplierId && e.evalYear == selectedYear && e.archivedAt == null).toList();
    final evalsForSelection = _evaluations.where((e) => e.supplierId == supplierId && e.evalYear == selectedYear).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildRatingSystemHelpEntry(),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jahresbewertung', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: supplierId,
                        decoration: const InputDecoration(labelText: 'Lieferant'),
                        items: _suppliers
                            .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                            .toList(),
                        onChanged: (value) {
                          final nextId = value ?? supplierId;
                          final nextSupplier = _suppliers.firstWhere(
                            (s) => s.id == nextId,
                            orElse: () => supplier,
                          );
                          setState(() {
                            _annualSupplierId = nextId;
                            _correspondenceLanguage =
                                nextSupplier.correspondenceLanguage.isNotEmpty ? nextSupplier.correspondenceLanguage : _correspondenceLanguage;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<int>(
                        value: selectedYear,
                        decoration: const InputDecoration(labelText: 'Jahr'),
                        items: years.map((year) => DropdownMenuItem(value: year, child: Text(year.toString()))).toList(),
                        onChanged: (value) => setState(() => _annualYear = value ?? selectedYear),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Lieferant: ${supplier.name}'),
                    Text('Nr.: ${supplier.supplierNumber.isNotEmpty ? supplier.supplierNumber : '—'}'),
                    Text('Kritisch: ${supplier.critical ? 'Ja' : 'Nein'}'),
                    Text('Sprache: ${supplier.correspondenceLanguage}'),
                  ],
                ),
                if (widget.canWrite) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _createAnnualEvaluation,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Jahresbewertung starten'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _downloadAnnualPdf(type: 'internal'),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF Report (intern)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _downloadAnnualPdf(type: 'letter'),
                        icon: const Icon(Icons.mail_outline),
                        label: const Text('PDF Brief an Lieferant'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _downloadReportCsv,
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Export CSV'),
                      ),
                      if (duplicates.length > 1)
                        TextButton.icon(
                          onPressed: () => _openEvaluationCleanupDialog(supplierId, selectedYear),
                          icon: const Icon(Icons.merge_type_outlined),
                          label: const Text('Entwürfe bereinigen'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gesamtbewertung', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Fälle gesamt: $totalWithDeleted'),
                    Text('Berücksichtigt: ${included.length}'),
                    Text('Offen: $openCount'),
                    Text('Gelöscht: $deletedCount'),
                    Text('Ø Score: ${_formatScore(avg)}'),
                    Chip(
                      label: Text(classification.isEmpty ? '—' : classification),
                      backgroundColor: _classificationColor(classification),
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
                    Text('Entscheidung: ${decision.isNotEmpty ? decision : '—'}'),
                  ],
                ),
                if (classification == 'E' || classification == 'F')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Hinweis: Eskalation erforderlich (Status gesperrt).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Treiber & Kriterien', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                ...criterionAverages.map((item) {
                  final isDriver = topDrivers.any((driver) => driver['key'] == item['key']);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['label'] as String),
                    trailing: Text(
                      item['average'] == null ? '—' : (item['average'] as double).toStringAsFixed(2),
                      style: TextStyle(fontWeight: isDriver ? FontWeight.bold : FontWeight.normal),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nachweise (Evidence)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (annualEntries.isEmpty)
                  const Text('Keine Einträge für dieses Jahr vorhanden.'),
                if (annualEntries.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Datum')),
                        DataColumn(label: Text('Bezug')),
                        DataColumn(label: Text('Nummer')),
                        DataColumn(label: Text('Kurzbeschreibung')),
                        DataColumn(label: Text('Score')),
                        DataColumn(label: Text('N/A Kriterien')),
                        DataColumn(label: Text('Jahresbewertung')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: annualEntries.map((entry) {
                        final naCount = entry.ratingsNa.values.where((value) => value).length;
                        return DataRow(
                          cells: [
                            DataCell(Text(_dateFmt.format(DateTime.fromMillisecondsSinceEpoch(entry.date)))),
                            DataCell(Text(entry.referenceType)),
                            DataCell(Text(entry.referenceNumber)),
                            DataCell(Text(entry.description)),
                            DataCell(Text(_formatScore(_computeEntryScore(entry.ratings, ratingsNa: entry.ratingsNa)))),
                            DataCell(Text(naCount.toString())),
                            DataCell(Text(entry.includeInAnnual ? 'Ja' : 'Nein')),
                            DataCell(Text(_computePerformanceStatus(entry.ratings, ratingsNa: entry.ratingsNa))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vorhandene Jahresbewertungen', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (evalsForSelection.isEmpty)
                  const Text('Keine gespeicherten Jahresbewertungen für dieses Jahr.'),
                if (evalsForSelection.isNotEmpty)
                  ...evalsForSelection.map((evaluation) {
                    final archived = evaluation.archivedAt != null;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Bewertung ${evaluation.id} • ${evaluation.status}'),
                      subtitle: Text(archived ? 'Archiviert' : 'Aktiv'),
                    );
                  }),
              ],
            ),
          ),
        ),
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
