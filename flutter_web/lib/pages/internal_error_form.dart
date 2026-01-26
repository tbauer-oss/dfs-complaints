import 'package:flutter/material.dart';
import '../models/internal_error_model.dart';
import '../widgets/date_field.dart';

class InternalErrorForm extends StatefulWidget {
  final InternalError initial;
  final bool canOverrideCapa;
  final ValueChanged<InternalError>? onChanged;

  const InternalErrorForm({
    super.key,
    required this.initial,
    required this.canOverrideCapa,
    this.onChanged,
  });

  @override
  State<InternalErrorForm> createState() => InternalErrorFormState();
}

class InternalErrorFormState extends State<InternalErrorForm> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _processAreaController;
  late TextEditingController _errorTypeController;
  late TextEditingController _articleController;
  late TextEditingController _descriptionController;
  late TextEditingController _rootCauseController;
  late TextEditingController _detectedByController;
  late TextEditingController _correctionActionController;
  late TextEditingController _responsibleController;
  late TextEditingController _checkerController;
  late TextEditingController _notesController;
  late TextEditingController _capaNumberController;
  late TextEditingController _capaOverrideReasonController;

  bool _customerRelated = false;
  bool _supplierRelated = false;
  DateTime? _dueDate;
  DateTime? _effectivenessCheckDate;
  bool? _effectivenessOk;
  int? _severity;
  int? _occurrence;
  String _status = 'Open';
  bool _capaRequired = false;
  bool _capaOverride = false;

  @override
  void initState() {
    super.initState();
    _processAreaController = TextEditingController(text: widget.initial.processArea);
    _errorTypeController = TextEditingController(text: widget.initial.errorType);
    _articleController = TextEditingController(text: widget.initial.articleOrProduct);
    _descriptionController = TextEditingController(text: widget.initial.description);
    _rootCauseController = TextEditingController(text: widget.initial.rootCause);
    _detectedByController = TextEditingController(text: widget.initial.detectedBy);
    _correctionActionController = TextEditingController(text: widget.initial.correctionAction);
    _responsibleController = TextEditingController(text: widget.initial.responsiblePerson);
    _checkerController = TextEditingController(text: widget.initial.checker);
    _notesController = TextEditingController(text: widget.initial.notes);
    _capaNumberController = TextEditingController(text: widget.initial.capaNumber ?? '');
    _capaOverrideReasonController = TextEditingController(text: widget.initial.capaOverrideReason);
    _customerRelated = widget.initial.customerRelated;
    _supplierRelated = widget.initial.supplierRelated;
    _dueDate = widget.initial.dueDate;
    _effectivenessCheckDate = widget.initial.effectivenessCheckDate;
    _effectivenessOk = widget.initial.effectivenessOk;
    _severity = widget.initial.severity > 0 ? widget.initial.severity : null;
    _occurrence = widget.initial.occurrence > 0 ? widget.initial.occurrence : null;
    _status = widget.initial.status;
    _capaRequired = widget.initial.capaRequired;
    _capaOverride = widget.initial.capaOverride;
  }

  @override
  void didUpdateWidget(covariant InternalErrorForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial.id != widget.initial.id) {
      _processAreaController.text = widget.initial.processArea;
      _errorTypeController.text = widget.initial.errorType;
      _articleController.text = widget.initial.articleOrProduct;
      _descriptionController.text = widget.initial.description;
      _rootCauseController.text = widget.initial.rootCause;
      _detectedByController.text = widget.initial.detectedBy;
      _correctionActionController.text = widget.initial.correctionAction;
      _responsibleController.text = widget.initial.responsiblePerson;
      _checkerController.text = widget.initial.checker;
      _notesController.text = widget.initial.notes;
      _capaNumberController.text = widget.initial.capaNumber ?? '';
      _capaOverrideReasonController.text = widget.initial.capaOverrideReason;
      _customerRelated = widget.initial.customerRelated;
      _supplierRelated = widget.initial.supplierRelated;
      _dueDate = widget.initial.dueDate;
      _effectivenessCheckDate = widget.initial.effectivenessCheckDate;
      _effectivenessOk = widget.initial.effectivenessOk;
      _severity = widget.initial.severity > 0 ? widget.initial.severity : null;
      _occurrence = widget.initial.occurrence > 0 ? widget.initial.occurrence : null;
      _status = widget.initial.status;
      _capaRequired = widget.initial.capaRequired;
      _capaOverride = widget.initial.capaOverride;
    }
  }

  @override
  void dispose() {
    _processAreaController.dispose();
    _errorTypeController.dispose();
    _articleController.dispose();
    _descriptionController.dispose();
    _rootCauseController.dispose();
    _detectedByController.dispose();
    _correctionActionController.dispose();
    _responsibleController.dispose();
    _checkerController.dispose();
    _notesController.dispose();
    _capaNumberController.dispose();
    _capaOverrideReasonController.dispose();
    super.dispose();
  }

  InternalError? submit({required void Function(String message) onError}) {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return null;
    final businessError = _validateBusinessRules();
    if (businessError != null) {
      onError(businessError);
      return null;
    }
    return _buildValue();
  }

  InternalError _buildValue() {
    final points = InternalError.pointsFor(_severity ?? 0, _occurrence ?? 0);
    final escalation = InternalError.escalationForPoints(points);
    final autoCapa = InternalError.capaRequiredForEscalation(escalation);
    final resolvedCapa = _capaOverride ? _capaRequired : autoCapa;
    return widget.initial.copyWith(
      processArea: _processAreaController.text.trim(),
      errorType: _errorTypeController.text.trim(),
      articleOrProduct: _articleController.text.trim(),
      description: _descriptionController.text.trim(),
      rootCause: _rootCauseController.text.trim(),
      detectedBy: _detectedByController.text.trim(),
      customerRelated: _customerRelated,
      supplierRelated: _supplierRelated,
      correctionAction: _correctionActionController.text.trim(),
      dueDate: _dueDate,
      responsiblePerson: _responsibleController.text.trim(),
      effectivenessCheckDate: _effectivenessCheckDate,
      effectivenessOk: _effectivenessOk,
      checker: _checkerController.text.trim(),
      notes: _notesController.text.trim(),
      severity: _severity ?? 0,
      occurrence: _occurrence ?? 0,
      points: points,
      escalation: escalation,
      capaRequired: resolvedCapa,
      capaNumber: _capaNumberController.text.trim().isEmpty ? null : _capaNumberController.text.trim(),
      status: _status,
      capaOverride: _capaOverride,
      capaOverrideReason: _capaOverrideReasonController.text.trim(),
    );
  }

  String? _validateBusinessRules() {
    final createdAt = widget.initial.createdAt;
    if (_dueDate != null && _dueDate!.isBefore(createdAt)) {
      return 'Das Termin-Datum muss nach dem Erstelldatum liegen.';
    }
    if (_capaOverride && _capaOverrideReasonController.text.trim().isEmpty) {
      return 'Bitte eine Begründung für die CAPA-Übersteuerung angeben.';
    }
    if (_status == 'Closed') {
      if (_correctionActionController.text.trim().isEmpty) {
        return 'Für den Abschluss ist eine Korrekturmaßnahme erforderlich.';
      }
      if (_effectivenessOk == null) {
        return 'Für den Abschluss muss die Wirksamkeit bewertet werden.';
      }
      final points = InternalError.pointsFor(_severity ?? 0, _occurrence ?? 0);
      final escalation = InternalError.escalationForPoints(points);
      final requiresCapa = (escalation == 'C' || escalation == 'D') || _capaRequired;
      final capaNumber = _capaNumberController.text.trim();
      final overrideReason = _capaOverrideReasonController.text.trim();
      if (requiresCapa && capaNumber.isEmpty && overrideReason.isEmpty) {
        return 'Für den Abschluss wird eine CAPA-Nummer oder eine QM-Übersteuerung benötigt.';
      }
    }
    return null;
  }

  void _notifyChange() {
    final updated = _buildValue();
    widget.onChanged?.call(updated);
  }

  void _updateDerivedFields({bool notify = true}) {
    final points = InternalError.pointsFor(_severity ?? 0, _occurrence ?? 0);
    final escalation = InternalError.escalationForPoints(points);
    final autoCapa = InternalError.capaRequiredForEscalation(escalation);
    if (!_capaOverride) {
      _capaRequired = autoCapa;
    }
    if (notify) {
      _notifyChange();
    }
  }

  Widget _buildSection({required String title, required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRow(List<Widget> children, {double spacing = 16}) {
    final isNarrow = MediaQuery.of(context).size.width < 900;
    if (isNarrow) {
      return children
          .expand((child) => [child, const SizedBox(height: 16)])
          .toList()
        ..removeLast();
    }
    return [
      Row(
        children: children
            .map((child) => Expanded(child: child))
            .toList()
            .expand((child) => [child, SizedBox(width: spacing)])
            .toList()
          ..removeLast(),
      ),
    ];
  }

  Widget _buildRelationToggles() {
    final isNarrow = MediaQuery.of(context).size.width < 900;
    if (isNarrow) {
      return Column(
        children: [
          SwitchListTile.adaptive(
            value: _customerRelated,
            contentPadding: EdgeInsets.zero,
            title: const Text('Kundenbezug'),
            onChanged: (value) {
              setState(() => _customerRelated = value);
              _notifyChange();
            },
          ),
          SwitchListTile.adaptive(
            value: _supplierRelated,
            contentPadding: EdgeInsets.zero,
            title: const Text('Lieferantenbezug'),
            onChanged: (value) {
              setState(() => _supplierRelated = value);
              _notifyChange();
            },
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: SwitchListTile.adaptive(
            value: _customerRelated,
            contentPadding: EdgeInsets.zero,
            title: const Text('Kundenbezug'),
            onChanged: (value) {
              setState(() => _customerRelated = value);
              _notifyChange();
            },
          ),
        ),
        Expanded(
          child: SwitchListTile.adaptive(
            value: _supplierRelated,
            contentPadding: EdgeInsets.zero,
            title: const Text('Lieferantenbezug'),
            onChanged: (value) {
              setState(() => _supplierRelated = value);
              _notifyChange();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionField({
    required TextEditingController controller,
    required String label,
    required List<String> options,
    bool requiredField = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: requiredField ? '$label *' : label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: PopupMenuButton<String>(
          tooltip: 'Auswahl öffnen',
          icon: const Icon(Icons.arrow_drop_down),
          onSelected: (value) {
            controller.text = value;
            _notifyChange();
          },
          itemBuilder: (context) => [
            for (final option in options)
              PopupMenuItem<String>(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
      validator: validator,
      onChanged: (_) => _notifyChange(),
    );
  }

  Widget _buildEscalationBadge(String escalation) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = _escalationColors(escalation, cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        'Eskalation $escalation',
        style: theme.textTheme.labelLarge?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  _EscalationColors _escalationColors(String escalation, ColorScheme cs) {
    switch (escalation) {
      case 'B':
        return _EscalationColors(
          background: cs.tertiaryContainer,
          foreground: cs.onTertiaryContainer,
          border: cs.tertiary.withOpacity(0.6),
        );
      case 'C':
        return _EscalationColors(
          background: cs.errorContainer,
          foreground: cs.onErrorContainer,
          border: cs.error.withOpacity(0.6),
        );
      case 'D':
        return _EscalationColors(
          background: Color.alphaBlend(cs.error.withOpacity(0.22), cs.surface),
          foreground: cs.error,
          border: cs.error,
        );
      case 'A':
      default:
        return _EscalationColors(
          background: cs.secondaryContainer,
          foreground: cs.onSecondaryContainer,
          border: cs.secondary.withOpacity(0.6),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = InternalError.pointsFor(_severity ?? 0, _occurrence ?? 0);
    final escalation = InternalError.escalationForPoints(points);
    final autoCapa = InternalError.capaRequiredForEscalation(escalation);
    final effectiveCapa = _capaOverride ? _capaRequired : autoCapa;

    final processAreas = [
      'Wareneingang',
      'Produktion',
      'Reinigung',
      'Sterilisation',
      'Verpackung',
      'Qualitätsprüfung',
      'Lager / Logistik',
      'Versand',
    ];

    final errorTypes = [
      'Produktionsfehler',
      'Materialfehler',
      'Dokumentationsfehler',
      'Prozessabweichung',
      'Kennzeichnungsfehler',
      'Lieferantenproblem',
      'Sonstiges (bitte im Text spezifizieren)',
    ];

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            title: 'Basisdaten',
            child: Column(
              children: [
                ..._buildRow([
                  TextFormField(
                    initialValue: widget.initial.errorCode.isEmpty
                        ? 'Wird bei Speicherung generiert'
                        : widget.initial.errorCode,
                    decoration: const InputDecoration(
                      labelText: 'Fehlercode',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    readOnly: true,
                  ),
                  TextFormField(
                    initialValue: widget.initial.createdAt.toIso8601String().split('T').first,
                    decoration: const InputDecoration(
                      labelText: 'Erstellt am',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    readOnly: true,
                  ),
                ]),
                const SizedBox(height: 16),
                ..._buildRow([
                  TextFormField(
                    initialValue: widget.initial.createdBy.isEmpty
                        ? '–'
                        : widget.initial.createdBy,
                    decoration: const InputDecoration(
                      labelText: 'Erstellt von',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    readOnly: true,
                  ),
                  _buildSuggestionField(
                    controller: _processAreaController,
                    label: 'Bereich/Prozess',
                    requiredField: true,
                    options: processAreas,
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
                  ),
                ]),
                const SizedBox(height: 16),
                ..._buildRow([
                  _buildSuggestionField(
                    controller: _errorTypeController,
                    label: 'Fehlerart',
                    requiredField: true,
                    options: errorTypes,
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
                  ),
                  TextFormField(
                    controller: _articleController,
                    decoration: const InputDecoration(
                      labelText: 'Artikel/Produkt/Gruppe',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _notifyChange(),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSection(
            title: 'Beschreibung & Ursache',
            child: Column(
              children: [
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  minLines: 3,
                  maxLines: 6,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
                  onChanged: (_) => _notifyChange(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _rootCauseController,
                  decoration: const InputDecoration(
                    labelText: 'Ursache (Root Cause)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => _notifyChange(),
                ),
                const SizedBox(height: 16),
                ..._buildRow([
                  TextFormField(
                    controller: _detectedByController,
                    decoration: const InputDecoration(
                      labelText: 'Entdeckt von *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
                    onChanged: (_) => _notifyChange(),
                  ),
                  _buildRelationToggles(),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSection(
            title: 'Maßnahmen & Verantwortlichkeit',
            child: Column(
              children: [
                TextFormField(
                  controller: _correctionActionController,
                  decoration: const InputDecoration(
                    labelText: 'Korrekturmaßnahme',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => _notifyChange(),
                ),
                const SizedBox(height: 16),
                ..._buildRow([
                  DateField(
                    label: 'Termin bis',
                    value: _dueDate,
                    onChanged: (value) {
                      setState(() => _dueDate = value);
                      _notifyChange();
                    },
                  ),
                  TextFormField(
                    controller: _responsibleController,
                    decoration: const InputDecoration(
                      labelText: 'Verantwortlich *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null,
                    onChanged: (_) => _notifyChange(),
                  ),
                ]),
                const SizedBox(height: 16),
                ..._buildRow([
                  DateField(
                    label: 'Wirksamkeitsprüfung',
                    value: _effectivenessCheckDate,
                    onChanged: (value) {
                      setState(() => _effectivenessCheckDate = value);
                      _notifyChange();
                    },
                  ),
                  DropdownButtonFormField<bool?>(
                    value: _effectivenessOk,
                    decoration: const InputDecoration(
                      labelText: 'Wirksamkeit ok?',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('ausstehend')),
                      DropdownMenuItem(value: true, child: Text('ja')),
                      DropdownMenuItem(value: false, child: Text('nein')),
                    ],
                    onChanged: (value) {
                      setState(() => _effectivenessOk = value);
                      _notifyChange();
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                ..._buildRow([
                  TextFormField(
                    controller: _checkerController,
                    decoration: const InputDecoration(
                      labelText: 'Prüfer',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _notifyChange(),
                  ),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notizen',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _notifyChange(),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSection(
            title: 'Bewertung & Eskalation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildRow([
                  DropdownButtonFormField<int>(
                    value: _severity,
                    decoration: InputDecoration(
                      labelText: 'Schweregrad *',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Tooltip(
                        message:
                            // AA852: severity definitions tooltip
                            '1 = Sehr geringer/kaum wahrnehmbarer Einfluss auf Produkt; Funktion/Sicherheit nicht beeinträchtigt; Behebung mit geringem Aufwand (einfache Nacharbeit).\n'
                            '2 = Geringfügige Beeinträchtigung; nicht sicherheitsrelevant; Wiederherstellung/Prozessanpassung mit überschaubarem Aufwand kurzfristig möglich.\n'
                            '3 = Hinweis auf möglichen systemischen/systematischen Ursprung; bisher keine sicherheitsrelevanten Auswirkungen; Einzelfallbewertung durch Qualität kann erforderlich sein.\n'
                            '4 = Sicherheitsrelevante Auswirkungen auf Produkt oder Prozess; Sofortmaßnahmen können nötig sein; CAPA-Entscheidung kann vorab durch QM erfolgen, bei Wiederholung automatisch. (betrifft nur Medizinprodukte/MP)\n'
                            '5 = Kritisch! Nichtkonforme Produkte wurden in Verkehr gebracht und beeinträchtigen Produktsicherheit; zwingend Sofortmaßnahmen (z. B. Produktionsstopp, Rückruf, Behördenmeldung). (betrifft nur MP)',
                        child: const Icon(Icons.info_outline),
                      ),
                    ),
                    items: List.generate(
                      5,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1}'),
                      ),
                    ),
                    validator: (value) => value == null ? 'Pflichtfeld' : null,
                    onChanged: (value) {
                      setState(() => _severity = value);
                      _updateDerivedFields();
                    },
                  ),
                  DropdownButtonFormField<int>(
                    value: _occurrence,
                    decoration: InputDecoration(
                      labelText: 'Auftreten *',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Tooltip(
                        message:
                            '1 = selten / Einzelfall\n'
                            '2 = gelegentlich\n'
                            '3 = wiederkehrend\n'
                            '4 = häufig\n'
                            '5 = sehr häufig / trendartig',
                        child: const Icon(Icons.info_outline),
                      ),
                    ),
                    items: List.generate(
                      5,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1}'),
                      ),
                    ),
                    validator: (value) => value == null ? 'Pflichtfeld' : null,
                    onChanged: (value) {
                      setState(() => _occurrence = value);
                      _updateDerivedFields();
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Automatische Berechnung',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('Punkte = Auftreten × Severity-Multiplikator',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$points Punkte',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          _buildEscalationBadge(escalation),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_capaOverride && widget.canOverrideCapa)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      label: const Text('CAPA-Pflicht überschrieben'),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    ),
                  ),
                ..._buildRow([
                  SwitchListTile.adaptive(
                    value: _capaRequired,
                    title: const Text('CAPA erforderlich'),
                    subtitle: Text(
                      effectiveCapa
                          ? 'Pflicht nach Eskalation ($escalation)'
                          : 'keine CAPA-Pflicht nach Eskalation',
                    ),
                    onChanged: widget.canOverrideCapa
                        ? (value) {
                            setState(() {
                              _capaOverride = true;
                              _capaRequired = value;
                            });
                            _notifyChange();
                          }
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Draft', child: Text('Draft (Entwurf)')),
                      DropdownMenuItem(value: 'Open', child: Text('Open (offen)')),
                      DropdownMenuItem(value: 'In Progress', child: Text('In Progress (in Bearbeitung)')),
                      DropdownMenuItem(
                        value: 'Waiting Effectiveness',
                        child: Text('Waiting Effectiveness'),
                      ),
                      DropdownMenuItem(value: 'Closed', child: Text('Closed (abgeschlossen)')),
                    ],
                    validator: (value) => value == null || value.isEmpty ? 'Pflichtfeld' : null,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _status = value);
                      _notifyChange();
                    },
                  ),
                ]),
                if (widget.canOverrideCapa) ...[
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    value: _capaOverride,
                    title: const Text('CAPA-Pflicht überschreiben'),
                    subtitle: const Text('Nur QM/Admin darf diese Pflicht anpassen (mit Begründung).'),
                    onChanged: (value) {
                      setState(() {
                        _capaOverride = value;
                        if (!value) {
                          _capaOverrideReasonController.clear();
                          _updateDerivedFields(notify: false);
                        }
                      });
                      _notifyChange();
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _capaOverrideReasonController,
                    decoration: const InputDecoration(
                      labelText: 'Begründung (CAPA-Override)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: _capaOverride,
                    validator: (value) {
                      if (!_capaOverride) return null;
                      return (value == null || value.trim().isEmpty) ? 'Pflichtfeld' : null;
                    },
                    onChanged: (_) => _notifyChange(),
                  ),
                ],
                const SizedBox(height: 16),
                if (effectiveCapa || escalation == 'C' || escalation == 'D')
                  TextFormField(
                    controller: _capaNumberController,
                    decoration: const InputDecoration(
                      labelText: 'CAPA-Nummer',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _notifyChange(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hinweis: Pflichtfelder sind mit * markiert.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _EscalationColors {
  final Color background;
  final Color foreground;
  final Color border;

  const _EscalationColors({
    required this.background,
    required this.foreground,
    required this.border,
  });
}
