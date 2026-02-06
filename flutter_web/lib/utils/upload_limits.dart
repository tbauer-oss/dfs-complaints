import 'dart:math' as math;

typedef ComplaintFilePayload = ({String name, List<int> bytes, String mime, String? preview});

const int kMobileAttachmentLimitBytes = 8 * 1024 * 1024;
const int kWebUploadPayloadBudgetBytes = 4 * 1024 * 1024;
const int kWebUploadChunkBytes = (kWebUploadPayloadBudgetBytes * 3) ~/ 4;

int estimateBase64Size(int byteLength) {
  if (byteLength <= 0) return 0;
  return ((byteLength + 2) ~/ 3) * 4;
}

Future<void> sendInChunks(
  List<ComplaintFilePayload> files,
  Future<void> Function(List<ComplaintFilePayload> chunk) sender, {
  int chunkSizeBytes = kWebUploadChunkBytes,
}) async {
  if (files.isEmpty) return;
  final limit = math.max(chunkSizeBytes, 1);
  final buffer = <ComplaintFilePayload>[];
  var bufferBytes = 0;

  Future<void> flush() async {
    if (buffer.isEmpty) return;
    await sender(List<ComplaintFilePayload>.from(buffer));
    buffer
      ..clear();
    bufferBytes = 0;
  };

  for (final file in files) {
    final size = file.bytes.length;
    if (bufferBytes > 0 && bufferBytes + size > limit) {
      await flush();
    }
    buffer.add(file);
    bufferBytes += size;
    if (bufferBytes >= limit) {
      await flush();
    }
  }

  await flush();
}
