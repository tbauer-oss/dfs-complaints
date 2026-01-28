import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../api/client.dart';
import '../models/training.dart';

class AdminTrainingPage extends StatefulWidget {
  const AdminTrainingPage({super.key, required this.api, required this.canWrite});

  final ApiClient api;
  final bool canWrite;

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
    final controllerDepartment = TextEditingController();
    final controllerTopic = TextEditingController();
    final controllerTimeframe = TextEditingController();
    final controllerFormat = TextEditingController();
    final controllerParticipants = TextEditingController();
    final controllerBudget = TextEditingController();
    final controllerComments = TextEditingController();
    final result = await showDialog<TrainingNeed>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neuer Schulungsbedarf'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controllerYear,
                    decoration: const InputDecoration(labelText: 'Schulungsjahr'),
                  ),
                  TextField(
                    controller: controllerContact,
                    decoration: const InputDecoration(labelText: 'Ansprechpartner'),
                  ),
                  TextField(
                    controller: controllerDepartment,
                    decoration: const InputDecoration(labelText: 'Abteilung/Team'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controllerTopic,
                    decoration: const InputDecoration(labelText: 'Schulungsthema'),
                  ),
                  TextField(
                    controller: controllerTimeframe,
                    decoration: const InputDecoration(labelText: 'Zeitraum'),
                  ),
                  TextField(
                    controller: controllerFormat,
                    decoration: const InputDecoration(labelText: 'Format'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controllerParticipants,
                          decoration: const InputDecoration(labelText: 'Teilnehmer'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: controllerBudget,
                          decoration: const InputDecoration(labelText: 'Budget'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: controllerComments,
                    decoration: const InputDecoration(labelText: 'Kommentare'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final item = TrainingNeedItem(
                  id: '',
                  topic: controllerTopic.text.trim(),
                  timeframe: controllerTimeframe.text.trim(),
                  format: controllerFormat.text.trim(),
                  participants: int.tryParse(controllerParticipants.text.trim()) ?? 0,
                  budget: double.tryParse(controllerBudget.text.trim()) ?? 0,
                  requirements: '',
                );
                final need = TrainingNeed(
                  id: '',
                  year: int.tryParse(controllerYear.text.trim()) ?? DateTime.now().year,
                  contactName: controllerContact.text.trim(),
                  position: '',
                  department: controllerDepartment.text.trim(),
                  team: '',
                  items: [item],
                  comments: controllerComments.text.trim(),
                  status: 'draft',
                  noNeed: false,
                );
                Navigator.of(context).pop(need);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    try {
      final saved = await widget.api.adminCreateTrainingNeed(result);
      setState(() => _needs = [..._needs, saved]);
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
    return DefaultTabController(
      length: 6,
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
