import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/client.dart';
import '../models/training.dart';

class AdminTrainingPage extends StatefulWidget {
  const AdminTrainingPage({
    super.key,
    required this.api,
    required this.canWrite,
    this.initialTab = 0,
  });

  final ApiClient api;
  final bool canWrite;
  final int initialTab;

  @override
  State<AdminTrainingPage> createState() => _AdminTrainingPageState();
}

class _AdminTrainingPageState extends State<AdminTrainingPage> {
  final _searchController = TextEditingController();
  List<TrainingNeed> _needs = const [];
  List<TrainingProgram> _programs = const [];
  List<TrainingRecord> _trainings = const [];
  List<TrainingQuestionnaireTemplate> _templates = const [];
  Map<String, dynamic> _summary = const {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
      ]);
      setState(() {
        _needs = results[0] as List<TrainingNeed>;
        _programs = results[1] as List<TrainingProgram>;
        _trainings = results[2] as List<TrainingRecord>;
        _templates = results[3] as List<TrainingQuestionnaireTemplate>;
        _summary = results[4] as Map<String, dynamic>;
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

  Future<void> _downloadProgramPdf(TrainingProgram program) async {
    try {
      final bytes = await widget.api.adminTrainingProgramPdf(program.year);
      _downloadBytes(bytes, 'Schulungsprogramm-${program.year}.pdf', 'application/pdf');
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Programm-PDF konnte nicht erstellt werden: $err')),
      );
    }
  }

  Future<void> _createNeed() async {
    if (!widget.canWrite) return;
    final controllerYear = TextEditingController(text: DateTime.now().year.toString());
    final controllerContact = TextEditingController();
    final controllerTopic = TextEditingController();
    final controllerParticipants = TextEditingController();
    final controllerBudget = TextEditingController();
    final controllerComments = TextEditingController();
    final controllerDepartmentOther = TextEditingController();
    final controllerPlannedDate = TextEditingController();
    final controllerMonthYear = TextEditingController();
    final controllerQuarterYear = TextEditingController();
    final controllerHalfYearYear = TextEditingController();
    final controllerIntervalOther = TextEditingController();
    final controllerTopicPriorities = TextEditingController();
    final controllerPreferredTrainers = TextEditingController();
    final controllerSpecialRequirements = TextEditingController();

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

    String? selectedDepartment = departmentOptions.first;
    String plannedPeriodType = plannedPeriodTypes.first;
    String? selectedMonth;
    String? selectedQuarter;
    String? selectedHalfYear;
    String? selectedFormat;
    String? selectedIntervalType;
    String? selectedIntervalValue;
    bool confirmationChecked = false;

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
      if (plannedPeriodType == 'date') {
        return controllerPlannedDate.text.trim().isEmpty ? null : controllerPlannedDate.text.trim();
      }
      if (plannedPeriodType == 'month') {
        final year = controllerMonthYear.text.trim();
        if (year.isEmpty || selectedMonth == null) return null;
        if (!RegExp(r'^\\d{4}$').hasMatch(year)) return null;
        return '$year-$selectedMonth';
      }
      if (plannedPeriodType == 'quarter') {
        final year = controllerQuarterYear.text.trim();
        if (year.isEmpty || selectedQuarter == null) return null;
        if (!RegExp(r'^\\d{4}$').hasMatch(year)) return null;
        return '$year-$selectedQuarter';
      }
      final year = controllerHalfYearYear.text.trim();
      if (year.isEmpty || selectedHalfYear == null) return null;
      if (!RegExp(r'^\\d{4}$').hasMatch(year)) return null;
      return '$year-$selectedHalfYear';
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

    final result = await showDialog<TrainingNeed>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final selectedDepartmentIsOther = selectedDepartment == 'Sonstiges...';
            final intervalIsRecurring = selectedIntervalType == 'recurring';
            final intervalIsOther = selectedIntervalValue == 'Sonstiges...';

            return AlertDialog(
              title: const Text('Neuer Schulungsbedarf'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controllerYear,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Schulungsjahr',
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
                            onSelected: (_) => setState(() => plannedPeriodType = 'date'),
                          ),
                          ChoiceChip(
                            label: const Text('Monat'),
                            selected: plannedPeriodType == 'month',
                            onSelected: (_) => setState(() => plannedPeriodType = 'month'),
                          ),
                          ChoiceChip(
                            label: const Text('Quartal'),
                            selected: plannedPeriodType == 'quarter',
                            onSelected: (_) => setState(() => plannedPeriodType = 'quarter'),
                          ),
                          ChoiceChip(
                            label: const Text('Halbjahr'),
                            selected: plannedPeriodType == 'halfYear',
                            onSelected: (_) => setState(() => plannedPeriodType = 'halfYear'),
                          ),
                        ],
                      ),
                      if (plannedPeriodType == 'date')
                        TextField(
                          controller: controllerPlannedDate,
                          readOnly: true,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(DateTime.now().year - 1),
                              lastDate: DateTime(DateTime.now().year + 5),
                            );
                            if (picked != null) {
                              setState(() => controllerPlannedDate.text = formatDate(picked));
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
                                onChanged: (value) => setState(() => selectedMonth = value),
                                decoration: const InputDecoration(labelText: 'Monat'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: controllerMonthYear,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  labelText: 'Jahr',
                                  errorText: errorPlannedPeriod,
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
                                onChanged: (value) => setState(() => selectedQuarter = value),
                                decoration: const InputDecoration(labelText: 'Quartal'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: controllerQuarterYear,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  labelText: 'Jahr',
                                  errorText: errorPlannedPeriod,
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
                                onChanged: (value) => setState(() => selectedHalfYear = value),
                                decoration: const InputDecoration(labelText: 'Halbjahr'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: controllerHalfYearYear,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  labelText: 'Jahr',
                                  errorText: errorPlannedPeriod,
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
                                    final plannedPeriodValue = buildPlannedPeriodValue();
                                    errorPlannedPeriod = plannedPeriodValue == null ? 'Bitte Zeitraum vollständig angeben.' : null;
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
                                      id: '',
                                      topic: topicText,
                                      timeframe: buildPlannedPeriodLabel(periodValue),
                                      format: trainingFormats[selectedFormat] ?? '',
                                      participants: participants ?? 0,
                                      budget: plannedBudget ?? 0,
                                      requirements: '',
                                    );
                                    final need = TrainingNeed(
                                      id: '',
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
                                      status: 'draft',
                                      noNeed: false,
                                    );
                                    Navigator.of(context).pop(need);
                                  }
                                : null,
                            child: const Text('Absenden'),
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
            );
          },
        );
      },
    );
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

  Future<void> _createProgram() async {
    if (!widget.canWrite) return;
    final controllerYear = TextEditingController(text: DateTime.now().year.toString());
    final controllerTitle = TextEditingController();
    final controllerOwner = TextEditingController();
    final controllerBudget = TextEditingController();
    final result = await showDialog<TrainingProgram>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neues Schulungsprogramm'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: controllerYear, decoration: const InputDecoration(labelText: 'Jahr')),
                TextField(controller: controllerTitle, decoration: const InputDecoration(labelText: 'Titel')),
                TextField(controller: controllerOwner, decoration: const InputDecoration(labelText: 'Koordinator')),
                TextField(controller: controllerBudget, decoration: const InputDecoration(labelText: 'Budget (Summe)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final program = TrainingProgram(
                  id: '',
                  year: int.tryParse(controllerYear.text.trim()) ?? DateTime.now().year,
                  title: controllerTitle.text.trim(),
                  status: 'draft',
                  owner: controllerOwner.text.trim(),
                  department: '',
                  needIds: const [],
                  trainingIds: const [],
                  budgetTotal: double.tryParse(controllerBudget.text.trim()) ?? 0,
                );
                Navigator.of(context).pop(program);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    try {
      final saved = await widget.api.adminCreateTrainingProgram(result);
      setState(() => _programs = [..._programs, saved]);
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $err')));
    }
  }

  Future<void> _createTraining() async {
    if (!widget.canWrite) return;
    final controllerTitle = TextEditingController();
    final controllerCategory = TextEditingController();
    final controllerType = TextEditingController();
    final controllerFormat = TextEditingController();
    final controllerDate = TextEditingController();
    final controllerTrainer = TextEditingController();
    final controllerLocation = TextEditingController();
    final controllerOwner = TextEditingController();
    final result = await showDialog<TrainingRecord>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neue Schulung'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: controllerTitle, decoration: const InputDecoration(labelText: 'Titel')),
                  TextField(controller: controllerCategory, decoration: const InputDecoration(labelText: 'Kategorie')),
                  TextField(controller: controllerType, decoration: const InputDecoration(labelText: 'Typ (intern/extern)')),
                  TextField(controller: controllerFormat, decoration: const InputDecoration(labelText: 'Format')),
                  TextField(controller: controllerDate, decoration: const InputDecoration(labelText: 'Datum')),
                  TextField(controller: controllerTrainer, decoration: const InputDecoration(labelText: 'Trainer/Anbieter')),
                  TextField(controller: controllerLocation, decoration: const InputDecoration(labelText: 'Ort/Link')),
                  TextField(controller: controllerOwner, decoration: const InputDecoration(labelText: 'Owner')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final record = TrainingRecord(
                  id: '',
                  trainingNumber: '',
                  year: DateTime.now().year,
                  title: controllerTitle.text.trim(),
                  category: controllerCategory.text.trim(),
                  type: controllerType.text.trim(),
                  format: controllerFormat.text.trim(),
                  startDate: controllerDate.text.trim(),
                  endDate: '',
                  trainer: controllerTrainer.text.trim(),
                  location: controllerLocation.text.trim(),
                  status: 'planned',
                  owner: controllerOwner.text.trim(),
                  targetGroup: '',
                  reason: '',
                  departments: const [],
                  isMandatory: false,
                  isExternal: controllerType.text.trim().toLowerCase() == 'extern',
                  participants: const [],
                  defaultQuestionnaireTemplateId: _templates.isNotEmpty ? _templates.first.id : '',
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $err')));
    }
  }

  Future<void> _createTemplate() async {
    if (!widget.canWrite) return;
    final controllerTitle = TextEditingController();
    final controllerDescription = TextEditingController();
    final controllerQuestion = TextEditingController();
    final result = await showDialog<TrainingQuestionnaireTemplate>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neues Template'),
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
                  id: '',
                  title: controllerTitle.text.trim(),
                  description: controllerDescription.text.trim(),
                  questions: [
                    {
                      'label': controllerQuestion.text.trim(),
                      'type': 'text',
                      'required': true,
                    },
                  ],
                );
                Navigator.of(context).pop(template);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    try {
      final saved = await widget.api.adminCreateTrainingTemplate(result);
      setState(() => _templates = [..._templates, saved]);
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $err')));
    }
  }

  List<TrainingRecord> _filteredTrainings() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _trainings;
    return _trainings.where((training) {
      return training.title.toLowerCase().contains(query) ||
          training.trainingNumber.toLowerCase().contains(query) ||
          training.category.toLowerCase().contains(query);
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
        : widget.initialTab > 5
            ? 5
            : widget.initialTab;
    return DefaultTabController(
      length: 6,
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
          return Card(
            child: ListTile(
              title: Text('${need.year} · ${need.department.isEmpty ? 'Unbekannt' : need.department}'),
              subtitle: Text(item == null ? 'Kein Bedarf' : '${item.topic} · ${item.timeframe} · ${item.format}'),
              trailing: Text(need.status),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildProgramsTab(ThemeData theme) {
    return ListView(
      children: [
        Row(
          children: [
            Text('Jahresprogramme', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (widget.canWrite)
              ElevatedButton.icon(
                onPressed: _createProgram,
                icon: const Icon(Icons.add),
                label: const Text('Neues Programm'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_programs.isEmpty)
          const Text('Noch keine Programme erstellt.'),
        ..._programs.map((program) {
          return Card(
            child: ListTile(
              title: Text(program.title.isEmpty ? 'Schulungsprogramm ${program.year}' : program.title),
              subtitle: Text('Status: ${program.status} · Budget: ${program.budgetTotal.toStringAsFixed(0)} €'),
              trailing: IconButton(
                tooltip: 'PDF Export',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => _downloadProgramPdf(program),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTrainingsTab(ThemeData theme) {
    return ListView(
      children: [
        Row(
          children: [
            Text('Schulungen (Einzelmaßnahmen)', style: theme.textTheme.titleMedium),
            const Spacer(),
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
          return Card(
            child: ListTile(
              title: Text('${training.trainingNumber.isEmpty ? 'Neu' : training.trainingNumber} · ${training.title}'),
              subtitle: Text('${training.category} · ${training.startDate} · ${training.status}'),
              trailing: IconButton(
                tooltip: 'PDF Export',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => _downloadTrainingPdf(training),
              ),
            ),
          );
        }),
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
              subtitle: Text('${training.category} · ${training.status}'),
              trailing: IconButton(
                tooltip: 'PDF Export',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => _downloadTrainingPdf(training),
              ),
            ),
          );
        }),
      ],
    );
  }
}
