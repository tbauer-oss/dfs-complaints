import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImageOptimizationResult {
  final List<int> bytes;
  final String mime;
  final bool changed;
  final String? suggestedName;

  const ImageOptimizationResult({
    required this.bytes,
    required this.mime,
    this.changed = false,
    this.suggestedName,
  });
}

bool _isImageMime(String mime) => mime.toLowerCase().startsWith('image/');

String? _suggestJpgName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return null;
  final idx = name.lastIndexOf('.');
  if (idx > 0) {
    return '${name.substring(0, idx)}.jpg';
  }
  return '$name.jpg';
}

img.Image _resizeIfNeeded(img.Image source, int maxDimension) {
  if (maxDimension <= 0) return source;
  final maxSide = max(source.width, source.height);
  if (maxSide <= maxDimension) return source;
  final scale = maxDimension / maxSide;
  final width = max(1, (source.width * scale).round());
  final height = max(1, (source.height * scale).round());
  return img.copyResize(source, width: width, height: height);
}

ImageOptimizationResult optimizeImageForUpload(
  List<int> input,
  String mime, {
  String? originalName,
  int targetBytes = 1400000,
  int maxDimension = 1920,
}) {
  if (input.isEmpty || !_isImageMime(mime) || input.length <= targetBytes) {
    return ImageOptimizationResult(bytes: input, mime: mime);
  }

  try {
    final decoded = img.decodeImage(Uint8List.fromList(input));
    if (decoded == null) {
      return ImageOptimizationResult(bytes: input, mime: mime);
    }

    final plans = <({int dimension, int quality})>[
      (dimension: maxDimension, quality: 85),
      (dimension: (maxDimension * 0.85).round(), quality: 75),
      (dimension: (maxDimension * 0.7).round(), quality: 65),
      (dimension: (maxDimension * 0.55).round(), quality: 55),
    ];

    List<int>? bestBytes;
    var bestSize = input.length;

    for (final plan in plans) {
      final sized = _resizeIfNeeded(decoded, max(plan.dimension, 640));
      final encoded = img.encodeJpg(sized, quality: plan.quality);
      if (bestBytes == null || encoded.length < bestSize) {
        bestBytes = encoded;
        bestSize = encoded.length;
      }
      if (encoded.length <= targetBytes) {
        return ImageOptimizationResult(
          bytes: encoded,
          mime: 'image/jpeg',
          changed: true,
          suggestedName: _suggestJpgName(originalName),
        );
      }
    }

    if (bestBytes != null && bestSize < input.length) {
      return ImageOptimizationResult(
        bytes: bestBytes,
        mime: 'image/jpeg',
        changed: true,
        suggestedName: _suggestJpgName(originalName),
      );
    }
  } catch (_) {
    // ignore decoding/encoding errors and fall back to original bytes
  }

  return ImageOptimizationResult(bytes: input, mime: mime);
}
