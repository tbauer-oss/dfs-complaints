// lib/pages/complaint_summary_page.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../l10n/app_localizations.dart';
import '../models/complaint_attachment.dart';

enum ComplaintSummaryResult { dashboard, newComplaint }

class ComplaintSummaryPage extends StatefulWidget {
  final String ticket;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? account;
  final List<ComplaintAttachment> attachments;

  const ComplaintSummaryPage({
    super.key,
    required this.ticket,
    required this.createdAt,
    required this.payload,
    required this.account,
    required this.attachments,
  });

  @override
  State<ComplaintSummaryPage> createState() => _ComplaintSummaryPageState();
}

class _ComplaintSummaryPageState extends State<ComplaintSummaryPage> {
  bool _savingPdf = false;
  bool _printing = false;

  AppLocalizations get _t => AppLocalizations.of(context)!;

  String _payloadValue(String key) => (widget.payload[key] ?? '').toString().trim();
  String _accountValue(String key) => (widget.account?[key] ?? '').toString().trim();

  String _formattedDate() {
    final locale = Localizations.localeOf(context);
    final formatter = DateFormat.yMMMMd(locale.toLanguageTag()).add_Hm();
    return formatter.format(widget.createdAt.toLocal());
  }

  List<ComplaintAttachment> get _imageAttachments =>
      widget.attachments.where((a) => a.isImage).toList(growable: false);

  Future<pw.ImageProvider?> _loadLogo() async {
    const logoPaths = ['assets/dfs_logo.png', 'assets/dfs_logo.svg'];
    for (final path in logoPaths) {
      try {
        final bytes = (await rootBundle.load(path)).buffer.asUint8List();
        return pw.MemoryImage(bytes);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<Uint8List> _buildPdfBytes() async {
    final doc = pw.Document();
    final attachments = _imageAttachments;
    final logo = await _loadLogo();

    const spacing = 12.0;
    const smallSpacing = 6.0;

    final baseStyle = pw.TextStyle(fontSize: 11);
    final mutedStyle = baseStyle.copyWith(color: PdfColors.grey700);
    final labelStyle = baseStyle.copyWith(fontWeight: pw.FontWeight.bold);
    final titleStyle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
    final headerTitleStyle = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);

    final details = <String, String>{
      _t.segment: _payloadValue('segment'),
      _t.batch: _payloadValue('batch'),
      _t.qty: _payloadValue('qty'),
      _t.expiry: _payloadValue('expiry'),
      _t.returned_question: _payloadValue('returned'),
      _t.handling: _payloadValue('handling'),
    };

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 24),
        pageFormat: PdfPageFormat.a4,
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: smallSpacing),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_t.complaint_summary_title, style: headerTitleStyle),
                    pw.SizedBox(height: 2),
                    pw.Text(_t.complaint_summary_subtitle, style: mutedStyle),
                  ],
                ),
              ),
              if (logo != null)
                pw.Container(
                  height: 36,
                  width: 120,
                  alignment: pw.Alignment.topRight,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
            ],
          ),
        ),
        build: (_) => [
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(children: [
                _tableInfoCell('${_t.complaint_summary_ticket_label}:', widget.ticket, labelStyle, baseStyle),
                _tableInfoCell('${_t.complaint_summary_date_label}:', _formattedDate(), labelStyle, baseStyle),
              ]),
            ],
          ),
          pw.SizedBox(height: spacing),
          pw.Text(_t.complaint_summary_customer_label, style: titleStyle),
          pw.SizedBox(height: smallSpacing),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final line in _customerLines())
                if (line.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Text(line, style: baseStyle),
                  ),
            ],
          ),
          pw.SizedBox(height: spacing),
          pw.Text(_t.complaint_summary_article_label, style: titleStyle),
          pw.SizedBox(height: smallSpacing),
          pw.Text(_payloadValue('article'), style: baseStyle),
          pw.SizedBox(height: smallSpacing),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in details.entries)
                if (entry.value.isNotEmpty)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.4, color: PdfColors.grey600),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text('${entry.key}: ${entry.value}', style: baseStyle),
                  ),
            ],
          ),
          pw.SizedBox(height: spacing),
          pw.Text(_t.complaint_summary_description_label, style: titleStyle),
          pw.SizedBox(height: smallSpacing),
          pw.Text(_payloadValue('desc'), style: baseStyle, textAlign: pw.TextAlign.justify),
          if (attachments.isNotEmpty) ...[
            pw.SizedBox(height: spacing),
            pw.Text(_t.complaint_summary_images_label, style: titleStyle),
            pw.SizedBox(height: smallSpacing),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in attachments)
                  pw.Container(
                    width: 120,
                    height: 90,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.4, color: PdfColors.grey500),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Image(
                        pw.MemoryImage(a.bytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  pw.Widget _tableInfoCell(
    String label,
    String value,
    pw.TextStyle labelStyle,
    pw.TextStyle valueStyle,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(right: 8, bottom: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: labelStyle),
          pw.SizedBox(height: 2),
          pw.Text(value, style: valueStyle),
        ],
      ),
    );
  }

  List<String> _customerLines() {
    final company = _accountValue('company');
    final contact = _accountValue('contact');
    final street = _accountValue('street');
    final zip = _accountValue('zip');
    final city = _accountValue('city');
    final country = _accountValue('country');
    final phone = _accountValue('phone');
    final email = _accountValue('email');
    final lines = <String>[];
    if (company.isNotEmpty) lines.add(company);
    if (contact.isNotEmpty) lines.add('${_t.complaint_summary_customer_contact}: $contact');
    if (street.isNotEmpty) lines.add(street);
    final place = '${zip.isNotEmpty ? '$zip ' : ''}$city'.trim();
    if (place.isNotEmpty) lines.add(place);
    if (country.isNotEmpty) lines.add(country);
    if (phone.isNotEmpty) lines.add(phone);
    if (email.isNotEmpty) lines.add(email);
    return lines;
  }

  Future<void> _handleSavePdf() async {
    setState(() => _savingPdf = true);
    try {
      final bytes = await _buildPdfBytes();
      await Printing.sharePdf(bytes: bytes, filename: 'dfs_${widget.ticket}.pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t.complaint_summary_pdf_ready)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t.complaint_summary_pdf_error)));
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  Future<void> _handlePrint() async {
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(onLayout: (_) => _buildPdfBytes());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_t.complaint_summary_print_error)));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Widget _infoRow(String label, String value, {TextStyle? style}) {
    final displayValue = value.trim().isEmpty ? '-' : value.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: style ?? const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(displayValue),
      ],
    );
  }

  Widget _chip(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceVariant.withOpacity(.45),
      ),
      child: Text('$label: $value'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final article = _payloadValue('article');
    final desc = _payloadValue('desc');
    final images = _imageAttachments;

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(ComplaintSummaryResult.dashboard);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t.complaint_summary_title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(ComplaintSummaryResult.dashboard),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t.complaint_summary_subtitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _infoRow(
                                    _t.complaint_summary_ticket_label,
                                    widget.ticket,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _infoRow(
                                    _t.complaint_summary_date_label,
                                    _formattedDate(),
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _t.complaint_summary_customer_label,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            for (final line in _customerLines())
                              if (line.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(line),
                                ),
                            const SizedBox(height: 18),
                            Text(
                              _t.complaint_summary_article_label,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(article.isEmpty ? '-' : article, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (_payloadValue('batch').isNotEmpty)
                                  _chip(_t.batch, _payloadValue('batch')),
                                if (_payloadValue('qty').isNotEmpty)
                                  _chip(_t.qty, _payloadValue('qty')),
                                if (_payloadValue('handling').isNotEmpty)
                                  _chip(_t.handling, _payloadValue('handling')),
                                if (_payloadValue('segment').isNotEmpty)
                                  _chip(_t.segment, _payloadValue('segment')),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _t.complaint_summary_description_label,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: theme.colorScheme.surfaceVariant.withOpacity(.3),
                              ),
                              child: SelectableText(desc.isEmpty ? '-' : desc),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _t.complaint_summary_images_label,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            if (images.isEmpty)
                              Text(
                                _t.complaint_summary_images_empty,
                                style: theme.textTheme.bodyMedium,
                              )
                            else
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: images
                                    .map(
                                      (a) => ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(
                                          a.bytes,
                                          width: 110,
                                          height: 110,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _savingPdf ? null : _handleSavePdf,
                                  icon: _savingPdf
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.picture_as_pdf_outlined),
                                  label: Text(_t.complaint_summary_pdf),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: _printing ? null : _handlePrint,
                                  icon: _printing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.print_outlined),
                                  label: Text(_t.complaint_summary_print),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(context).pop(ComplaintSummaryResult.dashboard),
                            child: Text(_t.complaint_summary_back),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.of(context).pop(ComplaintSummaryResult.newComplaint),
                            child: Text(_t.complaint_summary_new),
                          ),
                        ),
                      ],
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
}
