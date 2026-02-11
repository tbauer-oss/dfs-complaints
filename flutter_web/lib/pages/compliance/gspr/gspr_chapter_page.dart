import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/gspr.dart';
import 'gspr_state.dart';

class GsprChapterArgs {
  final GsprTdOption td;
  final GsprAccess access;
  final String? initialRequirementId;

  const GsprChapterArgs({
    required this.td,
    required this.access,
    this.initialRequirementId,
  });
}

class GsprChapterPage extends StatefulWidget {
  final String chapter;
  final ApiClient api;
  final GsprAccess access;
  final GsprTdOption? tdOverride;
  final String? initialRequirementId;
  final VoidCallback? onBackToOverview;

  const GsprChapterPage({
    super.key,
    required this.chapter,
    required this.api,
    required this.access,
    this.tdOverride,
    this.initialRequirementId,
    this.onBackToOverview,
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
  String _search = '';
  bool _filterOpen = false;
  bool _filterIssues = false;
  bool _filterNa = false;
  bool _filterMissingEvidence = false;
  String? _selectedId;
  Set<String> _expanded = {};
  GsprAssessment? _draftAssessment;

  GsprTdOption? get _td => widget.tdOverride ?? GsprTdState.selectedTd.value;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialRequirementId;
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
      if (_entries.isNotEmpty) {
        final candidate = _selectedId;
        if (candidate != null && _entries.any((entry) => entry.requirement.id == candidate)) {
          _setSelected(candidate);
        } else if (_selectedId == null) {
          _setSelected(_entries.first.requirement.id);
        }
      }
      _ensureDefaultExpansion();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _ensureDefaultExpansion() {
    if (_entries.isEmpty) return;
    final expanded = <String>{};
    for (final entry in _entries) {
      if (entry.requirement.level == 0) {
        expanded.add(entry.requirement.id);
      }
    }
    setState(() => _expanded = expanded);
  }

  void _setSelected(String id) {
    final entry = _entries.firstWhere((e) => e.requirement.id == id, orElse: () => _entries.first);
    setState(() {
      _selectedId = id;
      _draftAssessment = entry.assessment;
    });
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

  String _assessmentStatusLabel(AppLocalizations t, GsprAssessmentStatus status) {
    switch (status) {
      case GsprAssessmentStatus.fulfilled:
        return t.gsprAssessmentStatusFulfilled;
      case GsprAssessmentStatus.partial:
        return t.gsprAssessmentStatusPartial;
      case GsprAssessmentStatus.notFulfilled:
        return t.gsprAssessmentStatusNotFulfilled;
      case GsprAssessmentStatus.notApplicable:
        return t.gsprAssessmentStatusNotApplicable;
      case GsprAssessmentStatus.notAssessed:
      default:
        return t.gsprAssessmentStatusNotAssessed;
    }
  }

  IconData _assessmentStatusIcon(GsprAssessmentStatus status) {
    switch (status) {
      case GsprAssessmentStatus.fulfilled:
        return Icons.check_circle;
      case GsprAssessmentStatus.partial:
        return Icons.warning;
      case GsprAssessmentStatus.notFulfilled:
        return Icons.cancel;
      case GsprAssessmentStatus.notApplicable:
        return Icons.block;
      case GsprAssessmentStatus.notAssessed:
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color _assessmentStatusColor(ThemeData theme, GsprAssessmentStatus status) {
    switch (status) {
      case GsprAssessmentStatus.fulfilled:
        return theme.colorScheme.tertiary;
      case GsprAssessmentStatus.partial:
        return theme.colorScheme.secondary;
      case GsprAssessmentStatus.notFulfilled:
        return theme.colorScheme.error;
      case GsprAssessmentStatus.notApplicable:
        return theme.colorScheme.outline;
      case GsprAssessmentStatus.notAssessed:
      default:
        return theme.colorScheme.onSurfaceVariant;
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

  bool _assessmentComplete(GsprAssessment assessment) {
    if (assessment.status == GsprAssessmentStatus.notAssessed) return false;
    if ([
      GsprAssessmentStatus.notApplicable,
      GsprAssessmentStatus.partial,
      GsprAssessmentStatus.notFulfilled,
    ].contains(assessment.status)) {
      return assessment.rationale.trim().isNotEmpty;
    }
    return true;
  }

  bool get _canSubmit => _entries
      .where((entry) => entry.requirement.isAssessable)
      .every((entry) => entry.assessment != null && _assessmentComplete(entry.assessment!));

  bool _matchesSearch(GsprChapterEntry entry) {
    if (_search.trim().isEmpty) return true;
    final query = _search.trim().toLowerCase();
    return entry.requirement.id.toLowerCase().contains(query) ||
        entry.requirement.ref.toLowerCase().contains(query) ||
        entry.requirement.title.toLowerCase().contains(query) ||
        entry.requirement.text.toLowerCase().contains(query) ||
        (entry.requirement.contextText ?? '').toLowerCase().contains(query);
  }

  bool _matchesFilters(GsprChapterEntry entry, Map<String?, List<GsprChapterEntry>> byParent) {
    final status = _entryStatus(entry, byParent);
    if (_filterOpen && status != GsprAssessmentStatus.notAssessed) return false;
    if (_filterIssues &&
        !(status == GsprAssessmentStatus.partial || status == GsprAssessmentStatus.notFulfilled)) {
      return false;
    }
    if (_filterNa && status != GsprAssessmentStatus.notApplicable) return false;
    if (_filterMissingEvidence && !_entryMissingEvidence(entry, byParent)) return false;
    return true;
  }

  Map<String, GsprChapterEntry> _entryById() {
    return {for (final entry in _entries) entry.requirement.id: entry};
  }

  Map<String?, List<GsprChapterEntry>> _entriesByParent(Set<String> visibleIds) {
    final map = <String?, List<GsprChapterEntry>>{};
    for (final entry in _entries) {
      if (!visibleIds.contains(entry.requirement.id)) continue;
      final parent = entry.requirement.parentId;
      map.putIfAbsent(parent, () => []).add(entry);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.requirement.sortKey.compareTo(b.requirement.sortKey));
    }
    return map;
  }

  Set<String> _visibleIds(Map<String?, List<GsprChapterEntry>> byParent) {
    if (_search.trim().isEmpty && !_filterOpen && !_filterIssues && !_filterNa && !_filterMissingEvidence) {
      return _entries.map((e) => e.requirement.id).toSet();
    }
    final byId = _entryById();
    final matches = <String>{};
    for (final entry in _entries) {
      if (_matchesSearch(entry) && _matchesFilters(entry, byParent)) {
        matches.add(entry.requirement.id);
      }
    }
    final visible = <String>{};
    for (final id in matches) {
      var current = id;
      while (true) {
        if (!visible.add(current)) break;
        final parent = byId[current]?.requirement.parentId;
        if (parent == null) break;
        current = parent;
      }
    }
    return visible;
  }

  List<GsprChapterEntry> _flattenTree(Map<String?, List<GsprChapterEntry>> byParent, Set<String> visibleIds) {
    final result = <GsprChapterEntry>[];
    void visit(String? parentId) {
      final children = byParent[parentId] ?? const [];
      for (final entry in children) {
        if (!visibleIds.contains(entry.requirement.id)) continue;
        result.add(entry);
        if (_expanded.contains(entry.requirement.id)) {
          visit(entry.requirement.id);
        }
      }
    }
    visit(null);
    return result;
  }

  _GsprProgress _progressForItems(List<GsprChapterEntry> items) {
    final assessable = items.where((e) => e.requirement.isAssessable && e.assessment != null).toList();
    final total = assessable.length;
    final assessed = assessable.where((e) => e.assessment!.status != GsprAssessmentStatus.notAssessed).length;
    final notApplicable =
        assessable.where((e) => e.assessment!.status == GsprAssessmentStatus.notApplicable).length;
    final open = total - assessed;
    return _GsprProgress(total: total, assessed: assessed, open: open, notApplicable: notApplicable);
  }

  List<GsprChapterEntry> _descendants(String rootId, Map<String?, List<GsprChapterEntry>> byParent) {
    final result = <GsprChapterEntry>[];
    void walk(String id) {
      final children = byParent[id] ?? const [];
      for (final entry in children) {
        result.add(entry);
        walk(entry.requirement.id);
      }
    }
    walk(rootId);
    return result;
  }

  List<GsprChapterEntry> _assessableDescendants(String rootId, Map<String?, List<GsprChapterEntry>> byParent) {
    final result = <GsprChapterEntry>[];
    void walk(String id) {
      final children = byParent[id] ?? const [];
      for (final entry in children) {
        if (entry.requirement.isAssessable) {
          result.add(entry);
        }
        walk(entry.requirement.id);
      }
    }
    walk(rootId);
    return result;
  }

  GsprAssessmentStatus _entryStatus(
    GsprChapterEntry entry,
    Map<String?, List<GsprChapterEntry>> byParent,
  ) {
    if (entry.requirement.isAssessable) {
      return entry.assessment?.status ?? GsprAssessmentStatus.notAssessed;
    }
    final descendants = _assessableDescendants(entry.requirement.id, byParent);
    if (descendants.isEmpty) return GsprAssessmentStatus.notAssessed;
    if (descendants.any((d) => d.assessment?.status == GsprAssessmentStatus.notAssessed)) {
      return GsprAssessmentStatus.notAssessed;
    }
    if (descendants.any((d) => d.assessment?.status == GsprAssessmentStatus.notFulfilled)) {
      return GsprAssessmentStatus.notFulfilled;
    }
    if (descendants.any((d) => d.assessment?.status == GsprAssessmentStatus.partial)) {
      return GsprAssessmentStatus.partial;
    }
    if (descendants.every((d) => d.assessment?.status == GsprAssessmentStatus.notApplicable)) {
      return GsprAssessmentStatus.notApplicable;
    }
    return GsprAssessmentStatus.fulfilled;
  }

  bool _entryMissingEvidence(GsprChapterEntry entry, Map<String?, List<GsprChapterEntry>> byParent) {
    if (entry.requirement.isAssessable) {
      final assessment = entry.assessment;
      if (assessment == null) return false;
      return assessment.status != GsprAssessmentStatus.notAssessed && assessment.evidence.isEmpty;
    }
    final descendants = _assessableDescendants(entry.requirement.id, byParent);
    return descendants.any((desc) {
      final assessment = desc.assessment;
      if (assessment == null) return false;
      return assessment.status != GsprAssessmentStatus.notAssessed && assessment.evidence.isEmpty;
    });
  }

  Future<void> _saveAssessment() async {
    final assessment = _draftAssessment;
    if (assessment == null) return;
    final t = AppLocalizations.of(context)!;

    if ([
      GsprAssessmentStatus.notApplicable,
      GsprAssessmentStatus.partial,
      GsprAssessmentStatus.notFulfilled,
    ].contains(assessment.status)) {
      if (assessment.rationale.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.gsprValidationRationaleRequired)),
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final saved = await widget.api.updateGsprAssessment(assessment);
      if (!mounted) return;
      setState(() {
        _entries = _entries
            .map((entry) => entry.assessment?.id == saved.id
                ? GsprChapterEntry(requirement: entry.requirement, assessment: saved)
                : entry)
            .toList(growable: false);
        _draftAssessment = saved;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
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

    final allIds = _entries.map((e) => e.requirement.id).toSet();
    final byParentAll = _entriesByParent(allIds);
    final visibleIds = _visibleIds(byParentAll);
    final byId = _entryById();
    final byParent = _entriesByParent(visibleIds);
    final flatEntries = _flattenTree(byParent, visibleIds);
    final chapterProgress = _progressForItems(_entries);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.onBackToOverview == null,
        leading: widget.onBackToOverview == null
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBackToOverview,
              ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.gsprPageTitle),
            Text(
              '${td.displayCode} · ${_chapterLabel(t)}',
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
                      Text(
                        '${chapterProgress.assessed}/${chapterProgress.total} ${t.gsprSummaryAssessedLabel}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${chapterProgress.open} ${t.gsprSummaryOpenLabel}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${chapterProgress.notApplicable} ${t.gsprSummaryNotApplicableLabel}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!_canSubmit && _status == GsprStatus.draft)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      t.gsprSubmitIncompleteHint,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: LinearProgressIndicator(
                    value: chapterProgress.total == 0
                        ? 0
                        : chapterProgress.assessed / chapterProgress.total,
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 360,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: t.gsprSearchLabel,
                                  prefixIcon: const Icon(Icons.search),
                                ),
                                onChanged: (value) => setState(() => _search = value),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilterChip(
                                    label: Text(t.gsprFilterOpenOnly),
                                    selected: _filterOpen,
                                    onSelected: (value) => setState(() => _filterOpen = value),
                                  ),
                                  FilterChip(
                                    label: Text(t.gsprFilterIssuesOnly),
                                    selected: _filterIssues,
                                    onSelected: (value) => setState(() => _filterIssues = value),
                                  ),
                                  FilterChip(
                                    label: Text(t.gsprFilterNaOnly),
                                    selected: _filterNa,
                                    onSelected: (value) => setState(() => _filterNa = value),
                                  ),
                                  FilterChip(
                                    label: Text(t.gsprFilterMissingEvidence),
                                    selected: _filterMissingEvidence,
                                    onSelected: (value) => setState(() => _filterMissingEvidence = value),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.builder(
                                itemCount: flatEntries.length,
                                itemBuilder: (context, index) {
                                  final entry = flatEntries[index];
                                  final isSelected = entry.requirement.id == _selectedId;
                                  final hasChildren =
                                      (byParent[entry.requirement.id] ?? const []).isNotEmpty;
                                  final status = _entryStatus(entry, byParentAll);
                                  final color = _assessmentStatusColor(theme, status);
                                  final isTopLevel = entry.requirement.level == 0;
                                  final showProgress = isTopLevel || !entry.requirement.isAssessable;
                                  final progress = showProgress
                                      ? _progressForItems([
                                          entry,
                                          ..._descendants(entry.requirement.id, byParentAll),
                                        ])
                                      : null;
                                  return InkWell(
                                    onTap: () => _setSelected(entry.requirement.id),
                                    child: Container(
                                      color: isSelected
                                          ? theme.colorScheme.primaryContainer.withOpacity(0.4)
                                          : null,
                                      padding: EdgeInsets.fromLTRB(16 + entry.requirement.level * 12.0, 8, 12, 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (hasChildren)
                                            IconButton(
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                              icon: Icon(
                                                _expanded.contains(entry.requirement.id)
                                                    ? Icons.expand_more
                                                    : Icons.chevron_right,
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  if (_expanded.contains(entry.requirement.id)) {
                                                    _expanded.remove(entry.requirement.id);
                                                  } else {
                                                    _expanded.add(entry.requirement.id);
                                                  }
                                                });
                                              },
                                            )
                                          else
                                            const SizedBox(width: 24),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    if (!entry.requirement.isAssessable)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 6, right: 6),
                                                        child: Icon(
                                                          Icons.circle,
                                                          size: 8,
                                                          color: theme.colorScheme.outline,
                                                        ),
                                                      ),
                                                    Expanded(
                                                      child: Text(
                                                        '${entry.requirement.ref} ${entry.requirement.title}',
                                                        style: theme.textTheme.bodyMedium?.copyWith(
                                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (progress != null)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Text(
                                                      '${progress.assessed}/${progress.total} ${t.gsprSummaryAssessedLabel}',
                                                      style: theme.textTheme.bodySmall,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Icon(_assessmentStatusIcon(status), size: 18, color: color),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _selectedId == null
                            ? Center(child: Text(t.gsprSelectRequirementHint))
                            : _buildDetailPane(
                                t,
                                theme,
                                byId[_selectedId!],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDetailPane(AppLocalizations t, ThemeData theme, GsprChapterEntry? entry) {
    if (entry == null) return const SizedBox.shrink();
    final assessment = _draftAssessment ?? entry.assessment;
    final updatedAt = assessment?.updatedAt != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(assessment!.updatedAt!)
        : '—';
    final needsRationale = [
      GsprAssessmentStatus.notApplicable,
      GsprAssessmentStatus.partial,
      GsprAssessmentStatus.notFulfilled,
    ].contains(assessment?.status);
    final canAssess = _canEdit && entry.requirement.isAssessable && assessment != null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                  Text('${t.gsprColumnNumber} ${entry.requirement.ref}', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  if (!entry.requirement.isAssessable)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.gsprIntroNotAssessableBanner,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (entry.requirement.isAssessable && (entry.requirement.contextText ?? '').trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ExpansionTile(
                        title: Text(t.gsprContextLabel),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        initiallyExpanded: true,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(entry.requirement.contextText ?? ''),
                          ),
                        ],
                      ),
                    ),
                  Text(entry.requirement.text),
                  const SizedBox(height: 16),
                  if (entry.requirement.isAssessable && assessment != null)
                    DropdownButtonFormField<GsprAssessmentStatus>(
                      value: assessment.status,
                      decoration: InputDecoration(labelText: t.gsprAssessmentStatusLabel),
                      items: GsprAssessmentStatus.values
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(_assessmentStatusLabel(t, status)),
                            ),
                          )
                          .toList(),
                      onChanged: !canAssess
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _draftAssessment = assessment.copyWith(status: value);
                              });
                            },
                    ),
                  const SizedBox(height: 8),
                  if (entry.requirement.isAssessable && assessment != null)
                    TextField(
                      enabled: canAssess,
                      maxLines: 3,
                      controller: TextEditingController(text: assessment.rationale)
                        ..selection = TextSelection.collapsed(offset: assessment.rationale.length),
                      decoration: InputDecoration(
                        labelText: t.gsprAssessmentRationaleLabel,
                        helperText: needsRationale ? t.gsprAssessmentRationaleRequiredHint : null,
                      ),
                      onChanged: (value) => setState(() {
                        _draftAssessment = assessment.copyWith(rationale: value);
                      }),
                    ),
                  const SizedBox(height: 12),
                  if (entry.requirement.isAssessable && assessment != null) ...[
                    Text(t.gsprEvidenceTitle, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    ...assessment.evidence.asMap().entries.map((entryIndex) {
                      final index = entryIndex.key;
                      final evidence = entryIndex.value;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      enabled: canAssess,
                                      decoration: InputDecoration(labelText: t.gsprEvidenceDocId),
                                      controller: TextEditingController(text: evidence.docId)
                                        ..selection = TextSelection.collapsed(offset: evidence.docId.length),
                                      onChanged: (value) => _updateEvidence(index, evidence.copyWith(docId: value)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      enabled: canAssess,
                                      decoration: InputDecoration(labelText: t.gsprEvidenceRevision),
                                      controller: TextEditingController(text: evidence.revision)
                                        ..selection = TextSelection.collapsed(offset: evidence.revision.length),
                                      onChanged: (value) => _updateEvidence(index, evidence.copyWith(revision: value)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                enabled: canAssess,
                                decoration: InputDecoration(labelText: t.gsprEvidenceLink),
                                controller: TextEditingController(text: evidence.link)
                                  ..selection = TextSelection.collapsed(offset: evidence.link.length),
                                onChanged: (value) => _updateEvidence(index, evidence.copyWith(link: value)),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                enabled: canAssess,
                                decoration: InputDecoration(labelText: t.gsprEvidenceLabel),
                                controller: TextEditingController(text: evidence.label)
                                  ..selection = TextSelection.collapsed(offset: evidence.label.length),
                                onChanged: (value) => _updateEvidence(index, evidence.copyWith(label: value)),
                              ),
                              if (canAssess)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _removeEvidence(index),
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(t.gsprEvidenceRemove),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (canAssess)
                      TextButton.icon(
                        onPressed: _addEvidence,
                        icon: const Icon(Icons.add),
                        label: Text(t.gsprEvidenceAdd),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      enabled: canAssess,
                      decoration: InputDecoration(labelText: t.gsprAssessmentOwnerLabel),
                      controller: TextEditingController(text: assessment.owner)
                        ..selection = TextSelection.collapsed(offset: assessment.owner.length),
                      onChanged: (value) => setState(() {
                        _draftAssessment = assessment.copyWith(owner: value);
                      }),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: canAssess ? () => _pickDueDate(assessment) : null,
                      child: AbsorbPointer(
                        child: TextField(
                          decoration: InputDecoration(labelText: t.gsprAssessmentDueDateLabel),
                          controller: TextEditingController(
                            text: assessment.dueDate == null
                                ? ''
                                : DateFormat('yyyy-MM-dd').format(assessment.dueDate!),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('${t.gsprColumnUpdated}: $updatedAt'),
                    Text('${t.gsprFieldUpdatedBy}: ${assessment.updatedBy.isEmpty ? '—' : assessment.updatedBy}'),
                  ],
                  if (canAssess) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _submitting ? null : _saveAssessment,
                        child: Text(t.gsprSave),
                      ),
                    ),
                  ],
                ],
              ),
            ),
      )
    );
  }

  void _addEvidence() {
    final assessment = _draftAssessment;
    if (assessment == null) return;
    setState(() {
      final updated = [...assessment.evidence, const GsprEvidence(docId: '', revision: '', link: '', label: '')];
      _draftAssessment = assessment.copyWith(evidence: updated);
    });
  }

  void _removeEvidence(int index) {
    final assessment = _draftAssessment;
    if (assessment == null) return;
    setState(() {
      final updated = [...assessment.evidence]..removeAt(index);
      _draftAssessment = assessment.copyWith(evidence: updated);
    });
  }

  void _updateEvidence(int index, GsprEvidence updatedEvidence) {
    final assessment = _draftAssessment;
    if (assessment == null) return;
    setState(() {
      final updated = [...assessment.evidence];
      updated[index] = updatedEvidence;
      _draftAssessment = assessment.copyWith(evidence: updated);
    });
  }

  Future<void> _pickDueDate(GsprAssessment assessment) async {
    final initial = assessment.dueDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _draftAssessment = assessment.copyWith(dueDate: picked);
      });
    }
  }
}

class _GsprProgress {
  final int total;
  final int assessed;
  final int open;
  final int notApplicable;

  const _GsprProgress({
    required this.total,
    required this.assessed,
    required this.open,
    required this.notApplicable,
  });
}

extension on GsprEvidence {
  GsprEvidence copyWith({
    String? docId,
    String? revision,
    String? link,
    String? label,
  }) {
    return GsprEvidence(
      docId: docId ?? this.docId,
      revision: revision ?? this.revision,
      link: link ?? this.link,
      label: label ?? this.label,
    );
  }
}
