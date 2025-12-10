import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/capa_report.dart';
import '../widgets/date_field.dart';

class CapaDetailPage extends StatefulWidget {
  final ApiClient api;
  final CapaReport? initialReport;
  final bool canWrite;
  final Map<String, String>? complaintPrefill;
  final String? complaintId;
  final String? complaintLabel;

  const CapaDetailPage({
    super.key,
    required this.api,
    this.initialReport,
    this.canWrite = false,
    this.complaintPrefill,
    this.complaintId,
    this.complaintLabel,
  });

  @override
  State<CapaDetailPage> createState() => _CapaDetailPageState();
}

class _CapaDetailPageState extends State<CapaDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late CapaReport _report;
  bool _saving = false;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport ??
        CapaReport(
          complaintId: widget.complaintId ?? '',
          sections: CapaSections(
            product: widget.complaintPrefill?['product'] ?? '',
            batch: widget.complaintPrefill?['batch'] ?? '',
            problem: widget.complaintPrefill?['problem'] ?? '',
          ),
          title: widget.complaintPrefill?['title'] ?? '',
        );
    _tabController = TabController(length: 8, vsync: this);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      CapaReport saved;
      if ((_report.id).isEmpty) {
        saved = await widget.api.adminSaveCapa(_report);
      } else {
        saved = await widget.api.adminUpdateCapa(_report);
      }
      setState(() => _report = saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CAPA gespeichert.')));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _export(String lang) async {
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final id = _report.id.isNotEmpty ? _report.id : _report.capaNumber;
      if (id.isEmpty) throw Exception('Bitte zuerst speichern.');
      final bytes = await widget.api.adminCapaPdf(id: id, lang: lang);
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..download = '${_report.effectiveNumber}_${lang.toUpperCase()}.pdf'
        ..target = '_blank'
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _exporting = false);
    }
  }

  void _updateSections(CapaSections Function(CapaSections) updater) {
    setState(() => _report = _report.copyWith(sections: updater(_report.sections)));
  }

  void _updateReport({String? title, String? status, String? responsible}) {
    setState(() => _report = _report.copyWith(
          title: title ?? _report.title,
          status: status ?? _report.status,
          responsibleUserId: responsible ?? _report.responsibleUserId,
        ));
  }

  Widget _sectionContainer({required String title, required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTeamMembers() {
    final members = _report.sections.teamMembers;
    return Column(
      children: [
        for (final entry in members.asMap().entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: entry.value.name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          teamMembers: updateList(s.teamMembers, entry.key, (old) => old.copyWith(name: v)),
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: entry.value.role,
                    decoration: const InputDecoration(labelText: 'Funktion'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          teamMembers: updateList(s.teamMembers, entry.key, (old) => old.copyWith(role: v)),
                        )),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: members.length <= 1
                      ? null
                      : () => _updateSections((s) {
                            final copy = [...s.teamMembers];
                            copy.removeAt(entry.key);
                            return s.copyWith(teamMembers: copy);
                          }),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _updateSections(
              (s) => s.copyWith(teamMembers: [...s.teamMembers, const CapaTeamMember()]),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Mitglied hinzufügen'),
          ),
        ),
      ],
    );
  }

  Widget _buildImmediateActions() {
    final actions = _report.sections.immediateActions;
    return Column(
      children: [
        for (final entry in actions.asMap().entries)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: entry.value.action,
                    decoration: const InputDecoration(labelText: 'Sofortmaßnahme'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          immediateActions: updateList(s.immediateActions, entry.key, (old) => old.copyWith(action: v)),
                        )),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DateField(
                          label: 'Umgesetzt am',
                          value: entry.value.doneAt,
                          onChanged: (v) => _updateSections((s) => s.copyWith(
                                immediateActions: updateList(
                                  s.immediateActions,
                                  entry.key,
                                  (old) => old.copyWith(doneAt: v, clearDoneAt: v == null),
                                ),
                              )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.value.notes,
                          decoration: const InputDecoration(labelText: 'Details'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(
                                immediateActions: updateList(s.immediateActions, entry.key, (old) => old.copyWith(notes: v)),
                              )),
                        ),
                      ),
                      Checkbox(
                        value: entry.value.selected,
                        onChanged: (v) => _updateSections((s) => s.copyWith(
                              immediateActions: updateList(s.immediateActions, entry.key, (old) => old.copyWith(selected: v ?? false)),
                            )),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: actions.length <= 1
                          ? null
                          : () => _updateSections((s) {
                                final copy = [...s.immediateActions];
                                copy.removeAt(entry.key);
                                return s.copyWith(immediateActions: copy);
                              }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _updateSections(
              (s) => s.copyWith(immediateActions: [...s.immediateActions, const CapaImmediateAction(selected: true)]),
            ),
            icon: const Icon(Icons.add_task_outlined),
            label: const Text('Sofortmaßnahme hinzufügen'),
          ),
        ),
        TextFormField(
          initialValue: _report.sections.immediateDetails,
          decoration: const InputDecoration(labelText: 'Weitere Details'),
          maxLines: 3,
          onChanged: (v) => _updateSections((s) => s.copyWith(immediateDetails: v)),
        ),
      ],
    );
  }

  Widget _buildCauses() {
    final causes = _report.sections.causes;
    return Column(
      children: [
        for (final entry in causes.asMap().entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: entry.value.why,
                    decoration: const InputDecoration(labelText: 'Why / Ursache'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          causes: updateList(s.causes, entry.key, (old) => old.copyWith(why: v)),
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: entry.value.root,
                    decoration: const InputDecoration(labelText: 'Root Cause'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          causes: updateList(s.causes, entry.key, (old) => old.copyWith(root: v)),
                        )),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: causes.length <= 1
                      ? null
                      : () => _updateSections((s) {
                            final copy = [...s.causes];
                            copy.removeAt(entry.key);
                            return s.copyWith(causes: copy);
                          }),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _updateSections((s) => s.copyWith(causes: [...s.causes, const CapaCauseEntry()])),
            icon: const Icon(Icons.add),
            label: const Text('5-Why ergänzen'),
          ),
        ),
        TextFormField(
          initialValue: _report.sections.causeSummary,
          decoration: const InputDecoration(labelText: 'Root Cause Zusammenfassung'),
          maxLines: 3,
          onChanged: (v) => _updateSections((s) => s.copyWith(causeSummary: v)),
        ),
      ],
    );
  }

  Widget _buildCorrectiveActions() {
    final actions = _report.sections.correctiveActions;
    return Column(
      children: [
        for (final entry in actions.asMap().entries)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: entry.value.description,
                    decoration: const InputDecoration(labelText: 'Maßnahme'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          correctiveActions: updateList(
                            s.correctiveActions,
                            entry.key,
                            (old) => old.copyWith(description: v),
                          ),
                        )),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.value.owner,
                          decoration: const InputDecoration(labelText: 'Verantwortlicher'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(
                                correctiveActions: updateList(
                                  s.correctiveActions,
                                  entry.key,
                                  (old) => old.copyWith(owner: v),
                                ),
                              )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: entry.value.changeType.isEmpty ? null : entry.value.changeType,
                          items: const [
                            DropdownMenuItem(value: 'process', child: Text('Prozessanpassung')),
                            DropdownMenuItem(value: 'document', child: Text('Dokumentenänderung')),
                            DropdownMenuItem(value: 'training', child: Text('Schulung')),
                            DropdownMenuItem(value: 'other', child: Text('Sonstige')),
                          ],
                          decoration: const InputDecoration(labelText: 'Typ'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(
                                correctiveActions: updateList(
                                  s.correctiveActions,
                                  entry.key,
                                  (old) => old.copyWith(changeType: v ?? ''),
                                ),
                              )),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DateField(
                          label: 'Termin geplant',
                          value: entry.value.dueDate,
                          onChanged: (v) => _updateSections((s) => s.copyWith(
                                correctiveActions: updateList(
                                  s.correctiveActions,
                                  entry.key,
                                  (old) => old.copyWith(dueDate: v, clearDueDate: v == null),
                                ),
                              )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DateField(
                          label: 'Umgesetzt am',
                          value: entry.value.completedAt,
                          onChanged: (v) => _updateSections((s) => s.copyWith(
                                correctiveActions: updateList(
                                  s.correctiveActions,
                                  entry.key,
                                  (old) => old.copyWith(completedAt: v, clearCompletedAt: v == null),
                                ),
                              )),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: entry.value.status.isEmpty ? null : entry.value.status,
                          items: const [
                            DropdownMenuItem(value: 'open', child: Text('offen')),
                            DropdownMenuItem(value: 'inProgress', child: Text('in Bearbeitung')),
                            DropdownMenuItem(value: 'closed', child: Text('abgeschlossen')),
                          ],
                          decoration: const InputDecoration(labelText: 'Status'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(
                                correctiveActions: updateList(
                                  s.correctiveActions,
                                  entry.key,
                                  (old) => old.copyWith(status: v ?? ''),
                                ),
                              )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.value.notes,
                          decoration: const InputDecoration(labelText: 'Bemerkung'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(
                                correctiveActions: updateList(
                                  s.correctiveActions,
                                  entry.key,
                                  (old) => old.copyWith(notes: v),
                                ),
                              )),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: actions.length <= 1
                          ? null
                          : () => _updateSections((s) {
                                final copy = [...s.correctiveActions];
                                copy.removeAt(entry.key);
                                return s.copyWith(correctiveActions: copy);
                              }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _updateSections((s) => s.copyWith(correctiveActions: [...s.correctiveActions, const CapaCorrectiveAction()])),
            icon: const Icon(Icons.add_chart),
            label: const Text('Korrekturmaßnahme hinzufügen'),
          ),
        ),
      ],
    );
  }

  Widget _buildApprovals() {
    final approvals = _report.sections.approvals;
    return Column(
      children: [
        for (final entry in approvals.asMap().entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: entry.value.name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          approvals: updateList(s.approvals, entry.key, (old) => old.copyWith(name: v)),
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: entry.value.role,
                    decoration: const InputDecoration(labelText: 'Funktion'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          approvals: updateList(s.approvals, entry.key, (old) => old.copyWith(role: v)),
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DateField(
                    label: 'Datum',
                    value: entry.value.date,
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          approvals: updateList(
                            s.approvals,
                            entry.key,
                            (old) => old.copyWith(date: v, clearDate: v == null),
                          ),
                        )),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: approvals.length <= 1
                      ? null
                      : () => _updateSections((s) {
                            final copy = [...s.approvals];
                            copy.removeAt(entry.key);
                            return s.copyWith(approvals: copy);
                          }),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _updateSections((s) => s.copyWith(approvals: [...s.approvals, const CapaApprovalEntry()])),
            icon: const Icon(Icons.add_moderator_outlined),
            label: const Text('Freigabe hinzufügen'),
          ),
        ),
        TextFormField(
          initialValue: _report.sections.closingNote,
          decoration: const InputDecoration(labelText: 'Abschluss / Bemerkung'),
          maxLines: 3,
          onChanged: (v) => _updateSections((s) => s.copyWith(closingNote: v)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final readOnly = !widget.canWrite;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_report.effectiveNumber.isEmpty ? 'Neue CAPA' : _report.effectiveNumber),
            if (widget.complaintLabel != null)
              Text(widget.complaintLabel!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _report.status,
              onChanged: readOnly ? null : (v) => _updateReport(status: v ?? 'open'),
              items: const [
                DropdownMenuItem(value: 'open', child: Text('offen')),
                DropdownMenuItem(value: 'inProgress', child: Text('in Bearbeitung')),
                DropdownMenuItem(value: 'closed', child: Text('abgeschlossen')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: (readOnly || _saving) ? null : _save,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
            label: const Text('Speichern'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _exporting ? null : () => _export('de'),
            child: _exporting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('PDF DE'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _exporting ? null : () => _export('en'),
            child: _exporting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('PDF EN'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: cs.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(color: cs.onErrorContainer))),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: cs.onErrorContainer,
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
            ),
          if (_report.complaintId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.link, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Verknüpfte Reklamation: ${_report.complaintId}${widget.complaintLabel != null ? ' – ${widget.complaintLabel}' : ''}'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _report.title,
                    decoration: const InputDecoration(labelText: 'Titel / Problemkurzbeschreibung *'),
                    onChanged: (v) => _updateReport(title: v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    initialValue: _report.responsibleUserId,
                    decoration: const InputDecoration(labelText: 'Verantwortlicher'),
                    onChanged: (v) => _updateReport(responsible: v),
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: 'D1 Team'),
              Tab(text: 'D2 Sofortmaßnahmen'),
              Tab(text: 'D3 Ursachen'),
              Tab(text: 'D4 Korrekturmaßnahmen'),
              Tab(text: 'D5 Wirksamkeit'),
              Tab(text: 'D6 Prävention'),
              Tab(text: 'D7 Lessons'),
              Tab(text: 'D8 Abschluss'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _sectionContainer(title: 'Team & Problemdefinition', children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _report.sections.area,
                          decoration: const InputDecoration(labelText: 'Bereich'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(area: v)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DateField(
                          label: 'Datum',
                          value: _report.sections.date,
                          onChanged: (v) => _updateSections((s) => s.copyWith(date: v, clearDate: v == null)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _report.sections.teamLead,
                          decoration: const InputDecoration(labelText: 'Teamleiter'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(teamLead: v)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: _report.sections.product,
                          readOnly: widget.complaintPrefill != null && (widget.complaintPrefill?['product'] ?? '').isNotEmpty,
                          decoration: const InputDecoration(labelText: 'Produkt / Artikel'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(product: v)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _report.sections.batch,
                          readOnly: widget.complaintPrefill != null && (widget.complaintPrefill?['batch'] ?? '').isNotEmpty,
                          decoration: const InputDecoration(labelText: 'Charge / Batch'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(batch: v)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: _report.sections.problem,
                          readOnly: widget.complaintPrefill != null && (widget.complaintPrefill?['problem'] ?? '').isNotEmpty,
                          decoration: const InputDecoration(labelText: 'Problembeschreibung'),
                          maxLines: 3,
                          onChanged: (v) => _updateSections((s) => s.copyWith(problem: v)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTeamMembers(),
                ]),
                _sectionContainer(title: 'Sofortmaßnahmen', children: [_buildImmediateActions()]),
                _sectionContainer(title: 'Ursachenanalyse (5-Why)', children: [_buildCauses()]),
                _sectionContainer(title: 'Korrekturmaßnahmen', children: [_buildCorrectiveActions()]),
                _sectionContainer(title: 'Wirksamkeitsprüfung', children: [
                  TextFormField(
                    initialValue: _report.sections.d5Description,
                    decoration: const InputDecoration(labelText: 'Beschreibung der Verifizierung'),
                    maxLines: 3,
                    onChanged: (v) => _updateSections((s) => s.copyWith(d5Description: v)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DateField(
                          label: 'Datum',
                          value: _report.sections.d5Date,
                          onChanged: (v) => _updateSections((s) => s.copyWith(d5Date: v, clearD5Date: v == null)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<bool>(
                          value: _report.sections.d5Effective,
                          items: const [
                            DropdownMenuItem(value: true, child: Text('Ja')),
                            DropdownMenuItem(value: false, child: Text('Nein')),
                          ],
                          decoration: const InputDecoration(labelText: 'Wirksam?'),
                          onChanged: (v) => _updateSections((s) => s.copyWith(d5Effective: v ?? false)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: _report.sections.d5FollowUp,
                    decoration: const InputDecoration(labelText: 'Folgende Maßnahmen bei Nein'),
                    maxLines: 3,
                    onChanged: (v) => _updateSections((s) => s.copyWith(d5FollowUp: v)),
                  ),
                ]),
                _sectionContainer(title: 'Vorbeugungsmaßnahmen', children: [
                  TextFormField(
                    initialValue: _report.sections.preventiveActions.join('\n'),
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Präventive Maßnahmen (eine pro Zeile)'),
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          preventiveActions: v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                        )),
                  ),
                ]),
                _sectionContainer(title: 'Lessons Learned / Transfer', children: [
                  TextFormField(
                    initialValue: _report.sections.lessons.join('\n'),
                    decoration: const InputDecoration(labelText: 'Lessons Learned (eine pro Zeile)'),
                    maxLines: 3,
                    onChanged: (v) => _updateSections((s) => s.copyWith(
                          lessons: v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                        )),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: _report.sections.transfer,
                    decoration: const InputDecoration(labelText: 'Übertragbarkeit auf andere Produkte/Prozesse'),
                    maxLines: 3,
                    onChanged: (v) => _updateSections((s) => s.copyWith(transfer: v)),
                  ),
                ]),
                _sectionContainer(title: 'Abschluss & Freigabe', children: [
                  _buildApprovals(),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: _report.status == 'closed',
                    onChanged: readOnly
                        ? null
                        : (v) => _updateReport(status: (v ?? false) ? 'closed' : _report.status == 'closed' ? 'open' : _report.status),
                    title: const Text('Abgeschlossen'),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
