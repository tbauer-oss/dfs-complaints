import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/gspr.dart';

class DfsCiTheme {
  final PdfColor primaryColor;
  final PdfColor secondaryColor;
  final PdfColor neutralLight;
  final PdfColor neutralMid;
  final PdfColor neutralDark;
  final PdfColor headerBackground;
  final pw.Font? baseFont;
  final pw.Font? boldFont;
  final String documentVersion;

  const DfsCiTheme({
    required this.primaryColor,
    required this.secondaryColor,
    required this.neutralLight,
    required this.neutralMid,
    required this.neutralDark,
    required this.headerBackground,
    this.baseFont,
    this.boldFont,
    this.documentVersion = 'v1.0',
  });

  factory DfsCiTheme.defaults() {
    return const DfsCiTheme(
      primaryColor: PdfColor.fromInt(0xFF003A70),
      secondaryColor: PdfColor.fromInt(0xFF00A3E0),
      neutralLight: PdfColor.fromInt(0xFFF5F7FA),
      neutralMid: PdfColor.fromInt(0xFFD9DEE8),
      neutralDark: PdfColor.fromInt(0xFF1F2A3A),
      headerBackground: PdfColor.fromInt(0xFFEAF1F8),
    );
  }
}

class GsprExportModel {
  final List<GsprExportChapter> chapters;
  final DateTime generatedAt;

  const GsprExportModel({
    required this.chapters,
    required this.generatedAt,
  });
}

class GsprExportChapter {
  final String chapterTitle;
  final List<GsprChapterEntry> entries;

  const GsprExportChapter({
    required this.chapterTitle,
    required this.entries,
  });
}

class _ExportRow {
  final String chapterTitle;
  final bool isChapterBand;
  final bool isSectionRow;
  final String mdrRef;
  final String requirement;
  final String status;
  final String evaluation;
  final String rationale;
  final List<String> evidence;
  final String owner;
  final String dueDate;
  final String lastUpdate;
  final String comments;

  const _ExportRow({
    required this.chapterTitle,
    required this.isChapterBand,
    required this.isSectionRow,
    required this.mdrRef,
    required this.requirement,
    required this.status,
    required this.evaluation,
    required this.rationale,
    required this.evidence,
    required this.owner,
    required this.dueDate,
    required this.lastUpdate,
    required this.comments,
  });
}

Future<Uint8List> buildGsprPdf({
  required String mdrTd,
  required GsprExportModel model,
  required DfsCiTheme ci,
}) async {
  debugPrint('[GSPR][PDF] Build requested for $mdrTd.');
  final fonts = await _loadBundledFonts(ci);
  debugPrint('[GSPR][PDF] Fonts loaded.');
  final logoBytes = await _loadLogoBytes();
  debugPrint('[GSPR][PDF] Logo loaded: ${logoBytes != null}.');
  final doc = pw.Document(title: 'DFS Connect+ - GSPR Report');
  final sections = _buildSections(model);
  final textTheme = _buildTextTheme(ci);
  final generatedDate = _formatDate(model.generatedAt);
  final docIdentifier = sanitizeText('GSPR Report - $mdrTd - generated $generatedDate');

  const pageMargin = 20.0;
  final columnWidths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(70),
    1: const pw.FixedColumnWidth(250),
    2: const pw.FixedColumnWidth(62),
    3: const pw.FixedColumnWidth(150),
    4: const pw.FixedColumnWidth(130),
    5: const pw.FixedColumnWidth(170),
    6: const pw.FixedColumnWidth(62),
    7: const pw.FixedColumnWidth(62),
    8: const pw.FixedColumnWidth(72),
    9: const pw.FixedColumnWidth(150),
  };

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(pageMargin),
      theme: pw.ThemeData.withFont(
        base: fonts.base,
        bold: fonts.bold,
        fontFallback: [fonts.fallback],
      ),
      header: (context) => pw.Column(
        children: [
          _buildHeader(
            ci: ci,
            textTheme: textTheme,
            mdrTd: mdrTd,
            generatedDate: generatedDate,
            logoBytes: logoBytes,
          ),
          _tableHeaderBand(ci, textTheme),
        ],
      ),
      footer: (context) => _buildFooter(
        ci: ci,
        textTheme: textTheme,
        context: context,
        identifier: docIdentifier,
      ),
      build: (context) => [
        ..._buildSectionTables(
          sections: sections,
          ci: ci,
          textTheme: textTheme,
          columnWidths: columnWidths,
        ),
      ],
    ),
  );

  final pdfBytes = await doc.save();
  debugPrint('[GSPR][PDF] Document saved (${pdfBytes.length} bytes).');
  return pdfBytes;
}

pw.TextStyle _style(_PdfTextTheme t, {bool bold = false, PdfColor? color, double? size}) {
  return (bold ? t.bold : t.base).copyWith(color: color, fontSize: size);
}

class _PdfTextTheme {
  final pw.TextStyle base;
  final pw.TextStyle bold;

  const _PdfTextTheme({required this.base, required this.bold});
}

_PdfTextTheme _buildTextTheme(DfsCiTheme ci) {
  final base = pw.TextStyle(fontSize: 7.2, color: ci.neutralDark, lineSpacing: 1.22);
  final bold = pw.TextStyle(fontSize: 7.2, color: ci.neutralDark, fontWeight: pw.FontWeight.bold, lineSpacing: 1.22);
  return _PdfTextTheme(base: base, bold: bold);
}

pw.Widget _buildHeader({
  required DfsCiTheme ci,
  required _PdfTextTheme textTheme,
  required String mdrTd,
  required String generatedDate,
  required Uint8List? logoBytes,
}) {
  final titleText = sanitizeText('DFS Connect+ - GSPR Report');
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: pw.BoxDecoration(
      color: ci.headerBackground,
      border: pw.Border.all(color: ci.neutralMid, width: 0.6),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Text(titleText, style: _style(textTheme, bold: true, color: ci.primaryColor, size: 12)),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Text(sanitizeText('MDR-TD: $mdrTd'), style: _style(textTheme, bold: true, size: 9)),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Align(
            alignment: pw.Alignment.topRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(sanitizeText('Date: $generatedDate'), style: _style(textTheme, size: 8)),
                pw.SizedBox(height: 4),
                if (logoBytes != null)
                  pw.ConstrainedBox(
                    constraints: const pw.BoxConstraints(maxHeight: 20, maxWidth: 64),
                    child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                  )
                else
                  pw.Container(
                    width: 48,
                    height: 18,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: ci.neutralMid, width: 0.6),
                      color: PdfColors.white,
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Text('DFS', style: _style(textTheme, size: 7, color: ci.neutralMid)),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildFooter({
  required DfsCiTheme ci,
  required _PdfTextTheme textTheme,
  required pw.Context context,
  required String identifier,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: ci.neutralMid, width: 0.4))),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(sanitizeText(identifier), style: _style(textTheme, size: 7, color: ci.neutralDark))),
        pw.Text(sanitizeText('Page ${context.pageNumber} / ${context.pagesCount}'), style: _style(textTheme, size: 7, color: ci.neutralDark)),
      ],
    ),
  );
}

pw.Widget _tableHeaderBand(DfsCiTheme ci, _PdfTextTheme textTheme) {
  pw.Widget cell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(sanitizeText(text), style: _style(textTheme, bold: true, size: 7.8, color: ci.primaryColor)),
      );

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Table(
      border: pw.TableBorder.all(color: ci.neutralMid, width: 0.4),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(70),
        1: pw.FixedColumnWidth(250),
        2: pw.FixedColumnWidth(62),
        3: pw.FixedColumnWidth(150),
        4: pw.FixedColumnWidth(130),
        5: pw.FixedColumnWidth(170),
        6: pw.FixedColumnWidth(62),
        7: pw.FixedColumnWidth(62),
        8: pw.FixedColumnWidth(72),
        9: pw.FixedColumnWidth(150),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: ci.headerBackground),
          children: [
            cell('MDR Ref'),
            cell('Requirement / Subpoint text'),
            cell('Status'),
            cell('Assessment'),
            cell('Rationale / Justification'),
            cell('Evidence / Nachweise'),
            cell('Owner'),
            cell('Due Date'),
            cell('Last Update'),
            cell('Remarks / Comments'),
          ],
        ),
      ],
    ),
  );
}

List<pw.Widget> _buildSectionTables({
  required List<_ExportSection> sections,
  required DfsCiTheme ci,
  required _PdfTextTheme textTheme,
  required Map<int, pw.TableColumnWidth> columnWidths,
}) {
  final widgets = <pw.Widget>[];
  for (var i = 0; i < sections.length; i++) {
    final section = sections[i];
    widgets
      ..add(_buildChapterBand(section.chapterTitle, ci, textTheme))
      ..add(
        pw.Table(
          border: pw.TableBorder.all(color: ci.neutralMid, width: 0.4),
          columnWidths: columnWidths,
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
          children: _buildTableRows(section.rows, ci, textTheme),
        ),
      );
    if (i != sections.length - 1) {
      widgets.add(pw.SizedBox(height: 4));
    }
  }
  return widgets;
}

pw.Widget _buildChapterBand(String chapterTitle, DfsCiTheme ci, _PdfTextTheme textTheme) {
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 2, bottom: 3),
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: pw.BoxDecoration(
      color: ci.secondaryColor.shade(0.86),
      border: pw.Border.all(color: ci.neutralMid, width: 0.4),
    ),
    child: pw.Text(
      sanitizeText(chapterTitle),
      style: _style(textTheme, bold: true, size: 8.5, color: ci.primaryColor),
    ),
  );
}

List<pw.TableRow> _buildTableRows(List<_ExportRow> rows, DfsCiTheme ci, _PdfTextTheme textTheme) {
  final result = <pw.TableRow>[];

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final bg = row.isSectionRow
        ? ci.neutralLight
        : (i.isEven ? PdfColors.white : PdfColor.fromInt(0xFFFAFBFD));

    pw.Widget txt(String value, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.all(3.5),
          child: pw.Text(sanitizeText(value), style: _style(textTheme, bold: bold, size: 7.2)),
        );

    final evidenceWidget = pw.Padding(
      padding: const pw.EdgeInsets.all(3.5),
      child: row.evidence.isEmpty
          ? pw.Text('', style: _style(textTheme, size: 7.2))
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: row.evidence
                  .map((item) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 1),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('- ', style: _style(textTheme, size: 7.2)),
                            pw.Expanded(child: pw.Text(sanitizeText(item), style: _style(textTheme, size: 7.2))),
                          ],
                        ),
                      ))
                  .toList(growable: false),
            ),
    );

    result.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: bg),
        children: [
          txt(row.mdrRef, bold: row.isSectionRow),
          txt(row.requirement, bold: row.isSectionRow),
          txt(row.status),
          txt(row.evaluation),
          txt(row.rationale),
          evidenceWidget,
          txt(row.owner),
          txt(row.dueDate),
          txt(row.lastUpdate),
          txt(row.comments),
        ],
      ),
    );
  }

  return result;
}

List<_ExportSection> _buildSections(GsprExportModel model) {
  final sections = <_ExportSection>[];
  for (final chapter in model.chapters) {
    final rows = <_ExportRow>[];
    final safeChapterTitle = sanitizeText(chapter.chapterTitle);

    final byParent = <String?, List<GsprChapterEntry>>{};
    for (final entry in chapter.entries) {
      byParent.putIfAbsent(entry.requirement.parentId, () => []).add(entry);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.requirement.sortKey.compareTo(b.requirement.sortKey));
    }

    void walk(String? parentId) {
      final children = byParent[parentId] ?? const [];
      for (final entry in children) {
        final req = entry.requirement;
        final assessment = entry.assessment;
        final hasChildren = (byParent[req.id] ?? const []).isNotEmpty;
        final isSection = !req.isAssessable && hasChildren;
        final status = isSection ? '' : _statusText(assessment, req.isAssessable);
        final requirementText = '${'  ' * req.level}${req.title.isNotEmpty ? '${req.title}: ' : ''}${req.text}'.trim();
        final chunks = _splitForPage(
          requirement: requirementText,
          evaluation: _evaluationText(assessment),
          rationale: _rationaleText(assessment),
          comments: _commentsText(assessment),
          evidence: _evidenceLines(assessment),
        );

        for (var i = 0; i < chunks.length; i++) {
          final chunk = chunks[i];
          rows.add(
            _ExportRow(
              chapterTitle: safeChapterTitle,
              isChapterBand: false,
              isSectionRow: isSection,
              mdrRef: i == 0 ? _safe(req.ref) : '',
              requirement: i == 0 ? chunk.requirement : '${chunk.requirement} (cont.)',
              status: i == 0 ? status : '',
              evaluation: chunk.evaluation,
              rationale: chunk.rationale,
              evidence: chunk.evidence,
              owner: i == 0 ? _safe(assessment?.owner) : '',
              dueDate: i == 0 ? _formatDate(assessment?.dueDate) : '',
              lastUpdate: i == 0 ? _formatDate(assessment?.updatedAt) : '',
              comments: chunk.comments,
            ),
          );
        }

        walk(req.id);
      }
    }

    walk(null);
    sections.add(_ExportSection(chapterTitle: safeChapterTitle, rows: rows));
  }
  return sections;
}

class _ExportSection {
  final String chapterTitle;
  final List<_ExportRow> rows;

  const _ExportSection({required this.chapterTitle, required this.rows});
}

class _RowChunk {
  final String requirement;
  final String evaluation;
  final String rationale;
  final List<String> evidence;
  final String comments;

  const _RowChunk({
    required this.requirement,
    required this.evaluation,
    required this.rationale,
    required this.evidence,
    required this.comments,
  });
}

List<_RowChunk> _splitForPage({
  required String requirement,
  required String evaluation,
  required String rationale,
  required List<String> evidence,
  required String comments,
}) {
  const reqLimit = 470;
  const evalLimit = 260;
  const rationaleLimit = 250;
  const commentLimit = 250;
  const evidenceLineLimit = 95;

  final reqParts = _chunkText(requirement, reqLimit);
  final evalParts = _chunkText(evaluation, evalLimit);
  final rationaleParts = _chunkText(rationale, rationaleLimit);
  final commentParts = _chunkText(comments, commentLimit);
  final evidenceParts = evidence
      .expand((line) => _chunkText(line, evidenceLineLimit))
      .toList(growable: false);

  final count = [reqParts.length, evalParts.length, rationaleParts.length, commentParts.length, evidenceParts.length]
      .fold<int>(1, (max, current) => current > max ? current : max);

  String at(List<String> list, int i) => i < list.length ? list[i] : '';

  return List.generate(
    count,
    (i) => _RowChunk(
      requirement: at(reqParts, i),
      evaluation: at(evalParts, i),
      rationale: at(rationaleParts, i),
      evidence: at(evidenceParts, i).isEmpty ? const [] : [at(evidenceParts, i)],
      comments: at(commentParts, i),
    ),
    growable: false,
  );
}

List<String> _chunkText(String text, int limit) {
  final value = sanitizeText(text);
  if (value.isEmpty) return const [];
  final words = value.split(RegExp(r'\s+'));
  final chunks = <String>[];
  final buffer = StringBuffer();

  for (final word in words) {
    final candidate = buffer.isEmpty ? word : '${buffer.toString()} $word';
    if (candidate.length <= limit) {
      buffer
        ..clear()
        ..write(candidate);
      continue;
    }
    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString());
      buffer.clear();
      if (word.length <= limit) {
        buffer.write(word);
      } else {
        var start = 0;
        while (start < word.length) {
          final end = (start + limit).clamp(0, word.length);
          chunks.add(word.substring(start, end));
          start = end;
        }
      }
    } else {
      var start = 0;
      while (start < word.length) {
        final end = (start + limit).clamp(0, word.length);
        chunks.add(word.substring(start, end));
        start = end;
      }
    }
  }

  if (buffer.isNotEmpty) {
    chunks.add(buffer.toString());
  }

  return chunks;
}

String _statusText(GsprAssessment? assessment, bool isAssessable) {
  if (!isAssessable) return '';
  if (assessment == null) return 'Open';
  switch (assessment.status) {
    case GsprAssessmentStatus.fulfilled:
      return 'Compliant';
    case GsprAssessmentStatus.partial:
      return 'Planned / Partial';
    case GsprAssessmentStatus.notFulfilled:
      return 'Nonconformity';
    case GsprAssessmentStatus.notApplicable:
      return 'Not applicable';
    case GsprAssessmentStatus.notAssessed:
      return 'Open';
  }
}

String _evaluationText(GsprAssessment? assessment) {
  if (assessment == null) return '';
  final lines = <String>[];
  lines.add('Applicable: ${assessment.applicable ? 'Yes' : 'No'}');
  if (assessment.standards.trim().isNotEmpty) lines.add('Standards: ${assessment.standards.trim()}');
  if (assessment.edition.trim().isNotEmpty) lines.add('Edition: ${assessment.edition.trim()}');
  if (assessment.supportingDocs.trim().isNotEmpty) lines.add('Supporting docs: ${assessment.supportingDocs.trim()}');
  if (assessment.revision.trim().isNotEmpty) lines.add('Revision: ${assessment.revision.trim()}');
  if (assessment.date != null) lines.add('Date: ${_formatDate(assessment.date)}');
  return lines.join(' | ');
}

String _rationaleText(GsprAssessment? assessment) => _safe(assessment?.rationale);

String _commentsText(GsprAssessment? assessment) {
  if (assessment == null) return '';
  final lines = <String>[];
  if (assessment.comments.trim().isNotEmpty) lines.add(assessment.comments.trim());
  if (assessment.additionalDataRequired.trim().isNotEmpty) {
    lines.add('Additional data: ${assessment.additionalDataRequired.trim()}');
  }
  if (assessment.updatedBy.trim().isNotEmpty) lines.add('Updated by: ${assessment.updatedBy.trim()}');
  return lines.join(' | ');
}

List<String> _evidenceLines(GsprAssessment? assessment) {
  if (assessment == null || assessment.evidence.isEmpty) return const [];
  return assessment.evidence
      .map((item) {
        final parts = <String>[];
        if (item.label.trim().isNotEmpty) parts.add(item.label.trim());
        if (item.docId.trim().isNotEmpty) parts.add('ID: ${item.docId.trim()}');
        if (item.revision.trim().isNotEmpty) parts.add('Rev: ${item.revision.trim()}');
        if (item.link.trim().isNotEmpty) parts.add(item.link.trim());
        return parts.join(' | ');
      })
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
}

String _safe(String? value) => sanitizeText(value ?? '');

String _formatDate(DateTime? value) {
  if (value == null) return '';
  return DateFormat('yyyy-MM-dd').format(value);
}



class _PdfFonts {
  final pw.Font base;
  final pw.Font bold;
  final pw.Font fallback;

  const _PdfFonts({required this.base, required this.bold, required this.fallback});
}

Future<_PdfFonts> _loadBundledFonts(DfsCiTheme ci) async {
  if (ci.baseFont != null && ci.boldFont != null) {
    final fallbackData = await rootBundle.load('web/pdfjs/web/standard_fonts/LiberationSans-Italic.ttf');
    final baseFont = ci.baseFont;
    final boldFont = ci.boldFont;
    if (baseFont == null || boldFont == null) {
      throw StateError('Custom CI fonts were expected but not available.');
    }
    return _PdfFonts(
      base: baseFont,
      bold: boldFont,
      fallback: pw.Font.ttf(fallbackData),
    );
  }

  final baseData = await rootBundle.load('web/pdfjs/web/standard_fonts/LiberationSans-Regular.ttf');
  final boldData = await rootBundle.load('web/pdfjs/web/standard_fonts/LiberationSans-Bold.ttf');
  final fallbackData = await rootBundle.load('web/pdfjs/web/standard_fonts/LiberationSans-Italic.ttf');
  return _PdfFonts(
    base: pw.Font.ttf(baseData),
    bold: pw.Font.ttf(boldData),
    fallback: pw.Font.ttf(fallbackData),
  );
}

Future<Uint8List?> _loadLogoBytes() async {
  const logoCandidates = [
    'flutter_web/assets/dfs_logo.png',
    'assets/dfs_logo.png',
  ];

  for (final path in logoCandidates) {
    try {
      final bytes = await rootBundle.load(path);
      debugPrint('[GSPR][PDF] Loaded logo asset: $path');
      return bytes.buffer.asUint8List();
    } catch (e) {
      debugPrint('[GSPR][PDF] Failed to load logo asset $path: $e');
    }
  }

  debugPrint('[GSPR][PDF] Proceeding without logo.');
  return null;
}

String sanitizeText(String input) {
  final withoutInvisible = input
      .replaceAll(RegExp(r'[\u00AD\u200B-\u200D\uFEFF]'), '')
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '');
  return withoutInvisible.trim();
}

Future<Uint8List> buildGsprPdfWorstCaseDebug() async {
  final lorem = List.filled(120, 'Long regulatory justification text to stress wrapping and pagination.').join(' ');
  final mockEntry = GsprChapterEntry(
    requirement: GsprRequirement(
      id: '1(a)',
      ref: 'Annex I, Chapter I, 1(a)',
      chapter: 1,
      title: 'Safety by design',
      sortKey: '1.a',
      parentId: '1',
      level: 1,
      text: lorem,
      isAssessable: true,
      contextIds: const [],
      contextText: null,
    ),
    assessment: GsprAssessment.empty(tdId: 'debug', requirementId: '1(a)').copyWith(
      status: GsprAssessmentStatus.partial,
      rationale: lorem,
      comments: lorem,
      supportingDocs: lorem,
      evidence: [
        GsprEvidence(docId: 'DOC-001', revision: 'R03', link: 'https://example.local/doc/001', label: lorem),
      ],
    ),
  );

  return buildGsprPdf(
    mdrTd: 'MDR-TD99',
    model: GsprExportModel(
      generatedAt: DateTime.now(),
      chapters: [
        GsprExportChapter(chapterTitle: 'MDR Annex I – Chapter I', entries: List.filled(18, mockEntry)),
      ],
    ),
    ci: DfsCiTheme.defaults(),
  );
}
