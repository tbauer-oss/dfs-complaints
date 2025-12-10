import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/capa_report.dart';
import '../models/portal_user.dart';
import '../models/dfs_product.dart';
import '../services/product_lookup.dart';
import '../widgets/date_field.dart';

const List<String> _departmentOptions = [
  'Sinterei',
  'Galvanik',
  'Galvanik Vor-/Nachbereitung',
  'Schleiferei',
  'Bürstenproduktion',
  'Dreherei',
  'MP Spezialfertigung',
  'Chemie / Logistik',
  'Versand / Lager',
  'Vertrieb',
];

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
  bool _allocatingNumber = false;
  String? _error;
  final _responsibleCtrl = TextEditingController();
  final _teamLeadCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final ProductLookup _productLookup = ProductLookup();
  List<PortalUserSummary> _portalUsers = const [];
  bool _portalUsersLoading = false;
  String? _portalUsersError;
  bool _productLoading = false;
  DfsProduct? _selectedProduct;

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
    _syncControllersFromReport();
    _loadPortalUsers();
    _ensureProductsLoaded();
    _ensureCapaNumber();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _ensureCapaNumber();
      CapaReport saved;
      if ((_report.id).isEmpty) {
        saved = await widget.api.adminSaveCapa(_report);
      } else {
        saved = await widget.api.adminUpdateCapa(_report);
      }
      setState(() {
        _report = saved;
        _syncControllersFromReport();
      });
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

  void _syncControllersFromReport() {
    _responsibleCtrl.text = _report.responsibleUserId;
    _teamLeadCtrl.text = _report.sections.teamLead;
    _areaCtrl.text = _report.sections.area;
    _productCtrl.text = _report.sections.product;
    _updateSelectedProduct();
  }

  Future<void> _loadPortalUsers() async {
    setState(() {
      _portalUsersLoading = true;
      _portalUsersError = null;
    });
    try {
      final list = await widget.api.fetchPortalUsers();
      if (!mounted) return;
      setState(() => _portalUsers = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _portalUsersError = e.toString());
    } finally {
      if (mounted) setState(() => _portalUsersLoading = false);
    }
  }

  Future<void> _ensureProductsLoaded() async {
    if (_productLoading || _productLookup.hasProducts) return;
    setState(() => _productLoading = true);
    try {
      await _productLookup.loadProducts();
      _updateSelectedProduct();
    } finally {
      if (mounted) setState(() => _productLoading = false);
    }
  }

  void _updateSelectedProduct() {
    final found = _productLookup.byArticle(_productCtrl.text.trim());
    if (!mounted) return;
    setState(() => _selectedProduct = found);
  }

  List<PortalUserSummary> get _activePortalUsers =>
      _portalUsers.where((u) => u.portalStatus.isEmpty || u.portalStatus == 'active').toList();

  List<PortalUserSummary> get _superusers =>
      _activePortalUsers.where((u) => u.role.toLowerCase() == 'superuser').toList();

  Future<void> _ensureCapaNumber() async {
    if (_report.capaNumber.isNotEmpty || _allocatingNumber) return;
    setState(() => _allocatingNumber = true);
    try {
      final list = await widget.api.adminCapas();
      final next = _nextNumber(list);
      if (mounted) setState(() => _report = _report.copyWith(capaNumber: next));
    } catch (e) {
      if (mounted) {
        setState(() => _error = _error ?? 'CAPA-Nr. konnte nicht ermittelt werden: $e');
      }
    } finally {
      if (mounted) setState(() => _allocatingNumber = false);
    }
  }

  String _nextNumber(List<CapaReport> existing) {
    final now = DateTime.now();
    final yy = (now.year % 100).toString().padLeft(2, '0');
    final pattern = RegExp('^DFS-CAPA-$yy_(\\d+)$');
    int maxSeq = 0;
    for (final c in existing) {
      final match = pattern.firstMatch(c.capaNumber);
      if (match == null) continue;
      final parsed = int.tryParse(match.group(1) ?? '0') ?? 0;
      if (parsed > maxSeq) maxSeq = parsed;
    }
    final nextSeq = (maxSeq + 1).toString().padLeft(4, '0');
    return 'DFS-CAPA-$yy_$nextSeq';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _responsibleCtrl.dispose();
    _teamLeadCtrl.dispose();
    _areaCtrl.dispose();
    _productCtrl.dispose();
    super.dispose();
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
                        child: RawAutocomplete<PortalUserSummary>(
                          initialValue: TextEditingValue(text: entry.value.owner),
                          optionsBuilder: (text) {
                            final query = text.text.toLowerCase();
                            if (query.isEmpty) return _activePortalUsers;
                            return _activePortalUsers.where((u) =>
                                u.label.toLowerCase().contains(query) || u.email.toLowerCase().contains(query));
                          },
                          displayStringForOption: (u) => u.label,
                          fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) => TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Verantwortlicher',
                              suffixIcon: _portalUsersLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  : const Icon(Icons.arrow_drop_down),
                            ),
                            onChanged: (v) => _updateSections((s) => s.copyWith(
                                  correctiveActions: updateList(
                                    s.correctiveActions,
                                    entry.key,
                                    (old) => old.copyWith(owner: v),
                                  ),
                                )),
                            onFieldSubmitted: (_) => onFieldSubmitted(),
                          ),
                          onSelected: (u) => _updateSections((s) => s.copyWith(
                                correctiveActions: updateList(
                                  s.correctiveActions,
                                  entry.key,
                                  (old) => old.copyWith(owner: u.label),
                                ),
                              )),
                          optionsViewBuilder: (ctx, onSelected, options) => Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              child: SizedBox(
                                height: 220,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: options.length,
                                  itemBuilder: (ctx, idx) {
                                    final opt = options.elementAt(idx);
                                    return ListTile(
                                      title: Text(opt.label.isEmpty ? opt.email : opt.label),
                                      subtitle: Text(opt.email),
                                      onTap: () => onSelected(opt),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RawAutocomplete<PortalUserSummary>(
                        textEditingController: _responsibleCtrl,
                        optionsBuilder: (text) {
                          final query = text.text.toLowerCase();
                          if (query.isEmpty) return _superusers;
                          return _superusers.where((u) =>
                              u.label.toLowerCase().contains(query) || u.email.toLowerCase().contains(query));
                        },
                        displayStringForOption: (u) => u.label,
                        fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) => TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Verantwortlicher',
                            suffixIcon: _portalUsersLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child:
                                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : const Icon(Icons.arrow_drop_down),
                          ),
                          onChanged: (v) => _updateReport(responsible: v),
                          onFieldSubmitted: (_) => onFieldSubmitted(),
                        ),
                        onSelected: (u) => _updateReport(responsible: u.label),
                        optionsViewBuilder: (ctx, onSelected, options) => Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            child: SizedBox(
                              height: 200,
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: options.length,
                                itemBuilder: (ctx, idx) {
                                  final opt = options.elementAt(idx);
                                  return ListTile(
                                    title: Text(opt.label.isEmpty ? opt.email : opt.label),
                                    subtitle: Text(opt.email),
                                    onTap: () => onSelected(opt),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_portalUsersError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_portalUsersError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                    ],
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
                        child: RawAutocomplete<String>(
                          textEditingController: _areaCtrl,
                          optionsBuilder: (text) {
                            final query = text.text.toLowerCase();
                            return _departmentOptions
                                .where((o) => o.toLowerCase().contains(query))
                                .toList(growable: false);
                          },
                          fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) => TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(labelText: 'Bereich'),
                            onChanged: (v) => _updateSections((s) => s.copyWith(area: v)),
                            onFieldSubmitted: (_) => onFieldSubmitted(),
                          ),
                          optionsViewBuilder: (ctx, onSelected, options) => Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              child: SizedBox(
                                height: 200,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: options.length,
                                  itemBuilder: (ctx, idx) {
                                    final opt = options.elementAt(idx);
                                    return ListTile(
                                      title: Text(opt),
                                      onTap: () => onSelected(opt),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          onSelected: (value) => _updateSections((s) => s.copyWith(area: value)),
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
                        child: RawAutocomplete<PortalUserSummary>(
                          textEditingController: _teamLeadCtrl,
                          optionsBuilder: (text) {
                            final query = text.text.toLowerCase();
                            if (query.isEmpty) return _activePortalUsers;
                            return _activePortalUsers.where((u) =>
                                u.label.toLowerCase().contains(query) || u.email.toLowerCase().contains(query));
                          },
                          displayStringForOption: (u) => u.label,
                          fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) => TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(labelText: 'Bereichsverantwortlicher'),
                            onChanged: (v) => _updateSections((s) => s.copyWith(teamLead: v)),
                            onFieldSubmitted: (_) => onFieldSubmitted(),
                          ),
                          onSelected: (u) => _updateSections((s) => s.copyWith(teamLead: u.label)),
                          optionsViewBuilder: (ctx, onSelected, options) => Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              child: SizedBox(
                                height: 220,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: options.length,
                                  itemBuilder: (ctx, idx) {
                                    final opt = options.elementAt(idx);
                                    return ListTile(
                                      title: Text(opt.label.isEmpty ? opt.email : opt.label),
                                      subtitle: Text(opt.email),
                                      onTap: () => onSelected(opt),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RawAutocomplete<DfsProduct>(
                          textEditingController: _productCtrl,
                          optionsBuilder: (text) {
                            final query = text.text.toLowerCase();
                            if (query.isEmpty) return _productLookup.products;
                            return _productLookup.products.where((p) {
                              return p.articleNumber.toLowerCase().contains(query) ||
                                  p.productName.toLowerCase().contains(query) ||
                                  p.basicUdiDi.toLowerCase().contains(query);
                            });
                          },
                          displayStringForOption: (p) => p.articleNumber,
                          fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) => TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            readOnly: widget.complaintPrefill != null &&
                                (widget.complaintPrefill?['product'] ?? '').isNotEmpty,
                            decoration: InputDecoration(
                              labelText: 'Produkt / Artikel',
                              suffixIcon: _productLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  : const Icon(Icons.search),
                            ),
                            onChanged: (v) {
                              _updateSections((s) => s.copyWith(product: v));
                              _updateSelectedProduct();
                            },
                            onTap: _ensureProductsLoaded,
                            onFieldSubmitted: (_) => onFieldSubmitted(),
                          ),
                          onSelected: (product) {
                            _updateSections((s) => s.copyWith(product: product.articleNumber));
                            _productCtrl.text = product.articleNumber;
                            _updateSelectedProduct();
                          },
                          optionsViewBuilder: (ctx, onSelected, options) => Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              child: SizedBox(
                                height: 240,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: options.length,
                                  itemBuilder: (ctx, idx) {
                                    final opt = options.elementAt(idx);
                                    return ListTile(
                                      title: Text(opt.articleNumber.isEmpty ? '—' : opt.articleNumber),
                                      subtitle: Text(opt.productName),
                                      onTap: () => onSelected(opt),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedProduct != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Artikelbezeichnung: ${_selectedProduct?.productName ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
