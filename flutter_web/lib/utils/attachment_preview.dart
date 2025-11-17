import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

bool _isImageMime(String mime) => mime.toLowerCase().startsWith('image/');

String? createAttachmentPreview(List<int> bytes, String mime, {int maxDimension = 320}) {
  if (bytes.isEmpty || !_isImageMime(mime)) return null;
  try {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) return null;
    final maxSide = max(decoded.width, decoded.height);
    final target = max(maxDimension, 64);
    final resized = maxSide > target
        ? img.copyResize(
            decoded,
            width: (decoded.width * target / maxSide).round(),
            height: (decoded.height * target / maxSide).round(),
          )
        : decoded;
    final pngBytes = img.encodePng(resized, level: 6);
    return base64Encode(pngBytes);
  } catch (_) {
    return null;
  }
}
