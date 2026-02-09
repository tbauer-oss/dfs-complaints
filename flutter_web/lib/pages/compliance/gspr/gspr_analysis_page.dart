import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/fmea.dart';
import '../../../models/gspr.dart';
import 'gspr_chapter_page.dart';
import 'gspr_state.dart';

enum _GsprGroupBy {
  none,
  td,
  chapter,
  requirement,
}

class GsprAnalysisTab extends StatefulWidget {
  final ApiClient api;
  final GsprAccess access;
  final FmeaRecord? td;

  const GsprAnalysisTab({
    super.key,
    required this.api,
    required this.access,
    required this.td,
  });

  @override
  State<GsprAnalysisTab> createState() => _GsprAnalysisTabState();
}

class _GsprAnalysisTabState extends State<GsprAnalysisTab> {
  bool _loading = false;
  String? _error;
  GsprAnalysisResponse? _response;
  String? _chapter;
  final Set<GsprAssessmentStatus> _statusFilters = {};
  bool _onlyOpen = false;
  bool _onlyOverdue = false;
  bool _onlyDueSoon = false;
  bool _onlyMissingEvidence = false;
  int _dueSoonDays = 14;
  String _ownerFilter = '';
  String _search = '';
  int _page = 1;
  final int _pageSize = 50;
  _GsprGroupBy _groupBy = _GsprGroupBy.none;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GsprAnalysisTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.td?.id != widget.td?.id) {
      _page = 1;
      _response = null;
      _load();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final td = widget.td;
    if (td == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.gsprAnalysis(
        tdId: td.id,
        chapter: _chapter,
        statuses: _statusFilters.toList(growable: false),
        onlyOpen: _onlyOpen,
        onlyOverdue: _onlyOverdue,
        onlyDueSoon: _onlyDueSoon,
        onlyMissingEvidence: _onlyMissingEvidence,
        owner: _ownerFilter,
        search: _search,
        dueSoonDays: _dueSoonDays,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() => _response = response);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _page = 1);
      _load();
    });
  }

  String _statusLabel(AppLocalizations t, GsprAssessmentStatus status) {
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

  Color _statusColor(ThemeData theme, GsprAssessmentStatus status) {
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

  String _romanChapter(int chapter) {
    switch (chapter) {
      case 2:
        return 'II';
      case 3:
        return 'III';
      case 1:
      default:
        return 'I';
    }
  }

  String _chapterLabel(AppLocalizations t, int chapter) {
    switch (chapter) {
      case 2:
        return t.gsprChapterII;
      case 3:
        return t.gsprChapterIII;
      case 1:
      default:
        return t.gsprChapterI;
    }
  }

  void _openRequirement(GsprAnalysisRow row) {
    final td = widget.td;
    if (td == null) return;
    Navigator.of(context).pushNamed(
      '/compliance/gspr/chapter/${_romanChapter(row.chapter)}',
      arguments: GsprChapterArgs(
        td: td,
        access: widget.access,
        initialRequirementId: row.requirementId,
      ),
    );
  }

  Map<String, List<GsprAnalysisRow>> _groupRows(List<GsprAnalysisRow> rows, AppLocalizations t) {
    final sortedRows = [...rows]..sort((a, b) => a.ref.compareTo(b.ref));
    if (_groupBy == _GsprGroupBy.none) {
      return {'': sortedRows};
    }
    final groups = <String, List<GsprAnalysisRow>>{};
    for (final row in sortedRows) {
      String key;
      switch (_groupBy) {
        case _GsprGroupBy.td:
          key = row.mdrTd.isNotEmpty ? row.mdrTd : row.tdId;
          break;
        case _GsprGroupBy.chapter:
          key = _chapterLabel(t, row.chapter);
          break;
        case _GsprGroupBy.requirement:
          key = row.requirementId.split('.').first;
          break;
        case _GsprGroupBy.none:
        default:
          key = '';
      }
      groups.putIfAbsent(key, () => []).add(row);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final td = widget.td;

    if (td == null) {
      return Center(child: Text(t.gsprSelectTdHint));
    }

    final response = _response;
    final rows = response?.items ?? const [];
    final grouped = response != null ? _groupRows(rows, t) : <String, List<GsprAnalysisRow>>{};
    final totalPages = response == null
        ? 1
        : (response.total / _pageSize).ceil().clamp(1, 9999) as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (response != null)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryCard(
                label: t.gsprAnalysisSummaryTotal,
                value: response.summary.total.toString(),
              ),
              _SummaryCard(
                label: t.gsprAnalysisSummaryCompleted,
                value:
                    '${t.gsprAnalysisSummaryFulfilled}: ${response.summary.fulfilled}\n${t.gsprAnalysisSummaryNotApplicable}: ${response.summary.notApplicable}',
              ),
              _SummaryCard(
                label: t.gsprAnalysisSummaryOpen,
                value: response.summary.open.toString(),
              ),
              _SummaryCard(
                label: t.gsprAnalysisSummaryOverdue,
                value: response.summary.overdue.toString(),
              ),
              _SummaryCard(
                label: t.gsprAnalysisSummaryDueSoon,
                value: response.summary.dueSoon.toString(),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                value: _chapter,
                decoration: InputDecoration(labelText: t.gsprAnalysisFilterChapter),
                items: [
                  DropdownMenuItem(value: null, child: Text(t.gsprAnalysisFilterAllChapters)),
                  DropdownMenuItem(value: 'I', child: Text(t.gsprChapterI)),
                  DropdownMenuItem(value: 'II', child: Text(t.gsprChapterII)),
                  DropdownMenuItem(value: 'III', child: Text(t.gsprChapterIII)),
                ],
                onChanged: (value) {
                  setState(() {
                    _chapter = value;
                    _page = 1;
                  });
                  _load();
                },
              ),
            ),
            Wrap(
              spacing: 8,
              children: GsprAssessmentStatus.values.map((status) {
                final selected = _statusFilters.contains(status);
                return FilterChip(
                  label: Text(_statusLabel(t, status)),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _statusFilters.add(status);
                      } else {
                        _statusFilters.remove(status);
                      }
                      _page = 1;
                    });
                    _load();
                  },
                );
              }).toList(),
            ),
            FilterChip(
              label: Text(t.gsprAnalysisFilterOpenOnly),
              selected: _onlyOpen,
              onSelected: (value) {
                setState(() {
                  _onlyOpen = value;
                  _page = 1;
                });
                _load();
              },
            ),
            FilterChip(
              label: Text(t.gsprAnalysisFilterOverdueOnly),
              selected: _onlyOverdue,
              onSelected: (value) {
                setState(() {
                  _onlyOverdue = value;
                  _page = 1;
                });
                _load();
              },
            ),
            FilterChip(
              label: Text(t.gsprAnalysisFilterDueSoonOnly),
              selected: _onlyDueSoon,
              onSelected: (value) {
                setState(() {
                  _onlyDueSoon = value;
                  _page = 1;
                });
                _load();
              },
            ),
            ToggleButtons(
              isSelected: [7, 14, 30].map((days) => _dueSoonDays == days).toList(),
              onPressed: (index) {
                setState(() {
                  _dueSoonDays = [7, 14, 30][index];
                  _page = 1;
                });
                _load();
              },
              children: [7, 14, 30].map((days) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('${t.gsprAnalysisDueSoonLabel} $days'),
              )).toList(),
            ),
            FilterChip(
              label: Text(t.gsprAnalysisFilterMissingEvidence),
              selected: _onlyMissingEvidence,
              onSelected: (value) {
                setState(() {
                  _onlyMissingEvidence = value;
                  _page = 1;
                });
                _load();
              },
            ),
            SizedBox(
              width: 220,
              child: TextField(
                decoration: InputDecoration(labelText: t.gsprAnalysisFilterResponsible),
                onChanged: (value) {
                  setState(() => _ownerFilter = value);
                  _scheduleSearch();
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                decoration: InputDecoration(
                  labelText: t.gsprAnalysisSearchLabel,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) {
                  setState(() => _search = value);
                  _scheduleSearch();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<_GsprGroupBy>(
                value: _groupBy,
                decoration: InputDecoration(labelText: t.gsprAnalysisGroupByLabel),
                items: [
                  DropdownMenuItem(value: _GsprGroupBy.none, child: Text(t.gsprAnalysisGroupNone)),
                  DropdownMenuItem(value: _GsprGroupBy.td, child: Text(t.gsprAnalysisGroupTd)),
                  DropdownMenuItem(value: _GsprGroupBy.chapter, child: Text(t.gsprAnalysisGroupChapter)),
                  DropdownMenuItem(
                    value: _GsprGroupBy.requirement,
                    child: Text(t.gsprAnalysisGroupRequirement),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _groupBy = value ?? _GsprGroupBy.none);
                },
              ),
            ),
            IconButton(
              tooltip: t.gsprReload,
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: response == null
              ? const SizedBox.shrink()
              : rows.isEmpty
                  ? Center(child: Text(t.gsprAnalysisNoData))
                  : ListView(
                      children: grouped.entries.map((entry) {
                        final label = entry.key;
                        final groupRows = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (label.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(label, style: theme.textTheme.titleSmall),
                                ),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: [
                                    DataColumn(label: Text(t.gsprAnalysisColumnTd)),
                                    DataColumn(label: Text(t.gsprAnalysisColumnRef)),
                                    DataColumn(label: Text(t.gsprAnalysisColumnTitle)),
                                    DataColumn(label: Text(t.gsprAnalysisColumnStatus)),
                                    DataColumn(label: Text(t.gsprAnalysisColumnResponsible)),
                                    DataColumn(label: Text(t.gsprAnalysisColumnDueDate)),
                                    DataColumn(label: Text(t.gsprAnalysisColumnUpdated)),
                                    DataColumn(label: Text(t.gsprAnalysisColumnEvidence)),
                                  ],
                                  rows: groupRows.map((row) {
                                    final statusLabel = _statusLabel(t, row.status);
                                    final statusColor = _statusColor(theme, row.status);
                                    final dueDateText = row.dueDate == null
                                        ? '—'
                                        : DateFormat('yyyy-MM-dd').format(row.dueDate!);
                                    final updatedText = row.updatedAt == null
                                        ? '—'
                                        : DateFormat('yyyy-MM-dd').format(row.updatedAt!);
                                    final dueColor = row.overdue
                                        ? theme.colorScheme.error
                                        : row.dueSoon
                                            ? theme.colorScheme.secondary
                                            : theme.colorScheme.onSurface;
                                    return DataRow(
                                      onSelectChanged: (_) => _openRequirement(row),
                                      cells: [
                                        DataCell(Text(row.mdrTd.isNotEmpty ? row.mdrTd : row.tdId)),
                                        DataCell(Text(row.ref)),
                                        DataCell(Text(row.title)),
                                        DataCell(Row(
                                          children: [
                                            Icon(Icons.circle, size: 10, color: statusColor),
                                            const SizedBox(width: 6),
                                            Text(statusLabel),
                                          ],
                                        )),
                                        DataCell(Text(row.owner.isEmpty ? '—' : row.owner)),
                                        DataCell(Text(dueDateText, style: TextStyle(color: dueColor))),
                                        DataCell(Text(updatedText)),
                                        DataCell(
                                          row.missingEvidence
                                              ? Tooltip(
                                                  message: t.gsprAnalysisMissingEvidence,
                                                  child: Icon(
                                                    Icons.warning_amber,
                                                    color: theme.colorScheme.error,
                                                    size: 18,
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
        ),
        if (response != null)
          Row(
            children: [
              Text('${t.gsprAnalysisPagination} ${_page} / $totalPages'),
              const Spacer(),
              IconButton(
                onPressed: _page > 1
                    ? () {
                        setState(() => _page -= 1);
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: _page < totalPages
                    ? () {
                        setState(() => _page += 1);
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
