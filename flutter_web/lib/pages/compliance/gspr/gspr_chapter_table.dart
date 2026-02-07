import 'package:flutter/material.dart';

import '../../../api/client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/gspr.dart';
import 'gspr_item_detail_page.dart';

class GsprChapterTable extends StatefulWidget {
  final ApiClient api;
  final String chapter;
  final bool canEdit;
  final bool isPrrc;
  final bool isAdmin;
  final bool isQm;

  const GsprChapterTable({
    super.key,
    required this.api,
    required this.chapter,
    required this.canEdit,
    required this.isPrrc,
    required this.isAdmin,
    required this.isQm,
  });

  @override
  State<GsprChapterTable> createState() => _GsprChapterTableState();
}

class _GsprChapterTableState extends State<GsprChapterTable> {
  bool _loading = false;
  String? _error;
  List<GsprItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.gsprItems(chapter: widget.chapter);
      if (!mounted) return;
      setState(() {
        _items = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openItem(GsprItem item) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GsprItemDetailPage(
          api: widget.api,
          item: item,
          canEdit: widget.canEdit,
          isAdmin: widget.isAdmin,
          isPrrc: widget.isPrrc,
          isQm: widget.isQm,
        ),
      ),
    );
    if (updated == true) {
      await _load();
    }
  }

  Future<void> _createItem() async {
    final newItem = GsprItem.empty(chapter: widget.chapter);
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GsprItemDetailPage(
          api: widget.api,
          item: newItem,
          canEdit: widget.canEdit,
          isAdmin: widget.isAdmin,
          isPrrc: widget.isPrrc,
          isQm: widget.isQm,
          isNew: true,
        ),
      ),
    );
    if (updated == true) {
      await _load();
    }
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

  String _chapterTitle(AppLocalizations t) {
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final canAdd = widget.canEdit;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                _chapterTitle(t),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (canAdd)
                FilledButton.icon(
                  onPressed: _createItem,
                  icon: const Icon(Icons.add),
                  label: Text(t.gsprAddItem),
                ),
              IconButton(
                tooltip: t.gsprReload,
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(child: Text(t.gsprNoData))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(t.gsprColumnGsprRef)),
                        DataColumn(label: Text(t.gsprColumnAnnexRef)),
                        DataColumn(label: Text(t.gsprColumnRequirementTitle)),
                        DataColumn(label: Text(t.gsprColumnApplicable)),
                        DataColumn(label: Text(t.gsprColumnJustification)),
                        DataColumn(label: Text(t.gsprColumnImplementation)),
                        DataColumn(label: Text(t.gsprColumnEvidence)),
                        DataColumn(label: Text(t.gsprColumnLinks)),
                        DataColumn(label: Text(t.gsprColumnStatus)),
                        DataColumn(label: Text(t.gsprColumnPrrc)),
                        DataColumn(label: Text(t.gsprColumnVersion)),
                        DataColumn(label: Text(t.gsprColumnActions)),
                      ],
                      rows: _items.map((item) {
                        final annexRef = isEnglish ? item.annexRefEn : item.annexRefDe;
                        final title = isEnglish ? item.requirementTitleEn : item.requirementTitleDe;
                        final evidenceLabel =
                            item.evidence.isEmpty ? t.gsprEvidenceNone : '${item.evidence.length}';
                        final linkLabel = item.links.isEmpty ? t.gsprLinksNone : '${item.links.length}';
                        return DataRow(
                          cells: [
                            DataCell(Text(item.gsprCode)),
                            DataCell(Text(annexRef)),
                            DataCell(Text(title ?? '—')),
                            DataCell(Text(item.applicable ? t.gsprApplicableYes : t.gsprApplicableNo)),
                            DataCell(Text(item.applicable ? '—' : (item.justificationNa ?? ''))),
                            DataCell(Text(item.implementation ?? '')),
                            DataCell(Text(evidenceLabel)),
                            DataCell(Text(linkLabel)),
                            DataCell(Text(_statusLabel(t, item.status))),
                            DataCell(Text(item.approvedBy ?? '—')),
                            DataCell(Text(item.version.toString())),
                            DataCell(
                              TextButton(
                                onPressed: () => _openItem(item),
                                child: Text(widget.canEdit ? t.gsprEditItem : t.gsprViewItem),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
