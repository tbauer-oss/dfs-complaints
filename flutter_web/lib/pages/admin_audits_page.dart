import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/audit_admin_api.dart';
import '../api/client.dart';
import '../models/audit.dart';
import '../models/portal_user.dart';
import '../widgets/dialog_content_scroll.dart';

class AdminAuditsPage extends StatefulWidget {
  final ApiClient api;
  final int initialTab;
  final int? initialReportYear;
  const AdminAuditsPage({super.key, required this.api, this.initialTab = 0, this.initialReportYear});

  @override
  State<AdminAuditsPage> createState() => _AdminAuditsPageState();
}

class _AdminAuditsPageState extends State<AdminAuditsPage> with SingleTickerProviderStateMixin {
  late final AuditAdminApi _auditApi;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _auditApi = AuditAdminApi(widget.api);
    final initial = widget.initialTab.clamp(0, 3).toInt();
    _tabs = TabController(length: 4, vsync: this, initialIndex: initial);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audits'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Übersicht'),
            Tab(text: 'Auditprogramm'),
            Tab(text: 'Auditorenmatrix'),
            Tab(text: 'Jahresberichte'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _AuditOverviewTab(api: _auditApi),
          _AuditProgramTab(api: _auditApi),
          _AuditorMatrixTab(api: _auditApi),
          _AnnualReportTab(api: _auditApi, initialYear: widget.initialReportYear),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _AuditOverviewTab extends StatefulWidget {
  final AuditAdminApi api;
  const _AuditOverviewTab({required this.api});

  @override
  State<_AuditOverviewTab> createState() => _AuditOverviewTabState();
}

class _AuditPlanEntry {
  String from;
  String to;
  String agenda;
  String process;
  String participants;
  String auditor;
  String? auditorId;
  String reference;
  String notes;
  bool done;

  _AuditPlanEntry({
    this.from = '',
    this.to = '',
    this.agenda = '',
    this.process = '',
    this.participants = '',
    this.auditor = '',
    this.auditorId,
    this.reference = '',
    this.notes = '',
    this.done = false,
  });
}

class _AuditReportDraft {
  String summary;
  String scopeEvaluation;
  String findings;
  String conclusion;
  bool followUpRecommended;
  List<String> evidence;

  _AuditReportDraft({
    this.summary = '',
    this.scopeEvaluation = '',
    this.findings = '',
    this.conclusion = '',
    this.followUpRecommended = false,
    this.evidence = const [],
  });

  factory _AuditReportDraft.empty() => _AuditReportDraft();
}

class _AuditOverviewTabState extends State<_AuditOverviewTab> {
  bool _loading = false;
  String? _error;
  List<Audit> _audits = const [];
  List<Auditor> _auditors = const [];
  final Map<String, List<_AuditPlanEntry>> _plans = {};
  final Map<String, _AuditReportDraft> _reports = {};

  int _year = DateTime.now().year;
  String? _quarter;
  String? _status;
  String? _orgUnit;
  String? _leadAuditorId;
  DateTimeRange? _range;

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
      final audits = await widget.api.listAudits(
        year: _year,
        quarter: _quarter,
        status: _status,
        orgUnit: _orgUnit,
        leadAuditorId: _leadAuditorId,
        from: _range?.start,
        to: _range?.end,
      );
      final auditors = await widget.api.listAuditors();
      if (!mounted) return;
      setState(() {
        _audits = audits;
        _auditors = auditors;
        for (final a in audits) {
          _plans.putIfAbsent(a.id, () => []);
          _reports.putIfAbsent(a.id, () => _AuditReportDraft.empty());
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _countOpenFindings() => _audits.fold<int>(0, (p, a) => p + (a.openFindings ?? 0));
  int _countOverdueActions() => _audits.fold<int>(0, (p, a) => p + (a.overdueActions ?? 0));
  int _countCritical() => _audits.where((a) => a.status == 'nachauditRequired').length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 700;
    final kpis = [
      _KpiCard(label: 'Geplante Audits', value: _audits.where((a) => a.status == 'planned').length.toString()),
      _KpiCard(label: 'Offene Findings', value: _countOpenFindings().toString(), color: Colors.orange.shade700),
      _KpiCard(label: 'Überfällige Maßnahmen', value: _countOverdueActions().toString(), color: Colors.red.shade700),
      _KpiCard(label: 'Critical / Nachaudit', value: _countCritical().toString(), color: Colors.deepPurple),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: kpis,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildFilters(theme, isMobile),
            ),
          ),
          SliverFillRemaining(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorState(message: _error!, onRetry: _load)
                    : _audits.isEmpty
                        ? const Center(child: Text('Keine Audits gefunden.'))
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            child: isMobile ? _buildCards(theme) : _buildTable(theme),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(ThemeData theme, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.start,
                children: [
                  DropdownButton<int>(
                    value: _year,
                    onChanged: (v) => setState(() => _year = v ?? _year),
                    items: List.generate(4, (i) => DateTime.now().year - 1 + i)
                        .map((y) => DropdownMenuItem(value: y, child: Text('Jahr $y')))
                        .toList(),
                  ),
                  DropdownButton<String?>(
                    value: _quarter,
                    hint: const Text('Quartal'),
                    onChanged: (v) => setState(() => _quarter = v),
                    items: const [null, 'Q1', 'Q2', 'Q3', 'Q4']
                        .map((q) => DropdownMenuItem(value: q, child: Text(q == null ? 'Alle Quartale' : q)))
                        .toList(),
                  ),
                  DropdownButton<String?>(
                    value: _status,
                    hint: const Text('Status'),
                    onChanged: (v) => setState(() => _status = v),
                    items: const [null, 'planned', 'inProgress', 'completed', 'closed', 'nachauditRequired']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s == null ? 'Alle Status' : s)))
                        .toList(),
                  ),
                  DropdownButton<String?>(
                    value: _leadAuditorId,
                    hint: const Text('Lead Auditor'),
                    onChanged: (v) => setState(() => _leadAuditorId = v),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Alle Auditoren')),
                      ..._auditors.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                    ],
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'Bereich / OrgUnit', border: OutlineInputBorder(), isDense: true),
                      onChanged: (v) => _orgUnit = v,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(now.year - 1, 1, 1),
                        lastDate: DateTime(now.year + 1, 12, 31),
                        initialDateRange: _range ?? DateTimeRange(start: DateTime(now.year, 1, 1), end: DateTime(now.year, 12, 31)),
                      );
                      if (picked != null) setState(() => _range = picked);
                    },
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(_range == null ? 'Zeitraum' : '${DateFormat('dd.MM.yyyy').format(_range!.start)} – ${DateFormat('dd.MM.yyyy').format(_range!.end)}'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.search), label: const Text('Filtern')),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.add_task_outlined),
              onPressed: () => _openEditor(),
              label: const Text('Neues Audit'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: () => _openProgram(),
              label: const Text('Auditprogramm'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _openReports(),
              label: const Text('Jahresbericht erzeugen'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTable(ThemeData theme) {
    final columns = const ['Audit Nr', 'Titel', 'Quartal', 'Zeitraum', 'Status', 'Lead', 'Findings', 'Überfällige'];
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStatePropertyAll(theme.colorScheme.surfaceVariant),
          columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
          rows: _audits
              .map(
                (a) => DataRow(cells: [
                      DataCell(Text(a.auditNumber)),
                      DataCell(Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => _openDetail(a)),
                      DataCell(Text(a.cluster ?? '-')),
                      DataCell(Text(a.displayPeriod)),
                      DataCell(_StatusChip(status: a.status)),
                      DataCell(Text(_auditors
                          .firstWhere((au) => au.id == a.leadAuditorId, orElse: () => const Auditor(id: '', name: '-', email: '', status: 'inactive'))
                          .name)),
                      DataCell(Text((a.openFindings ?? 0).toString())),
                      DataCell(Text((a.overdueActions ?? 0).toString(),
                          style: TextStyle(color: (a.overdueActions ?? 0) > 0 ? Colors.red : null))),
                    ],
                    onSelectChanged: (_) => _openDetail(a),
                  ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildCards(ThemeData theme) {
    return ListView.separated(
      itemCount: _audits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final a = _audits[i];
        final lead = _auditors.firstWhere((au) => au.id == a.leadAuditorId, orElse: () => const Auditor(id: '', name: '-', email: '', status: 'inactive'));
        return Card(
          child: ListTile(
            title: Text('${a.auditNumber} · ${a.title}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.cluster ?? '-'} · ${a.displayPeriod}'),
                const SizedBox(height: 4),
                Text('Lead: ${lead.name}'),
                Text('Findings: ${a.openFindings ?? 0}, Überfällig: ${a.overdueActions ?? 0}')
              ],
            ),
            trailing: _StatusChip(status: a.status),
            onTap: () => _openDetail(a),
          ),
        );
      },
    );
  }

  Future<void> _openEditor() async {
    final created = await showDialog<Audit>(
      context: context,
      builder: (_) => _AuditEditorDialog(api: widget.api, auditors: _auditors),
    );
    if (created != null) _load();
  }

  void _openProgram() {
    Navigator.of(context, rootNavigator: true).pushNamed('/admin/audits/program');
  }

  void _openReports() {
    Navigator.of(context, rootNavigator: true).pushNamed('/admin/audits/reports/${_year.toString()}');
  }

  Future<void> _openDetail(Audit audit) async {
    final changed = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AuditDetailPage(api: widget.api, audit: audit),
      ),
    );
    if (changed == true) _load();
  }
}

class _AuditProgramTab extends StatefulWidget {
  final AuditAdminApi api;
  const _AuditProgramTab({required this.api});

  @override
  State<_AuditProgramTab> createState() => _AuditProgramTabState();
}

class _AuditProgramTabState extends State<_AuditProgramTab> {
  bool _loading = false;
  String? _error;
  List<AuditProgram> _programs = const [];

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
      final p = await widget.api.listPrograms();
      if (!mounted) return;
      setState(() {
        _programs = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _programs.length,
      itemBuilder: (_, i) {
        final program = _programs[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text('${program.year} – ${program.title}'),
            subtitle: Text('Status: ${program.status}'),
            trailing: IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Programm exportieren',
              onPressed: () => _showProgram(program),
            ),
          ),
        );
      },
    );
  }

  void _showProgram(AuditProgram program) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Auditprogramm ${program.year}'),
        content: DialogContentScroll(
          child: Text('Cluster: ${(program.clusters.isEmpty ? ['Q1', 'Q2', 'Q3', 'Q4'] : program.clusters).join(', ')}'),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
      ),
    );
  }
}

class _AuditorMatrixTab extends StatefulWidget {
  final AuditAdminApi api;
  const _AuditorMatrixTab({required this.api});

  @override
  State<_AuditorMatrixTab> createState() => _AuditorMatrixTabState();
}

class _AuditorMatrixTabState extends State<_AuditorMatrixTab> {
  bool _loading = true;
  String? _error;
  List<Auditor> _auditors = const [];
  List<PortalUserSummary> _dfsUsers = const [];
  List<String> _orgUnits = const ['QM', 'Operations', 'Produktion', 'IT', 'RA/QA', 'Logistik'];

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
      final results = await Future.wait([
        widget.api.listAuditors(),
        widget.api.listDfsEmployees(),
      ]);
      if (!mounted) return;
      setState(() {
        _auditors = results[0] as List<Auditor>;
        _dfsUsers = results[1] as List<PortalUserSummary>;
        final observedOrgUnits = {
          ..._orgUnits,
          ..._auditors.map((a) => a.orgUnit ?? '').where((e) => e.isNotEmpty),
          ..._dfsUsers.expand((u) => u.assignedDepartments).where((e) => e.isNotEmpty),
        }..removeWhere((e) => e.isEmpty);
        final sortedOrgUnits = observedOrgUnits.toList(growable: true)..sort();
        _orgUnits = sortedOrgUnits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text('Auditorenmatrix', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(onPressed: _addAuditor, icon: const Icon(Icons.add), label: const Text('Auditor hinzufügen')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (_, i) {
              final a = _auditors[i];
              final due = a.nextRequalification ?? a.requalificationDueDate;
              final warn = due != null && due.isBefore(DateTime.now());
              return Card(
                child: ListTile(
                  leading: Icon(Icons.badge_outlined, color: warn ? Colors.red : null),
                  title: Text(a.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.email),
                      Text('Status: ${a.qualificationStatus}'),
                      Text('Erfahrung: ${(a.experienceYears ?? 0)} Jahre'),
                      Text('Co-Audit: ${a.coAuditCount} · Lead: ${a.leadAuditCount}'),
                      if (a.restrictedOrgUnits.isNotEmpty)
                        Text('Restriktionen: ${a.restrictedOrgUnits.join(', ')}'),
                      if (due != null)
                        Text('Re-Qual fällig: ${DateFormat('dd.MM.yyyy').format(due)}',
                            style: TextStyle(color: warn ? Colors.red : null)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (warn) const Icon(Icons.warning_amber, color: Colors.red),
                      IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editAuditor(a)),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteAuditor(a)),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: _auditors.length,
          ),
        ),
      ],
    );
  }

  Future<void> _addAuditor() async {
    const empty = Auditor(id: '', name: '', email: '', status: 'active');
    await _editAuditor(empty);
  }
  Future<void> _editAuditor(Auditor auditor) async {
    final nameCtrl = TextEditingController(text: auditor.name);
    final coCtrl = TextEditingController(text: auditor.coAuditCount.toString());
    final leadCtrl = TextEditingController(text: auditor.leadAuditCount.toString());
    final expCtrl = TextEditingController(text: (auditor.experienceYears ?? 0).toString());
    final userCtrl = TextEditingController(text: auditor.name);
    final userFocus = FocusNode();
    DateTime? trainingDate = auditor.trainingDate ?? auditor.internalAuditorTrainingDate;
    String trainingType = auditor.trainingType;
    bool iso13485 = auditor.standardsKnowledge.contains('ISO13485');
    bool iso19011 = auditor.standardsKnowledge.contains('ISO19011');
    bool mdr = auditor.standardsKnowledge.contains('MDR');
    bool active = auditor.status == 'active';
    bool uploading = false;
    String? selectedOrgUnit = auditor.orgUnit;
    final attachments = auditor.evidenceAttachments.toList();
    PortalUserSummary? selectedUser = _dfsUsers.firstWhere(
      (u) => u.email.toLowerCase() == auditor.email.toLowerCase() || u.displayName == auditor.name,
      orElse: () => const PortalUserSummary(email: '', displayName: '', role: '', portalStatus: ''),
    );
    if (selectedUser.email.isEmpty) selectedUser = null;
    if ((selectedOrgUnit == null || selectedOrgUnit.isEmpty) &&
        (selectedUser?.assignedDepartments.isNotEmpty ?? false)) {
      selectedOrgUnit = selectedUser!.assignedDepartments.first;
    }
    if (selectedOrgUnit != null && selectedOrgUnit.isNotEmpty && !_orgUnits.contains(selectedOrgUnit)) {
      setState(() => _orgUnits = {..._orgUnits, selectedOrgUnit!}.toList(growable: true)..sort());
    }
    userCtrl.text = selectedUser?.displayName ?? auditor.name;

    final updated = await showDialog<Auditor>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setModalState) {
        Future<void> pickFile() async {
          setModalState(() => uploading = true);
          try {
            final res = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
            if (res == null || res.files.isEmpty) {
              setModalState(() => uploading = false);
              return;
            }
            final file = res.files.first;
            if (file.bytes == null) {
              setModalState(() => uploading = false);
              return;
            }
            final mime = lookupMimeType(file.name) ?? 'application/octet-stream';
            final dataUrl = 'data:$mime;base64,${base64Encode(file.bytes!)}';
            final evidence = AuditorEvidence(
              name: file.name,
              downloadUrl: dataUrl,
              size: file.bytes!.length,
              uploadedAt: DateTime.now().toUtc(),
              mime: mime,
            );
            setModalState(() => attachments
              ..removeWhere((e) => e.name == evidence.name)
              ..add(evidence));
          } finally {
            setModalState(() => uploading = false);
          }
        }

        void removeEvidence(AuditorEvidence evidence) {
          setModalState(() => attachments.remove(evidence));
        }

        Future<void> openEvidence(AuditorEvidence evidence) async {
          final link = evidence.downloadUrl ?? evidence.url;
          if (link == null || link.isEmpty) return;
          final uri = Uri.tryParse(link);
          if (uri == null) return;
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Download-Link nicht verfügbar')));
            }
          }
        }

        final tempStatus = (() {
          final co = int.tryParse(coCtrl.text) ?? 0;
          final lead = int.tryParse(leadCtrl.text) ?? 0;
          final expYears = int.tryParse(expCtrl.text) ?? 0;
          final requal = trainingDate != null
              ? DateTime(trainingDate!.year + 3, trainingDate!.month, trainingDate!.day)
              : auditor.requalificationDueDate;
          final requalOk = requal == null || !requal.isBefore(DateTime.now());
          final hasTraining = trainingDate != null;
          final countsOk = co >= 2 || lead >= 1;
          if (hasTraining && countsOk && attachments.isNotEmpty && expYears >= 3 && requalOk) {
            return 'qualifiziert';
          }
          if (hasTraining && attachments.isEmpty) return 'in Arbeit';
          return 'nicht qualifiziert';
        })();

        return AlertDialog(
          title: const Text('Auditor bearbeiten'),
          content: DialogContentScroll(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedUser?.email.isNotEmpty == true ? selectedUser!.email : null,
                  decoration: InputDecoration(
                    labelText: 'DFS-Mitarbeiter',
                    helperText: _dfsUsers.isEmpty ? 'Keine aktiven DFS-Profile gefunden' : null,
                  ),
                  items: _dfsUsers
                      .map((u) => DropdownMenuItem(
                            value: u.email,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u.displayName),
                                Text(u.email, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (email) {
                    final opt = _dfsUsers.firstWhere((u) => u.email == email);
                    final observedOrgUnits = {
                      ..._orgUnits,
                      ...opt.assignedDepartments,
                    }..removeWhere((e) => e.isEmpty);
                    setState(() => _orgUnits = observedOrgUnits.toList(growable: true)..sort());
                    setModalState(() {
                      selectedUser = opt;
                      nameCtrl.text = opt.displayName;
                      userCtrl.text = opt.displayName;
                      if (opt.assignedDepartments.isNotEmpty) {
                        selectedOrgUnit = opt.assignedDepartments.first;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Anzeigename')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedOrgUnit != null && selectedOrgUnit!.isNotEmpty ? selectedOrgUnit : null,
                  decoration: const InputDecoration(labelText: 'Bereich / OrgUnit'),
                  items: _orgUnits
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedOrgUnit = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: trainingType,
                  decoration: const InputDecoration(labelText: 'Training (intern/extern)'),
                  items: const [
                    DropdownMenuItem(value: 'internal', child: Text('Intern')),
                    DropdownMenuItem(value: 'external', child: Text('Extern')),
                  ],
                  onChanged: (v) => setModalState(() => trainingType = v ?? 'internal'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Trainingsdatum'),
                  subtitle: Text(trainingDate != null ? DateFormat('dd.MM.yyyy').format(trainingDate!) : 'offen'),
                  trailing: IconButton(
                    icon: const Icon(Icons.event_outlined),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(DateTime.now().year - 5),
                        lastDate: DateTime(DateTime.now().year + 5),
                        initialDate: trainingDate ?? DateTime.now(),
                      );
                      if (picked != null) {
                        setModalState(() => trainingDate = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: expCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Erfahrung (Jahre)'),
                ),
                const SizedBox(height: 12),
                TextField(controller: coCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Co-Audits')),
                const SizedBox(height: 12),
                TextField(controller: leadCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Lead-Audits')),
                CheckboxListTile(
                  value: iso13485,
                  onChanged: (v) => setModalState(() => iso13485 = v ?? false),
                  title: const Text('ISO 13485'),
                ),
                CheckboxListTile(
                  value: iso19011,
                  onChanged: (v) => setModalState(() => iso19011 = v ?? false),
                  title: const Text('ISO 19011'),
                ),
                CheckboxListTile(
                  value: mdr,
                  onChanged: (v) => setModalState(() => mdr = v ?? false),
                  title: const Text('MDR'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: attachments
                        .map((a) => InputChip(
                              label: Text(a.name),
                              onPressed: () => openEvidence(a),
                              onDeleted: () => removeEvidence(a),
                              avatar: const Icon(Icons.attachment_outlined, size: 18),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: uploading ? null : pickFile,
                      icon: uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file_outlined),
                      label: const Text('Qualifikationsnachweis hochladen'),
                    ),
                    const SizedBox(width: 8),
                    if (uploading) const Text('Upload...'),
                  ],
                ),
                SwitchListTile(
                  value: active,
                  onChanged: (v) => setModalState(() => active = v),
                  title: const Text('Aktiv'),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Status: $tempStatus', style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: uploading || selectedUser == null
                  ? null
                  : () async {
                      try {
                        final requal = trainingDate != null
                            ? DateTime(trainingDate!.year + 3, trainingDate!.month, trainingDate!.day)
                            : auditor.requalificationDueDate;
                        final saved = await widget.api.saveAuditor(
                          Auditor(
                            id: auditor.id,
                            userId: selectedUser?.email.isNotEmpty == true ? selectedUser!.email : auditor.userId,
                            name: nameCtrl.text.trim().isEmpty
                                ? (selectedUser?.displayName ?? auditor.name)
                                : nameCtrl.text.trim(),
                            email: selectedUser?.email.isNotEmpty == true ? selectedUser!.email : auditor.email,
                            status: active ? 'active' : 'inactive',
                            orgUnit: (selectedOrgUnit ?? '').trim().isEmpty ? null : selectedOrgUnit!.trim(),
                            role: auditor.role,
                            restrictedProcessOwners: auditor.restrictedProcessOwners,
                            restrictedOrgUnits: auditor.restrictedOrgUnits,
                            internalAuditorTrainingDate: trainingDate,
                            trainingType: trainingType,
                            trainingDate: trainingDate,
                            experienceYears: int.tryParse(expCtrl.text) ?? auditor.experienceYears,
                            standardsKnowledge: [
                              if (iso13485) 'ISO13485',
                              if (iso19011) 'ISO19011',
                              if (mdr) 'MDR'
                            ],
                            requalificationDueDate: requal,
                            evidenceAttachments: attachments,
                            coAuditCount: int.tryParse(coCtrl.text) ?? auditor.coAuditCount,
                            leadAuditCount: int.tryParse(leadCtrl.text) ?? auditor.leadAuditCount,
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Auditor gespeichert')),
                          );
                          Navigator.pop(context, saved);
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
                      }
                    },
              child: const Text('Speichern'),
            ),
          ],
        );
      }),
    );
    if (updated != null) _load();
  }

  Future<void> _deleteAuditor(Auditor auditor) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Auditor löschen?'),
            content: Text('Soll ${auditor.name} wirklich gelöscht werden?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await widget.api.deleteAuditor(auditor.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${auditor.name} entfernt')),
        );
      }
      await _load();
    } catch (e) {
      final deactivate = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Löschen nicht möglich'),
              content: Text('Der Auditor ist referenziert. Stattdessen deaktivieren? ($e)'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deaktivieren')),
              ],
            ),
          ) ??
          false;
      if (deactivate) {
        final inactive = Auditor(
          id: auditor.id,
          userId: auditor.userId,
          name: auditor.name,
          email: auditor.email,
          status: 'inactive',
          orgUnit: auditor.orgUnit,
          role: auditor.role,
          restrictedProcessOwners: auditor.restrictedProcessOwners,
          restrictedOrgUnits: auditor.restrictedOrgUnits,
          internalAuditorTrainingDate: auditor.internalAuditorTrainingDate,
          trainingType: auditor.trainingType,
          trainingDate: auditor.trainingDate,
          experienceYears: auditor.experienceYears,
          standardsKnowledge: auditor.standardsKnowledge,
          requalificationDueDate: auditor.requalificationDueDate,
          evidenceAttachments: auditor.evidenceAttachments,
          coAuditCount: auditor.coAuditCount,
          leadAuditCount: auditor.leadAuditCount,
        );
        await widget.api.saveAuditor(inactive);
        await _load();
      }
    }
  }
}

class _AnnualReportTab extends StatefulWidget {
  final AuditAdminApi api;
  final int? initialYear;
  const _AnnualReportTab({required this.api, this.initialYear});

  @override
  State<_AnnualReportTab> createState() => _AnnualReportTabState();
}

class _AnnualReportTabState extends State<_AnnualReportTab> {
  bool _loading = false;
  String? _error;
  List<AuditAnnualReport> _reports = const [];
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear ?? DateTime.now().year;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.listAnnualReports(_year);
      if (!mounted) return;
      setState(() {
        _reports = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      await widget.api.generateAnnualReport(_year);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jahresbericht erstellt')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorState(message: _error!, onRetry: _load);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              DropdownButton<int>(
                value: _year,
                onChanged: (v) => setState(() => _year = v ?? _year),
                items: List.generate(4, (i) => DateTime.now().year - 1 + i)
                    .map((y) => DropdownMenuItem(value: y, child: Text('Jahr $y')))
                    .toList(),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(onPressed: _generate, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Bericht erzeugen')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _reports.length,
            itemBuilder: (_, i) {
              final r = _reports[i];
              return Card(
                child: ListTile(
                  title: Text('Jahresbericht ${r.year}'),
                  subtitle: Text('Erstellt: ${r.generatedAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(r.generatedAt!.toLocal()) : '-'}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.download_outlined),
                    onPressed: (r.exportFiles.isEmpty)
                        ? null
                        : () {
                            final file = r.exportFiles.first;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download unter ${file.url}')));
                          },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuditEditorDialog extends StatefulWidget {
  final AuditAdminApi api;
  final List<Auditor> auditors;
  final Audit? existing;
  const _AuditEditorDialog({required this.api, required this.auditors, this.existing});

  @override
  State<_AuditEditorDialog> createState() => _AuditEditorDialogState();
}

class _AuditEditorDialogState extends State<_AuditEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _site;
  late final TextEditingController _scope;
  late final TextEditingController _orgUnit;
  DateTime? _start;
  DateTime? _end;
  String _cluster = 'Q1';
  String _status = 'planned';
  String? _lead;
  String? _coAuditor;
  bool _busy = false;
  String? _error;

  List<Auditor> get _eligibleAuditors {
    final orgUnit = _orgUnit.text.trim().toLowerCase();
    final scopeOrgUnits = {
      ...?widget.existing?.auditeesOrgUnits,
      if (orgUnit.isNotEmpty) _orgUnit.text.trim(),
    }.where((e) => e.trim().isNotEmpty).map((e) => e.toLowerCase()).toSet();
    final processOwners = widget.existing?.processOwners.map((e) => e.toLowerCase()) ?? const Iterable<String>.empty();
    return widget.auditors.where((a) {
      if (a.status.toLowerCase() != 'active') return false;
      if (!a.isQualified) return false;
      final auditorOrg = (a.orgUnit ?? '').toLowerCase();
      if (orgUnit.isNotEmpty && auditorOrg == orgUnit) return false;
      final restrictedOrgUnits = a.restrictedOrgUnits.map((e) => e.toLowerCase()).toList();
      if (scopeOrgUnits.any(restrictedOrgUnits.contains)) return false;
      final restrictedOwners = a.restrictedProcessOwners.map((e) => e.toLowerCase()).toList();
      if (processOwners.any(restrictedOwners.contains)) return false;
      return true;
    }).toList();
  }

  bool _isLeadAllowed(String? id) => id == null || _eligibleAuditors.any((a) => a.id == id);

  String _errorText(Object e) {
    if (e is ApiError) {
      if (e.details.isNotEmpty) return '${e.message}: ${e.details.join('; ')}';
      return e.message;
    }
    return e.toString();
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _site = TextEditingController(text: existing?.site ?? '');
    _scope = TextEditingController(text: existing?.scopeText ?? '');
    _orgUnit = TextEditingController(text: existing?.auditeesOrgUnits.isNotEmpty == true ? existing!.auditeesOrgUnits.first : '');
    _start = existing?.plannedStart;
    _end = existing?.plannedEnd;
    _cluster = existing?.cluster ?? 'Q1';
    _status = existing?.status ?? 'planned';
    _lead = existing?.leadAuditorId;
    _coAuditor = existing?.coAuditorId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Neues Audit' : 'Audit bearbeiten'),
      content: DialogContentScroll(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Titel')),
            const SizedBox(height: 12),
            TextField(controller: _site, decoration: const InputDecoration(labelText: 'Standort')),
            const SizedBox(height: 12),
            TextField(controller: _scope, maxLines: 3, decoration: const InputDecoration(labelText: 'Scope / Umfang')),
            const SizedBox(height: 12),
            TextField(
              controller: _orgUnit,
              decoration: const InputDecoration(labelText: 'OrgUnit / Bereich'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _cluster,
                    onChanged: (v) => setState(() => _cluster = v ?? 'Q1'),
                    decoration: const InputDecoration(labelText: 'Quartal'),
                    items: const ['Q1', 'Q2', 'Q3', 'Q4']
                        .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                        .toList(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    onChanged: (v) => setState(() => _status = v ?? 'planned'),
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const ['planned', 'inProgress', 'completed', 'closed', 'nachauditRequired']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(DateTime.now().year - 1, 1, 1),
                        lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                        initialDate: _start ?? DateTime.now(),
                      );
                      if (picked != null) setState(() => _start = picked);
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_start == null ? 'Start' : DateFormat('dd.MM.yyyy').format(_start!)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(DateTime.now().year - 1, 1, 1),
                        lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                        initialDate: _end ?? DateTime.now(),
                      );
                      if (picked != null) setState(() => _end = picked);
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_end == null ? 'Ende' : DateFormat('dd.MM.yyyy').format(_end!)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Builder(builder: (context) {
              var options = _eligibleAuditors;
              final selectedLead = widget.auditors.firstWhere(
                (a) => a.id == _lead,
                orElse: () => const Auditor(id: '', name: '', email: '', status: 'inactive'),
              );
              final selectedCo = widget.auditors.firstWhere(
                (a) => a.id == _coAuditor,
                orElse: () => const Auditor(id: '', name: '', email: '', status: 'inactive'),
              );
              if (_lead != null && options.every((a) => a.id != selectedLead.id)) {
                options = [...options, selectedLead];
              }
              if (_coAuditor != null && options.every((a) => a.id != selectedCo.id)) {
                options = [...options, selectedCo];
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String?>(
                    value: _lead,
                    decoration: const InputDecoration(labelText: 'Lead Auditor'),
                    onChanged: (v) {
                      if (!_isLeadAllowed(v)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Unabhängigkeit verletzt oder Auditor nicht qualifiziert.')),
                        );
                        return;
                      }
                      setState(() => _lead = v);
                    },
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Noch nicht zugewiesen')),
                      ...options
                          .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} (${a.orgUnit ?? '-'})')))
                          .toList(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: _coAuditor,
                    decoration: const InputDecoration(labelText: 'Co-Auditor'),
                    onChanged: (v) => setState(() => _coAuditor = v),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Kein Co-Auditor')),
                      ...options
                          .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} (${a.orgUnit ?? '-'})')))
                          .toList(),
                    ],
                  ),
                  if (_eligibleAuditors.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                const Text('Keine unabhängigen Auditoren verfügbar.'),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    Navigator.of(context, rootNavigator: true).pushNamed('/admin/audits/matrix');
                                  },
                                  child: const Text('Auditorenmatrix öffnen'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Speichern'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_isLeadAllowed(_lead)) {
      setState(() => _error = 'Unabhängiger, qualifizierter Lead Auditor erforderlich.');
      return;
    }
    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      final audit = Audit(
        id: existing?.id ?? '',
        auditNumber: existing?.auditNumber ?? 'TEMP-${DateTime.now().millisecondsSinceEpoch}',
        year: existing?.year ?? DateTime.now().year,
        cluster: _cluster,
        auditType: existing?.auditType ?? 'System',
        title: _title.text.trim(),
        site: _site.text.trim().isEmpty ? null : _site.text.trim(),
        plannedStart: _start,
        plannedEnd: _end,
        actualStart: existing?.actualStart,
        actualEnd: existing?.actualEnd,
        status: _status,
        scopeText: _scope.text.trim().isEmpty ? null : _scope.text.trim(),
        objectives: existing?.objectives ?? const [],
        criteria: existing?.criteria ?? const [],
        references: existing?.references ?? const [],
        auditeesOrgUnits: _orgUnit.text.trim().isEmpty
            ? (existing?.auditeesOrgUnits ?? const [])
            : [_orgUnit.text.trim()],
        processOwners: existing?.processOwners ?? const [],
        participants: existing?.participants ?? const [],
        leadAuditorId: _lead,
        coAuditorId: _coAuditor,
        linkedDocs: existing?.linkedDocs ?? const [],
        findings: existing?.findings ?? const [],
        actions: existing?.actions ?? const [],
        openFindings: existing?.openFindings,
        overdueActions: existing?.overdueActions,
      );
      Audit saved;
      if (existing == null) {
        saved = await widget.api.createAudit(audit);
      } else {
        saved = await widget.api.updateAudit(audit);
      }
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _error = _errorText(e));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error!)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _site.dispose();
    _scope.dispose();
    _orgUnit.dispose();
    super.dispose();
  }
}

class _AuditDetailPage extends StatefulWidget {
  final AuditAdminApi api;
  final Audit audit;
  const _AuditDetailPage({required this.api, required this.audit});

  @override
  State<_AuditDetailPage> createState() => _AuditDetailPageState();
}

class _AuditDetailPageState extends State<_AuditDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Audit? _audit;
  List<Auditor> _auditors = const [];
  List<AuditFinding> _findings = const [];
  List<AuditAction> _actions = const [];
  final List<_AuditPlanEntry> _planEntries = [];
  _AuditReportDraft _reportDraft = _AuditReportDraft.empty();
  bool _loading = true;
  bool _planSaving = false;
  bool _planLoaded = false;
  String? _error;

  String _planErrorMessage(Object error) {
    if (error is ApiError) {
      if (error.status == 404) return 'Auditplan nicht gefunden (404).';
      return 'Auditplan konnte nicht geladen werden: ${error.message}';
    }
    return 'Auditplan konnte nicht geladen werden: $error';
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_planLoaded) {
        _loadPlanEntries();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _planLoaded = false;
    });
    try {
      final audits = await widget.api.listAudits(year: widget.audit.year);
      final audit = audits.firstWhere((a) => a.id == widget.audit.id, orElse: () => widget.audit);
      final auditorsFuture = widget.api.listAuditors();
      final findingsFuture = widget.api.listFindings(widget.audit.id);
      final actionsFuture = widget.api.listActions(widget.audit.id);
      final planFuture = widget.api.loadAuditPlan(widget.audit.id);
      final auditors = await auditorsFuture;
      final findings = await findingsFuture;
      final actions = await actionsFuture;
      final planEntries = await planFuture;
      if (!mounted) return;
      setState(() {
        _audit = audit;
        _auditors = auditors;
        _findings = findings;
        _actions = actions;
        _applyPlan(planEntries);
        _reportDraft = _reportDraft;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _planErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadPlanEntries() async {
    if (_audit == null) return;
    try {
      final planEntries = await widget.api.loadAuditPlan(_audit!.id);
      if (!mounted) return;
      setState(() {
        _applyPlan(planEntries);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _planErrorMessage(e));
    }
  }

  Auditor? _findAuditor(String? id) {
    if (id == null || id.isEmpty) return null;
    return _auditors.cast<Auditor?>().firstWhere((a) => a?.id == id, orElse: () => null);
  }

  String? _auditorName(String? id) => _findAuditor(id)?.name;

  void _applyPlan(List<AuditPlanEntry> planEntries) {
    _planEntries
      ..clear()
      ..addAll(planEntries.map(_mapPlan));
    _planLoaded = true;
    _syncPlanAuditorSelection();
  }

  void _syncPlanAuditorSelection() {
    final leadId = _audit?.leadAuditorId;
    final coId = _audit?.coAuditorId;
    for (final entry in _planEntries) {
      if ((entry.auditorId == null || entry.auditorId!.isEmpty) && coId == null && leadId != null) {
        entry.auditorId = leadId;
      }
      final name = _auditorName(entry.auditorId);
      if (name != null && name.isNotEmpty) {
        entry.auditor = name;
      }
    }
  }

  List<Auditor> _planAuditorOptions() {
    final options = <Auditor>[];
    final lead = _findAuditor(_audit?.leadAuditorId);
    final co = _findAuditor(_audit?.coAuditorId);
    if (lead != null) options.add(lead);
    if (co != null && co.id != lead?.id) options.add(co);
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final title = _audit?.title ?? widget.audit.auditNumber;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Audit löschen',
            onPressed: _audit == null ? null : _confirmDelete,
            icon: const Icon(Icons.delete_outline),
          )
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Plan'),
            Tab(text: 'Auditplan'),
            Tab(text: 'Auditbericht'),
            Tab(text: 'Findings'),
            Tab(text: 'Maßnahmen'),
            Tab(text: 'Historie'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildPlan(),
                    _buildSchedule(),
                    _buildReport(),
                    _buildFindings(),
                    _buildActions(),
                    _buildHistory(),
                  ],
                ),
    );
  }

  Widget _buildPlan() {
    if (_audit == null) return const SizedBox();
    final audit = _audit!;
    final lead = _auditors
        .firstWhere((a) => a.id == audit.leadAuditorId, orElse: () => const Auditor(id: '', name: '-', email: '', status: 'inactive'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(title: const Text('Auditnummer'), subtitle: Text(audit.auditNumber)),
        ListTile(title: const Text('Quartal'), subtitle: Text(audit.cluster ?? '-')),
        ListTile(title: const Text('Zeitraum geplant'), subtitle: Text(audit.displayPeriod)),
        ListTile(title: const Text('Lead Auditor'), subtitle: Text(lead.name)),
        ListTile(title: const Text('Scope'), subtitle: Text(audit.scopeText ?? '-')),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: audit.objectives.map((o) => Chip(label: Text(o))).toList(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => _openEditor(), icon: const Icon(Icons.edit_outlined), label: const Text('Plan bearbeiten')),
      ],
    );
  }

  bool get _isClosed {
    final status = (_audit?.status ?? '').toLowerCase();
    return status == 'closed' || status == 'archived';
  }

  _AuditPlanEntry _mapPlan(AuditPlanEntry p) => _AuditPlanEntry(
        from: p.from,
        to: p.to,
        agenda: p.agenda,
        process: p.process,
        participants: p.participants,
        auditor: p.auditor,
        auditorId: p.auditorId,
        reference: p.reference,
        notes: p.notes,
        done: p.done,
      );

  AuditPlanEntry _mapPlanBack(_AuditPlanEntry p) => AuditPlanEntry(
        from: p.from,
        to: p.to,
        agenda: p.agenda,
        process: p.process,
        participants: p.participants,
        auditor: p.auditor,
        auditorId: p.auditorId,
        reference: p.reference,
        notes: p.notes,
        done: p.done,
      );

  Audit _auditWith({String? status, List<AuditPlanEntry>? plan}) {
    final current = _audit!;
    return Audit(
      id: current.id,
      auditNumber: current.auditNumber,
      year: current.year,
      cluster: current.cluster,
      auditType: current.auditType,
      title: current.title,
      site: current.site,
      plannedStart: current.plannedStart,
      plannedEnd: current.plannedEnd,
      actualStart: current.actualStart,
      actualEnd: current.actualEnd,
      status: status ?? current.status,
      scopeText: current.scopeText,
      objectives: current.objectives,
      criteria: current.criteria,
      references: current.references,
      auditeesOrgUnits: current.auditeesOrgUnits,
      processOwners: current.processOwners,
      participants: current.participants,
      leadAuditorId: current.leadAuditorId,
      coAuditorId: current.coAuditorId,
      linkedDocs: current.linkedDocs,
      findings: current.findings,
      actions: current.actions,
      openFindings: current.openFindings,
      overdueActions: current.overdueActions,
      planEntries: plan ?? _planEntries.map(_mapPlanBack).toList(),
    );
  }

  Future<void> _savePlan() async {
    if (_audit == null || _planSaving) return;
    setState(() => _planSaving = true);
    try {
      final savedPlan = await widget.api.saveAuditPlan(_audit!.id, _planEntries.map(_mapPlanBack).toList());
      if (!mounted) return;
      setState(() {
        _applyPlan(savedPlan);
        _audit = _auditWith(plan: savedPlan);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auditplan gespeichert.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _planSaving = false);
    }
  }

  Widget _buildSchedule() {
    _syncPlanAuditorSelection();
    final auditorOptions = _planAuditorOptions();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Auditplan (täglich)', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (!_isClosed)
              FilledButton.icon(
                onPressed: () => setState(() => _planEntries.add(_AuditPlanEntry())),
                icon: const Icon(Icons.add),
                label: const Text('Zeile hinzufügen'),
              ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _isClosed || _planEntries.isEmpty || _planSaving ? null : _savePlan,
              icon: _planSaving
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Plan speichern'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Zeit von')),
                DataColumn(label: Text('Zeit bis')),
                DataColumn(label: Text('Agenda')),
                DataColumn(label: Text('Prozess/Bereich')),
                DataColumn(label: Text('Teilnehmer')),
                DataColumn(label: Text('Auditor')),
                DataColumn(label: Text('Norm / Referenz')),
                DataColumn(label: Text('Notizen')),
                DataColumn(label: Text('abgehakt')),
                DataColumn(label: Text('')),
              ],
              rows: _planEntries
                  .map(
                    (e) {
                      final editable = !_isClosed && !e.done;
                      final selection =
                          e.auditorId?.isNotEmpty == true ? e.auditorId : (auditorOptions.length == 1 ? auditorOptions.first.id : null);
                      if (selection != null && e.auditorId != selection) {
                        e.auditorId = selection;
                        e.auditor = _auditorName(selection) ?? e.auditor;
                      }
                      return DataRow(
                        color: MaterialStateProperty.resolveWith(
                          (states) => e.done ? Colors.grey.shade200 : null,
                        ),
                        cells: [
                          DataCell(
                            _TimeCell(initialValue: e.from, enabled: editable, onChanged: (v) => setState(() => e.from = v)),
                          ),
                          DataCell(
                            _TimeCell(initialValue: e.to, enabled: editable, onChanged: (v) => setState(() => e.to = v)),
                          ),
                          DataCell(_EditableCell(initialValue: e.agenda, enabled: editable, onSaved: (v) => e.agenda = v)),
                          DataCell(_EditableCell(initialValue: e.process, enabled: editable, onSaved: (v) => e.process = v)),
                          DataCell(
                              _EditableCell(initialValue: e.participants, enabled: editable, onSaved: (v) => e.participants = v)),
                          DataCell(
                            auditorOptions.isEmpty
                                ? Text(e.auditor.isNotEmpty ? e.auditor : '-')
                                : DropdownButton<String>(
                                    value: selection,
                                    hint: const Text('Auditor wählen'),
                                    onChanged: !editable
                                        ? null
                                        : (value) => setState(() {
                                              e.auditorId = value;
                                              e.auditor = _auditorName(value) ?? e.auditor;
                                            }),
                                    items: auditorOptions
                                        .map((a) => DropdownMenuItem<String>(value: a.id, child: Text(a.name)))
                                        .toList(),
                                  ),
                          ),
                          DataCell(_EditableCell(initialValue: e.reference, enabled: editable, onSaved: (v) => e.reference = v)),
                          DataCell(_EditableCell(initialValue: e.notes, enabled: editable, onSaved: (v) => e.notes = v)),
                          DataCell(
                            Checkbox(
                              value: e.done,
                              onChanged: _isClosed
                                  ? null
                                  : (value) => setState(() {
                                        e.done = value ?? false;
                                      }),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              onPressed: _isClosed
                                  ? null
                                  : () => setState(() => _planEntries.remove(e)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Der Plan wird auditbezogen gespeichert und kann exportiert werden.', style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }

  Future<void> _archiveAudit() async {
    if (_audit == null) return;
    try {
      final saved = await widget.api.updateAudit(_auditWith(status: 'archived'));
      if (!mounted) return;
      setState(() => _audit = saved);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audit archiviert.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmDelete() async {
    if (_audit == null) return;
    final hasBlocking = _findings.isNotEmpty || _actions.isNotEmpty;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(hasBlocking ? 'Löschen nicht möglich' : 'Audit löschen?'),
        content: Text(hasBlocking
            ? 'Das Audit enthält bereits Findings oder Maßnahmen und kann nicht gelöscht werden.'
            : 'Möchten Sie dieses Audit endgültig löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          if (hasBlocking)
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
                _archiveAudit();
              },
              child: const Text('Archivieren'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen'),
            ),
        ],
      ),
    );
    if (shouldDelete == true) {
      try {
        await widget.api.deleteAudit(_audit!.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audit gelöscht.')));
        Navigator.of(context).pop(true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _buildReport() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Auditbericht', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (_isClosed) const Chip(label: Text('Abgeschlossen')), // read-only indicator
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: !_isClosed,
          controller: TextEditingController(text: _reportDraft.summary),
          onChanged: (v) => _reportDraft.summary = v,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Zusammenfassung'),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: !_isClosed,
          controller: TextEditingController(text: _reportDraft.scopeEvaluation),
          onChanged: (v) => _reportDraft.scopeEvaluation = v,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Scope-Bewertung'),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: !_isClosed,
          controller: TextEditingController(text: _reportDraft.findings),
          onChanged: (v) => _reportDraft.findings = v,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Findings / Beobachtungen'),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: !_isClosed,
          controller: TextEditingController(text: _reportDraft.conclusion),
          onChanged: (v) => _reportDraft.conclusion = v,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Gesamtfazit'),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _reportDraft.followUpRecommended,
          onChanged: _isClosed ? null : (v) => setState(() => _reportDraft.followUpRecommended = v),
          title: const Text('Nachaudit empfohlen'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._reportDraft.evidence.map((f) => Chip(label: Text(f))),
            if (!_isClosed)
              OutlinedButton.icon(
                onPressed: () => setState(() => _reportDraft.evidence = [..._reportDraft.evidence, 'Evidence_${_reportDraft.evidence.length + 1}.pdf']),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Nachweis hinzufügen'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF Export')),
            const SizedBox(width: 12),
            OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.description_outlined), label: const Text('DOCX Export')),
          ],
        ),
      ],
    );
  }

  Widget _buildFindings() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              FilledButton.icon(onPressed: _addFinding, icon: const Icon(Icons.add_alert_outlined), label: const Text('Finding anlegen')),
              const Spacer(),
              Text('Anzahl: ${_findings.length}'),
            ],
          ),
        ),
        Expanded(
          child: _findings.isEmpty
              ? const Center(child: Text('Keine Findings erfasst.'))
              : ListView.builder(
                  itemCount: _findings.length,
                  itemBuilder: (_, i) {
                    final f = _findings[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        title: Text('${f.type} – ${f.description}'),
                        subtitle: Text(f.requirementRef ?? '-'),
                        trailing: _StatusChip(status: f.status),
                        onTap: () => _editFinding(f),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              FilledButton.icon(onPressed: _addAction, icon: const Icon(Icons.add_task_outlined), label: const Text('Maßnahme anlegen')),
              const Spacer(),
              Text('Offen: ${_actions.where((a) => a.status != 'done' && a.status != 'closed').length}'),
            ],
          ),
        ),
        Expanded(
          child: _actions.isEmpty
              ? const Center(child: Text('Keine Maßnahmen erfasst.'))
              : ListView.builder(
                  itemCount: _actions.length,
                  itemBuilder: (_, i) {
                    final a = _actions[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        title: Text('${a.actionType} – ${a.description}'),
                        subtitle: Text('Fällig: ${a.dueDate != null ? DateFormat('dd.MM.yyyy').format(a.dueDate!) : '-'}'),
                        trailing: _StatusChip(status: a.status),
                        onTap: () => _editAction(a),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ListTile(title: Text('Historie'), subtitle: Text('Audit-Trail ist read-only.')),
        ..._findings.map((f) => ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text('Finding ${f.type}'),
              subtitle: Text(f.description),
            )),
        ..._actions.map((a) => ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: Text('Action ${a.status}'),
              subtitle: Text(a.description),
            )),
      ],
    );
  }

  Future<void> _openEditor() async {
    if (_audit == null) return;
    final updated = await showDialog<Audit>(
      context: context,
      builder: (_) => _AuditEditorDialog(api: widget.api, auditors: _auditors, existing: _audit),
    );
    if (updated != null) _load();
  }

  Future<void> _addFinding() async {
    final saved = await showDialog<AuditFinding>(
      context: context,
      builder: (_) => _FindingDialog(api: widget.api, auditId: widget.audit.id),
    );
    if (saved != null) _load();
  }

  Future<void> _editFinding(AuditFinding f) async {
    final saved = await showDialog<AuditFinding>(
      context: context,
      builder: (_) => _FindingDialog(api: widget.api, auditId: widget.audit.id, existing: f),
    );
    if (saved != null) _load();
  }

  Future<void> _addAction() async {
    final saved = await showDialog<AuditAction>(
      context: context,
      builder: (_) => _ActionDialog(api: widget.api, auditId: widget.audit.id, findings: _findings),
    );
    if (saved != null) _load();
  }

  Future<void> _editAction(AuditAction a) async {
    final saved = await showDialog<AuditAction>(
      context: context,
      builder: (_) => _ActionDialog(api: widget.api, auditId: widget.audit.id, findings: _findings, existing: a),
    );
    if (saved != null) _load();
  }
}

class _FindingDialog extends StatefulWidget {
  final AuditAdminApi api;
  final String auditId;
  final AuditFinding? existing;
  const _FindingDialog({required this.api, required this.auditId, this.existing});

  @override
  State<_FindingDialog> createState() => _FindingDialogState();
}

class _FindingDialogState extends State<_FindingDialog> {
  late final TextEditingController _desc;
  late final TextEditingController _ref;
  String _type = 'Minor';
  String _status = 'open';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    _desc = TextEditingController(text: f?.description ?? '');
    _ref = TextEditingController(text: f?.requirementRef ?? '');
    _type = f?.type ?? 'Minor';
    _status = f?.status ?? 'open';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Finding anlegen' : 'Finding bearbeiten'),
      content: DialogContentScroll(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Einstufung'),
              onChanged: (v) => setState(() => _type = v ?? 'Minor'),
              items: const ['Konformität', 'Hinweis', 'Minor', 'Major', 'Critical']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(controller: _ref, decoration: const InputDecoration(labelText: 'Referenz / Kapitel')),
            const SizedBox(height: 12),
            TextField(controller: _desc, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Beschreibung')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              onChanged: (v) => setState(() => _status = v ?? 'open'),
              items: const ['open', 'accepted', 'convertedToCapa', 'closed']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Speichern'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await widget.api.saveFinding(AuditFinding(
        id: widget.existing?.id ?? '',
        auditId: widget.auditId,
        type: _type,
        description: _desc.text.trim(),
        requirementRef: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
        evidenceText: widget.existing?.evidenceText,
        linkedComplaintIds: widget.existing?.linkedComplaintIds ?? const [],
        linkedCapaIds: widget.existing?.linkedCapaIds ?? const [],
        ownerOrgUnit: widget.existing?.ownerOrgUnit,
        processOwner: widget.existing?.processOwner,
        createdInMeeting: widget.existing?.createdInMeeting,
        status: _status,
      ));
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ActionDialog extends StatefulWidget {
  final AuditAdminApi api;
  final String auditId;
  final List<AuditFinding> findings;
  final AuditAction? existing;
  const _ActionDialog({required this.api, required this.auditId, required this.findings, this.existing});

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  late final TextEditingController _desc;
  String? _findingId;
  String _type = 'Korrektur';
  String _status = 'open';
  DateTime? _due;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _desc = TextEditingController(text: a?.description ?? '');
    _findingId = a?.findingId;
    _type = a?.actionType ?? 'Korrektur';
    _status = a?.status ?? 'open';
    _due = a?.dueDate;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Maßnahme anlegen' : 'Maßnahme bearbeiten'),
      content: DialogContentScroll(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Maßnahmentyp'),
              onChanged: (v) => setState(() => _type = v ?? 'Korrektur'),
              items: const ['Korrektur', 'CAPA', 'Sofortmaßnahme', 'Nachaudit-Action']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _findingId,
              decoration: const InputDecoration(labelText: 'Finding Bezug'),
              onChanged: (v) => setState(() => _findingId = v),
              items: [const DropdownMenuItem(value: null, child: Text('Kein direktes Finding')),
                ...widget.findings.map((f) => DropdownMenuItem(value: f.id, child: Text(f.description, overflow: TextOverflow.ellipsis)))],
            ),
            const SizedBox(height: 12),
            TextField(controller: _desc, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Beschreibung')),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(DateTime.now().year - 1, 1, 1),
                  lastDate: DateTime(DateTime.now().year + 2, 12, 31),
                  initialDate: _due ?? DateTime.now(),
                );
                if (picked != null) setState(() => _due = picked);
              },
              icon: const Icon(Icons.event_note_outlined),
              label: Text(_due == null ? 'Fälligkeitsdatum' : DateFormat('dd.MM.yyyy').format(_due!)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              onChanged: (v) => setState(() => _status = v ?? 'open'),
              items: const ['open', 'inWork', 'done', 'overdue', 'ineffective', 'closed']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Speichern'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await widget.api.saveAction(AuditAction(
        id: widget.existing?.id ?? '',
        auditId: widget.auditId,
        findingId: _findingId?.isEmpty == true ? null : _findingId,
        actionType: _type,
        description: _desc.text.trim(),
        responsibleUserId: widget.existing?.responsibleUserId,
        responsibleOrgUnit: widget.existing?.responsibleOrgUnit,
        dueDate: _due,
        completedAt: widget.existing?.completedAt,
        effectivenessCheckRequired: widget.existing?.effectivenessCheckRequired ?? false,
        effectivenessCheckMethod: widget.existing?.effectivenessCheckMethod,
        effectivenessCheckedAt: widget.existing?.effectivenessCheckedAt,
        effectivenessResult: widget.existing?.effectivenessResult,
        escalationLevel: widget.existing?.escalationLevel ?? 'none',
        escalationReason: widget.existing?.escalationReason,
        status: _status,
      ));
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_outlined), label: const Text('Erneut versuchen')),
          ]
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _KpiCard({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  final String initialValue;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _TimeCell({required this.initialValue, required this.enabled, required this.onChanged});

  TimeOfDay _parse(String value) {
    final parts = value.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  String _format(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final display = initialValue.isEmpty ? '--:--' : initialValue;
    return TextButton(
      onPressed: !enabled
          ? null
          : () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: initialValue.isEmpty ? TimeOfDay.now() : _parse(initialValue),
              );
              if (picked != null) onChanged(_format(picked));
            },
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
      child: Text(display),
    );
  }
}

class _EditableCell extends StatefulWidget {
  final String initialValue;
  final bool enabled;
  final ValueChanged<String> onSaved;
  const _EditableCell({required this.initialValue, required this.enabled, required this.onSaved});

  @override
  State<_EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<_EditableCell> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _EditableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      onChanged: widget.onSaved,
      decoration: const InputDecoration(border: InputBorder.none, isDense: true),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color? color;
    switch (status) {
      case 'planned':
        color = Colors.blueGrey;
        break;
      case 'inProgress':
        color = Colors.blue;
        break;
      case 'completed':
        color = Colors.green;
        break;
      case 'closed':
        color = Colors.black87;
        break;
      case 'nachauditRequired':
        color = Colors.deepOrange;
        break;
      default:
        color = Colors.grey;
    }
    return Chip(
      backgroundColor: color.withOpacity(0.12),
      label: Text(status),
      labelStyle: TextStyle(color: color),
    );
  }
}

