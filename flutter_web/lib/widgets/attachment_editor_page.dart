import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

enum _EditorTool { pen, arrow }

class _Stroke {
  _Stroke({required this.color, required this.width, required this.tool});

  final Color color;
  final double width;
  final _EditorTool tool;
  final List<Offset> points = [];
  Offset? start;
  Offset? end;

  bool get isEmpty => tool == _EditorTool.pen ? points.length < 2 : start == null || end == null;
}

class AttachmentEditorPage extends StatefulWidget {
  const AttachmentEditorPage({super.key, required this.initialBytes, required this.title});

  final Uint8List initialBytes;
  final String title;

  @override
  State<AttachmentEditorPage> createState() => _AttachmentEditorPageState();
}

class _AttachmentEditorPageState extends State<AttachmentEditorPage> {
  static const _colors = [Colors.redAccent, Colors.amber, Colors.lightGreen];

  ui.Image? _image;
  bool _loading = true;
  final List<_Stroke> _strokes = [];
  _Stroke? _activeStroke;
  Color _activeColor = _colors.first;
  _EditorTool _tool = _EditorTool.pen;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final decoded = await decodeImageFromList(widget.initialBytes);
    if (!mounted) return;
    setState(() {
      _image = decoded;
      _loading = false;
    });
  }

  void _startStroke(Offset pos, Size size) {
    final stroke = _Stroke(color: _activeColor, width: 4, tool: _tool);
    if (_tool == _EditorTool.pen) {
      stroke.points.add(_normalize(pos, size));
    } else {
      stroke.start = _normalize(pos, size);
      stroke.end = stroke.start;
    }
    setState(() => _activeStroke = stroke);
  }

  void _updateStroke(Offset pos, Size size) {
    final stroke = _activeStroke;
    if (stroke == null) return;
    if (stroke.tool == _EditorTool.pen) {
      stroke.points.add(_normalize(pos, size));
    } else {
      stroke.end = _normalize(pos, size);
    }
    setState(() {});
  }

  void _endStroke() {
    final stroke = _activeStroke;
    if (stroke == null || stroke.isEmpty) {
      setState(() => _activeStroke = null);
      return;
    }
    setState(() {
      _strokes.add(stroke);
      _activeStroke = null;
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _activeStroke = null;
    });
  }

  Offset _normalize(Offset input, Size size) => Offset(
        (input.dx / size.width).clamp(0, 1),
        (input.dy / size.height).clamp(0, 1),
      );

  Offset _denormalize(Offset input, Size size) => Offset(input.dx * size.width, input.dy * size.height);

  Path _arrowHead(Offset start, Offset end, double length) {
    final dir = (end - start);
    final norm = dir.distance == 0 ? Offset.zero : dir / dir.distance;
    final perp = Offset(-norm.dy, norm.dx);
    final tip = end;
    final base = tip - norm * length;
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + perp.dx * length * 0.4, base.dy + perp.dy * length * 0.4)
      ..lineTo(base.dx - perp.dx * length * 0.4, base.dy - perp.dy * length * 0.4)
      ..close();
  }

  Future<Uint8List?> _renderAnnotated() async {
    final image = _image;
    if (image == null) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));

    paintImage(canvas: canvas, image: image, rect: Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));

    void paintStroke(_Stroke stroke) {
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke.width;

      if (stroke.tool == _EditorTool.pen) {
        final points = stroke.points.map((p) => _denormalize(p, Size(image.width.toDouble(), image.height.toDouble()))).toList();
        for (var i = 0; i < points.length - 1; i++) {
          canvas.drawLine(points[i], points[i + 1], paint);
        }
      } else {
        final start = _denormalize(stroke.start!, Size(image.width.toDouble(), image.height.toDouble()));
        final end = _denormalize(stroke.end!, Size(image.width.toDouble(), image.height.toDouble()));
        canvas.drawLine(start, end, paint);
        final head = _arrowHead(start, end, stroke.width * 5);
        canvas.drawPath(head, paint..style = PaintingStyle.fill);
      }
    }

    for (final stroke in _strokes) {
      paintStroke(stroke);
    }

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(image.width, image.height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _save() async {
    final bytes = await _renderAnnotated();
    if (bytes == null || !mounted) return;
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text('${t.attachment_editor_title} – ${widget.title}'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(t.attachment_editor_save),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _image!.width / _image!.height,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = Size(constraints.maxWidth, constraints.maxHeight);
                            return GestureDetector(
                              onPanStart: (d) => _startStroke(d.localPosition, size),
                              onPanUpdate: (d) => _updateStroke(d.localPosition, size),
                              onPanEnd: (_) => _endStroke(),
                              child: Container(
                                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                                child: CustomPaint(
                                  painter: _EditorPainter(
                                    image: _image!,
                                    strokes: _strokes,
                                    active: _activeStroke,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(t.attachment_editor_pen),
                            selected: _tool == _EditorTool.pen,
                            onSelected: (_) => setState(() => _tool = _EditorTool.pen),
                          ),
                          ChoiceChip(
                            label: Text(t.attachment_editor_arrow),
                            selected: _tool == _EditorTool.arrow,
                            onSelected: (_) => setState(() => _tool = _EditorTool.arrow),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        onPressed: _undo,
                        tooltip: t.attachment_editor_undo,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        onPressed: _clear,
                        tooltip: t.attachment_editor_clear,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(t.color, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Wrap(
                        spacing: 10,
                        children: [
                          for (final color in _colors)
                            GestureDetector(
                              onTap: () => setState(() => _activeColor = color),
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: color,
                                foregroundColor: Colors.black,
                                child: _activeColor == color ? const Icon(Icons.check, size: 16) : null,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  _EditorPainter({required this.image, required this.strokes, required this.active});

  final ui.Image image;
  final List<_Stroke> strokes;
  final _Stroke? active;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(canvas: canvas, image: image, rect: Offset.zero & size, fit: BoxFit.contain);

    for (final stroke in [...strokes, if (active != null) active!]) {
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke.width;

      if (stroke.tool == _EditorTool.pen) {
        if (stroke.points.length < 2) continue;
        final points = stroke.points.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
        for (var i = 0; i < points.length - 1; i++) {
          canvas.drawLine(points[i], points[i + 1], paint);
        }
      } else {
        if (stroke.start == null || stroke.end == null) continue;
        final start = Offset(stroke.start!.dx * size.width, stroke.start!.dy * size.height);
        final end = Offset(stroke.end!.dx * size.width, stroke.end!.dy * size.height);
        canvas.drawLine(start, end, paint);
        final head = _arrowHead(start, end, stroke.width * 5);
        canvas.drawPath(head, paint..style = PaintingStyle.fill);
      }
    }
  }

  Path _arrowHead(Offset start, Offset end, double length) {
    final dir = (end - start);
    final norm = dir.distance == 0 ? Offset.zero : dir / dir.distance;
    final perp = Offset(-norm.dy, norm.dx);
    final tip = end;
    final base = tip - norm * length;
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + perp.dx * length * 0.4, base.dy + perp.dy * length * 0.4)
      ..lineTo(base.dx - perp.dx * length * 0.4, base.dy - perp.dy * length * 0.4)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.strokes != strokes || oldDelegate.active != active;
}
