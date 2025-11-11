// lib/widgets/pdf_view_web.dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui; // platformViewRegistry ist hier im Web verfügbar
import 'package:dfs_mobile/web_compat/html_web.dart' as html;

class PdfInAppPage extends StatefulWidget {
  final String url;
  final String title;
  const PdfInAppPage({super.key, required this.url, required this.title});

  @override
  State<PdfInAppPage> createState() => _PdfInAppPageState();
}

class _PdfInAppPageState extends State<PdfInAppPage> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();

    // 1) PDF-URL relativ auflösen
    final pdfUrl = Uri.base.resolve(widget.url).toString();

    // 2) pdf.js Viewer relativ laden (keine führenden Slashes!)
    final viewerPath = 'pdfjs/web/viewer.html'
        '?file=${Uri.encodeComponent(pdfUrl)}#zoom=page-width&pagemode=none';

    final viewerUrl = Uri.base.resolve(viewerPath).toString();

    _viewType = 'pdfjs-${DateTime.now().millisecondsSinceEpoch}';

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = html.IFrameElement()
        ..src = viewerUrl
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: const SizedBox.expand(
        child: HtmlElementView(viewType: 'html-element-view'), // Platzhalter wird überschrieben
      ),
    );
  }
}
