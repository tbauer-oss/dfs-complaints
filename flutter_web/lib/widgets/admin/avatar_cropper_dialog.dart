import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class AvatarCropperDialog extends StatefulWidget {
  const AvatarCropperDialog({super.key, required this.imageBytes, this.outputSize = 512});

  final Uint8List imageBytes;
  final double outputSize;

  @override
  State<AvatarCropperDialog> createState() => _AvatarCropperDialogState();
}

class _AvatarCropperDialogState extends State<AvatarCropperDialog> {
  final _controller = TransformationController();
  final _boundaryKey = GlobalKey();
  double _scale = 1.0;
  double _viewportSize = 320;
  static const _minScale = 0.7;
  static const _maxScale = 4.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTransform);
    _controller.dispose();
    super.dispose();
  }

  void _handleTransform() {
    setState(() => _scale = _controller.value.getMaxScaleOnAxis());
  }

  Future<String?> _exportCropped() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final pixelRatio = (widget.outputSize / _viewportSize).clamp(1.0, 8.0);
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    final pngBytes = byteData.buffer.asUint8List();
    return 'data:image/png;base64,${base64Encode(pngBytes)}';
  }

  void _setScale(double scale) {
    final matrix = _controller.value;
    final dx = matrix.storage[12];
    final dy = matrix.storage[13];
    setState(() {
      _scale = scale;
      _controller.value = Matrix4.identity()
        ..translate(dx, dy)
        ..scale(scale);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Profilbild zuschneiden'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(constraints.maxWidth, constraints.maxHeight);
                  _viewportSize = size.clamp(240, 420);
                  return Center(
                    child: SizedBox.square(
                      dimension: _viewportSize,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            key: _boundaryKey,
                            child: ClipOval(
                              child: Container(
                                color: Colors.black,
                                child: InteractiveViewer(
                                  transformationController: _controller,
                                  minScale: _minScale,
                                  maxScale: _maxScale,
                                  clipBehavior: Clip.none,
                                  child: Image.memory(
                                    widget.imageBytes,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _AvatarCropOverlayPainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.zoom_out),
                Expanded(
                  child: Slider(
                    value: _scale.clamp(_minScale, _maxScale),
                    min: _minScale,
                    max: _maxScale,
                    onChanged: _setScale,
                  ),
                ),
                const Icon(Icons.zoom_in),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Positionieren und zoomen Sie das Bild innerhalb des Kreises. '
              'Der sichtbare Bereich wird als Avatar gespeichert.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            final dataUrl = await _exportCropped();
            if (dataUrl != null && context.mounted) {
              Navigator.of(context).pop(dataUrl);
            }
          },
          icon: const Icon(Icons.check),
          label: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

class _AvatarCropOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2 - 6;
    final center = size.center(Offset.zero);
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.55);
    final clearPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(clearPath, overlayPaint);
    final holePaint = Paint()..blendMode = BlendMode.clear;
    canvas.drawCircle(center, radius, holePaint);
    canvas.restore();

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<String?> showAvatarCropperDialog(BuildContext context, Uint8List imageBytes) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AvatarCropperDialog(imageBytes: imageBytes),
  );
}
