import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/gspr.dart';

class GsprItemDetailPage extends StatefulWidget {
  final ApiClient api;
  final GsprItem item;
  final bool canEdit;
  final bool isPrrc;
  final bool isAdmin;
  final bool isQm;
  final bool isNew;

  const GsprItemDetailPage({
    super.key,
    required this.api,
    required this.item,
    required this.canEdit,
    required this.isPrrc,
    required this.isAdmin,
    required this.isQm,
    this.isNew = false,
  });

  @override
  State<GsprItemDetailPage> createState() => _GsprItemDetailPageState();
}

class _GsprItemDetailPageState extends State<GsprItemDetailPage> {
  late GsprItem _item;
  late TextEditingController _gsprCodeCtrl;
  late TextEditingController _annexDeCtrl;
  late TextEditingController _annexEnCtrl;
  late TextEditingController _titleDeCtrl;
  late TextEditingController _titleEnCtrl;
  late TextEditingController _textDeCtrl;
  late TextEditingController _textEnCtrl;
  late TextEditingController _justificationCtrl;
  late TextEditingController _implementationCtrl;
  final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');
  bool _showAltLanguage = false;
  bool _saving = false;
  bool _loadingAudit = false;
  List<AuditEvent> _audit = const [];

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _gsprCodeCtrl = TextEditingController(text: _item.gsprCode);
    _annexDeCtrl = TextEditingController(text: _item.annexRefDe);
    _annexEnCtrl = TextEditingController(text: _item.annexRefEn);
    _titleDeCtrl = TextEditingController(text: _item.requirementTitleDe ?? '');
    _titleEnCtrl = TextEditingController(text: _item.requirementTitleEn ?? '');
    _textDeCtrl = TextEditingController(text: _item.textDe);
    _textEnCtrl = TextEditingController(text: _item.textEn);
    _justificationCtrl = TextEditingController(text: _item.justificationNa ?? '');
    _implementationCtrl = TextEditingController(text: _item.implementation ?? '');
    _loadAudit();
  }

  @override
  void dispose() {
    _gsprCodeCtrl.dispose();
    _annexDeCtrl.dispose();
    _annexEnCtrl.dispose();
    _titleDeCtrl.dispose();
    _titleEnCtrl.dispose();
    _textDeCtrl.dispose();
    _textEnCtrl.dispose();
    _justificationCtrl.dispose();
    _implementationCtrl.dispose();
    super.dispose();
  }

  bool get _readOnly => !widget.canEdit || _item.status == WorkflowStatus.approved;

  bool get _canRequestChange => (widget.isAdmin || widget.isQm) && _item.status == WorkflowStatus.approved;

  Future<void> _loadAudit() async {
    if (widget.isNew) return;
    setState(() => _loadingAudit = true);
    try {
      final events = await widget.api.gsprAudit(_item.id);
      if (!mounted) return;
      setState(() => _audit = events);
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _loadingAudit = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context)!;
    if (!_item.applicable && _justificationCtrl.text.trim().isEmpty) {
      _showSnack(t.gsprValidationJustificationRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = _item.copyWith(
        gsprCode: _gsprCodeCtrl.text.trim(),
        annexRefDe: _annexDeCtrl.text.trim(),
        annexRefEn: _annexEnCtrl.text.trim(),
        requirementTitleDe: _titleDeCtrl.text.trim(),
        requirementTitleEn: _titleEnCtrl.text.trim(),
        textDe: _textDeCtrl.text.trim(),
        textEn: _textEnCtrl.text.trim(),
        justificationNa: _item.applicable ? '' : _justificationCtrl.text.trim(),
        implementation: _implementationCtrl.text.trim(),
      );
      final saved = widget.isNew ? await widget.api.createGsprItem(updated) : await widget.api.updateGsprItem(updated);
      if (!mounted) return;
      setState(() => _item = saved);
      _showSnack(t.gsprSaved);
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addEvidence() async {
    final t = AppLocalizations.of(context)!;
    final result = await _openReferenceDialog(
      title: t.gsprEvidenceAdd,
      typeLabel: t.gsprEvidenceType,
      labelLabel: t.gsprEvidenceLabel,
      refLabel: t.gsprEvidenceRef,
      typeOptions: const ['TD', 'IFU', 'TEST_REPORT', 'SOP', 'OTHER'],
    );
    if (result == null) return;
    setState(() {
      _item = _item.copyWith(evidence: [..._item.evidence, result.asEvidence()]);
    });
  }

  Future<void> _addLink() async {
    final t = AppLocalizations.of(context)!;
    final result = await _openReferenceDialog(
      title: t.gsprLinksAdd,
      typeLabel: t.gsprLinksType,
      labelLabel: t.gsprLinksLabel,
      refLabel: t.gsprLinksRef,
      typeOptions: const ['FMEA', 'IFU', 'TD', 'PMS', 'PMCF', 'COMPLAINT', 'OTHER'],
    );
    if (result == null) return;
    setState(() {
      _item = _item.copyWith(links: [..._item.links, result.asLink()]);
    });
  }

  Future<_ReferenceDraft?> _openReferenceDialog({
    required String title,
    required String typeLabel,
    required String labelLabel,
    required String refLabel,
    required List<String> typeOptions,
  }) async {
    final typeCtrl = ValueNotifier<String>(typeOptions.first);
    final labelCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final t = AppLocalizations.of(context)!;
    final result = await showDialog<_ReferenceDraft>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: typeCtrl,
              builder: (context, value, _) => DropdownButtonFormField<String>(
                value: value,
                items: typeOptions
                    .map((type) => DropdownMenuItem(value: type, child: Text(_typeLabel(t, type))))
                    .toList(),
                onChanged: (next) => typeCtrl.value = next ?? typeOptions.first,
                decoration: InputDecoration(labelText: typeLabel),
              ),
            ),
            TextField(
              controller: labelCtrl,
              decoration: InputDecoration(labelText: labelLabel),
            ),
            TextField(
              controller: refCtrl,
              decoration: InputDecoration(labelText: refLabel),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.gsprCancel)),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(
                _ReferenceDraft(
                  type: typeCtrl.value,
                  label: labelCtrl.text.trim(),
                  ref: refCtrl.text.trim(),
                ),
              );
            },
            child: Text(t.gsprAdd),
          ),
        ],
      ),
    );
    labelCtrl.dispose();
    refCtrl.dispose();
    return result;
  }

  String _typeLabel(AppLocalizations t, String type) {
    switch (type) {
      case 'TD':
        return t.gsprTypeTd;
      case 'IFU':
        return t.gsprTypeIfu;
      case 'TEST_REPORT':
        return t.gsprTypeTestReport;
      case 'SOP':
        return t.gsprTypeSop;
      case 'FMEA':
        return t.gsprTypeFmea;
      case 'PMS':
        return t.gsprTypePms;
      case 'PMCF':
        return t.gsprTypePmcF;
      case 'COMPLAINT':
        return t.gsprTypeComplaint;
      case 'OTHER':
      default:
        return t.gsprTypeOther;
    }
  }

  Future<void> _removeEvidence(int index) async {
    setState(() {
      final updated = [..._item.evidence]..removeAt(index);
      _item = _item.copyWith(evidence: updated);
    });
  }

  Future<void> _removeLink(int index) async {
    setState(() {
      final updated = [..._item.links]..removeAt(index);
      _item = _item.copyWith(links: updated);
    });
  }

  Future<void> _runWorkflow(String action) async {
    final t = AppLocalizations.of(context)!;
    String? comment;
    String? reason;
    if (action == 'return_to_draft') {
      comment = await _promptComment(t.gsprWorkflowCommentLabel);
      if (comment == null || comment.trim().isEmpty) {
        _showSnack(t.gsprValidationCommentRequired);
        return;
      }
    }
    if (action == 'request_change') {
      reason = await _promptComment(t.gsprWorkflowReasonLabel);
      if (reason == null || reason.trim().isEmpty) {
        _showSnack(t.gsprValidationReasonRequired);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final updated = await widget.api.gsprWorkflowAction(
        _item.id,
        action: action,
        comment: comment?.trim().isEmpty == true ? null : comment?.trim(),
        reason: reason?.trim().isEmpty == true ? null : reason?.trim(),
      );
      if (!mounted) return;
      setState(() => _item = updated);
      await _loadAudit();
      _showSnack(t.gsprWorkflowUpdated);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _promptComment(String label) async {
    final controller = TextEditingController();
    final t = AppLocalizations.of(context)!;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(hintText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.gsprCancel)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(t.gsprConfirm),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  String _statusLabel(AppLocalizations t, WorkflowStatus status) {
    switch (status) {
      case WorkflowStatus.qmReview:
        return t.gsprStatusQmReview;
      case WorkflowStatus.prrcReview:
        return t.gsprStatusPrrcReview;
      case WorkflowStatus.approved:
        return t.gsprStatusApproved;
      case WorkflowStatus.rejected:
        return t.gsprStatusRejected;
      case WorkflowStatus.draft:
      default:
        return t.gsprStatusDraft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final showAlt = _showAltLanguage;
    final canSubmitToQm = widget.isQm || widget.isAdmin;
    final canSubmitToPrrc = widget.isQm || widget.isAdmin;
    final canApprove = widget.isPrrc || widget.isAdmin;
    final showJustification = !_item.applicable;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.gsprDetailTitle),
        actions: [
          if (!_readOnly)
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(t.gsprSave),
            ),
        ],
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${t.gsprColumnGsprRef}: ${_item.gsprCode}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${t.gsprColumnAnnexRef}: ${isEnglish ? _item.annexRefEn : _item.annexRefDe}'),
                  const SizedBox(height: 16),
                  _buildTextField(_gsprCodeCtrl, t.gsprFieldGsprCode, enabled: !_readOnly),
                  const SizedBox(height: 12),
                  _buildTextField(_annexDeCtrl, t.gsprFieldAnnexRefDe, enabled: !_readOnly),
                  const SizedBox(height: 12),
                  _buildTextField(_annexEnCtrl, t.gsprFieldAnnexRefEn, enabled: !_readOnly),
                  const SizedBox(height: 12),
                  _buildTextField(_titleDeCtrl, t.gsprFieldRequirementTitleDe, enabled: !_readOnly),
                  const SizedBox(height: 12),
                  _buildTextField(_titleEnCtrl, t.gsprFieldRequirementTitleEn, enabled: !_readOnly),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(t.gsprRequirementTextLabel, style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      Switch(
                        value: _showAltLanguage,
                        onChanged: (value) => setState(() => _showAltLanguage = value),
                      ),
                      Text(t.gsprToggleLanguage),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildTextArea(
                    isEnglish ? _textEnCtrl : _textDeCtrl,
                    isEnglish ? t.gsprFieldTextEn : t.gsprFieldTextDe,
                    enabled: !_readOnly,
                  ),
                  if (showAlt) ...[
                    const SizedBox(height: 12),
                    _buildTextArea(
                      isEnglish ? _textDeCtrl : _textEnCtrl,
                      isEnglish ? t.gsprFieldTextDe : t.gsprFieldTextEn,
                      enabled: !_readOnly,
                    ),
                  ],
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(t.gsprFieldApplicable),
                    value: _item.applicable,
                    onChanged: _readOnly
                        ? null
                        : (value) => setState(() => _item = _item.copyWith(applicable: value)),
                  ),
                  if (showJustification) ...[
                    const SizedBox(height: 12),
                    _buildTextArea(
                      _justificationCtrl,
                      t.gsprFieldJustification,
                      enabled: !_readOnly,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildTextArea(
                    _implementationCtrl,
                    t.gsprFieldImplementation,
                    enabled: !_readOnly,
                  ),
                  const SizedBox(height: 16),
                  _buildEvidenceSection(t),
                  const SizedBox(height: 16),
                  _buildLinksSection(t),
                  const SizedBox(height: 16),
                  _buildWorkflowSection(
                    t,
                    canSubmitToQm: canSubmitToQm,
                    canSubmitToPrrc: canSubmitToPrrc,
                    canApprove: canApprove,
                  ),
                  const SizedBox(height: 16),
                  _buildAuditTrail(t),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {required bool enabled}) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _buildTextArea(TextEditingController controller, String label, {required bool enabled}) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: 5,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _buildEvidenceSection(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(t.gsprEvidenceTitle, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (!_readOnly)
              TextButton.icon(
                onPressed: _addEvidence,
                icon: const Icon(Icons.add),
                label: Text(t.gsprEvidenceAdd),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_item.evidence.isEmpty)
              Text(t.gsprEvidenceNone)
            else
              ..._item.evidence.asMap().entries.map((entry) {
                final idx = entry.key;
                final evidence = entry.value;
                final label = '${_typeLabel(t, evidence.type)} · ${evidence.label}';
                return Chip(
                  label: Text(label),
                  onDeleted: _readOnly ? null : () => _removeEvidence(idx),
                );
              }),
          ],
        ),
      ],
    );
  }

  Widget _buildLinksSection(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(t.gsprLinksTitle, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (!_readOnly)
              TextButton.icon(
                onPressed: _addLink,
                icon: const Icon(Icons.add),
                label: Text(t.gsprLinksAdd),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_item.links.isEmpty)
              Text(t.gsprLinksNone)
            else
              ..._item.links.asMap().entries.map((entry) {
                final idx = entry.key;
                final link = entry.value;
                final label = '${_typeLabel(t, link.type)} · ${link.label}';
                return Chip(
                  label: Text(label),
                  onDeleted: _readOnly ? null : () => _removeLink(idx),
                );
              }),
          ],
        ),
      ],
    );
  }

  Widget _buildWorkflowSection(
    AppLocalizations t, {
    required bool canSubmitToQm,
    required bool canSubmitToPrrc,
    required bool canApprove,
  }) {
    final statusLabel = _statusLabel(t, _item.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.gsprWorkflowTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text('${t.gsprFieldStatus}: $statusLabel'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (_item.status == WorkflowStatus.draft && canSubmitToQm)
              OutlinedButton(
                onPressed: () => _runWorkflow('submit_to_qm_review'),
                child: Text(t.gsprWorkflowSubmitToQm),
              ),
            if (_item.status == WorkflowStatus.qmReview && canSubmitToPrrc)
              OutlinedButton(
                onPressed: () => _runWorkflow('submit_to_prrc_review'),
                child: Text(t.gsprWorkflowSubmitToPrrc),
              ),
            if (_item.status == WorkflowStatus.qmReview || _item.status == WorkflowStatus.prrcReview)
              OutlinedButton(
                onPressed: () => _runWorkflow('return_to_draft'),
                child: Text(t.gsprWorkflowReturnToDraft),
              ),
            if (_item.status == WorkflowStatus.prrcReview && canApprove)
              FilledButton(
                onPressed: () => _runWorkflow('approve'),
                child: Text(t.gsprWorkflowApprove),
              ),
            if (_canRequestChange)
              OutlinedButton(
                onPressed: () => _runWorkflow('request_change'),
                child: Text(t.gsprWorkflowRequestChange),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuditTrail(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.gsprAuditTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_loadingAudit) const CircularProgressIndicator(),
        if (!_loadingAudit && _audit.isEmpty) Text(t.gsprAuditEmpty),
        if (!_loadingAudit && _audit.isNotEmpty)
          Column(
            children: _audit.map((event) {
              final when = _dateFmt.format(event.timestamp);
              final action = _auditActionLabel(t, event.action);
              final statusChange = event.toStatus != null ? ' → ${event.toStatus}' : '';
              final comment = event.comment?.trim().isNotEmpty == true ? ' • ${event.comment}' : '';
              return ListTile(
                dense: true,
                title: Text('$action$statusChange'),
                subtitle: Text('$when · ${event.actorName}$comment'),
              );
            }).toList(),
          ),
      ],
    );
  }

  String _auditActionLabel(AppLocalizations t, String action) {
    switch (action) {
      case 'STATUS_CHANGE':
        return t.gsprAuditStatusChange;
      case 'EVIDENCE_ADD':
        return t.gsprAuditEvidenceAdd;
      case 'EVIDENCE_REMOVE':
        return t.gsprAuditEvidenceRemove;
      case 'LINK_ADD':
        return t.gsprAuditLinkAdd;
      case 'LINK_REMOVE':
        return t.gsprAuditLinkRemove;
      case 'OVERRIDE':
        return t.gsprAuditOverride;
      case 'EDIT':
      default:
        return t.gsprAuditEdit;
    }
  }
}

class _ReferenceDraft {
  final String type;
  final String label;
  final String ref;

  const _ReferenceDraft({
    required this.type,
    required this.label,
    required this.ref,
  });

  EvidenceRef asEvidence() => EvidenceRef(type: type, label: label, ref: ref);

  LinkRef asLink() => LinkRef(type: type, label: label, targetRef: ref);
}
