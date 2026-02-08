import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/fmea.dart';
import '../../../models/gspr.dart';
import 'gspr_state.dart';

class GsprChapterArgs {
  final FmeaRecord td;
  final GsprAccess access;

  const GsprChapterArgs({required this.td, required this.access});
}

class GsprChapterPage extends StatefulWidget {
  final String chapter;
  final ApiClient api;
  final GsprAccess access;
  final FmeaRecord? tdOverride;

  const GsprChapterPage({
    super.key,
    required this.chapter,
    required this.api,
    required this.access,
    this.tdOverride,
  });

  @override
  State<GsprChapterPage> createState() => _GsprChapterPageState();
}

class _GsprChapterPageState extends State<GsprChapterPage> {
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  List<GsprChapterEntry> _entries = const [];
  GsprStatus _status = GsprStatus.draft;
  bool _readOnly = false;

  FmeaRecord? get _td => widget.tdOverride ?? GsprTdState.selectedTd.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final td = _td;
    if (td == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.gsprChapter(tdId: td.id, chapter: widget.chapter);
      if (!mounted) return;
      setState(() {
        _entries = response.items;
        _status = response.status;
        _readOnly = response.readOnly;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(AppLocalizations t, GsprStatus status) {
    switch (status) {
      case GsprStatus.approved:
        return t.gsprStatusApproved;
      case GsprStatus.inReview:
        return t.gsprStatusInReview;
      case GsprStatus.draft:
      default:
        return t.gsprStatusDraft;
    }
  }

  String _chapterLabel(AppLocalizations t) {
    switch (widget.chapter) {
      case 'II':
        return t.gsprChapterII;
      case 'III':
        return t.gsprChapterIII;
      case 'I':
      default:
        return t.gsprChapterI;
    }
  }

  bool get _canEdit => widget.access.canEdit && !_readOnly && _status != GsprStatus.approved;

  bool get _canSubmit {
    if (!_canEdit) return false;
    if (_status != GsprStatus.draft) return false;
    return _entries.every((entry) {
      if (!entry.assessment.applicable) return true;
      return entry.assessment.standards.trim().isNotEmpty ||
          entry.assessment.supportingDocs.trim().isNotEmpty ||
          entry.assessment.comments.trim().isNotEmpty;
    });
  }

  Future<void> _toggleApplicable(GsprChapterEntry entry, bool value) async {
    final updated = entry.assessment.copyWith(applicable: value);
    await _saveAssessment(updated);
  }

  Future<void> _saveAssessment(GsprAssessment assessment) async {
    setState(() => _submitting = true);
    try {
      final saved = await widget.api.updateGsprAssessment(assessment);
      if (!mounted) return;
      setState(() {
        _entries = _entries
            .map((entry) => entry.assessment.id == saved.id
                ? GsprChapterEntry(requirement: entry.requirement, assessment: saved)
                : entry)
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openDialog(GsprChapterEntry entry) async {
    final updated = await showDialog<GsprAssessment>(
      context: context,
      builder: (context) => GsprAssessmentDialog(
        api: widget.api,
        entry: entry,
        canEdit: widget.access.canEdit,
        readOnly: _readOnly || _status == GsprStatus.approved,
      ),
    );
    if (updated != null) {
      setState(() {
        _entries = _entries
            .map((e) => e.assessment.id == updated.id
                ? GsprChapterEntry(requirement: e.requirement, assessment: updated)
                : e)
            .toList(growable: false);
      });
      await _load();
    }
  }

  Future<void> _submit() async {
    final td = _td;
    if (td == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.submitGsprTd(td.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _approve() async {
    final td = _td;
    if (td == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.approveGsprTd(td.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _truncate(String text, {int limit = 120}) {
    if (text.length <= limit) return text;
    return '${text.substring(0, limit)}…';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final td = _td;

    if (td == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.gsprPageTitle)),
        body: Center(child: Text(t.gsprSelectTdHint)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.gsprPageTitle),
            Text(
              '${td.mdrTd} · ${_chapterLabel(t)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (_status == GsprStatus.draft && _canSubmit)
            TextButton(
              onPressed: _submitting ? null : _submit,
              child: Text(t.gsprSubmitForReview),
            ),
          if (_status == GsprStatus.inReview && widget.access.isPrrc)
            TextButton(
              onPressed: _submitting ? null : _approve,
              child: Text(t.gsprApprovePrrc),
            ),
          IconButton(
            tooltip: t.gsprReload,
            onPressed: _submitting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                if (_readOnly)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      t.gsprTdReadOnlyHint,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Text('${t.gsprSummaryStatusLabel}: ${_statusLabel(t, _status)}'),
                      const Spacer(),
                      if (!_canSubmit && _status == GsprStatus.draft)
                        Text(
                          t.gsprSubmitIncompleteHint,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(t.gsprColumnNumber)),
                        DataColumn(label: Text(t.gsprColumnRequirement)),
                        DataColumn(label: Text(t.gsprColumnApplicable)),
                        DataColumn(label: Text(t.gsprColumnStatus)),
                        DataColumn(label: Text(t.gsprColumnVersion)),
                        DataColumn(label: Text(t.gsprColumnUpdated)),
                      ],
                      rows: _entries.map((entry) {
                        final assessment = entry.assessment;
                        final updated = assessment.updatedAt != null
                            ? DateFormat('yyyy-MM-dd').format(assessment.updatedAt!)
                            : '—';
                        return DataRow(
                          onSelectChanged: (_) => _openDialog(entry),
                          cells: [
                            DataCell(Text(entry.requirement.ref)),
                            DataCell(Text(_truncate(entry.requirement.fullText))),
                            DataCell(
                              Switch(
                                value: assessment.applicable,
                                onChanged: _canEdit ? (value) => _toggleApplicable(entry, value) : null,
                              ),
                            ),
                            DataCell(Text(_statusLabel(t, assessment.status))),
                            DataCell(Text(assessment.version.toString())),
                            DataCell(Text(updated)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class GsprAssessmentDialog extends StatefulWidget {
  final ApiClient api;
  final GsprChapterEntry entry;
  final bool canEdit;
  final bool readOnly;

  const GsprAssessmentDialog({
    super.key,
    required this.api,
    required this.entry,
    required this.canEdit,
    required this.readOnly,
  });

  @override
  State<GsprAssessmentDialog> createState() => _GsprAssessmentDialogState();
}

class _GsprAssessmentDialogState extends State<GsprAssessmentDialog> {
  late GsprAssessment _assessment;
  late TextEditingController _standardsCtrl;
  late TextEditingController _editionCtrl;
  late TextEditingController _supportingDocsCtrl;
  late TextEditingController _revisionCtrl;
  late TextEditingController _dateCtrl;
  late TextEditingController _commentsCtrl;
  late TextEditingController _additionalCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _assessment = widget.entry.assessment;
    _standardsCtrl = TextEditingController(text: _assessment.standards);
    _editionCtrl = TextEditingController(text: _assessment.edition);
    _supportingDocsCtrl = TextEditingController(text: _assessment.supportingDocs);
    _revisionCtrl = TextEditingController(text: _assessment.revision);
    _dateCtrl = TextEditingController(text: _formatDate(_assessment.date));
    _commentsCtrl = TextEditingController(text: _assessment.comments);
    _additionalCtrl = TextEditingController(text: _assessment.additionalDataRequired);
  }

  @override
  void dispose() {
    _standardsCtrl.dispose();
    _editionCtrl.dispose();
    _supportingDocsCtrl.dispose();
    _revisionCtrl.dispose();
    _dateCtrl.dispose();
    _commentsCtrl.dispose();
    _additionalCtrl.dispose();
    super.dispose();
  }

  bool get _readOnly => widget.readOnly || !widget.canEdit;

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _statusLabel(AppLocalizations t, GsprStatus status) {
    switch (status) {
      case GsprStatus.approved:
        return t.gsprStatusApproved;
      case GsprStatus.inReview:
        return t.gsprStatusInReview;
      case GsprStatus.draft:
      default:
        return t.gsprStatusDraft;
    }
  }

  Future<void> _pickDate() async {
    if (_readOnly) return;
    final initial = _assessment.date ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context)!;
    final hasContent = _standardsCtrl.text.trim().isNotEmpty ||
        _supportingDocsCtrl.text.trim().isNotEmpty ||
        _commentsCtrl.text.trim().isNotEmpty;
    if (_assessment.applicable && !hasContent) {
      setState(() => _error = t.gsprValidationContentRequired);
      return;
    }
    if (_revisionCtrl.text.trim().isNotEmpty && _dateCtrl.text.trim().isEmpty) {
      setState(() => _error = t.gsprValidationDateRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = _assessment.copyWith(
        applicable: _assessment.applicable,
        standards: _standardsCtrl.text.trim(),
        edition: _editionCtrl.text.trim(),
        supportingDocs: _supportingDocsCtrl.text.trim(),
        revision: _revisionCtrl.text.trim(),
        date: _dateCtrl.text.trim().isEmpty ? null : DateTime.tryParse(_dateCtrl.text.trim()),
        comments: _commentsCtrl.text.trim(),
        additionalDataRequired: _additionalCtrl.text.trim(),
      );
      final saved = await widget.api.updateGsprAssessment(updated);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _newVersion() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.newGsprAssessmentVersion(_assessment.id);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final updatedAt = _assessment.updatedAt != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(_assessment.updatedAt!)
        : '—';

    return AlertDialog(
      title: Text(t.gsprEditTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t.gsprColumnNumber} ${widget.entry.requirement.ref}'),
              const SizedBox(height: 8),
              Text(widget.entry.requirement.fullText),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(t.gsprFieldApplicable),
                value: _assessment.applicable,
                onChanged: _readOnly
                    ? null
                    : (value) => setState(() => _assessment = _assessment.copyWith(applicable: value)),
              ),
              TextField(
                controller: _standardsCtrl,
                enabled: !_readOnly,
                decoration: InputDecoration(labelText: t.gsprFieldStandards),
              ),
              TextField(
                controller: _editionCtrl,
                enabled: !_readOnly,
                decoration: InputDecoration(labelText: t.gsprFieldEdition),
              ),
              TextField(
                controller: _supportingDocsCtrl,
                enabled: !_readOnly,
                maxLines: 3,
                decoration: InputDecoration(labelText: t.gsprFieldSupportingDocs),
              ),
              TextField(
                controller: _revisionCtrl,
                enabled: !_readOnly,
                decoration: InputDecoration(labelText: t.gsprFieldRevision),
              ),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: TextField(
                    controller: _dateCtrl,
                    enabled: !_readOnly,
                    decoration: InputDecoration(labelText: t.gsprFieldDate),
                  ),
                ),
              ),
              TextField(
                controller: _commentsCtrl,
                enabled: !_readOnly,
                maxLines: 3,
                decoration: InputDecoration(labelText: t.gsprFieldComments),
              ),
              TextField(
                controller: _additionalCtrl,
                enabled: !_readOnly,
                maxLines: 2,
                decoration: InputDecoration(labelText: t.gsprFieldAdditionalData),
              ),
              const SizedBox(height: 16),
              Text('${t.gsprFieldStatus}: ${_statusLabel(t, _assessment.status)}'),
              Text('${t.gsprColumnVersion}: ${_assessment.version}'),
              Text('${t.gsprFieldUpdatedAt}: $updatedAt'),
              Text('${t.gsprFieldUpdatedBy}: ${_assessment.updatedBy.isEmpty ? '—' : _assessment.updatedBy}'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (_assessment.status == GsprStatus.approved && widget.canEdit)
          TextButton(
            onPressed: _saving ? null : _newVersion,
            child: Text(t.gsprNewVersion),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(t.gsprCancel),
        ),
        if (!_readOnly)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(t.gsprSave),
          ),
      ],
    );
  }
}
