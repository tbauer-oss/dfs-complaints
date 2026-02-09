import 'package:flutter/material.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/gspr.dart';
import 'gspr_analysis_page.dart';
import 'gspr_chapter_page.dart';
import 'gspr_state.dart';

class GsprHomePage extends StatefulWidget {
  final ApiClient api;
  final GsprAccess access;

  const GsprHomePage({
    super.key,
    required this.api,
    required this.access,
  });

  @override
  State<GsprHomePage> createState() => _GsprHomePageState();
}

class _GsprHomePageState extends State<GsprHomePage> {
  bool _loading = false;
  String? _error;
  List<GsprTdOption> _tds = const [];
  GsprSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadTds();
  }

  Future<void> _loadTds() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.gsprTdOptions();
      if (!mounted) return;
      list.sort((a, b) => compareGsprTdLabels(a.label, b.label));
      final selected = GsprTdState.selectedTd.value;
      GsprTdOption? matched;
      if (selected != null) {
        for (final entry in list) {
          if (entry.id == selected.id) {
            matched = entry;
            break;
          }
        }
      }
      setState(() => _tds = list);
      if (matched != null) {
        GsprTdState.selectedTd.value = matched;
        await _loadSummary(matched.id);
      } else {
        setState(() {
          GsprTdState.selectedTd.value = null;
          _summary = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSummary(String tdId) async {
    try {
      final summary = await widget.api.gsprSummary(tdId: tdId);
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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

  void _openChapter(String chapter) {
    final td = GsprTdState.selectedTd.value;
    if (td == null) return;
    Navigator.of(context).pushNamed(
      '/compliance/gspr/chapter/$chapter',
      arguments: GsprChapterArgs(
        td: td,
        access: widget.access,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selected = GsprTdState.selectedTd.value;

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.gsprPageTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            DropdownButtonFormField<GsprTdOption>(
              value: selected,
              decoration: InputDecoration(labelText: t.gsprSelectTdLabel),
              items: _tds
                  .map(
                    (td) => DropdownMenuItem(
                      value: td,
                      child: Text(td.displayLabel),
                    ),
                  )
                  .toList(),
              onChanged: (td) {
                setState(() {
                  GsprTdState.selectedTd.value = td;
                  _summary = null;
                });
                if (td != null) {
                  _loadSummary(td.id);
                }
              },
            ),
            const SizedBox(height: 16),
            if (selected != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${t.gsprSelectTdLabel}: ${selected.displayLabel}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (selected == null)
              Text(
                t.gsprSelectTdHint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            if (selected != null && _summary != null && _summary!.readOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  t.gsprTdReadOnlyHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            TabBar(
              tabs: [
                Tab(text: t.gsprTabAssessments),
                Tab(text: t.gsprTabAnalysis),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                children: [
                  _buildSummaryTab(t, theme, selected),
                  GsprAnalysisTab(
                    api: widget.api,
                    access: widget.access,
                    td: selected,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roman(int chapter) {
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

  Widget _buildSummaryTab(AppLocalizations t, ThemeData theme, GsprTdOption? selected) {
    if (selected == null) {
      return Center(
        child: Text(
          t.gsprSelectTdHint,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      );
    }
    if (_summary == null) {
      return const SizedBox.shrink();
    }
    return ListView(
      children: _summary!.chapters.map((chapter) {
        final label = _chapterLabel(t, chapter.chapter);
        return _GsprSummaryCard(
          label: label,
          summary: chapter,
          statusLabel: _statusLabel(t, _summary!.status),
          onTap: () => _openChapter(_roman(chapter.chapter)),
        );
      }).toList(),
    );
  }
}

class _GsprSummaryCard extends StatelessWidget {
  final String label;
  final GsprSummaryChapter summary;
  final String statusLabel;
  final VoidCallback onTap;

  const _GsprSummaryCard({
    required this.label,
    required this.summary,
    required this.statusLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Card(
      elevation: 1,
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          '${summary.assessed}/${summary.total} ${t.gsprSummaryAssessedLabel}\n'
          '${summary.notApplicable} ${t.gsprSummaryNotApplicableLabel}\n'
          '${t.gsprSummaryStatusLabel}: $statusLabel',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
