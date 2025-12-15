import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/audit_admin_api.dart';
import '../api/client.dart';
import '../models/audit.dart';
import '../widgets/dialog_content_scroll.dart';
import '../widgets/legal_footer.dart';

class AdminAuditsPage extends StatefulWidget {
  final ApiClient api;
  const AdminAuditsPage({super.key, required this.api});

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
    _tabs = TabController(length: 4, vsync: this);
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
          _AnnualReportTab(api: _auditApi),
        ],
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
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

class _AuditOverviewTabState extends State<_AuditOverviewTab> {
  bool _loading = false;
  String? _error;
  List<Audit> _audits = const [];
  List<Auditor> _auditors = const [];

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

  int _countOpenFindings() => _audits.fold<int>(0, (p, a) => p + a.openFindings);
  int _countOverdueActions() => _audits.fold<int>(0, (p, a) => p + a.overdueActions);
  int _countCritical() => _audits.where((a) => a.status == 'nachauditRequired' || a.riskPriority == 5).length;

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
                      DataCell(Text(a.cluster)),
                      DataCell(Text(a.displayPeriod)),
                      DataCell(_StatusChip(status: a.status)),
                      DataCell(Text(_auditors.firstWhere((au) => au.id == a.leadAuditorId, orElse: () => const Auditor(id: '', name: '-', email: '')).name)),
                      DataCell(Text(a.openFindings.toString())),
                      DataCell(Text(a.overdueActions.toString(), style: TextStyle(color: a.overdueActions > 0 ? Colors.red : null))),
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
        final lead = _auditors.firstWhere((au) => au.id == a.leadAuditorId, orElse: () => const Auditor(id: '', name: '-', email: ''));
        return Card(
          child: ListTile(
            title: Text('${a.auditNumber} · ${a.title}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.cluster} · ${a.displayPeriod}'),
                const SizedBox(height: 4),
                Text('Lead: ${lead.name}'),
                Text('Findings: ${a.openFindings}, Überfällig: ${a.overdueActions}')
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
    final parent = DefaultTabController.maybeOf(context);
    parent?.animateTo(1);
  }

  void _openReports() {
    final parent = DefaultTabController.maybeOf(context);
    parent?.animateTo(3);
  }

  void _openDetail(Audit audit) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AuditDetailPage(api: widget.api, auditId: audit.id, auditNumber: audit.auditNumber),
      ),
    );
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
      final data = await widget.api.listAuditors();
      if (!mounted) return;
      setState(() {
        _auditors = data;
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, i) {
        final a = _auditors[i];
        final due = a.requalificationDueDate;
        final warn = due != null && due.isBefore(DateTime.now());
        return Card(
          child: ListTile(
            leading: Icon(Icons.badge_outlined, color: warn ? Colors.red : null),
            title: Text(a.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.email),
                Text('Qualifiziert: ${a.qualifications['qualified'] == true ? 'Ja' : 'Nein'}'),
                if (a.independenceRules.isNotEmpty)
                  Text('Restriktionen: ${(a.independenceRules['restrictedOrgUnits'] as List?)?.join(', ') ?? '-'}'),
                if (due != null) Text('Re-Qual fällig: ${DateFormat('dd.MM.yyyy').format(due)}', style: TextStyle(color: warn ? Colors.red : null)),
              ],
            ),
            trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editAuditor(a)),
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: _auditors.length,
    );
  }

  Future<void> _editAuditor(Auditor auditor) async {
    final nameCtrl = TextEditingController(text: auditor.name);
    final deptCtrl = TextEditingController(text: auditor.department ?? '');
    final updated = await showDialog<Auditor>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Auditor bearbeiten'),
        content: DialogContentScroll(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(controller: deptCtrl, decoration: const InputDecoration(labelText: 'Bereich/OrgUnit')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () async {
              final body = {
                'id': auditor.id,
                'name': nameCtrl.text.trim(),
                'orgUnit': deptCtrl.text.trim(),
              };
              try {
                final saved = await widget.api.updateAuditor(auditor.id, body);
                if (context.mounted) Navigator.pop(context, saved);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (updated != null) _load();
  }
}

class _AnnualReportTab extends StatefulWidget {
  final AuditAdminApi api;
  const _AnnualReportTab({required this.api});

  @override
  State<_AnnualReportTab> createState() => _AnnualReportTabState();
}

class _AnnualReportTabState extends State<_AnnualReportTab> {
  bool _loading = false;
  String? _error;
  List<AuditAnnualReport> _reports = const [];
  int _year = DateTime.now().year;

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
      final list = await widget.api.listAnnualReports(year: _year);
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
      await widget.api.generateReport({'year': _year});
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
  DateTime? _start;
  DateTime? _end;
  String _cluster = 'Q1';
  String _status = 'planned';
  String? _lead;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _site = TextEditingController(text: existing?.site ?? '');
    _scope = TextEditingController(text: existing?.scopeText ?? '');
    _start = existing?.plannedStart;
    _end = existing?.plannedEnd;
    _cluster = existing?.cluster ?? 'Q1';
    _status = existing?.status ?? 'planned';
    _lead = existing?.leadAuditorId;
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
            DropdownButtonFormField<String?>(
              value: _lead,
              decoration: const InputDecoration(labelText: 'Lead Auditor'),
              onChanged: (v) => setState(() => _lead = v),
              items: [const DropdownMenuItem(value: null, child: Text('Noch nicht zugewiesen')),
                ...widget.auditors.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))],
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
      final payload = {
        'title': _title.text.trim(),
        'site': _site.text.trim(),
        'scopeText': _scope.text.trim(),
        'cluster': _cluster,
        'status': _status,
        if (_start != null) 'plannedStart': _start!.toIso8601String(),
        if (_end != null) 'plannedEnd': _end!.toIso8601String(),
        if (_lead != null) 'leadAuditorId': _lead,
      };
      Audit saved;
      if (widget.existing == null) {
        saved = await widget.api.saveAudit(payload);
      } else {
        saved = await widget.api.updateAudit(widget.existing!.id, payload);
      }
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AuditDetailPage extends StatefulWidget {
  final AuditAdminApi api;
  final String auditId;
  final String auditNumber;
  const _AuditDetailPage({required this.api, required this.auditId, required this.auditNumber});

  @override
  State<_AuditDetailPage> createState() => _AuditDetailPageState();
}

class _AuditDetailPageState extends State<_AuditDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Audit? _audit;
  List<Auditor> _auditors = const [];
  List<AuditFinding> _findings = const [];
  List<AuditAction> _actions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
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
    });
    try {
      final audit = await widget.api.getAudit(widget.auditId);
      final auditors = await widget.api.listAuditors();
      final findings = await widget.api.listFindings(widget.auditId);
      final actions = await widget.api.listActions(widget.auditId);
      if (!mounted) return;
      setState(() {
        _audit = audit;
        _auditors = auditors;
        _findings = findings;
        _actions = actions;
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
    final title = _audit?.title ?? widget.auditNumber;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Plan'),
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
    final lead = _auditors.firstWhere((a) => a.id == audit.leadAuditorId, orElse: () => const Auditor(id: '', name: '-', email: ''));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(title: const Text('Auditnummer'), subtitle: Text(audit.auditNumber)),
        ListTile(title: const Text('Quartal'), subtitle: Text(audit.cluster)),
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
      builder: (_) => _FindingDialog(api: widget.api, auditId: widget.auditId),
    );
    if (saved != null) _load();
  }

  Future<void> _editFinding(AuditFinding f) async {
    final saved = await showDialog<AuditFinding>(
      context: context,
      builder: (_) => _FindingDialog(api: widget.api, auditId: widget.auditId, existing: f),
    );
    if (saved != null) _load();
  }

  Future<void> _addAction() async {
    final saved = await showDialog<AuditAction>(
      context: context,
      builder: (_) => _ActionDialog(api: widget.api, auditId: widget.auditId, findings: _findings),
    );
    if (saved != null) _load();
  }

  Future<void> _editAction(AuditAction a) async {
    final saved = await showDialog<AuditAction>(
      context: context,
      builder: (_) => _ActionDialog(api: widget.api, auditId: widget.auditId, findings: _findings, existing: a),
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
      final payload = {
        'auditId': widget.auditId,
        'type': _type,
        'description': _desc.text.trim(),
        'requirementRef': _ref.text.trim(),
        'status': _status,
      };
      AuditFinding saved;
      if (widget.existing == null) {
        saved = await widget.api.saveFinding(payload);
      } else {
        saved = await widget.api.updateFinding(widget.existing!.id, payload);
      }
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
      final payload = {
        'auditId': widget.auditId,
        'findingId': _findingId,
        'description': _desc.text.trim(),
        'actionType': _type,
        'status': _status,
        if (_due != null) 'dueDate': _due!.toIso8601String(),
      };
      AuditAction saved;
      if (widget.existing == null) {
        saved = await widget.api.saveAction(payload);
      } else {
        saved = await widget.api.updateAction(widget.existing!.id, payload);
      }
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

