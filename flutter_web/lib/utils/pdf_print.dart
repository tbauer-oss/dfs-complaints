import 'dart:typed_data';

import 'pdf_print_stub.dart'
    if (dart.library.html) 'pdf_print_web.dart';

Future<void> printPdf(Uint8List bytes) => printPdfImpl(bytes);
