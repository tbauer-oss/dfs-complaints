import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
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
    final windowBase = iframe.contentWindow;
    if (windowBase != null) {
      js_util.callMethod<void>(windowBase, 'focus', const <Object?>[]);
      js_util.callMethod<void>(windowBase, 'print', const <Object?>[]);
    }
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    iframe.remove();
    html.Url.revokeObjectUrl(url);
  }
}
