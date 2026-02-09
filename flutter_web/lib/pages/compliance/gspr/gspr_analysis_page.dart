import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
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
  final GsprTdOption? td;

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
  bool _showAdvancedFilters = false;
  late final TextEditingController _searchController;
  late final TextEditingController _ownerController;
  final ScrollController _tableHorizontalController = ScrollController();
  final ScrollController _tableVerticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: _search);
    _ownerController = TextEditingController(text: _ownerFilter);
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
    _searchController.dispose();
    _ownerController.dispose();
    _tableHorizontalController.dispose();
    _tableVerticalController.dispose();
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

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _search = '';
      _page = 1;
    });
    _load();
  }

  void _clearOwner() {
    _ownerController.clear();
    setState(() {
      _ownerFilter = '';
      _page = 1;
    });
    _load();
  }

  Map<int, TableColumnWidth> _columnWidths(double tableWidth) {
    const widths = <int, double>{
      0: 120,
      1: 120,
      2: 320,
      3: 160,
      4: 160,
      5: 120,
      6: 120,
      7: 100,
    };
    final totalWidth = widths.values.fold<double>(0, (sum, value) => sum + value);
    final extra = (tableWidth - totalWidth) > 0 ? (tableWidth - totalWidth) / 8 : 0.0;
    return widths.map((index, value) => MapEntry(index, FixedColumnWidth(value + extra)));
  }

  Widget _buildStickyHeader(AppLocalizations t, double tableWidth) {
    final widths = _columnWidths(tableWidth);
    return Container(
      height: 44,
      color: Theme.of(context).colorScheme.surfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Table(
        columnWidths: widths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              Text(t.gsprAnalysisColumnTd, style: Theme.of(context).textTheme.labelLarge),
              Text(t.gsprAnalysisColumnRef, style: Theme.of(context).textTheme.labelLarge),
              Text(t.gsprAnalysisColumnTitle, style: Theme.of(context).textTheme.labelLarge),
              Text(t.gsprAnalysisColumnStatus, style: Theme.of(context).textTheme.labelLarge),
              Text(t.gsprAnalysisColumnResponsible, style: Theme.of(context).textTheme.labelLarge),
              Text(t.gsprAnalysisColumnDueDate, style: Theme.of(context).textTheme.labelLarge),
              Text(t.gsprAnalysisColumnUpdated, style: Theme.of(context).textTheme.labelLarge),
              Text(t.gsprAnalysisColumnEvidence, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ],
      ),
    );
  }

  List<TableRow> _buildTableRows(
    Map<String, List<GsprAnalysisRow>> grouped,
    AppLocalizations t,
    ThemeData theme,
  ) {
    final rows = <TableRow>[];
    for (final entry in grouped.entries) {
      if (entry.key.isNotEmpty) {
        rows.add(
          TableRow(
            decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant.withOpacity(0.4)),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(entry.key, style: theme.textTheme.titleSmall),
              ),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
            ],
          ),
        );
      }

      for (final row in entry.value) {
        final statusLabel = _statusLabel(t, row.status);
        final statusColor = _statusColor(theme, row.status);
        final dueDateText = row.dueDate == null ? '—' : DateFormat('yyyy-MM-dd').format(row.dueDate!);
        final updatedText = row.updatedAt == null ? '—' : DateFormat('yyyy-MM-dd').format(row.updatedAt!);
        final dueColor = row.overdue
            ? theme.colorScheme.error
            : row.dueSoon
                ? theme.colorScheme.secondary
                : theme.colorScheme.onSurface;
        final tapHandler = () => _openRequirement(row);
        rows.add(
          TableRow(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
              ),
            ),
            children: [
              _TableCell(text: row.mdrTd.isNotEmpty ? row.mdrTd : row.tdId, onTap: tapHandler),
              _TableCell(text: row.ref, onTap: tapHandler),
              _TableCell(text: row.title, onTap: tapHandler),
              _TableCell(
                onTap: tapHandler,
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: statusColor),
                    const SizedBox(width: 6),
                    Flexible(child: Text(statusLabel)),
                  ],
                ),
              ),
              _TableCell(text: row.owner.isEmpty ? '—' : row.owner, onTap: tapHandler),
              _TableCell(
                onTap: tapHandler,
                child: Text(dueDateText, style: TextStyle(color: dueColor)),
              ),
              _TableCell(text: updatedText, onTap: tapHandler),
              _TableCell(
                onTap: tapHandler,
                child: row.missingEvidence
                    ? Tooltip(
                        message: t.gsprAnalysisMissingEvidence,
                        child: Icon(Icons.warning_amber, color: theme.colorScheme.error, size: 18),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }
    }
    return rows;
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
        Card(
          elevation: 1,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GsprAnalysisHeaderBar(
              response: response,
              statusFilters: _statusFilters,
              chapter: _chapter,
              onlyOpen: _onlyOpen,
              onlyOverdue: _onlyOverdue,
              onlyDueSoon: _onlyDueSoon,
              onlyMissingEvidence: _onlyMissingEvidence,
              dueSoonDays: _dueSoonDays,
              groupBy: _groupBy,
              searchController: _searchController,
              ownerController: _ownerController,
              showAdvanced: _showAdvancedFilters,
              onToggleAdvanced: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
              onClearSearch: _clearSearch,
              onClearOwner: _clearOwner,
              onReload: _loading ? null : _load,
              onSearchChanged: (value) {
                setState(() => _search = value);
                _scheduleSearch();
              },
              onOwnerChanged: (value) {
                setState(() => _ownerFilter = value);
                _scheduleSearch();
              },
              onChapterChanged: (value) {
                setState(() {
                  _chapter = value;
                  _page = 1;
                });
                _load();
              },
              onStatusToggle: (status, selected) {
                setState(() {
                  if (selected) {
                    _statusFilters.add(status);
                  } else {
                    _statusFilters.remove(status);
                  }
                  _page = 1;
                });
                _load();
              },
              onToggleOpenOnly: (value) {
                setState(() {
                  _onlyOpen = value;
                  _page = 1;
                });
                _load();
              },
              onToggleOverdueOnly: (value) {
                setState(() {
                  _onlyOverdue = value;
                  _page = 1;
                });
                _load();
              },
              onToggleDueSoonOnly: (value) {
                setState(() {
                  _onlyDueSoon = value;
                  _page = 1;
                });
                _load();
              },
              onToggleMissingEvidence: (value) {
                setState(() {
                  _onlyMissingEvidence = value;
                  _page = 1;
                });
                _load();
              },
              onDueSoonDaysChanged: (value) {
                setState(() {
                  _dueSoonDays = value;
                  _page = 1;
                });
                _load();
              },
              onGroupByChanged: (value) => setState(() => _groupBy = value),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            elevation: 1,
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: response == null
                      ? const SizedBox.shrink()
                      : rows.isEmpty
                          ? Center(child: Text(t.gsprAnalysisNoData))
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                const minTableWidth = 1240.0;
                                final tableWidth = constraints.maxWidth > minTableWidth
                                    ? constraints.maxWidth
                                    : minTableWidth;

                                return Scrollbar(
                                  controller: _tableHorizontalController,
                                  thumbVisibility: true,
                                  trackVisibility: true,
                                  interactive: true,
                                  child: SingleChildScrollView(
                                    controller: _tableHorizontalController,
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: tableWidth),
                                      child: Column(
                                        children: [
                                          _buildStickyHeader(t, tableWidth),
                                          const Divider(height: 1),
                                          Expanded(
                                            child: Scrollbar(
                                              controller: _tableVerticalController,
                                              thumbVisibility: true,
                                              trackVisibility: true,
                                              interactive: true,
                                              notificationPredicate: (notif) =>
                                                  notif.metrics.axis == Axis.vertical,
                                              child: SingleChildScrollView(
                                                controller: _tableVerticalController,
                                                scrollDirection: Axis.vertical,
                                                child: ConstrainedBox(
                                                  constraints: BoxConstraints(minWidth: tableWidth),
                                                  child: Table(
                                                    columnWidths: _columnWidths(tableWidth),
                                                    defaultVerticalAlignment:
                                                        TableCellVerticalAlignment.middle,
                                                    children: _buildTableRows(grouped, t, theme),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                if (response != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant,
                      border: Border(top: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Row(
                      children: [
                        Text('${t.gsprAnalysisPagination} ${_page} / $totalPages'),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _page > 1
                              ? () {
                                  setState(() => _page -= 1);
                                  _load();
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
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
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class GsprAnalysisHeaderBar extends StatelessWidget {
  final GsprAnalysisResponse? response;
  final Set<GsprAssessmentStatus> statusFilters;
  final String? chapter;
  final bool onlyOpen;
  final bool onlyOverdue;
  final bool onlyDueSoon;
  final bool onlyMissingEvidence;
  final int dueSoonDays;
  final _GsprGroupBy groupBy;
  final TextEditingController searchController;
  final TextEditingController ownerController;
  final bool showAdvanced;
  final VoidCallback onToggleAdvanced;
  final VoidCallback onClearSearch;
  final VoidCallback onClearOwner;
  final VoidCallback? onReload;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onOwnerChanged;
  final ValueChanged<String?> onChapterChanged;
  final void Function(GsprAssessmentStatus status, bool selected) onStatusToggle;
  final ValueChanged<bool> onToggleOpenOnly;
  final ValueChanged<bool> onToggleOverdueOnly;
  final ValueChanged<bool> onToggleDueSoonOnly;
  final ValueChanged<bool> onToggleMissingEvidence;
  final ValueChanged<int> onDueSoonDaysChanged;
  final ValueChanged<_GsprGroupBy> onGroupByChanged;

  const GsprAnalysisHeaderBar({
    super.key,
    required this.response,
    required this.statusFilters,
    required this.chapter,
    required this.onlyOpen,
    required this.onlyOverdue,
    required this.onlyDueSoon,
    required this.onlyMissingEvidence,
    required this.dueSoonDays,
    required this.groupBy,
    required this.searchController,
    required this.ownerController,
    required this.showAdvanced,
    required this.onToggleAdvanced,
    required this.onClearSearch,
    required this.onClearOwner,
    required this.onReload,
    required this.onSearchChanged,
    required this.onOwnerChanged,
    required this.onChapterChanged,
    required this.onStatusToggle,
    required this.onToggleOpenOnly,
    required this.onToggleOverdueOnly,
    required this.onToggleDueSoonOnly,
    required this.onToggleMissingEvidence,
    required this.onDueSoonDaysChanged,
    required this.onGroupByChanged,
  });

  InputDecoration _inputDecoration(BuildContext context, String label, {Widget? prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildKpiStrip(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final summary = response?.summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final completed = summary.fulfilled + summary.notApplicable;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _KpiChip(label: t.gsprAnalysisSummaryTotal, value: summary.total.toString()),
        Tooltip(
          message: '${t.gsprAnalysisSummaryFulfilled}: ${summary.fulfilled}\n'
              '${t.gsprAnalysisSummaryNotApplicable}: ${summary.notApplicable}',
          child: _KpiChip(label: t.gsprAnalysisSummaryCompleted, value: completed.toString()),
        ),
        _KpiChip(label: t.gsprAnalysisSummaryOpen, value: summary.open.toString()),
        _KpiChip(
          label: t.gsprAnalysisSummaryOverdue,
          value: summary.overdue.toString(),
          accent: theme.colorScheme.error,
        ),
        _KpiChip(
          label: t.gsprAnalysisSummaryDueSoon,
          value: summary.dueSoon.toString(),
          accent: theme.colorScheme.secondary,
        ),
      ],
    );
  }

  Widget _buildStatusChips(BuildContext context, AppLocalizations t) {
    final orderedStatuses = [
      GsprAssessmentStatus.notAssessed,
      GsprAssessmentStatus.fulfilled,
      GsprAssessmentStatus.partial,
      GsprAssessmentStatus.notFulfilled,
      GsprAssessmentStatus.notApplicable,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: orderedStatuses.map((status) {
          final selected = statusFilters.contains(status);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(_statusLabelForChip(t, status)),
              selected: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (value) => onStatusToggle(status, value),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _statusLabelForChip(AppLocalizations t, GsprAssessmentStatus status) {
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

  Widget _buildAdvancedFilters(BuildContext context, AppLocalizations t) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ToggleButtons(
          isSelected: [7, 14, 30].map((days) => dueSoonDays == days).toList(),
          onPressed: (index) => onDueSoonDaysChanged([7, 14, 30][index]),
          constraints: const BoxConstraints(minHeight: 32, minWidth: 56),
          children: [7, 14, 30]
              .map((days) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('${t.gsprAnalysisDueSoonLabel} $days'),
                  ))
              .toList(),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            controller: ownerController,
            decoration: _inputDecoration(
              context,
              t.gsprAnalysisFilterResponsible,
              suffixIcon: ownerController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: onClearOwner,
                    ),
            ),
            onChanged: onOwnerChanged,
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<_GsprGroupBy>(
            value: groupBy,
            decoration: _inputDecoration(context, t.gsprAnalysisGroupByLabel),
            items: [
              DropdownMenuItem(value: _GsprGroupBy.none, child: Text(t.gsprAnalysisGroupNone)),
              DropdownMenuItem(value: _GsprGroupBy.td, child: Text(t.gsprAnalysisGroupTd)),
              DropdownMenuItem(value: _GsprGroupBy.chapter, child: Text(t.gsprAnalysisGroupChapter)),
              DropdownMenuItem(
                value: _GsprGroupBy.requirement,
                child: Text(t.gsprAnalysisGroupRequirement),
              ),
            ],
            onChanged: (value) => onGroupByChanged(value ?? _GsprGroupBy.none),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1200;
        final isMedium = constraints.maxWidth >= 900 && constraints.maxWidth < 1200;
        final isNarrow = constraints.maxWidth < 900;

        final advancedContent = _buildAdvancedFilters(context, t);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKpiStrip(context, t),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: isWide ? 320 : 260,
                  child: TextField(
                    controller: searchController,
                    decoration: _inputDecoration(
                      context,
                      t.gsprAnalysisSearchLabel,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: onClearSearch,
                            ),
                    ),
                    onChanged: onSearchChanged,
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    value: chapter,
                    decoration: _inputDecoration(context, t.gsprAnalysisFilterChapter),
                    items: [
                      DropdownMenuItem(value: null, child: Text(t.gsprAnalysisFilterAllChapters)),
                      DropdownMenuItem(value: 'I', child: Text(t.gsprChapterI)),
                      DropdownMenuItem(value: 'II', child: Text(t.gsprChapterII)),
                      DropdownMenuItem(value: 'III', child: Text(t.gsprChapterIII)),
                    ],
                    onChanged: onChapterChanged,
                  ),
                ),
                SizedBox(
                  width: isWide ? 420 : 320,
                  child: _buildStatusChips(context, t),
                ),
                FilterChip(
                  label: Text(t.gsprAnalysisFilterOpenOnly),
                  selected: onlyOpen,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: onToggleOpenOnly,
                ),
                FilterChip(
                  label: Text(t.gsprAnalysisFilterOverdueOnly),
                  selected: onlyOverdue,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: onToggleOverdueOnly,
                ),
                FilterChip(
                  label: Text(t.gsprAnalysisFilterDueSoonOnly),
                  selected: onlyDueSoon,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: onToggleDueSoonOnly,
                ),
                FilterChip(
                  label: Text(t.gsprAnalysisFilterMissingEvidence),
                  selected: onlyMissingEvidence,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: onToggleMissingEvidence,
                ),
                OutlinedButton.icon(
                  onPressed: isNarrow
                      ? () {
                          showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            builder: (context) => Padding(
                              padding: const EdgeInsets.all(16),
                              child: advancedContent,
                            ),
                          );
                        }
                      : onToggleAdvanced,
                  icon: Icon(isNarrow || !showAdvanced ? Icons.tune : Icons.expand_less),
                  label: const Text('Weitere Filter'),
                ),
                IconButton(
                  tooltip: t.gsprReload,
                  visualDensity: VisualDensity.compact,
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (!isNarrow)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: advancedContent,
                ),
                crossFadeState: showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            if (isMedium && showAdvanced) const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}

class _KpiChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _KpiChip({
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(color: accent ?? theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String? text;
  final Widget? child;
  final VoidCallback onTap;

  const _TableCell({
    this.text,
    this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = child ?? Text(text ?? '');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: content,
      ),
    );
  }
}
