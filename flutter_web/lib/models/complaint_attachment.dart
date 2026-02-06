// lib/models/complaint_attachment.dart
import 'dart:typed_data';

class ComplaintAttachment {
  final String name;
  final Uint8List bytes;
  final String mime;

  const ComplaintAttachment({
    required this.name,
    required this.bytes,
    required this.mime,
  });

  bool get isImage => mime.toLowerCase().startsWith('image/');
}
