import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signature/signature.dart';
import '../api/client.dart';
import '../models/portal_user.dart';
import '../models/training.dart';

class _DeleteDecision {
  const _DeleteDecision({required this.confirmed, this.deleteInstances = false});

  final bool confirmed;
  final bool deleteInstances;
}

class AdminTrainingPage extends StatefulWidget {
  const AdminTrainingPage({
    super.key,
    required this.api,
    required this.canWrite,
    required this.canDelete,
    this.initialTab = 0,
  });

  final ApiClient api;
  final bool canWrite;
  final bool canDelete;
  final int initialTab;

  @override
  State<AdminTrainingPage> createState() => _AdminTrainingPageState();
}

class _AdminTrainingPageState extends State<AdminTrainingPage> {
  static const List<Map<String, String>> _trainingCategoryOptions = [
    {'value': 'pflichtschulung', 'label': 'Pflichtschulung'},
    {'value': 'qm-iso-mdr', 'label': 'QM / ISO / MDR'},
    {'value': 'arbeitssicherheit', 'label': 'Arbeitssicherheit'},
    {'value': 'produktion-prozess', 'label': 'Produktion / Prozess'},
    {'value': 'it-datenschutz', 'label': 'IT / Datenschutz'},
    {'value': 'soft-skills', 'label': 'Soft Skills'},
    {'value': 'other', 'label': 'Sonstiges...'},
  ];
  static const List<Map<String, String>> _trainingTypeOptions = [
    {'value': 'intern', 'label': 'Intern'},
    {'value': 'extern', 'label': 'Extern'},
  ];
  static const List<Map<String, String>> _trainingFormatOptions = [
    {'value': 'praesenz', 'label': 'Präsenz'},
    {'value': 'online', 'label': 'Online'},
  ];
  static const List<String> _trainingLocationOptions = [
    'DFS Riedenburg – Schulungsraum',
    'DFS Riedenburg – Produktion',
    'Diaswiss Nyon – Besprechungsraum',
    'Extern – beim Anbieter',
  ];
  static const List<Map<String, String>> _meetingPlatforms = [
    {'value': 'teams', 'label': 'Microsoft Teams'},
    {'value': 'zoom', 'label': 'Zoom'},
    {'value': 'webex', 'label': 'Webex'},
    {'value': 'other', 'label': 'Andere'},
  ];
  final _searchController = TextEditingController();
  final _programSearchController = TextEditingController();
  List<TrainingNeed> _needs = const [];
  List<TrainingProgram> _programs = const [];
  List<TrainingRecord> _trainings = const [];
  List<TrainingQuestionnaireTemplate> _templates = const [];
  List<PortalUserSummary> _staffUsers = const [];
  Map<String, dynamic> _wkReminders = const {};
  Map<String, dynamic> _summary = const {};
  bool _loading = false;
  String? _error;
  int _programYearFilter = DateTime.now().year;
  String? _programDepartmentFilter;
  String? _programStatusFilter;
  String? _programFormatFilter;
  String _programSort = 'plannedPeriod';
  bool _programSortAsc = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _programSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.adminTrainingNeeds(),
        widget.api.adminTrainingPrograms(),
        widget.api.adminTrainings(),
        widget.api.adminTrainingTemplates(),
        widget.api.adminTrainingSummary(),
        widget.api.adminStaffUsers(includeInactive: false),
        widget.api.trainingWkReminders(),
      ]);
      setState(() {
        _needs = results[0] as List<TrainingNeed>;
        _programs = results[1] as List<TrainingProgram>;
        _trainings = results[2] as List<TrainingRecord>;
        _templates = results[3] as List<TrainingQuestionnaireTemplate>;
        _summary = results[4] as Map<String, dynamic>;
        _staffUsers = results[5] as List<PortalUserSummary>;
        _wkReminders = results[6] as Map<String, dynamic>;
        if (_programs.isNotEmpty) {
          final years = _programs.map((entry) => entry.year).toSet();
          if (!years.contains(_programYearFilter)) {
            _programYearFilter = years.reduce((a, b) => a > b ? a : b);
          }
        }
      });
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _downloadBytes(Uint8List bytes, String filename, String mime) {
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)..download = filename;
    anchor.click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _reloadWkReminders() async {
    try {
      final data = await widget.api.trainingWkReminders();
      if (!mounted) return;
      setState(() => _wkReminders = data);
    } catch (_) {
      // Ignore reminder refresh errors
    }
  }

  Future<void> _downloadTrainingPdf(TrainingRecord record) async {
    try {
      final bytes = await widget.api.adminTrainingPdf(record.id);
      _downloadBytes(bytes, '${record.trainingNumber.isEmpty ? 'training' : record.trainingNumber}.pdf', 'application/pdf');
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF konnte nicht erstellt werden: $err')),
      );
    }
  }

  Future<void> _downloadProgramPdf(int year) async {
    try {
      final bytes = await widget.api.adminTrainingProgramPdf(
        year,
        department: _programDepartmentFilter,
        status: _programStatusFilter,
        format: _programFormatFilter,
        search: _programSearchController.text.trim(),
        sort: _programSort,
      );
      _downloadBytes(bytes, 'Schulungsprogramm-$year.pdf', 'application/pdf');
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Programm-PDF konnte nicht erstellt werden: $err')),
      );
    }
  }

  String get _currentUserEmail {
    final profile = widget.api.portalProfile;
    return (profile?['email'] ?? '').toString().toLowerCase();
  }

  bool get _isAdminUser {
    final role = (widget.api.portalProfile?['role'] ?? '').toString().toLowerCase();
    return role == 'admin' || role == 'superuser';
  }

  PortalUserSummary? _staffByEmail(String? email) {
    if (email == null || email.isEmpty) return null;
    for (final user in _staffUsers) {
      if (user.email.toLowerCase() == email.toLowerCase()) return user;
    }
    return null;
  }

  String _trainingStatusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Entwurf';
      case 'planned':
        return 'Geplant';
      case 'scheduled':
        return 'Terminiert';
      case 'inProgress':
        return 'In Durchführung';
      case 'conducted':
        return 'Durchgeführt';
      case 'completed':
        return 'Abgeschlossen';
      case 'cancelled':
        return 'Abgesagt';
      default:
        return status;
    }
  }

  String _trainingCategoryLabel(TrainingRecord record) {
    if (record.category == 'other') {
      final freeText = record.categoryFreeText ?? '';
      return freeText.isNotEmpty ? freeText : 'Sonstiges';
    }
    final match = _trainingCategoryOptions.firstWhere(
      (entry) => entry['value'] == record.category,
      orElse: () => const {'label': ''},
    );
    return match['label']!.isNotEmpty ? match['label']! : record.category;
  }

  String _trainingTypeLabel(String type) {
    if (type == 'intern') return 'Intern';
    if (type == 'extern') return 'Extern';
    return type;
  }

  String _trainingFormatLabel(String format) {
    if (format == 'praesenz') return 'Präsenz';
    if (format == 'online') return 'Online';
    return format;
  }

  String _trainingTimeLabel(TrainingRecord record) {
    final start = record.startTime ?? '';
    final end = record.endTime ?? '';
    if (start.isNotEmpty && end.isNotEmpty) {
      return '$start – $end';
    }
    return '';
  }

  String _trainingLocationLabel(TrainingRecord record) {
    if (record.format == 'online') {
      return (record.meetingLink ?? record.location).trim();
    }
    return record.location;
  }

  String _trainingTrainerLabel(TrainingRecord record) {
    if (record.type == 'extern') {
      return (record.providerCompany ?? record.trainer).trim();
    }
    return (record.trainerInternal ?? record.trainer).trim();
  }

  String _trainingOwnerLabel(TrainingRecord record) {
    final ownerId = record.ownerUserId ?? record.owner;
    return _staffByEmail(ownerId)?.label ?? record.owner;
  }

  String _wkMethodLabel(String? method) {
    switch (method) {
      case 'questionnaire':
        return 'Fragebogen (digital)';
      case 'direct':
        return 'Direkte Messung (Befragung)';
      case 'indirect':
        return 'Indirekte Messung (Überprüfung der Arbeitsergebnisse)';
      default:
        return '—';
    }
  }

  String _wkStatusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'offen';
      case 'in_progress':
        return 'in Arbeit';
      case 'done':
        return 'abgeschlossen';
      case 'overdue':
        return 'überfällig';
      default:
        return '—';
    }
  }

  Future<_DeleteDecision?> _confirmDeleteDecision({
    required String title,
    required String message,
    bool allowInstanceDelete = false,
  }) {
    bool deleteInstances = false;
    return showDialog<_DeleteDecision>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  if (allowInstanceDelete)
                    CheckboxListTile(
                      value: deleteInstances,
                      onChanged: (value) => setState(() => deleteInstances = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Vorlage + alle automatisch erzeugten Instanzen löschen'),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_DeleteDecision(confirmed: true, deleteInstances: deleteInstances)),
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                  child: const Text('Löschen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool?> _confirmPurge(String scopeLabel) {
    final controller = TextEditingController();
    bool confirmChecked = false;
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final phraseOk = controller.text.trim().toUpperCase() == 'LÖSCHEN';
            final canConfirm = phraseOk && confirmChecked;
            return AlertDialog(
              title: Text('Alles löschen ($scopeLabel)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Diese Aktion kann nicht rückgängig gemacht werden. Bitte bestätigen Sie das Löschen.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Bestätigung (LÖSCHEN)',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  CheckboxListTile(
                    value: confirmChecked,
                    onChanged: (value) => setState(() => confirmChecked = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Ich bestätige unwiderruflich'),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: canConfirm ? () => Navigator.of(context).pop(true) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                  child: const Text('Alles löschen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _purgeTrainingScope(String scope, String scopeLabel) async {
    if (!widget.canDelete) return;
    final confirmed = await _confirmPurge(scopeLabel);
    if (confirmed != true) return;
    try {
      await widget.api.adminPurgeTraining(scope);
      await _loadAll();
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $err')));
    }
  }

  Future<void> _deleteNeed(TrainingNeed need) async {
    if (!widget.canDelete) return;
    final allowInstances = need.intervalType == 'recurring' && (need.parentRecurringId == null || need.parentRecurringId!.isEmpty);
    final decision = await _confirmDeleteDecision(
      title: 'Schulungsbedarf löschen',
      message: 'Möchten Sie diesen Schulungsbedarf wirklich löschen?',
      allowInstanceDelete: allowInstances,
    );
    if (decision?.confirmed != true) return;
    try {
      await widget.api.adminDeleteTrainingNeed(need.id, deleteInstances: decision?.deleteInstances ?? false);
      setState(() {
        _needs = _needs.where((entry) {
          if (entry.id == need.id) return false;
          if ((decision?.deleteInstances ?? false) && entry.parentRecurringId == need.id) return false;
          return true;
        }).toList();
      });
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $err')));
    }
  }

  Future<void> _deleteProgram(TrainingProgram program) async {
    if (!widget.canDelete) return;
    final decision = await _confirmDeleteDecision(
      title: 'Schulungsprogramm löschen',
      message: 'Möchten Sie dieses Schulungsprogramm wirklich löschen?',
    );
    if (decision?.confirmed != true) return;
    try {
      await widget.api.adminDeleteTrainingProgram(program.id);
      setState(() => _programs = _programs.where((entry) => entry.id != program.id).toList());
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $err')));
    }
  }

  Future<void> _deleteTraining(TrainingRecord training) async {
    if (!widget.canDelete) return;
    final allowInstances = training.intervalType == 'recurring' &&
        (training.parentRecurringId == null || training.parentRecurringId!.isEmpty);
    final decision = await _confirmDeleteDecision(
      title: 'Schulung löschen',
      message: 'Möchten Sie diese Schulung wirklich löschen?',
      allowInstanceDelete: allowInstances,
    );
    if (decision?.confirmed != true) return;
    try {
      await widget.api.adminDeleteTraining(training.id, deleteInstances: decision?.deleteInstances ?? false);
      setState(() {
        _trainings = _trainings.where((entry) {
          if (entry.id == training.id) return false;
          if ((decision?.deleteInstances ?? false) && entry.parentRecurringId == training.id) return false;
          return true;
        }).toList();
      });
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $err')));
    }
  }

  Future<void> _deleteTemplate(TrainingQuestionnaireTemplate template) async {
    if (!widget.canDelete) return;
    final decision = await _confirmDeleteDecision(
      title: 'Template löschen',
      message: 'Möchten Sie dieses Template wirklich löschen?',
    );
    if (decision?.confirmed != true) return;
    try {
      await widget.api.adminDeleteTrainingTemplate(template.id);
      setState(() => _templates = _templates.where((entry) => entry.id != template.id).toList());
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $err')));
    }
  }

  Widget _autoBadge(ThemeData theme) {
    return Chip(
      label: const Text('Automatisch'),
      labelStyle: theme.textTheme.labelSmall,
      backgroundColor: theme.colorScheme.secondaryContainer,
      padding: EdgeInsets.zero,
    );
  }

  Future<TrainingNeed?> _openNeedDialog({TrainingNeed? initial}) async {
    if (!widget.canWrite) return null;
    final controllerYear = TextEditingController(text: (initial?.year ?? DateTime.now().year).toString());
    final controllerContact = TextEditingController(text: initial?.contactName ?? '');
    final controllerTopic = TextEditingController(text: initial?.items.isNotEmpty == true ? initial!.items.first.topic : '');
    final controllerParticipants = TextEditingController(
      text: initial?.items.isNotEmpty == true ? initial!.items.first.participants.toString() : '',
    );
    final controllerBudget = TextEditingController(
      text: initial?.plannedBudget == null ? '' : initial!.plannedBudget!.toStringAsFixed(0),
    );
    final controllerComments = TextEditingController(text: initial?.comments ?? '');
    final controllerDepartmentOther = TextEditingController(text: initial?.departmentTeamFreeText ?? '');
    final controllerPlannedDate = TextEditingController();
    final controllerIntervalOther = TextEditingController(text: initial?.intervalValueFreeText ?? '');
    final controllerTopicPriorities = TextEditingController(text: initial?.topicPriorities ?? '');
    final controllerPreferredTrainers = TextEditingController(text: initial?.preferredTrainers ?? '');
    final controllerSpecialRequirements = TextEditingController(text: initial?.specialRequirements ?? '');

    const departmentOptions = [
      'Gesamte Organisation',
      'Gesamte Produktion',
      'Produktion 1',
      'Produktion 2',
      'Abt. Schleiferei',
      'Abt. Chemie / Logistik',
      'Abt. Sinterei',
      'Abt. Bürstenproduktion',
      'Abt. Sonderwerkzeuge',
      'Abt. Galvanik',
      'Abt. Galvanik Vor-/Nachbereitung',
      'Abt. Dreherei',
      'Abt. Werkzeugbau',
      'Versand',
      'Vertrieb',
      'Einkauf',
      'Geschäftsleitung',
      'Human Ressources / Personal',
      'Finanzen',
      'Sonstiges...',
    ];
    const intervalOptions = [
      'vierteljährlich',
      'halbjährlich',
      'jährlich',
      'alle 2 Jahre',
      'alle 3 Jahre',
      'alle 4 Jahre',
      'alle 5 Jahre',
      'Sonstiges...',
    ];
    const plannedPeriodTypes = ['date', 'month', 'quarter', 'halfYear'];
    const trainingFormats = {'praesenz': 'Präsenz', 'online': 'Online'};
    const intervalTypes = {'once': 'einmalig', 'recurring': 'wiederkehrend'};

    String? selectedDepartment = initial?.departmentTeamSelected.isNotEmpty == true
        ? initial!.departmentTeamSelected
        : departmentOptions.first;
    String plannedPeriodType = initial?.plannedPeriodType.isNotEmpty == true ? initial!.plannedPeriodType : plannedPeriodTypes.first;
    String? selectedMonth;
    String? selectedQuarter;
    String? selectedHalfYear;
    DateTime? selectedPlannedDate;
    String? plannedPeriodValue = initial?.plannedPeriodValue;
    String? selectedFormat = initial?.trainingFormat.isNotEmpty == true ? initial!.trainingFormat : null;
    String? selectedIntervalType = initial?.intervalType.isNotEmpty == true ? initial!.intervalType : null;
    String? selectedIntervalValue = initial?.intervalValue;
    bool confirmationChecked = initial != null;
    bool recurrenceActive = initial?.recurrenceActive ?? true;

    String? errorYear;
    String? errorContact;
    String? errorDepartment;
    String? errorDepartmentOther;
    String? errorTopic;
    String? errorPlannedPeriod;
    String? errorFormat;
    String? errorIntervalType;
    String? errorIntervalValue;
    String? errorIntervalOther;
    String? errorParticipants;
    String? errorBudget;

    String formatDate(DateTime date) {
      final y = date.year.toString().padLeft(4, '0');
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    String? buildPlannedPeriodValue() {
      final trainingYear = int.tryParse(controllerYear.text.trim());
      if (trainingYear == null) return null;
      final yearText = trainingYear.toString().padLeft(4, '0');
      if (plannedPeriodType == 'date') {
        if (selectedPlannedDate == null) return null;
        final forcedDate = DateTime(trainingYear, selectedPlannedDate!.month, selectedPlannedDate!.day);
        return formatDate(forcedDate);
      }
      if (plannedPeriodType == 'month') {
        if (selectedMonth == null) return null;
        return '$yearText-$selectedMonth';
      }
      if (plannedPeriodType == 'quarter') {
        if (selectedQuarter == null) return null;
        return '$yearText-$selectedQuarter';
      }
      if (selectedHalfYear == null) return null;
      return '$yearText-$selectedHalfYear';
    }

    String buildPlannedPeriodLabel(String value) {
      switch (plannedPeriodType) {
        case 'date':
          return 'Datum: $value';
        case 'month':
          return 'Monat: $value';
        case 'quarter':
          return 'Quartal: ${value.split('-').last} ${value.split('-').first}';
        case 'halfYear':
          return 'Halbjahr: ${value.split('-').last} ${value.split('-').first}';
      }
      return value;
    }

    void syncPlannedPeriodValue() {
      plannedPeriodValue = buildPlannedPeriodValue();
      if (plannedPeriodValue != null) {
        errorPlannedPeriod = null;
      }
    }

    void syncPlannedPeriodYear() {
      final trainingYear = int.tryParse(controllerYear.text.trim());
      if (trainingYear == null || selectedPlannedDate == null) return;
      final updated = DateTime(trainingYear, selectedPlannedDate!.month, selectedPlannedDate!.day);
      selectedPlannedDate = updated;
      controllerPlannedDate.text = formatDate(updated);
    }

    if (plannedPeriodValue != null) {
      if (plannedPeriodType == 'date' && plannedPeriodValue!.length >= 10) {
        controllerPlannedDate.text = plannedPeriodValue!;
        selectedPlannedDate = DateTime.tryParse(plannedPeriodValue!);
      } else if (plannedPeriodType == 'month') {
        selectedMonth = plannedPeriodValue!.split('-').last;
      } else if (plannedPeriodType == 'quarter') {
        selectedQuarter = plannedPeriodValue!.split('-').last;
      } else if (plannedPeriodType == 'halfYear') {
        selectedHalfYear = plannedPeriodValue!.split('-').last;
      }
    }

    final result = await showDialog<TrainingNeed>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final selectedDepartmentIsOther = selectedDepartment == 'Sonstiges...';
            final intervalIsRecurring = selectedIntervalType == 'recurring';
            final intervalIsOther = selectedIntervalValue == 'Sonstiges...';

            return AlertDialog(
              title: Text(initial == null ? 'Neuer Schulungsbedarf' : 'Schulungsbedarf bearbeiten'),
              content: SizedBox(
                width: 520,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      TextField(
                        controller: controllerYear,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {
                          syncPlannedPeriodYear();
                          syncPlannedPeriodValue();
                        }),
                        decoration: InputDecoration(
                          labelText: 'Schulungsjahr',
                          labelStyle: const TextStyle(overflow: TextOverflow.visible),
                          errorText: errorYear,
                        ),
                      ),
                      TextField(
                        controller: controllerContact,
                        decoration: InputDecoration(
                          labelText: 'Ansprechpartner',
                          errorText: errorContact,
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        value: selectedDepartment,
                        items: departmentOptions
                            .map((option) => DropdownMenuItem(value: option, child: Text(option)))
                            .toList(),
                        onChanged: (value) => setState(() {
                          selectedDepartment = value;
                          if (selectedDepartment != 'Sonstiges...') {
                            controllerDepartmentOther.clear();
                          }
                        }),
                        decoration: InputDecoration(
                          labelText: 'Abteilung/Team',
                          errorText: errorDepartment,
                        ),
                      ),
                      if (selectedDepartmentIsOther)
                        TextField(
                          controller: controllerDepartmentOther,
                          decoration: InputDecoration(
                            labelText: 'Bitte Abteilung/Team angeben',
                            errorText: errorDepartmentOther,
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controllerTopic,
                        decoration: InputDecoration(
                          labelText: 'Schulungsthema',
                          errorText: errorTopic,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Geplanter Zeitraum',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Datum'),
                            selected: plannedPeriodType == 'date',
                            onSelected: (_) => setState(() {
                              plannedPeriodType = 'date';
                              syncPlannedPeriodValue();
                            }),
                          ),
                          ChoiceChip(
                            label: const Text('Monat'),
                            selected: plannedPeriodType == 'month',
                            onSelected: (_) => setState(() {
                              plannedPeriodType = 'month';
                              syncPlannedPeriodValue();
                            }),
                          ),
                          ChoiceChip(
                            label: const Text('Quartal'),
                            selected: plannedPeriodType == 'quarter',
                            onSelected: (_) => setState(() {
                              plannedPeriodType = 'quarter';
                              syncPlannedPeriodValue();
                            }),
                          ),
                          ChoiceChip(
                            label: const Text('Halbjahr'),
                            selected: plannedPeriodType == 'halfYear',
                            onSelected: (_) => setState(() {
                              plannedPeriodType = 'halfYear';
                              syncPlannedPeriodValue();
                            }),
                          ),
                        ],
                      ),
                      if (plannedPeriodType == 'date')
                        TextField(
                          controller: controllerPlannedDate,
                          readOnly: true,
                          onTap: () async {
                            final year = int.tryParse(controllerYear.text.trim()) ?? DateTime.now().year;
                            final initial = selectedPlannedDate ?? DateTime(year, 1, 1);
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(year, 1, 1),
                              lastDate: DateTime(year, 12, 31),
                            );
                            if (picked != null) {
                              setState(() {
                                final forcedDate = DateTime(year, picked.month, picked.day);
                                selectedPlannedDate = forcedDate;
                                controllerPlannedDate.text = formatDate(forcedDate);
                                syncPlannedPeriodValue();
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Datum',
                            hintText: 'YYYY-MM-DD',
                            errorText: errorPlannedPeriod,
                          ),
                        ),
                      if (plannedPeriodType == 'month')
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedMonth,
                                items: List.generate(
                                  12,
                                  (idx) {
                                    final month = (idx + 1).toString().padLeft(2, '0');
                                    return DropdownMenuItem(value: month, child: Text(month));
                                  },
                                ),
                                onChanged: (value) => setState(() {
                                  selectedMonth = value;
                                  syncPlannedPeriodValue();
                                }),
                                decoration: const InputDecoration(labelText: 'Monat'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Jahr'),
                                child: Text(
                                  'Jahr: ${controllerYear.text.trim().isEmpty ? 'JJJJ' : controllerYear.text.trim()} (aus Schulungsjahr übernommen)',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (plannedPeriodType == 'quarter')
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedQuarter,
                                items: const [
                                  DropdownMenuItem(value: 'Q1', child: Text('Q1')),
                                  DropdownMenuItem(value: 'Q2', child: Text('Q2')),
                                  DropdownMenuItem(value: 'Q3', child: Text('Q3')),
                                  DropdownMenuItem(value: 'Q4', child: Text('Q4')),
                                ],
                                onChanged: (value) => setState(() {
                                  selectedQuarter = value;
                                  syncPlannedPeriodValue();
                                }),
                                decoration: const InputDecoration(labelText: 'Quartal'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Jahr'),
                                child: Text(
                                  'Jahr: ${controllerYear.text.trim().isEmpty ? 'JJJJ' : controllerYear.text.trim()} (aus Schulungsjahr übernommen)',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (plannedPeriodType == 'halfYear')
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedHalfYear,
                                items: const [
                                  DropdownMenuItem(value: 'H1', child: Text('H1')),
                                  DropdownMenuItem(value: 'H2', child: Text('H2')),
                                ],
                                onChanged: (value) => setState(() {
                                  selectedHalfYear = value;
                                  syncPlannedPeriodValue();
                                }),
                                decoration: const InputDecoration(labelText: 'Halbjahr'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Jahr'),
                                child: Text(
                                  'Jahr: ${controllerYear.text.trim().isEmpty ? 'JJJJ' : controllerYear.text.trim()} (aus Schulungsjahr übernommen)',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (plannedPeriodType != 'date' && errorPlannedPeriod != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              errorPlannedPeriod!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Format',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: trainingFormats.entries
                            .map(
                              (entry) => ChoiceChip(
                                label: Text(entry.value),
                                selected: selectedFormat == entry.key,
                                onSelected: (_) => setState(() => selectedFormat = entry.key),
                              ),
                            )
                            .toList(),
                      ),
                      if (errorFormat != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              errorFormat!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Schulungsintervall',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: intervalTypes.entries
                            .map(
                              (entry) => ChoiceChip(
                                label: Text(entry.value),
                                selected: selectedIntervalType == entry.key,
                                onSelected: (_) => setState(() {
                                  selectedIntervalType = entry.key;
                                  if (selectedIntervalType != 'recurring') {
                                    selectedIntervalValue = null;
                                    controllerIntervalOther.clear();
                                  }
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      if (errorIntervalType != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              errorIntervalType!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                            ),
                          ),
                        ),
                      if (intervalIsRecurring)
                        DropdownButtonFormField<String>(
                          value: selectedIntervalValue,
                          items: intervalOptions
                              .map((option) => DropdownMenuItem(value: option, child: Text(option)))
                              .toList(),
                          onChanged: (value) => setState(() {
                            selectedIntervalValue = value;
                            if (selectedIntervalValue != 'Sonstiges...') {
                              controllerIntervalOther.clear();
                            }
                          }),
                          decoration: InputDecoration(
                            labelText: 'Intervall',
                            errorText: errorIntervalValue,
                          ),
                        ),
                      if (intervalIsRecurring && intervalIsOther)
                        TextField(
                          controller: controllerIntervalOther,
                          decoration: InputDecoration(
                            labelText: 'Intervall (frei)',
                            errorText: errorIntervalOther,
                          ),
                        ),
                      if (intervalIsRecurring)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Wiederholung aktiv'),
                          subtitle: const Text('Automatische Eintragung für zukünftige Zeiträume'),
                          value: recurrenceActive,
                          onChanged: (value) => setState(() => recurrenceActive = value),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controllerParticipants,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                labelText: 'Teilnehmer',
                                errorText: errorParticipants,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: controllerBudget,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Geplantes Budget',
                                suffixText: '€',
                                errorText: errorBudget,
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: controllerComments,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Zusätzliche Hinweise / Kommentare'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controllerTopicPriorities,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Welche Themen / Fachgebiete sind für Ihre Abteilung besonders wichtig?',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controllerPreferredTrainers,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Gibt es spezifische Trainer oder Schulungsanbieter, die Sie bevorzugen?',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controllerSpecialRequirements,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText:
                              'Gibt es besondere Anforderungen (z. B. barrierefreie Schulung, Sprachbarrieren, spezifische Inhalte)?',
                        ),
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        value: confirmationChecked,
                        onChanged: (value) => setState(() => confirmationChecked = value ?? false),
                        title: const Text('Ich bestätige die Angaben.'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Abbrechen'),
                          ),
                          const Spacer(),
                        ElevatedButton(
                          onPressed: confirmationChecked
                              ? () {
                                    final yearText = controllerYear.text.trim();
                                    final contactText = controllerContact.text.trim();
                                    final topicText = controllerTopic.text.trim();
                                    final participantsText = controllerParticipants.text.trim();
                                    final departmentOtherText = controllerDepartmentOther.text.trim();
                                    final intervalOtherText = controllerIntervalOther.text.trim();
                                    final budgetText = controllerBudget.text.trim();

                                    errorYear = yearText.isEmpty ? 'Pflichtfeld' : null;
                                    errorContact = contactText.isEmpty ? 'Pflichtfeld' : null;
                                    errorDepartment =
                                        (selectedDepartment == null || selectedDepartment!.isEmpty) ? 'Pflichtfeld' : null;
                                    errorDepartmentOther = selectedDepartmentIsOther
                                        ? (departmentOtherText.length < 2 ? 'Bitte mindestens 2 Zeichen eingeben.' : null)
                                        : null;
                                    errorTopic = topicText.isEmpty ? 'Pflichtfeld' : null;
                                    plannedPeriodValue = buildPlannedPeriodValue();
                                    if (plannedPeriodValue == null) {
                                      errorPlannedPeriod = 'Bitte Zeitraum vollständig angeben.';
                                    } else {
                                      errorPlannedPeriod = null;
                                    }
                                    errorFormat = selectedFormat == null ? 'Bitte Format auswählen.' : null;
                                    errorIntervalType = selectedIntervalType == null ? 'Bitte auswählen.' : null;
                                    errorIntervalValue = intervalIsRecurring && (selectedIntervalValue == null || selectedIntervalValue!.isEmpty)
                                        ? 'Bitte Intervall auswählen.'
                                        : null;
                                    errorIntervalOther = intervalIsRecurring && intervalIsOther
                                        ? (intervalOtherText.length < 2 ? 'Bitte mindestens 2 Zeichen eingeben.' : null)
                                        : null;
                                    final participants = int.tryParse(participantsText);
                                    errorParticipants = participants == null || participants <= 0
                                        ? 'Bitte eine gültige Anzahl angeben.'
                                        : null;
                                    double? plannedBudget;
                                    if (budgetText.isNotEmpty) {
                                      plannedBudget = double.tryParse(budgetText.replaceAll(',', '.'));
                                      if (plannedBudget == null || plannedBudget < 0) {
                                        errorBudget = 'Bitte gültigen Betrag eingeben.';
                                      } else {
                                        errorBudget = null;
                                      }
                                    } else {
                                      errorBudget = null;
                                    }
                                    if ([
                                      errorYear,
                                      errorContact,
                                      errorDepartment,
                                      errorDepartmentOther,
                                      errorTopic,
                                      errorPlannedPeriod,
                                      errorFormat,
                                      errorIntervalType,
                                      errorIntervalValue,
                                      errorIntervalOther,
                                      errorParticipants,
                                      errorBudget,
                                    ].any((entry) => entry != null)) {
                                      setState(() {});
                                      return;
                                    }

                                    final resolvedDepartment = selectedDepartmentIsOther ? departmentOtherText : selectedDepartment!;
                                    final periodValue = plannedPeriodValue!;
                                    final item = TrainingNeedItem(
                                      id: initial?.items.isNotEmpty == true ? initial!.items.first.id : '',
                                      topic: topicText,
                                      timeframe: buildPlannedPeriodLabel(periodValue),
                                      format: trainingFormats[selectedFormat] ?? '',
                                      participants: participants ?? 0,
                                      budget: plannedBudget ?? 0,
                                      requirements: '',
                                    );
                                    final need = TrainingNeed(
                                      id: initial?.id ?? '',
                                      year: int.tryParse(yearText) ?? DateTime.now().year,
                                      contactName: contactText,
                                      position: '',
                                      department: resolvedDepartment,
                                      team: '',
                                      items: [item],
                                      comments: controllerComments.text.trim(),
                                      departmentTeamSelected: selectedDepartment!,
                                      departmentTeamFreeText: selectedDepartmentIsOther ? departmentOtherText : null,
                                      plannedPeriodType: plannedPeriodType,
                                      plannedPeriodValue: periodValue,
                                      trainingFormat: selectedFormat ?? '',
                                      intervalType: selectedIntervalType ?? '',
                                      intervalValue: intervalIsRecurring ? selectedIntervalValue : null,
                                      intervalValueFreeText: intervalIsRecurring && intervalIsOther ? intervalOtherText : null,
                                      plannedBudget: plannedBudget,
                                      additionalNotes: controllerComments.text.trim().isEmpty
                                          ? null
                                          : controllerComments.text.trim(),
                                      topicPriorities: controllerTopicPriorities.text.trim().isEmpty
                                          ? null
                                          : controllerTopicPriorities.text.trim(),
                                      preferredTrainers: controllerPreferredTrainers.text.trim().isEmpty
                                          ? null
                                          : controllerPreferredTrainers.text.trim(),
                                      specialRequirements: controllerSpecialRequirements.text.trim().isEmpty
                                          ? null
                                          : controllerSpecialRequirements.text.trim(),
                                      status: initial?.status ?? 'draft',
                                      noNeed: false,
                                      recurrenceActive: recurrenceActive,
                                      updatedAt: initial?.updatedAt,
                                    );
                                    Navigator.of(context).pop(need);
                                  }
                                : null,
                            child: Text(initial == null ? 'Absenden' : 'Speichern'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Hiermit bestätige ich, dass auf Grundlage der oben genannten Angaben ein Schulungsbedarf '
                          'für das Schulungsjahr ${controllerYear.text.trim().isEmpty ? 'JJJJ' : controllerYear.text.trim()} '
                          'in unserer Abteilung besteht. Die relevanten Themen, Zielgruppen, Zeiträume und Formate '
                          'wurden erfasst und dienen einer zielgerichteten und bedarfsgerechten Schulungsplanung.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            );
          },
        );
      },
    );
    return result;
  }

  Future<void> _createNeed() async {
    final result = await _openNeedDialog();
    if (result == null) return;
    try {
      final saved = await widget.api.adminCreateTrainingNeed(result);
      setState(() => _needs = [..._needs, saved.need]);
      if (saved.warning != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(saved.warning!)),
        );
      }
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $err')));
    }
  }

  Future<void> _editNeed(TrainingNeed need) async {
    final result = await _openNeedDialog(initial: need);
    if (result == null) return;
    try {
      final saved = await widget.api.adminUpdateTrainingNeed(result);
      setState(() {
        _needs = _needs.map((entry) => entry.id == saved.id ? saved : entry).toList();
      });
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aktualisieren fehlgeschlagen: $err')));
    }
  }

  Future<TrainingProgram?> _openProgramDialog({TrainingProgram? initial}) async {
    if (!widget.canWrite) return null;
    final controllerYear = TextEditingController(text: (initial?.year ?? _programYearFilter).toString());
    final controllerTitle = TextEditingController(text: initial?.title ?? '');
    final controllerTargetGroup = TextEditingController(text: initial?.targetGroup ?? '');
    final controllerDepartmentOther = TextEditingController();
    final controllerResponsible = TextEditingController(text: initial?.responsiblePerson ?? '');
    final controllerParticipants = TextEditingController(text: initial?.participantsPlanned ?? '');
    final controllerTrainer = TextEditingController(text: initial?.trainerProvider ?? '');
    final controllerLocation = TextEditingController(text: initial?.location ?? '');
    final controllerDuration = TextEditingController(text: initial?.duration ?? '');
    final controllerNotes = TextEditingController(text: initial?.notes ?? '');
    final controllerCancellationReason = TextEditingController(text: initial?.cancellationReason ?? '');
    final controllerPlannedDate = TextEditingController();

    const departmentOptions = [
      'Gesamte Organisation',
      'Gesamte Produktion',
      'Produktion 1',
      'Produktion 2',
      'Abt. Schleiferei',
      'Abt. Chemie / Logistik',
      'Abt. Sinterei',
      'Abt. Bürstenproduktion',
      'Abt. Sonderwerkzeuge',
      'Abt. Galvanik',
      'Abt. Galvanik Vor-/Nachbereitung',
      'Abt. Dreherei',
      'Abt. Werkzeugbau',
      'Versand',
      'Vertrieb',
      'Einkauf',
      'Geschäftsleitung',
      'Human Ressources / Personal',
      'Finanzen',
      'Sonstiges...',
    ];
    const plannedPeriodTypes = ['date', 'month', 'quarter', 'halfYear'];
    const trainingFormats = {'praesenz': 'Präsenz', 'online': 'Online'};
    const statusOptions = {
      'planned': 'Geplant',
      'inProgress': 'In Arbeit',
      'completed': 'Abgeschlossen',
      'cancelled': 'Abgesagt',
      'notOccurred': 'Nicht erfolgt',
      'removed': 'Entfernt',
      'abgebrochen': 'Abgebrochen',
    };

    String? selectedDepartment =
        initial?.department.isNotEmpty == true ? initial!.department : departmentOptions.first;
    if (selectedDepartment != null && !departmentOptions.contains(selectedDepartment)) {
      controllerDepartmentOther.text = selectedDepartment!;
      selectedDepartment = 'Sonstiges...';
    }
    String plannedPeriodType =
        initial?.plannedPeriodType.isNotEmpty == true ? initial!.plannedPeriodType : plannedPeriodTypes.first;
    String? selectedMonth;
    String? selectedQuarter;
    String? selectedHalfYear;
    DateTime? selectedPlannedDate;
    String? plannedPeriodValue = initial?.plannedPeriodValue;
    String? selectedFormat = initial?.format.isNotEmpty == true ? initial!.format : null;
    String selectedStatus = initial?.status.isNotEmpty == true ? initial!.status : 'planned';

    final hasExecutions = initial != null && _trainings.any((t) => t.linkedProgramId == initial.id);

    String? errorYear;
    String? errorTitle;
    String? errorDepartment;
    String? errorTargetGroup;
    String? errorPlannedPeriod;
    String? errorFormat;
    String? errorResponsible;
    String? errorParticipants;
    String? errorStatus;
    String? errorCancellationReason;

    String formatDate(DateTime date) {
      final y = date.year.toString().padLeft(4, '0');
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    String? buildPlannedPeriodValue() {
      final trainingYear = int.tryParse(controllerYear.text.trim());
      if (trainingYear == null) return null;
      final yearText = trainingYear.toString().padLeft(4, '0');
      if (plannedPeriodType == 'date') {
        if (selectedPlannedDate == null) return null;
        final forcedDate = DateTime(trainingYear, selectedPlannedDate!.month, selectedPlannedDate!.day);
        return formatDate(forcedDate);
      }
      if (plannedPeriodType == 'month') {
        if (selectedMonth == null) return null;
        return '$yearText-$selectedMonth';
      }
      if (plannedPeriodType == 'quarter') {
        if (selectedQuarter == null) return null;
        return '$yearText-$selectedQuarter';
      }
      if (selectedHalfYear == null) return null;
      return '$yearText-$selectedHalfYear';
    }

    void syncPlannedPeriodValue() {
      plannedPeriodValue = buildPlannedPeriodValue();
      if (plannedPeriodValue != null) {
        errorPlannedPeriod = null;
      }
    }

    if (plannedPeriodValue != null) {
      if (plannedPeriodType == 'date' && plannedPeriodValue!.length >= 10) {
        controllerPlannedDate.text = plannedPeriodValue!;
        selectedPlannedDate = DateTime.tryParse(plannedPeriodValue!);
      } else if (plannedPeriodType == 'month') {
        selectedMonth = plannedPeriodValue!.split('-').last;
      } else if (plannedPeriodType == 'quarter') {
        selectedQuarter = plannedPeriodValue!.split('-').last;
      } else if (plannedPeriodType == 'halfYear') {
        selectedHalfYear = plannedPeriodValue!.split('-').last;
      }
    }

    final result = await showDialog<TrainingProgram>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final selectedDepartmentIsOther = selectedDepartment == 'Sonstiges...';
            final statusNeedsReason = ['cancelled', 'notOccurred', 'removed', 'abgebrochen'].contains(selectedStatus);
            return AlertDialog(
              title: Text(initial == null ? 'Neue geplante Schulung' : 'Geplante Schulung bearbeiten'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controllerYear,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(labelText: 'Programmjahr', errorText: errorYear),
                        onChanged: (_) => setState(syncPlannedPeriodValue),
                      ),
                      TextField(
                        controller: controllerTitle,
                        decoration: InputDecoration(labelText: 'Thema', errorText: errorTitle),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedDepartment,
                        items: departmentOptions
                            .map((entry) => DropdownMenuItem(value: entry, child: Text(entry)))
                            .toList(),
                        onChanged: (value) => setState(() => selectedDepartment = value),
                        decoration: InputDecoration(labelText: 'Abteilung/Team', errorText: errorDepartment),
                      ),
                      if (selectedDepartmentIsOther)
                        TextField(
                          controller: controllerDepartmentOther,
                          decoration: const InputDecoration(labelText: 'Abteilung/Team (Sonstiges)'),
                          onChanged: (_) => setState(() {}),
                        ),
                      TextField(
                        controller: controllerTargetGroup,
                        decoration: InputDecoration(labelText: 'Zielgruppe', errorText: errorTargetGroup),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Geplanter Zeitraum', style: Theme.of(context).textTheme.titleSmall),
                      ),
                      Wrap(
                        spacing: 8,
                        children: plannedPeriodTypes.map((type) {
                          final label = {
                            'date': 'Datum',
                            'month': 'Monat',
                            'quarter': 'Quartal',
                            'halfYear': 'Halbjahr',
                          }[type];
                          return ChoiceChip(
                            label: Text(label ?? type),
                            selected: plannedPeriodType == type,
                            onSelected: (_) => setState(() {
                              plannedPeriodType = type;
                              syncPlannedPeriodValue();
                            }),
                          );
                        }).toList(),
                      ),
                      if (plannedPeriodType == 'date')
                        TextField(
                          controller: controllerPlannedDate,
                          decoration: InputDecoration(labelText: 'Datum (YYYY-MM-DD)', errorText: errorPlannedPeriod),
                          onChanged: (value) => setState(() {
                            selectedPlannedDate = DateTime.tryParse(value);
                            syncPlannedPeriodValue();
                          }),
                        ),
                      if (plannedPeriodType == 'month')
                        DropdownButtonFormField<String>(
                          value: selectedMonth,
                          items: List.generate(12, (index) => (index + 1).toString().padLeft(2, '0'))
                              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (value) => setState(() {
                            selectedMonth = value;
                            syncPlannedPeriodValue();
                          }),
                          decoration: InputDecoration(labelText: 'Monat', errorText: errorPlannedPeriod),
                        ),
                      if (plannedPeriodType == 'quarter')
                        DropdownButtonFormField<String>(
                          value: selectedQuarter,
                          items: const ['Q1', 'Q2', 'Q3', 'Q4']
                              .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                              .toList(),
                          onChanged: (value) => setState(() {
                            selectedQuarter = value;
                            syncPlannedPeriodValue();
                          }),
                          decoration: InputDecoration(labelText: 'Quartal', errorText: errorPlannedPeriod),
                        ),
                      if (plannedPeriodType == 'halfYear')
                        DropdownButtonFormField<String>(
                          value: selectedHalfYear,
                          items: const ['H1', 'H2']
                              .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                              .toList(),
                          onChanged: (value) => setState(() {
                            selectedHalfYear = value;
                            syncPlannedPeriodValue();
                          }),
                          decoration: InputDecoration(labelText: 'Halbjahr', errorText: errorPlannedPeriod),
                        ),
                      DropdownButtonFormField<String>(
                        value: selectedFormat,
                        items: trainingFormats.entries
                            .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                            .toList(),
                        onChanged: (value) => setState(() => selectedFormat = value),
                        decoration: InputDecoration(labelText: 'Format', errorText: errorFormat),
                      ),
                      TextField(
                        controller: controllerResponsible,
                        decoration: InputDecoration(labelText: 'Verantwortlich', errorText: errorResponsible),
                      ),
                      TextField(
                        controller: controllerParticipants,
                        decoration: InputDecoration(labelText: 'Teilnehmer (geplant)', errorText: errorParticipants),
                      ),
                      DropdownButtonFormField<String>(
                        value: selectedStatus,
                        items: statusOptions.entries
                            .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                            .toList(),
                        onChanged: (value) => setState(() => selectedStatus = value ?? 'planned'),
                        decoration: InputDecoration(labelText: 'Status', errorText: errorStatus),
                      ),
                      if (!hasExecutions && selectedStatus == 'completed')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Hinweis: Für den Status "Abgeschlossen" muss mindestens eine Durchführung erfasst sein.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange.shade300),
                          ),
                        ),
                      if (statusNeedsReason)
                        TextField(
                          controller: controllerCancellationReason,
                          decoration: InputDecoration(
                            labelText: 'Begründung (Pflichtfeld bei Abbruch/Nicht erfolgt)',
                            errorText: errorCancellationReason,
                          ),
                        ),
                      TextField(
                        controller: controllerTrainer,
                        decoration: const InputDecoration(labelText: 'Trainer/Anbieter (optional)'),
                      ),
                      TextField(
                        controller: controllerLocation,
                        decoration: const InputDecoration(labelText: 'Ort/Meeting-Link (optional)'),
                      ),
                      TextField(
                        controller: controllerDuration,
                        decoration: const InputDecoration(labelText: 'Dauer (optional)'),
                      ),
                      TextField(
                        controller: controllerNotes,
                        decoration: const InputDecoration(labelText: 'Notizen (optional)'),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () {
                    errorYear =
                        controllerYear.text.trim().length == 4 ? null : 'Bitte gültiges Jahr eingeben.';
                    errorTitle = controllerTitle.text.trim().isEmpty ? 'Pflichtfeld' : null;
                    errorDepartment = (selectedDepartment == null || selectedDepartment!.isEmpty) ? 'Pflichtfeld' : null;
                    if (selectedDepartment == 'Sonstiges...' && controllerDepartmentOther.text.trim().length < 2) {
                      errorDepartment = 'Bitte Abteilung/Team angeben.';
                    }
                    errorTargetGroup = controllerTargetGroup.text.trim().isEmpty ? 'Pflichtfeld' : null;
                    plannedPeriodValue = buildPlannedPeriodValue();
                    errorPlannedPeriod = plannedPeriodValue == null ? 'Bitte Zeitraum auswählen.' : null;
                    errorFormat = selectedFormat == null ? 'Bitte Format auswählen.' : null;
                    errorResponsible = controllerResponsible.text.trim().isEmpty ? 'Pflichtfeld' : null;
                    errorParticipants = controllerParticipants.text.trim().isEmpty ? 'Pflichtfeld' : null;
                    errorStatus = selectedStatus.isEmpty ? 'Pflichtfeld' : null;
                    errorCancellationReason = statusNeedsReason &&
                            controllerCancellationReason.text.trim().length < 5
                        ? 'Mindestens 5 Zeichen erforderlich.'
                        : null;
                    if (!hasExecutions && selectedStatus == 'completed') {
                      errorStatus = 'Mind. eine Durchführung erforderlich.';
                    }
                    if ([
                      errorYear,
                      errorTitle,
                      errorDepartment,
                      errorTargetGroup,
                      errorPlannedPeriod,
                      errorFormat,
                      errorResponsible,
                      errorParticipants,
                      errorStatus,
                      errorCancellationReason,
                    ].any((entry) => entry != null)) {
                      setState(() {});
                      return;
                    }

                    final resolvedDepartment =
                        selectedDepartment == 'Sonstiges...' ? controllerDepartmentOther.text.trim() : selectedDepartment ?? '';
                    final program = TrainingProgram(
                      id: initial?.id ?? '',
                      year: int.tryParse(controllerYear.text.trim()) ?? DateTime.now().year,
                      title: controllerTitle.text.trim(),
                      status: selectedStatus,
                      owner: controllerResponsible.text.trim(),
                      department: resolvedDepartment,
                      targetGroup: controllerTargetGroup.text.trim(),
                      plannedPeriodType: plannedPeriodType,
                      plannedPeriodValue: plannedPeriodValue!,
                      format: selectedFormat ?? '',
                      responsiblePerson: controllerResponsible.text.trim(),
                      participantsPlanned: controllerParticipants.text.trim(),
                      trainerProvider: controllerTrainer.text.trim(),
                      location: controllerLocation.text.trim(),
                      duration: controllerDuration.text.trim(),
                      notes: controllerNotes.text.trim(),
                      cancellationReason: statusNeedsReason ? controllerCancellationReason.text.trim() : null,
                      needIds: initial?.needIds ?? const [],
                      trainingIds: initial?.trainingIds ?? const [],
                      budgetTotal: initial?.budgetTotal ?? 0,
                      updatedAt: initial?.updatedAt,
                    );
                    Navigator.of(context).pop(program);
                  },
                  child: Text(initial == null ? 'Speichern' : 'Aktualisieren'),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  Future<void> _createProgram() async {
    final result = await _openProgramDialog();
    if (result == null) return;
    try {
      final saved = await widget.api.adminCreateTrainingProgram(result);
      setState(() => _programs = [..._programs, saved]);
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $err')));
    }
  }

  Future<void> _editProgram(TrainingProgram program) async {
    final result = await _openProgramDialog(initial: program);
    if (result == null) return;
    try {
      final saved = await widget.api.adminUpdateTrainingProgram(result);
      setState(() => _programs = _programs.map((entry) => entry.id == saved.id ? saved : entry).toList());
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aktualisieren fehlgeschlagen: $err')));
    }
  }

  Future<TrainingParticipant?> _openExternalParticipantDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final result = await showDialog<TrainingParticipant>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Externe Teilnehmer hinzufügen'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: emailController, decoration: const InputDecoration(labelText: 'E-Mail (optional)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final email = emailController.text.trim();
                final userId = email.isNotEmpty ? email : name;
                final participant = TrainingParticipant(
                  id: '',
                  userId: userId,
                  name: name,
                  email: email,
                  status: 'invited',
                  external: true,
                );
                Navigator.of(context).pop(participant);
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<List<TrainingParticipant>?> _openParticipantsDialog({
    required List<TrainingParticipant> initial,
  }) async {
    final selected = <String, TrainingParticipant>{
      for (final p in initial)
        (p.userId.isNotEmpty ? p.userId : (p.email.isNotEmpty ? p.email : p.name)): p,
    };
    final searchController = TextEditingController();
    return showDialog<List<TrainingParticipant>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchController.text.trim().toLowerCase();
            final filtered = _staffUsers.where((user) {
              final label = user.label.toLowerCase();
              return query.isEmpty || label.contains(query) || user.email.toLowerCase().contains(query);
            }).toList();
            return AlertDialog(
              title: const Text('Teilnehmer auswählen'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(labelText: 'Suche'),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 300,
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final user = filtered[index];
                          final key = user.email;
                          final isSelected = selected.containsKey(key);
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(user.label),
                            subtitle: Text(user.email),
                            onChanged: (value) {
                              setModalState(() {
                                if (value == true) {
                                  selected[key] = TrainingParticipant(
                                    id: selected[key]?.id ?? '',
                                    userId: user.email,
                                    name: user.label,
                                    email: user.email,
                                    status: selected[key]?.status ?? 'invited',
                                    external: false,
                                    departmentTeam: user.assignedDepartments.isNotEmpty
                                        ? user.assignedDepartments.first
                                        : null,
                                  );
                                } else {
                                  selected.remove(key);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final external = await _openExternalParticipantDialog();
                    if (external == null) return;
                    setModalState(() {
                      final key = external.userId.isNotEmpty ? external.userId : external.name;
                      selected[key] = external;
                    });
                  },
                  child: const Text('Extern hinzufügen'),
                ),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(selected.values.toList()),
                  child: const Text('Übernehmen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _openSignatureDialog({required String participantName}) async {
    final controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black87,
      exportBackgroundColor: Colors.white,
    );
    bool confirmed = false;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text('Unterschrift von $participantName'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Signature(controller: controller, backgroundColor: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: confirmed,
                      title: const Text('Ich bestätige die Teilnahme an der Schulung.'),
                      onChanged: (value) => setModalState(() => confirmed = value ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    controller.clear();
                    setModalState(() {});
                  },
                  child: const Text('Löschen'),
                ),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: confirmed && controller.isNotEmpty
                      ? () async {
                          final data = await controller.toPngBytes();
                          if (data == null) return;
                          final base64 = base64Encode(data);
                          Navigator.of(context).pop(base64);
                        }
                      : null,
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<TrainingRecord?> _openTrainingDialog({TrainingRecord? initial}) async {
    if (!widget.canWrite) return null;
    final controllerTitle = TextEditingController(text: initial?.title ?? '');
    final controllerCategoryFree = TextEditingController(text: initial?.categoryFreeText ?? '');
    final controllerDate = TextEditingController(text: initial?.startDate ?? '');
    final controllerStartTime = TextEditingController(text: initial?.startTime ?? '');
    final controllerEndTime = TextEditingController(text: initial?.endTime ?? '');
    final controllerTrainerInternal = TextEditingController(
      text: initial?.trainerInternal ?? (initial?.type == 'intern' ? initial?.trainer ?? '' : ''),
    );
    final controllerProviderCompany = TextEditingController(
      text: initial?.providerCompany ?? (initial?.type == 'extern' ? initial?.trainer ?? '' : ''),
    );
    final controllerLocationFree = TextEditingController();
    final controllerMeetingLink = TextEditingController(
      text: initial?.meetingLink ?? (initial?.format == 'online' ? initial?.location ?? '' : ''),
    );
    final controllerNotes = TextEditingController(text: initial?.notes ?? '');
    final existingCategory = initial?.category ?? '';
    String? selectedCategory = existingCategory.isEmpty
        ? null
        : _trainingCategoryOptions.any((entry) => entry['value'] == existingCategory)
            ? existingCategory
            : 'other';
    if (selectedCategory == 'other' && controllerCategoryFree.text.trim().isEmpty && existingCategory.isNotEmpty) {
      controllerCategoryFree.text = existingCategory;
    }
    String? selectedType = ['intern', 'extern'].contains(initial?.type)
        ? initial?.type
        : initial?.isExternal == true
            ? 'extern'
            : null;
    String? selectedFormat =
        _trainingFormatOptions.any((entry) => entry['value'] == initial?.format) ? initial?.format : null;
    String? selectedLocation = null;
    if (selectedFormat == 'praesenz') {
      final location = initial?.location ?? '';
      if (location.isNotEmpty && _trainingLocationOptions.contains(location)) {
        selectedLocation = location;
      } else if (location.isNotEmpty) {
        selectedLocation = 'other';
        controllerLocationFree.text = location;
      }
    }
    String? selectedPlatform =
        _meetingPlatforms.any((entry) => entry['value'] == initial?.platform) ? initial?.platform : null;
    String selectedOwnerId = initial?.ownerUserId ?? initial?.owner ?? _currentUserEmail;
    List<TrainingParticipant> selectedParticipants =
        List<TrainingParticipant>.from(initial?.participants ?? const []);

    Map<String, String> validateForm() {
      final errors = <String, String>{};
      final title = controllerTitle.text.trim();
      if (title.isEmpty) errors['title'] = 'Titel ist erforderlich.';

      if (selectedCategory == null || selectedCategory!.isEmpty) {
        errors['category'] = 'Bitte Kategorie auswählen.';
      } else if (selectedCategory == 'other' && controllerCategoryFree.text.trim().isEmpty) {
        errors['categoryFreeText'] = 'Bitte Kategorie (frei) angeben.';
      }

      if (selectedType == null || selectedType!.isEmpty) {
        errors['type'] = 'Bitte Typ auswählen.';
      } else if (selectedType == 'intern' && controllerTrainerInternal.text.trim().isEmpty) {
        errors['trainerInternal'] = 'Bitte Trainer (intern) angeben.';
      } else if (selectedType == 'extern' && controllerProviderCompany.text.trim().isEmpty) {
        errors['providerCompany'] = 'Bitte Anbieter/Firma angeben.';
      }

      if (selectedFormat == null || selectedFormat!.isEmpty) {
        errors['format'] = 'Bitte Format auswählen.';
      }

      final dateValue = controllerDate.text.trim();
      if (!RegExp(r'^\\d{4}-\\d{2}-\\d{2}\$').hasMatch(dateValue)) {
        errors['startDate'] = 'Bitte gültiges Datum auswählen.';
      }

      final startTime = controllerStartTime.text.trim();
      final endTime = controllerEndTime.text.trim();
      if (startTime.isNotEmpty || endTime.isNotEmpty) {
        if (startTime.isEmpty || endTime.isEmpty) {
          errors['time'] = 'Bitte Start- und Endzeit angeben.';
        } else if (!RegExp(r'^\\d{2}:\\d{2}\$').hasMatch(startTime) ||
            !RegExp(r'^\\d{2}:\\d{2}\$').hasMatch(endTime)) {
          errors['time'] = 'Bitte gültige Uhrzeit angeben.';
        } else {
          final startParts = startTime.split(':').map(int.parse).toList();
          final endParts = endTime.split(':').map(int.parse).toList();
          final startMinutes = startParts[0] * 60 + startParts[1];
          final endMinutes = endParts[0] * 60 + endParts[1];
          if (endMinutes <= startMinutes) {
            errors['time'] = 'Ende muss nach Start liegen.';
          }
        }
      }

      if (selectedFormat == 'praesenz') {
        if (selectedLocation == null || selectedLocation!.isEmpty) {
          errors['location'] = 'Bitte Ort auswählen.';
        } else if (selectedLocation == 'other' && controllerLocationFree.text.trim().isEmpty) {
          errors['location'] = 'Bitte Ort angeben.';
        }
      } else if (selectedFormat == 'online') {
        final link = controllerMeetingLink.text.trim();
        if (link.isEmpty) {
          errors['meetingLink'] = 'Bitte Meeting-Link angeben.';
        } else {
          final uri = Uri.tryParse(link);
          if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
            errors['meetingLink'] = 'Bitte gültige URL angeben.';
          }
        }
      }

      if (selectedOwnerId.trim().isEmpty) {
        errors['owner'] = 'Owner ist erforderlich.';
      }

      if (selectedParticipants.isEmpty) {
        errors['participants'] = 'Mindestens 1 Teilnehmer erforderlich.';
      }

      return errors;
    }

    var errors = validateForm();
    var isFormValid = errors.isEmpty;
    final result = await showDialog<TrainingRecord>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void refreshValidation() {
              errors = validateForm();
              isFormValid = errors.isEmpty;
              setModalState(() {});
            }

            Future<void> pickDate() async {
              final initialDate = DateTime.tryParse(controllerDate.text.trim()) ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: initialDate,
                firstDate: DateTime(DateTime.now().year - 5),
                lastDate: DateTime(DateTime.now().year + 5),
              );
              if (picked != null) {
                controllerDate.text = picked.toIso8601String().split('T').first;
                refreshValidation();
              }
            }

            Future<void> pickTime(TextEditingController controller) async {
              TimeOfDay initialTime = TimeOfDay.now();
              final text = controller.text.trim();
              if (RegExp(r'^\\d{2}:\\d{2}\$').hasMatch(text)) {
                final parts = text.split(':').map(int.parse).toList();
                initialTime = TimeOfDay(hour: parts[0], minute: parts[1]);
              }
              final picked = await showTimePicker(context: context, initialTime: initialTime);
              if (picked != null) {
                final formatted =
                    picked.hour.toString().padLeft(2, '0') + ':' + picked.minute.toString().padLeft(2, '0');
                controller.text = formatted;
                refreshValidation();
              }
            }

            final theme = Theme.of(context);
            final ownerLabel = _staffByEmail(selectedOwnerId)?.label ?? selectedOwnerId;
            return AlertDialog(
              title: Text(initial == null ? 'Neue Schulung' : 'Schulung bearbeiten'),
              content: SizedBox(
                width: 620,
                height: 600,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Grunddaten', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            TextField(
                              controller: controllerTitle,
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: 'Titel',
                                hintText: 'z.B. MDR / Reklamationsprozess',
                                errorText: errors['title'],
                              ),
                              onChanged: (_) => refreshValidation(),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: selectedCategory,
                              decoration: InputDecoration(
                                labelText: 'Kategorie',
                                errorText: errors['category'],
                              ),
                              items: _trainingCategoryOptions
                                  .map(
                                    (entry) => DropdownMenuItem(
                                      value: entry['value'],
                                      child: Text(entry['label'] ?? ''),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                selectedCategory = value;
                                refreshValidation();
                              },
                            ),
                            if (selectedCategory == 'other') ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: controllerCategoryFree,
                                decoration: InputDecoration(
                                  labelText: 'Kategorie (frei)',
                                  errorText: errors['categoryFreeText'],
                                ),
                                onChanged: (_) => refreshValidation(),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text('Typ', style: theme.textTheme.labelMedium),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: _trainingTypeOptions.map((entry) {
                                final value = entry['value'];
                                return ChoiceChip(
                                  label: Text(entry['label'] ?? ''),
                                  selected: selectedType == value,
                                  onSelected: (_) {
                                    selectedType = value;
                                    if (value == 'intern') {
                                      controllerProviderCompany.clear();
                                    }
                                    if (value == 'extern') {
                                      controllerTrainerInternal.clear();
                                    }
                                    refreshValidation();
                                  },
                                );
                              }).toList(),
                            ),
                            if (errors['type'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(errors['type']!, style: TextStyle(color: theme.colorScheme.error)),
                              ),
                            const SizedBox(height: 12),
                            Text('Format', style: theme.textTheme.labelMedium),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: _trainingFormatOptions.map((entry) {
                                final value = entry['value'];
                                return ChoiceChip(
                                  label: Text(entry['label'] ?? ''),
                                  selected: selectedFormat == value,
                                  onSelected: (_) {
                                    selectedFormat = value;
                                    if (value == 'online') {
                                      selectedLocation = null;
                                      controllerLocationFree.clear();
                                    }
                                    if (value == 'praesenz') {
                                      controllerMeetingLink.clear();
                                      selectedPlatform = null;
                                    }
                                    refreshValidation();
                                  },
                                );
                              }).toList(),
                            ),
                            if (errors['format'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(errors['format']!, style: TextStyle(color: theme.colorScheme.error)),
                              ),
                            const SizedBox(height: 20),
                            Text('Termin & Durchführung', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            TextField(
                              controller: controllerDate,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Datum',
                                suffixIcon: const Icon(Icons.calendar_today_outlined),
                                errorText: errors['startDate'],
                              ),
                              onTap: pickDate,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: controllerStartTime,
                                    readOnly: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Start (optional)',
                                      suffixIcon: Icon(Icons.schedule),
                                    ),
                                    onTap: () => pickTime(controllerStartTime),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: controllerEndTime,
                                    readOnly: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Ende (optional)',
                                      suffixIcon: Icon(Icons.schedule),
                                    ),
                                    onTap: () => pickTime(controllerEndTime),
                                  ),
                                ),
                              ],
                            ),
                            if (errors['time'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(errors['time']!, style: TextStyle(color: theme.colorScheme.error)),
                              ),
                            const SizedBox(height: 12),
                            if (selectedFormat == 'praesenz') ...[
                              DropdownButtonFormField<String>(
                                value: selectedLocation,
                                decoration: InputDecoration(
                                  labelText: 'Ort',
                                  errorText: errors['location'],
                                ),
                                items: [
                                  ..._trainingLocationOptions.map(
                                    (entry) => DropdownMenuItem(
                                      value: entry,
                                      child: Text(entry),
                                    ),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'other',
                                    child: Text('Sonstiges...'),
                                  ),
                                ],
                                onChanged: (value) {
                                  selectedLocation = value;
                                  refreshValidation();
                                },
                              ),
                              if (selectedLocation == 'other') ...[
                                const SizedBox(height: 8),
                                TextField(
                                  controller: controllerLocationFree,
                                  decoration: InputDecoration(
                                    labelText: 'Ort (frei)',
                                    errorText: errors['location'],
                                  ),
                                  onChanged: (_) => refreshValidation(),
                                ),
                              ],
                            ],
                            if (selectedFormat == 'online') ...[
                              TextField(
                                controller: controllerMeetingLink,
                                decoration: InputDecoration(
                                  labelText: 'Meeting-Link',
                                  hintText: 'https://…',
                                  errorText: errors['meetingLink'],
                                ),
                                onChanged: (_) => refreshValidation(),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: selectedPlatform,
                                decoration: const InputDecoration(labelText: 'Plattform (optional)'),
                                items: _meetingPlatforms
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry['value'],
                                        child: Text(entry['label'] ?? ''),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  selectedPlatform = value;
                                  refreshValidation();
                                },
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (selectedType == 'intern') ...[
                              TextField(
                                controller: controllerTrainerInternal,
                                decoration: InputDecoration(
                                  labelText: 'Trainer (intern)',
                                  hintText: 'Name',
                                  errorText: errors['trainerInternal'],
                                ),
                                onChanged: (_) => refreshValidation(),
                              ),
                            ],
                            if (selectedType == 'extern') ...[
                              TextField(
                                controller: controllerProviderCompany,
                                decoration: InputDecoration(
                                  labelText: 'Anbieter/Firma',
                                  hintText: 'Name',
                                  errorText: errors['providerCompany'],
                                ),
                                onChanged: (_) => refreshValidation(),
                              ),
                            ],
                            const SizedBox(height: 20),
                            Text('Organisation', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            if (_isAdminUser)
                              DropdownButtonFormField<String>(
                                value: selectedOwnerId.isEmpty ? null : selectedOwnerId,
                                decoration: InputDecoration(
                                  labelText: 'Owner',
                                  errorText: errors['owner'],
                                ),
                                items: _staffUsers
                                    .map(
                                      (user) => DropdownMenuItem(
                                        value: user.email,
                                        child: Text(user.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  selectedOwnerId = value ?? '';
                                  refreshValidation();
                                },
                              )
                            else
                              InputDecorator(
                                decoration: const InputDecoration(labelText: 'Owner'),
                                child: Text(ownerLabel.isEmpty ? '—' : ownerLabel),
                              ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Teilnehmer', style: theme.textTheme.titleSmall),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: selectedParticipants.isEmpty
                                  ? [const Text('Noch keine Teilnehmer ausgewählt.')]
                                  : selectedParticipants.map((participant) {
                                      return InputChip(
                                        label: Text(participant.name),
                                        onDeleted: () {
                                          selectedParticipants = selectedParticipants
                                              .where((entry) =>
                                                  entry.id != participant.id && entry.userId != participant.userId)
                                              .toList();
                                          refreshValidation();
                                        },
                                      );
                                    }).toList(),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mindestens 1 Teilnehmer erforderlich.',
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                            ),
                            if (errors['participants'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(errors['participants']!, style: TextStyle(color: theme.colorScheme.error)),
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final updated = await _openParticipantsDialog(initial: selectedParticipants);
                                  if (updated == null) return;
                                  setModalState(() => selectedParticipants = updated);
                                  refreshValidation();
                                },
                                icon: const Icon(Icons.group_add_outlined),
                                label: const Text('Teilnehmer auswählen'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('Zusatz', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            TextField(
                              controller: controllerNotes,
                              maxLines: 4,
                              decoration: const InputDecoration(labelText: 'Notizen / Agenda (optional)'),
                            ),
                            if (initial != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'Status: ${_trainingStatusLabel(initial.status)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: isFormValid
                      ? () {
                          final categoryValue = selectedCategory ?? '';
                          final trainerInternal = controllerTrainerInternal.text.trim();
                          final providerCompany = controllerProviderCompany.text.trim();
                          final meetingLink = controllerMeetingLink.text.trim();
                          final locationValue = selectedFormat == 'praesenz'
                              ? (selectedLocation == 'other'
                                  ? controllerLocationFree.text.trim()
                                  : (selectedLocation ?? '').trim())
                              : '';
                          final ownerLabelValue = _staffByEmail(selectedOwnerId)?.label ?? selectedOwnerId;
                          final startTimeValue = controllerStartTime.text.trim();
                          final endTimeValue = controllerEndTime.text.trim();
                          final record = TrainingRecord(
                            id: initial?.id ?? '',
                            trainingNumber: initial?.trainingNumber ?? '',
                            year: initial?.year ?? DateTime.now().year,
                            title: controllerTitle.text.trim(),
                            category: categoryValue,
                            categoryFreeText: categoryValue == 'other' ? controllerCategoryFree.text.trim() : null,
                            type: selectedType ?? '',
                            format: selectedFormat ?? '',
                            startDate: controllerDate.text.trim(),
                            startTime: startTimeValue.isEmpty ? null : startTimeValue,
                            endTime: endTimeValue.isEmpty ? null : endTimeValue,
                            endDate: '',
                            trainer: selectedType == 'extern' ? providerCompany : trainerInternal,
                            trainerInternal: trainerInternal.isEmpty ? null : trainerInternal,
                            providerCompany: providerCompany.isEmpty ? null : providerCompany,
                            location: locationValue,
                            meetingLink: selectedFormat == 'online' ? meetingLink : null,
                            platform: selectedFormat == 'online' ? selectedPlatform : null,
                            status: initial?.status ?? 'planned',
                            owner: ownerLabelValue,
                            ownerUserId: selectedOwnerId,
                            targetGroup: '',
                            reason: '',
                            departments: const [],
                            isMandatory: false,
                            isExternal: selectedType == 'extern',
                            participants: selectedParticipants,
                            defaultQuestionnaireTemplateId: _templates.isNotEmpty ? _templates.first.id : '',
                            linkedProgramId: initial?.linkedProgramId,
                            updatedAt: initial?.updatedAt,
                            completedAt: initial?.completedAt,
                            wkMethod: initial?.wkMethod,
                            wkDelayDays: initial?.wkDelayDays,
                            wkDueAt: initial?.wkDueAt,
                            wkStatus: initial?.wkStatus,
                            wkCompletedAt: initial?.wkCompletedAt,
                            wkResponsibleId: initial?.wkResponsibleId,
                            wkQuestionnaireTemplateId: initial?.wkQuestionnaireTemplateId,
                            wkTargetParticipantIds: initial?.wkTargetParticipantIds,
                            notes: controllerNotes.text.trim().isEmpty ? null : controllerNotes.text.trim(),
                          );
                          Navigator.of(context).pop(record);
                        }
                      : null,
                  child: Text(initial == null ? 'Speichern' : 'Aktualisieren'),
                ),
              ],
            );
          },
        );
      },
    );
    controllerTitle.dispose();
    controllerCategoryFree.dispose();
    controllerDate.dispose();
    controllerStartTime.dispose();
    controllerEndTime.dispose();
    controllerTrainerInternal.dispose();
    controllerProviderCompany.dispose();
    controllerLocationFree.dispose();
    controllerMeetingLink.dispose();
    controllerNotes.dispose();
    return result;
  }

  Future<void> _createTraining() async {
    final result = await _openTrainingDialog();
    if (result == null) return;
    try {
      final saved = await widget.api.adminCreateTraining(result);
      setState(() => _trainings = [..._trainings, saved]);
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $err')));
    }
  }

  void _updateTrainingRecord(TrainingRecord updated) {
    setState(() => _trainings = _trainings.map((entry) => entry.id == updated.id ? updated : entry).toList());
  }

  Future<void> _editTraining(TrainingRecord record) async {
    final result = await _openTrainingDialog(initial: record);
    if (result == null) return;
    try {
      final saved = await widget.api.adminUpdateTraining(result);
      _updateTrainingRecord(saved);
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aktualisieren fehlgeschlagen: $err')));
    }
  }

  Future<void> _openTrainingDetailDialog(TrainingRecord record) async {
    final currentUser = _currentUserEmail;
    final canManage = _isAdminUser;
    var current = record;
    final wkMethod = ValueNotifier<String>(current.wkMethod ?? '');
    final wkDelayDays = ValueNotifier<int>(current.wkDelayDays ?? 0);
    final wkResponsible = ValueNotifier<String>(current.wkResponsibleId ?? currentUser);
    final wkTemplateId = ValueNotifier<String>(current.wkQuestionnaireTemplateId ?? '');
    final wkCustomDelay = TextEditingController();
    final wkResult = TextEditingController();
    final wkNotes = TextEditingController();
    DateTime? wkPerformedAt;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final participants = current.participants;
            return AlertDialog(
              title: Text('${current.trainingNumber.isEmpty ? 'Schulung' : current.trainingNumber} · ${current.title}'),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: ${_trainingStatusLabel(current.status)}'),
                      if (current.completedAt != null)
                        Text('Durchgeführt am: ${DateTime.fromMillisecondsSinceEpoch(current.completedAt!).toLocal()}'),
                      const SizedBox(height: 12),
                      Text('Stammdaten', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text('Kategorie: ${_trainingCategoryLabel(current)}'),
                      Text('Typ/Format: ${_trainingTypeLabel(current.type)} / ${_trainingFormatLabel(current.format)}'),
                      Text('Datum: ${current.startDate}${_trainingTimeLabel(current).isNotEmpty ? ' · ${_trainingTimeLabel(current)}' : ''}'),
                      if (_trainingTrainerLabel(current).isNotEmpty)
                        Text('Trainer/Anbieter: ${_trainingTrainerLabel(current)}'),
                      if (_trainingLocationLabel(current).isNotEmpty)
                        Text('Ort/Link: ${_trainingLocationLabel(current)}'),
                      if ((current.platform ?? '').isNotEmpty) Text('Plattform: ${current.platform}'),
                      if (_trainingOwnerLabel(current).isNotEmpty) Text('Owner: ${_trainingOwnerLabel(current)}'),
                      if ((current.notes ?? '').isNotEmpty) Text('Notizen: ${current.notes}'),
                      const SizedBox(height: 12),
                      Text('Unterschriften', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      if (participants.isEmpty)
                        const Text('Noch keine Teilnehmer erfasst.')
                      else
                        ...participants.map((participant) {
                          final isSigned = participant.isSigned;
                          final canSign = (participant.userId.toLowerCase() == currentUser) || canManage;
                          final signedAt = participant.signedAt == null
                              ? null
                              : DateTime.fromMillisecondsSinceEpoch(participant.signedAt!).toLocal();
                          return Card(
                            elevation: 0,
                            color: Colors.grey.shade50,
                            child: ListTile(
                              title: Text(participant.name),
                              subtitle: Text(isSigned ? 'unterschrieben ${signedAt ?? ''}' : 'offen'),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  if (!isSigned)
                                    ElevatedButton(
                                      onPressed: canSign
                                          ? () async {
                                              final signature = await _openSignatureDialog(participantName: participant.name);
                                              if (signature == null) return;
                                              try {
                                                final updated = await widget.api.trainingSignParticipant(
                                                  trainingId: current.id,
                                                  participantId: participant.id,
                                                  signatureBase64: signature,
                                                );
                                                _updateTrainingRecord(updated);
                                                setModalState(() => current = updated);
                                                await _reloadWkReminders();
                                              } catch (err) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(content: Text('Unterschrift fehlgeschlagen: $err')));
                                              }
                                            }
                                          : null,
                                      child: const Text('Unterschreiben'),
                                    ),
                                  if (canManage)
                                    PopupMenuButton<String>(
                                      tooltip: 'Weitere Aktionen',
                                      onSelected: (value) async {
                                        if (value == 'reset') {
                                          final reasonController = TextEditingController();
                                          final reason = await showDialog<String>(
                                            context: context,
                                            builder: (context) {
                                              return AlertDialog(
                                                title: const Text('Unterschrift zurücksetzen'),
                                                content: TextField(
                                                  controller: reasonController,
                                                  decoration: const InputDecoration(labelText: 'Begründung'),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.of(context).pop(),
                                                    child: const Text('Abbrechen'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () => Navigator.of(context).pop(reasonController.text.trim()),
                                                    child: const Text('Bestätigen'),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                          if (reason == null || reason.isEmpty) return;
                                          try {
                                            final updated = await widget.api.trainingResetParticipantSignature(
                                              trainingId: current.id,
                                              participantId: participant.id,
                                              reason: reason,
                                            );
                                            _updateTrainingRecord(updated);
                                            setModalState(() => current = updated);
                                            await _reloadWkReminders();
                                          } catch (err) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(content: Text('Reset fehlgeschlagen: $err')));
                                          }
                                        }
                                        if (value == 'override') {
                                          final reasonController = TextEditingController();
                                          final reason = await showDialog<String>(
                                            context: context,
                                            builder: (context) {
                                              return AlertDialog(
                                                title: const Text('Teilnahme ohne Signatur bestätigen'),
                                                content: TextField(
                                                  controller: reasonController,
                                                  decoration: const InputDecoration(labelText: 'Begründung'),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.of(context).pop(),
                                                    child: const Text('Abbrechen'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () => Navigator.of(context).pop(reasonController.text.trim()),
                                                    child: const Text('Bestätigen'),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                          if (reason == null || reason.isEmpty) return;
                                          try {
                                            final updated = await widget.api.trainingOverrideParticipantSignature(
                                              trainingId: current.id,
                                              participantId: participant.id,
                                              reason: reason,
                                            );
                                            _updateTrainingRecord(updated);
                                            setModalState(() => current = updated);
                                            await _reloadWkReminders();
                                          } catch (err) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(content: Text('Override fehlgeschlagen: $err')));
                                          }
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(value: 'reset', child: Text('Unterschrift zurücksetzen')),
                                        const PopupMenuItem(value: 'override', child: Text('Teilnahme ohne Signatur bestätigen')),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                      Text('Wirksamkeitskontrolle', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<String>(
                        valueListenable: wkMethod,
                        builder: (context, value, _) {
                          return DropdownButtonFormField<String>(
                            value: value.isEmpty ? null : value,
                            decoration: const InputDecoration(labelText: 'WK Methode'),
                            items: const [
                              DropdownMenuItem(value: 'questionnaire', child: Text('Fragebogen (digital)')),
                              DropdownMenuItem(value: 'direct', child: Text('Direkte Messung (Befragung)')),
                              DropdownMenuItem(value: 'indirect', child: Text('Indirekte Messung (Überprüfung der Arbeitsergebnisse)')),
                            ],
                            onChanged: (method) => wkMethod.value = method ?? '',
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<int>(
                        valueListenable: wkDelayDays,
                        builder: (context, value, _) {
                          return DropdownButtonFormField<int>(
                            value: value > 0 ? value : null,
                            decoration: const InputDecoration(labelText: 'WK erforderlich nach'),
                            items: const [
                              DropdownMenuItem(value: 7, child: Text('1 Woche')),
                              DropdownMenuItem(value: 14, child: Text('2 Wochen')),
                              DropdownMenuItem(value: 30, child: Text('1 Monat')),
                              DropdownMenuItem(value: 60, child: Text('2 Monate')),
                              DropdownMenuItem(value: 90, child: Text('3 Monate')),
                              DropdownMenuItem(value: 180, child: Text('6 Monate')),
                            ],
                            onChanged: (delay) => wkDelayDays.value = delay ?? 0,
                          );
                        },
                      ),
                      TextField(
                        controller: wkCustomDelay,
                        decoration: const InputDecoration(labelText: 'Custom Delay (Tage)', helperText: 'Optional'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<String>(
                        valueListenable: wkResponsible,
                        builder: (context, value, _) {
                          return DropdownButtonFormField<String>(
                            value: value.isNotEmpty ? value : null,
                            decoration: const InputDecoration(labelText: 'WK Verantwortlich'),
                            items: _staffUsers
                                .map((user) => DropdownMenuItem(value: user.email, child: Text(user.label)))
                                .toList(),
                            onChanged: (selection) => wkResponsible.value = selection ?? '',
                          );
                        },
                      ),
                      ValueListenableBuilder<String>(
                        valueListenable: wkMethod,
                        builder: (context, method, _) {
                          if (method != 'questionnaire') return const SizedBox.shrink();
                          return DropdownButtonFormField<String>(
                            value: wkTemplateId.value.isNotEmpty ? wkTemplateId.value : null,
                            decoration: const InputDecoration(labelText: 'Fragebogen-Template'),
                            items: _templates
                                .map((template) => DropdownMenuItem(value: template.id, child: Text(template.title)))
                                .toList(),
                            onChanged: (selection) => wkTemplateId.value = selection ?? '',
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      if (current.wkDueAt != null)
                        Text('Fällig am: ${DateTime.fromMillisecondsSinceEpoch(current.wkDueAt!).toLocal()}'),
                      Text('Status: ${_wkStatusLabel(current.wkStatus)}'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: canManage
                            ? () async {
                                final customDelay = int.tryParse(wkCustomDelay.text.trim());
                                final delay = customDelay != null && customDelay > 0 ? customDelay : wkDelayDays.value;
                                if (wkMethod.value.isEmpty || delay <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('WK Methode und Verzögerung sind erforderlich.')),
                                  );
                                  return;
                                }
                                try {
                                  final updated = await widget.api.trainingConfigureWk(
                                    trainingId: current.id,
                                    wkMethod: wkMethod.value,
                                    wkDelayDays: delay,
                                    wkResponsibleId: wkResponsible.value,
                                    wkQuestionnaireTemplateId: wkTemplateId.value,
                                  );
                                  _updateTrainingRecord(updated);
                                  setModalState(() {
                                    current = updated;
                                    wkMethod.value = updated.wkMethod ?? '';
                                    wkDelayDays.value = updated.wkDelayDays ?? 0;
                                    wkResponsible.value = updated.wkResponsibleId ?? currentUser;
                                    wkTemplateId.value = updated.wkQuestionnaireTemplateId ?? '';
                                  });
                                  await _reloadWkReminders();
                                } catch (err) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text('WK Konfiguration fehlgeschlagen: $err')));
                                }
                              }
                            : null,
                        child: const Text('WK speichern'),
                      ),
                      const SizedBox(height: 16),
                      if (current.wkMethod == 'direct' || current.wkMethod == 'indirect') ...[
                        Text('WK Dokumentation', style: Theme.of(context).textTheme.titleSmall),
                        TextField(
                          controller: wkResult,
                          decoration: const InputDecoration(labelText: 'Ergebnis (wirksam/teilweise/nicht wirksam)'),
                        ),
                        TextField(
                          controller: wkNotes,
                          decoration: const InputDecoration(labelText: 'Notizen'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(DateTime.now().year - 2),
                              lastDate: DateTime(DateTime.now().year + 2),
                            );
                            if (picked != null) {
                              setModalState(() => wkPerformedAt = picked);
                            }
                          },
                          icon: const Icon(Icons.event),
                          label: Text(wkPerformedAt == null ? 'Datum wählen' : wkPerformedAt!.toLocal().toString()),
                        ),
                        ElevatedButton(
                          onPressed: canManage
                              ? () async {
                                  if (wkResult.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Bitte Ergebnis angeben.')),
                                    );
                                    return;
                                  }
                                  try {
                                    final updated = await widget.api.trainingCompleteWk(
                                      trainingId: current.id,
                                      result: wkResult.text.trim(),
                                      notes: wkNotes.text.trim(),
                                      performedAt: wkPerformedAt,
                                    );
                                    _updateTrainingRecord(updated);
                                    setModalState(() => current = updated);
                                    await _reloadWkReminders();
                                  } catch (err) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(content: Text('WK Abschluss fehlgeschlagen: $err')));
                                  }
                                }
                              : null,
                          child: const Text('WK abschließen'),
                        ),
                      ] else if (current.wkMethod == 'questionnaire') ...[
                        Text('WK Fragebogen', style: Theme.of(context).textTheme.titleSmall),
                        const Text('Fragebogen-Auswertung erfolgt über die Teilnehmerantworten.'),
                        if (canManage)
                          TextButton(
                            onPressed: () async {
                              final reasonController = TextEditingController();
                              final reason = await showDialog<String>(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: const Text('WK als ausreichend markieren'),
                                    content: TextField(
                                      controller: reasonController,
                                      decoration: const InputDecoration(labelText: 'Begründung'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text('Abbrechen'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.of(context).pop(reasonController.text.trim()),
                                        child: const Text('Bestätigen'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (reason == null || reason.isEmpty) return;
                              try {
                                final updated = await widget.api.trainingCompleteWk(
                                  trainingId: current.id,
                                  result: 'override',
                                  override: true,
                                  reason: reason,
                                );
                                _updateTrainingRecord(updated);
                                setModalState(() => current = updated);
                                await _reloadWkReminders();
                              } catch (err) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('WK Abschluss fehlgeschlagen: $err')));
                              }
                            },
                            child: const Text('WK als ausreichend markieren'),
                          ),
                      ],
                      const SizedBox(height: 16),
                      Text('Audit-Log', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      if (current.auditLog.isEmpty)
                        const Text('Keine Audit-Einträge vorhanden.')
                      else
                        ...current.auditLog.map((entry) {
                          final timestamp =
                              entry.at == null ? '—' : DateTime.fromMillisecondsSinceEpoch(entry.at!).toLocal().toString();
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.message),
                            subtitle: Text('${entry.action} · ${entry.by} · $timestamp'),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen')),
              ],
            );
          },
        );
      },
    );
    wkCustomDelay.dispose();
    wkResult.dispose();
    wkNotes.dispose();
  }

  Future<TrainingQuestionnaireTemplate?> _openTemplateDialog({TrainingQuestionnaireTemplate? initial}) async {
    if (!widget.canWrite) return null;
    final controllerTitle = TextEditingController(text: initial?.title ?? '');
    final controllerDescription = TextEditingController(text: initial?.description ?? '');
    final controllerQuestion = TextEditingController(
      text: initial?.questions.isNotEmpty == true ? initial!.questions.first['label']?.toString() ?? '' : '',
    );
    final result = await showDialog<TrainingQuestionnaireTemplate>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(initial == null ? 'Neues Template' : 'Template bearbeiten'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: controllerTitle, decoration: const InputDecoration(labelText: 'Titel')),
                TextField(controller: controllerDescription, decoration: const InputDecoration(labelText: 'Beschreibung')),
                TextField(controller: controllerQuestion, decoration: const InputDecoration(labelText: 'Frage')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final template = TrainingQuestionnaireTemplate(
                  id: initial?.id ?? '',
                  title: controllerTitle.text.trim(),
                  description: controllerDescription.text.trim(),
                  questions: [
                    {
                      'id': initial?.questions.isNotEmpty == true ? initial!.questions.first['id'] : null,
                      'label': controllerQuestion.text.trim(),
                      'type': 'text',
                      'required': true,
                    },
                  ],
                );
                Navigator.of(context).pop(template);
              },
              child: Text(initial == null ? 'Speichern' : 'Aktualisieren'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _createTemplate() async {
    final result = await _openTemplateDialog();
    if (result == null) return;
    try {
      final saved = await widget.api.adminCreateTrainingTemplate(result);
      setState(() => _templates = [..._templates, saved]);
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $err')));
    }
  }

  Future<void> _editTemplate(TrainingQuestionnaireTemplate template) async {
    final result = await _openTemplateDialog(initial: template);
    if (result == null) return;
    try {
      final saved = await widget.api.adminUpdateTrainingTemplate(result);
      setState(() => _templates = _templates.map((entry) => entry.id == saved.id ? saved : entry).toList());
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aktualisieren fehlgeschlagen: $err')));
    }
  }

  List<TrainingRecord> _filteredTrainings() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _trainings;
    return _trainings.where((training) {
      final categoryLabel = _trainingCategoryLabel(training).toLowerCase();
      return training.title.toLowerCase().contains(query) ||
          training.trainingNumber.toLowerCase().contains(query) ||
          training.category.toLowerCase().contains(query) ||
          categoryLabel.contains(query);
    }).toList();
  }

  Widget _buildErrorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400),
              const SizedBox(width: 8),
              Expanded(child: Text(_error ?? 'Fehler beim Laden.')),
              TextButton(onPressed: _loadAll, child: const Text('Neu laden')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initialIndex = widget.initialTab < 0
        ? 0
        : widget.initialTab > 6
            ? 6
            : widget.initialTab;
    return DefaultTabController(
      length: 7,
      initialIndex: initialIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Schulungswesen', style: theme.textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                onPressed: _loadAll,
                tooltip: 'Aktualisieren',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildErrorBanner(),
          TabBar(
            isScrollable: true,
            tabs: const [
              Tab(text: 'Dashboard'),
              Tab(text: 'Schulungsbedarf'),
              Tab(text: 'Schulungsprogramm'),
              Tab(text: 'Schulungen'),
              Tab(text: 'Wirksamkeitskontrolle'),
              Tab(text: 'Fragebogen-Templates'),
              Tab(text: 'Archiv'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _buildDashboardTab(theme),
                      _buildNeedsTab(theme),
                      _buildProgramsTab(theme),
                      _buildTrainingsTab(theme),
                      _buildEffectivenessTab(theme),
                      _buildTemplatesTab(theme),
                      _buildArchiveTab(theme),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(ThemeData theme) {
    final total = _summary['total'] ?? _trainings.length;
    final planned = _summary['planned'] ?? _trainings.where((t) => t.status != 'completed').length;
    final completed = _summary['completed'] ?? _trainings.where((t) => t.status == 'completed').length;
    final participation = _summary['participationRate'] ?? 0;
    final dueSoon = (_wkReminders['dueSoon'] as List? ?? const []).length;
    final overdue = (_wkReminders['overdue'] as List? ?? const []).length;
    return ListView(
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _metricCard('Geplante Schulungen', planned.toString(), Icons.event_note_outlined, Colors.blue.shade700),
            _metricCard('Durchgeführt', completed.toString(), Icons.verified_outlined, Colors.green.shade700),
            _metricCard('Teilnahmequote', '$participation%', Icons.people_outline, Colors.orange.shade700),
            _metricCard('Summe (Datensätze)', total.toString(), Icons.list_alt_outlined, Colors.purple.shade700),
            _metricCard('WK fällig (14 Tage)', dueSoon.toString(), Icons.fact_check_outlined, Colors.indigo.shade700),
            _metricCard('WK überfällig', overdue.toString(), Icons.warning_amber_outlined, Colors.red.shade700),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Statusüberblick & Fristen (Prozess AA127)',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'November: Bedarfserhebung starten · Rückgabe bis 15.12. · Januar: Programm freigeben. '
          'Wirksamkeit regelmäßig dokumentieren und bei Bedarf CAPA-Vorschlag erzeugen.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildNeedsTab(ThemeData theme) {
    return ListView(
      children: [
        Row(
          children: [
            Text('Bedarfserhebung (FB620)', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (widget.canDelete)
              TextButton.icon(
                onPressed: () => _purgeTrainingScope('needs', 'Schulungsbedarfe'),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Alles löschen'),
              ),
            if (widget.canWrite)
              ElevatedButton.icon(
                onPressed: _createNeed,
                icon: const Icon(Icons.add),
                label: const Text('Neuer Bedarf'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_needs.isEmpty)
          const Text('Noch keine Bedarfe erfasst.'),
        ..._needs.map((need) {
          final item = need.items.isNotEmpty ? need.items.first : null;
          final isAuto = need.isAutoGenerated;
          return Card(
            child: ListTile(
              title: Text('${need.year} · ${need.department.isEmpty ? 'Unbekannt' : need.department}'),
              subtitle: Text(item == null ? 'Kein Bedarf' : '${item.topic} · ${item.timeframe} · ${item.format}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isAuto) _autoBadge(theme),
                  if (isAuto) const SizedBox(width: 8),
                  Text(need.status),
                  if (widget.canWrite) const SizedBox(width: 8),
                  if (widget.canWrite)
                    IconButton(
                      tooltip: 'Bearbeiten',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editNeed(need),
                    ),
                  if (widget.canDelete) const SizedBox(width: 8),
                  if (widget.canDelete)
                    IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteNeed(need),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _programPlannedPeriodLabel(TrainingProgram program) {
    final value = program.plannedPeriodValue;
    if (value.isEmpty) return '—';
    switch (program.plannedPeriodType) {
      case 'date':
        return 'Datum: $value';
      case 'month':
        return 'Monat: $value';
      case 'quarter':
        return 'Quartal: ${value.split('-').last} ${value.split('-').first}';
      case 'halfYear':
        return 'Halbjahr: ${value.split('-').last} ${value.split('-').first}';
    }
    return value;
  }

  Color _programStatusTint(String status, ThemeData theme) {
    switch (status) {
      case 'completed':
        return Colors.green.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.12);
      case 'cancelled':
      case 'notOccurred':
      case 'removed':
      case 'abgebrochen':
        return Colors.red.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.12);
      case 'planned':
      case 'inProgress':
      default:
        return Colors.amber.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.12);
    }
  }

  List<TrainingProgram> _filteredPrograms() {
    final query = _programSearchController.text.trim().toLowerCase();
    final filtered = _programs.where((entry) {
      if (entry.year != _programYearFilter) return false;
      if (_programDepartmentFilter != null && _programDepartmentFilter!.isNotEmpty) {
        if (entry.department != _programDepartmentFilter) return false;
      }
      if (_programStatusFilter != null && _programStatusFilter!.isNotEmpty) {
        if (entry.status != _programStatusFilter) return false;
      }
      if (_programFormatFilter != null && _programFormatFilter!.isNotEmpty) {
        if (entry.format != _programFormatFilter) return false;
      }
      if (query.isEmpty) return true;
      return entry.title.toLowerCase().contains(query) ||
          entry.trainerProvider.toLowerCase().contains(query) ||
          entry.responsiblePerson.toLowerCase().contains(query);
    }).toList();
    filtered.sort((a, b) {
      int result;
      if (_programSort == 'title') {
        result = a.title.compareTo(b.title);
      } else if (_programSort == 'status') {
        result = a.status.compareTo(b.status);
      } else {
        result = a.plannedPeriodValue.compareTo(b.plannedPeriodValue);
      }
      return _programSortAsc ? result : -result;
    });
    return filtered;
  }

  Future<void> _addExecution(TrainingProgram program) async {
    if (!widget.canWrite) return;
    final controllerDate = TextEditingController();
    final controllerParticipants = TextEditingController();
    final controllerNotes = TextEditingController();
    final controllerEffectiveness = TextEditingController();
    final result = await showDialog<TrainingRecord>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Durchführung eintragen'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controllerDate,
                  decoration: const InputDecoration(labelText: 'Durchführungsdatum (YYYY-MM-DD)'),
                ),
                TextField(
                  controller: controllerParticipants,
                  decoration: const InputDecoration(labelText: 'Teilnehmer (tatsächlich)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: controllerEffectiveness,
                  decoration: const InputDecoration(labelText: 'Wirksamkeit (optional)'),
                ),
                TextField(
                  controller: controllerNotes,
                  decoration: const InputDecoration(labelText: 'Notizen (optional)'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final record = TrainingRecord(
                  id: '',
                  trainingNumber: '',
                  year: program.year,
                  title: program.title,
                  category: 'other',
                  categoryFreeText: program.department,
                  type: program.trainerProvider.trim().isNotEmpty ? 'extern' : 'intern',
                  format: program.format,
                  startDate: controllerDate.text.trim(),
                  endDate: '',
                  trainer: program.trainerProvider.trim().isNotEmpty ? program.trainerProvider : program.responsiblePerson,
                  trainerInternal: program.trainerProvider.trim().isEmpty ? program.responsiblePerson : null,
                  providerCompany: program.trainerProvider.trim().isNotEmpty ? program.trainerProvider : null,
                  location: program.format == 'praesenz' ? program.location : '',
                  meetingLink: program.format == 'online' ? program.location : null,
                  status: 'completed',
                  owner: program.responsiblePerson.isNotEmpty ? program.responsiblePerson : _currentUserEmail,
                  ownerUserId: _currentUserEmail,
                  targetGroup: program.targetGroup,
                  reason: '',
                  departments: [program.department],
                  isMandatory: false,
                  isExternal: false,
                  participants: const [],
                  defaultQuestionnaireTemplateId: _templates.isNotEmpty ? _templates.first.id : '',
                  linkedProgramId: program.id,
                  actualParticipants: int.tryParse(controllerParticipants.text.trim()),
                  executionNotes: controllerNotes.text.trim(),
                  effectivenessResult: controllerEffectiveness.text.trim(),
                );
                Navigator.of(context).pop(record);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    try {
      final saved = await widget.api.adminCreateTraining(result);
      setState(() => _trainings = [..._trainings, saved]);
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Durchführung konnte nicht gespeichert werden: $err')));
    }
  }

  Future<void> _showProgramDetails(TrainingProgram program) async {
    final executions = _trainings.where((t) => t.linkedProgramId == program.id).toList();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(program.title),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Zeitraum: ${_programPlannedPeriodLabel(program)}'),
                  Text('Abteilung/Team: ${program.department}'),
                  Text('Zielgruppe: ${program.targetGroup}'),
                  Text('Teilnehmer (geplant): ${program.participantsPlanned}'),
                  Text('Format: ${program.format}'),
                  Text('Status: ${program.status}'),
                  Text('Verantwortlich: ${program.responsiblePerson}'),
                  if (program.trainerProvider.isNotEmpty) Text('Trainer/Anbieter: ${program.trainerProvider}'),
                  if (program.location.isNotEmpty) Text('Ort/Link: ${program.location}'),
                  if (program.cancellationReason != null && program.cancellationReason!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Begründung: ${program.cancellationReason}'),
                    ),
                  const SizedBox(height: 12),
                  Text('Durchführungen', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  if (executions.isEmpty)
                    const Text('Noch keine Durchführungen erfasst.')
                  else
                    ...executions.map(
                      (exec) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(exec.startDate.isEmpty ? 'Ohne Datum' : exec.startDate),
                        subtitle: Text(
                          'Teilnehmer: ${exec.actualParticipants ?? exec.participants.length} · ${exec.executionNotes ?? ''}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen')),
            if (widget.canWrite)
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _addExecution(program);
                },
                icon: const Icon(Icons.add),
                label: const Text('Durchführung eintragen'),
              ),
          ],
        );
      },
    );
  }

  Widget _buildProgramsTab(ThemeData theme) {
    final programs = _filteredPrograms();
    final years = _programs.map((e) => e.year).toSet().toList()..sort();
    if (years.isEmpty) years.add(_programYearFilter);
    final departmentOptions = _programs.map((e) => e.department).where((e) => e.isNotEmpty).toSet().toList()..sort();
    const formatOptions = {'praesenz': 'Präsenz', 'online': 'Online'};
    const statusOptions = {
      'planned': 'Geplant',
      'inProgress': 'In Arbeit',
      'completed': 'Abgeschlossen',
      'cancelled': 'Abgesagt',
      'notOccurred': 'Nicht erfolgt',
      'removed': 'Entfernt',
      'abgebrochen': 'Abgebrochen',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 980;
        return ListView(
          children: [
            Row(
              children: [
                Text('Schulungsprogramm', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (widget.canDelete)
                  TextButton.icon(
                    onPressed: () => _purgeTrainingScope('program', 'Schulungsprogramme'),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Alles löschen'),
                  ),
                if (widget.canWrite)
                  ElevatedButton.icon(
                    onPressed: _createProgram,
                    icon: const Icon(Icons.add),
                    label: const Text('+ Neue geplante Schulung'),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _downloadProgramPdf(_programYearFilter),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF Export'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<int>(
                    value: _programYearFilter,
                    items: years.map((year) => DropdownMenuItem(value: year, child: Text('$year'))).toList(),
                    onChanged: (value) => setState(() => _programYearFilter = value ?? _programYearFilter),
                    decoration: const InputDecoration(labelText: 'Jahr'),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    value: _programDepartmentFilter,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Alle Abteilungen')),
                      ...departmentOptions.map((dept) => DropdownMenuItem<String?>(value: dept, child: Text(dept))),
                    ],
                    onChanged: (value) => setState(() => _programDepartmentFilter = value),
                    decoration: const InputDecoration(labelText: 'Abteilung/Team'),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String?>(
                    value: _programStatusFilter,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Alle Status')),
                      ...statusOptions.entries
                          .map((entry) => DropdownMenuItem<String?>(value: entry.key, child: Text(entry.value))),
                    ],
                    onChanged: (value) => setState(() => _programStatusFilter = value),
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String?>(
                    value: _programFormatFilter,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Alle Formate')),
                      ...formatOptions.entries
                          .map((entry) => DropdownMenuItem<String?>(value: entry.key, child: Text(entry.value))),
                    ],
                    onChanged: (value) => setState(() => _programFormatFilter = value),
                    decoration: const InputDecoration(labelText: 'Format'),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _programSearchController,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Suche'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    value: _programSort,
                    items: const [
                      DropdownMenuItem(value: 'plannedPeriod', child: Text('Sortieren: Zeitraum')),
                      DropdownMenuItem(value: 'title', child: Text('Sortieren: Thema')),
                      DropdownMenuItem(value: 'status', child: Text('Sortieren: Status')),
                    ],
                    onChanged: (value) => setState(() => _programSort = value ?? 'plannedPeriod'),
                    decoration: const InputDecoration(labelText: 'Sortierung'),
                  ),
                ),
                IconButton(
                  tooltip: _programSortAsc ? 'Aufsteigend' : 'Absteigend',
                  onPressed: () => setState(() => _programSortAsc = !_programSortAsc),
                  icon: Icon(_programSortAsc ? Icons.arrow_upward : Icons.arrow_downward),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (programs.isEmpty)
              const Text('Keine geplanten Schulungen gefunden.')
            else if (isWide)
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: const [
                        Expanded(flex: 2, child: Text('Zeitraum')),
                        Expanded(flex: 3, child: Text('Thema')),
                        Expanded(flex: 2, child: Text('Abteilung/Team')),
                        Expanded(flex: 1, child: Text('Format')),
                        Expanded(flex: 2, child: Text('Status')),
                        Expanded(flex: 2, child: Text('Verantwortlich')),
                        Expanded(flex: 2, child: Text('Aktionen')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...programs.map((program) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: _programStatusTint(program.status, theme),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text(_programPlannedPeriodLabel(program))),
                          Expanded(
                            flex: 3,
                            child: Text(
                              program.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(flex: 2, child: Text(program.department)),
                          Expanded(flex: 1, child: Text(formatOptions[program.format] ?? program.format)),
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(statusOptions[program.status] ?? program.status),
                                ),
                              ],
                            ),
                          ),
                          Expanded(flex: 2, child: Text(program.responsiblePerson)),
                          Expanded(
                            flex: 2,
                            child: Wrap(
                              spacing: 6,
                              children: [
                                IconButton(
                                  tooltip: 'Details',
                                  icon: const Icon(Icons.info_outline),
                                  onPressed: () => _showProgramDetails(program),
                                ),
                                if (widget.canWrite)
                                  IconButton(
                                    tooltip: 'Bearbeiten',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _editProgram(program),
                                  ),
                                if (widget.canWrite)
                                  IconButton(
                                    tooltip: 'Durchführung eintragen',
                                    icon: const Icon(Icons.playlist_add),
                                    onPressed: () => _addExecution(program),
                                  ),
                                if (widget.canDelete)
                                  IconButton(
                                    tooltip: 'Löschen',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _deleteProgram(program),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              )
            else
              ...programs.map(
                (program) => Card(
                  color: _programStatusTint(program.status, theme),
                  child: ListTile(
                    title: Text(program.title),
                    subtitle: Text(
                      '${_programPlannedPeriodLabel(program)} · ${program.department} · ${statusOptions[program.status] ?? program.status}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Details',
                          icon: const Icon(Icons.info_outline),
                          onPressed: () => _showProgramDetails(program),
                        ),
                        if (widget.canWrite)
                          IconButton(
                            tooltip: 'Bearbeiten',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editProgram(program),
                          ),
                        if (widget.canWrite)
                          IconButton(
                            tooltip: 'Durchführung eintragen',
                            icon: const Icon(Icons.playlist_add),
                            onPressed: () => _addExecution(program),
                          ),
                        if (widget.canDelete)
                          IconButton(
                            tooltip: 'Löschen',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteProgram(program),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTrainingsTab(ThemeData theme) {
    return ListView(
      children: [
        Row(
          children: [
            Text('Schulungen (Einzelmaßnahmen)', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (widget.canDelete)
              TextButton.icon(
                onPressed: () => _purgeTrainingScope('sessions', 'Schulungen'),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Alles löschen'),
              ),
            if (widget.canWrite)
              ElevatedButton.icon(
                onPressed: _createTraining,
                icon: const Icon(Icons.add),
                label: const Text('Neue Schulung'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_trainings.isEmpty)
          const Text('Noch keine Schulungen erstellt.'),
        ..._trainings.map((training) {
          final isAuto = training.isAutoGenerated;
          final timeLabel = _trainingTimeLabel(training);
          final dateLabel = training.startDate.isNotEmpty
              ? '${training.startDate}${timeLabel.isNotEmpty ? ' · $timeLabel' : ''}'
              : 'Ohne Datum';
          return Card(
            child: ListTile(
              title: Text('${training.trainingNumber.isEmpty ? 'Neu' : training.trainingNumber} · ${training.title}'),
              subtitle: Text(
                '${_trainingCategoryLabel(training)} · $dateLabel · ${_trainingStatusLabel(training.status)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isAuto) _autoBadge(theme),
                  if (isAuto) const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'PDF Export',
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    onPressed: () => _downloadTrainingPdf(training),
                  ),
                  IconButton(
                    tooltip: 'Details',
                    icon: const Icon(Icons.fact_check_outlined),
                    onPressed: () => _openTrainingDetailDialog(training),
                  ),
                  if (widget.canWrite)
                    IconButton(
                      tooltip: 'Bearbeiten',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editTraining(training),
                    ),
                  if (widget.canDelete)
                    IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteTraining(training),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEffectivenessTab(ThemeData theme) {
    final dueSoon = (_wkReminders['dueSoon'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final overdue = (_wkReminders['overdue'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    return ListView(
      children: [
        Text('Wirksamkeitskontrolle', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (dueSoon.isEmpty && overdue.isEmpty)
          const Text('Keine fälligen Wirksamkeitskontrollen.'),
        if (overdue.isNotEmpty) ...[
          Text('Überfällig', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...overdue.map((item) {
            final title = (item['title'] ?? '').toString();
            final number = (item['trainingNumber'] ?? '').toString();
            final dueRaw = item['wkDueAt'];
            final dueAt = dueRaw is num ? DateTime.fromMillisecondsSinceEpoch(dueRaw.toInt()).toLocal() : null;
            return Card(
              child: ListTile(
                leading: Icon(Icons.warning_amber_outlined, color: Colors.red.shade400),
                title: Text('$number · $title'),
                subtitle: Text(dueAt == null ? 'Fällig: —' : 'Fällig: ${dueAt.toString()}'),
              ),
            );
          }),
        ],
        if (dueSoon.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Fällig in den nächsten 14 Tagen', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...dueSoon.map((item) {
            final title = (item['title'] ?? '').toString();
            final number = (item['trainingNumber'] ?? '').toString();
            final dueRaw = item['wkDueAt'];
            final dueAt = dueRaw is num ? DateTime.fromMillisecondsSinceEpoch(dueRaw.toInt()).toLocal() : null;
            return Card(
              child: ListTile(
                leading: Icon(Icons.calendar_today_outlined, color: Colors.orange.shade600),
                title: Text('$number · $title'),
                subtitle: Text(dueAt == null ? 'Fällig: —' : 'Fällig: ${dueAt.toString()}'),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildTemplatesTab(ThemeData theme) {
    return ListView(
      children: [
        Row(
          children: [
            Text('Fragebogen-Templates', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (widget.canDelete)
              TextButton.icon(
                onPressed: () => _purgeTrainingScope('templates', 'Templates'),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Alles löschen'),
              ),
            if (widget.canWrite)
              ElevatedButton.icon(
                onPressed: _createTemplate,
                icon: const Icon(Icons.add),
                label: const Text('Neues Template'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_templates.isEmpty)
          const Text('Noch keine Templates verfügbar.'),
        ..._templates.map((template) {
          return Card(
            child: ListTile(
              title: Text(template.title),
              subtitle: Text('${template.questions.length} Fragen'),
              trailing: widget.canDelete
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.canWrite)
                          IconButton(
                            tooltip: 'Bearbeiten',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editTemplate(template),
                          ),
                        IconButton(
                          tooltip: 'Löschen',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteTemplate(template),
                        ),
                      ],
                    )
                  : widget.canWrite
                      ? IconButton(
                          tooltip: 'Bearbeiten',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editTemplate(template),
                        )
                      : null,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildArchiveTab(ThemeData theme) {
    final filtered = _filteredTrainings();
    return ListView(
      children: [
        Text('Archiv & Suche', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Suche nach Nummer, Thema, Kategorie',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Text('Keine Treffer im Archiv.'),
        ...filtered.map((training) {
          return Card(
            child: ListTile(
              title: Text('${training.trainingNumber} · ${training.title}'),
              subtitle: Text('${_trainingCategoryLabel(training)} · ${_trainingStatusLabel(training.status)}'),
              trailing: Wrap(
                spacing: 6,
                children: [
                  IconButton(
                    tooltip: 'PDF Export',
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    onPressed: () => _downloadTrainingPdf(training),
                  ),
                  IconButton(
                    tooltip: 'Details',
                    icon: const Icon(Icons.fact_check_outlined),
                    onPressed: () => _openTrainingDetailDialog(training),
                  ),
                  if (widget.canWrite)
                    IconButton(
                      tooltip: 'Bearbeiten',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editTraining(training),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
