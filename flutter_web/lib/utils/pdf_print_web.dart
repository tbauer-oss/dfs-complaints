import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> printPdfImpl(Uint8List bytes) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final iframe = html.IFrameElement()
    ..style.border = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..src = url;

  html.document.body?.append(iframe);
  try {
    await iframe.onLoad.first.timeout(const Duration(seconds: 5));
    iframe.contentWindow?.focus();
    iframe.contentWindow?.print();
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    iframe.remove();
    html.Url.revokeObjectUrl(url);
  }
}
