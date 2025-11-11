// lib/widgets/pdf_view_stub.dart
import 'package:flutter/material.dart';

/// Stub für Nicht-Web: zeigt einen Hinweis.
/// Optional: Du kannst hier url_launcher verwenden, um die PDF extern zu öffnen.
class PdfInAppPage extends StatelessWidget {
  final String url;
  final String title;
  const PdfInAppPage({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Der integrierte PDF-Viewer ist nur in der Web-Version verfügbar.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Pfad: ',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(url, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              // Wenn du url_launcher nutzt, kannst du hier einen Button zum Öffnen setzen.
              // Sonst einfach nur Info anzeigen.
            ],
          ),
        ),
      ),
    );
  }
}
