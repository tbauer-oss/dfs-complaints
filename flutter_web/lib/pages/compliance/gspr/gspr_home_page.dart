import 'package:flutter/material.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/fmea.dart';
import '../../../models/gspr.dart';
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
  List<FmeaRecord> _tds = const [];
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
      final list = await widget.api.adminFmeas();
      if (!mounted) return;
      list.sort((a, b) => a.mdrTd.compareTo(b.mdrTd));
      setState(() => _tds = list);
      final selected = GsprTdState.selectedTd.value;
      if (selected != null) {
        await _loadSummary(selected.id);
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

  String _tdLabel(FmeaRecord td) {
    final title = td.title.isNotEmpty ? td.title : td.productGroup;
    if (title.isNotEmpty) return '${td.mdrTd} – $title';
    return td.mdrTd;
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

    return Padding(
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
          DropdownButtonFormField<FmeaRecord>(
            value: selected,
            decoration: InputDecoration(labelText: t.gsprSelectTdLabel),
            items: _tds
                .map(
                  (td) => DropdownMenuItem(
                    value: td,
                    child: Text(_tdLabel(td)),
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
                '${t.gsprSelectTdLabel}: ${_tdLabel(selected)}',
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
          if (selected != null && _summary != null)
            Expanded(
              child: ListView(
                children: _summary!.chapters.map((chapter) {
                  final label = _chapterLabel(t, chapter.chapter);
                  return _GsprSummaryCard(
                    label: label,
                    summary: chapter,
                    statusLabel: _statusLabel(t, _summary!.status),
                    onTap: () => _openChapter(_roman(chapter.chapter)),
                  );
                }).toList(),
              ),
            ),
        ],
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
