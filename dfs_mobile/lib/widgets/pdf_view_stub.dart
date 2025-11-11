// lib/widgets/pdf_view_stub.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class PdfInAppPage extends StatefulWidget {
  final String url;
  final String title;
  const PdfInAppPage({super.key, required this.url, required this.title});

  @override
  State<PdfInAppPage> createState() => _PdfInAppPageState();
}

class _PdfInAppPageState extends State<PdfInAppPage> {
  @override
  void initState() {
    super.initState();
    _openExternal();
  }

  Future<void> _openExternal() async {
    final ok = await launchUrlString(
      widget.url,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF konnte nicht geöffnet werden.')),
      );
    }
    // Zurück zur Dashboard-Seite
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    // Minimaler Fallback-Bildschirm während des Öffnens
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
