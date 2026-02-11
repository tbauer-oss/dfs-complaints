import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/gspr.dart';
import '../../../services/gspr_pdf_export.dart';
import '../../../utils/pdf_download.dart';
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
  static const String _fallbackSourceName = 'EUR-Lex / Access to European Union law';
  static const String _fallbackSourcePermalink = 'https://eur-lex.europa.eu/legal-content/de/ALL/?uri=CELEX:32017R0745';

  bool _loading = false;
  String? _error;
  List<GsprTdOption> _tds = const [];
  GsprSummary? _summary;
  String? _activeChapter;
  String? _initialRequirementId;
  bool _exportingPdf = false;
  bool _syncingSource = false;

  @override
  void initState() {
    super.initState();
    _loadTds();
  }

  Future<void> _openSourcePermalink(String permalink) async {
    final uri = Uri.tryParse(permalink);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatSyncDate(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('dd.MM.yyyy HH:mm').format(value.toLocal());
  }

  Future<void> _syncSourceNow() async {
    if (_syncingSource) return;
    setState(() {
      _syncingSource = true;
      _error = null;
    });
    try {
      await widget.api.gsprSyncSource();
      final selected = GsprTdState.selectedTd.value;
      if (selected != null) {
        await _loadSummary(selected.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GSPR-Synchronisierung erfolgreich gestartet/aktualisiert.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Synchronisierung fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _syncingSource = false);
    }
  }

  Future<void> _exportPdf() async {
    final selected = GsprTdState.selectedTd.value;
    final localizations = AppLocalizations.of(context);
    if (selected == null || _summary == null || _exportingPdf) {
      if (mounted) {
        final snackBarMessage = localizations?.gsprSelectTdHint ?? 'Please select an MDR-TD before exporting.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(snackBarMessage)));
      }
      return;
    }

    setState(() {
      _exportingPdf = true;
      _error = null;
    });
    // Ensure the export overlay is painted before PDF generation starts.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      debugPrint('[GSPR][Export] Start export for TD ${selected.id} (${selected.displayCode}).');
      final chapters = <GsprExportChapter>[];
      for (final chapter in const ['I', 'II', 'III']) {
        final response = await widget.api.gsprChapter(tdId: selected.id, chapter: chapter);
        final chapterIndex = chapter == 'I' ? 1 : chapter == 'II' ? 2 : 3;
        final chapterLabel = localizations != null ? _chapterLabel(localizations, chapterIndex) : 'Chapter $chapter';
        chapters.add(
          GsprExportChapter(
            chapterTitle: chapterLabel,
            entries: response.items,
          ),
        );
      }
      debugPrint('[GSPR][Export] Loaded chapter data (${chapters.length} chapter(s)).');

      final bytes = await buildGsprPdf(
        mdrTd: selected.displayCode,
        model: GsprExportModel(chapters: chapters, generatedAt: DateTime.now()),
        ci: DfsCiTheme.defaults(),
      );
      debugPrint('[GSPR][Export] PDF built (${bytes.length} bytes).');

      final filename = 'gspr_${selected.displayCode}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      if (kIsWeb) {
        debugPrint('[GSPR][Export] Web detected: triggering direct download.');
        await downloadPdf(bytes, filename);
        debugPrint('[GSPR][Export] Browser download triggered successfully.');
      } else {
        try {
          await Printing.layoutPdf(onLayout: (_) async => bytes);
          debugPrint('[GSPR][Export] Printing.layoutPdf started successfully.');
        } catch (layoutError) {
          debugPrint('[GSPR][Export] Printing.layoutPdf failed: $layoutError');
          await Printing.sharePdf(bytes: bytes, filename: filename);
          debugPrint('[GSPR][Export] Fallback Printing.sharePdf started successfully.');
        }
      }
    } catch (e, st) {
      debugPrint('[GSPR][Export] Export failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      final message = e.toString();
      setState(() => _error = message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
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
      setState(() {
        _error = e.toString();
        _tds = const [];
        GsprTdState.selectedTd.value = null;
        _summary = null;
      });
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
    _openChapterInternal(chapter);
  }

  void _openChapterInternal(String chapter, {String? initialRequirementId}) {
    if (GsprTdState.selectedTd.value == null) return;
    setState(() {
      _activeChapter = chapter;
      _initialRequirementId = initialRequirementId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selected = GsprTdState.selectedTd.value;
    final canExport = selected != null && _summary != null;

    if (_activeChapter != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: GsprChapterPage(
          chapter: _activeChapter!,
          api: widget.api,
          access: widget.access,
          tdOverride: selected,
          initialRequirementId: _initialRequirementId,
          key: ValueKey('${_activeChapter!}:${selected?.id ?? ''}:${_initialRequirementId ?? ''}'),
        ),
      );
    }

    return Stack(
      children: [
        DefaultTabController(
          length: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.gsprPageTitle, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                _buildSourceInfo(theme),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: theme.colorScheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${t.gsprSelectTdLabel}: ${selected.displayLabel}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _exportingPdf || !canExport ? null : _exportPdf,
                          icon: _exportingPdf
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Export PDF'),
                        ),
                      ],
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
                        onOpenChapter: _openChapterInternal,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_exportingPdf) _buildExportOverlay(theme),
      ],
    );
  }

  Widget _buildSourceInfo(ThemeData theme) {
    final sourceName = _summary?.sourceName.trim().isNotEmpty == true
        ? _summary!.sourceName.trim()
        : _fallbackSourceName;
    final permalink = _summary?.sourcePermalink.trim().isNotEmpty == true
        ? _summary!.sourcePermalink.trim()
        : _fallbackSourcePermalink;
    final syncDate = _formatSyncDate(_summary?.sourceLastSyncAt);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quelle der GSPR-Texte: $sourceName',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Der EUR-Lex-Permalink verweist immer auf die aktuelle konsolidierte Fassung.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Letzte Synchronisierung: $syncDate',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Letzter Synchronisierungsversuch: ${_formatSyncDate(_summary?.sourceLastAttemptAt)}',
              style: theme.textTheme.bodySmall,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _openSourcePermalink(permalink),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Permalink öffnen'),
                ),
                if (widget.access.canEdit)
                  FilledButton.icon(
                    onPressed: _syncingSource ? null : _syncSourceNow,
                    icon: _syncingSource
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: const Text('Jetzt synchronisieren'),
                  ),
              ],
            ),
            if ((_summary?.sourceLastError ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Letzter Sync-Fehler: ${_summary!.sourceLastError}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
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


  Widget _buildExportOverlay(ThemeData theme) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: theme.colorScheme.scrim.withOpacity(0.26),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 10,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.picture_as_pdf_outlined, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          'PDF wird erstellt…',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bitte einen Moment warten. Der Export läuft im Hintergrund und wird anschließend automatisch geöffnet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(minHeight: 10),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Große Datensätze können etwas länger dauern.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
