import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<Uint8List> _identity(Uint8List bytes) async => bytes;

Future<void> printPdfImpl(Uint8List bytes) {
  return Printing.layoutPdf(onLayout: (_) => _identity(bytes));
}
