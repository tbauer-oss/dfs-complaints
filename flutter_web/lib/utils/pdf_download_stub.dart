import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<void> downloadPdfImpl(Uint8List bytes, String filename) {
  return Printing.sharePdf(bytes: bytes, filename: filename);
}
