import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

enum _EditorTool { pen, arrow, text }

abstract class _Drawable {
  const _Drawable();
}

class _Stroke extends _Drawable {
  _Stroke({required this.color, required this.widthFactor, required this.tool});

  final Color color;
  final double widthFactor;
  final _EditorTool tool;
  final List<Offset> points = [];
  Offset? start;
  Offset? end;

  bool get isEmpty => tool == _EditorTool.pen ? points.length < 2 : start == null || end == null;
}

class _TextLabel extends _Drawable {
  _TextLabel({
    required this.position,
    required this.color,
    required this.text,
    required this.fontFactor,
  });

  final Offset position;
  final Color color;
  final String text;
  final double fontFactor;
}

class AttachmentEditorPage extends StatefulWidget {
  const AttachmentEditorPage({super.key, required this.initialBytes, required this.title});

  final Uint8List initialBytes;
  final String title;

  @override
  State<AttachmentEditorPage> createState() => _AttachmentEditorPageState();
}

class _AttachmentEditorPageState extends State<AttachmentEditorPage> {
  static const _defaultStrokeWidth = 4.0;
  static const _baseFontSize = 22.0;
  static const _colors = [Colors.redAccent, Colors.amber, Colors.lightGreen];

  ui.Image? _image;
  bool _loading = true;
  final List<_Drawable> _elements = [];
  _Stroke? _activeStroke;
  Color _activeColor = _colors.first;
  _EditorTool _tool = _EditorTool.pen;
  double _textScale = 1.0;
  int? _draggingLabelIndex;
  Offset? _dragPointerOffset;

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

  Rect _imageRect(Size canvasSize) {
    final img = _image!;
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(img.width.toDouble(), img.height.toDouble()),
      canvasSize,
    );
    final renderSize = fitted.destination;
    final offset = Offset(
      (canvasSize.width - renderSize.width) / 2,
      (canvasSize.height - renderSize.height) / 2,
    );
    return offset & renderSize;
  }

  void _startStroke(Offset pos, Rect rect) {
    if (_tool == _EditorTool.text) return;
    final stroke = _Stroke(
      color: _activeColor,
      widthFactor: _defaultStrokeWidth / rect.shortestSide,
      tool: _tool,
    );
    if (_tool == _EditorTool.pen) {
      stroke.points.add(_normalize(pos, rect));
    } else {
      stroke.start = _normalize(pos, rect);
      stroke.end = stroke.start;
    }
    setState(() => _activeStroke = stroke);
  }

  void _updateStroke(Offset pos, Rect rect) {
    final stroke = _activeStroke;
    if (stroke == null || _tool == _EditorTool.text) return;
    if (stroke.tool == _EditorTool.pen) {
      stroke.points.add(_normalize(pos, rect));
    } else {
      stroke.end = _normalize(pos, rect);
    }
    setState(() {});
  }

  void _endStroke() {
    final stroke = _activeStroke;
    if (stroke == null || stroke.isEmpty || _tool == _EditorTool.text) {
      setState(() => _activeStroke = null);
      return;
    }
    setState(() {
      _elements.add(stroke);
      _activeStroke = null;
    });
  }

  void _undo() {
    if (_elements.isEmpty) return;
    setState(() => _elements.removeLast());
  }

  void _clear() {
    setState(() {
      _elements.clear();
      _activeStroke = null;
    });
  }

  Future<void> _addTextLabel(Offset pos, Rect rect) async {
    final t = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final focusNode = FocusNode();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) => focusNode.requestFocus());

        return AlertDialog(
          title: Text(t.attachment_editor_add_text_title),
          content: TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(hintText: t.attachment_editor_add_text_hint),
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(t.attachment_editor_save),
            ),
          ],
        );
      },
    );

    controller.dispose();
    focusNode.dispose();

    if (!mounted || result == null || result.isEmpty) return;

    setState(() {
      _elements.add(
        _TextLabel(
          position: _normalize(pos, rect),
          color: _activeColor,
          text: result,
          fontFactor: (_baseFontSize * _textScale) / rect.shortestSide,
        ),
      );
    });
  }

  Offset _normalize(Offset input, Rect rect) => Offset(
        ((input.dx - rect.left) / rect.width).clamp(0, 1),
        ((input.dy - rect.top) / rect.height).clamp(0, 1),
      );

  Offset _denormalize(Offset input, Rect rect) => Offset(
        rect.left + input.dx * rect.width,
        rect.top + input.dy * rect.height,
      );

  TextPainter _buildTextPainter(_TextLabel label, double maxWidth, double fontSize) => TextPainter(
        text: TextSpan(
          text: label.text,
          style: TextStyle(color: label.color, fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )
        ..layout(maxWidth: maxWidth);

  Rect _labelRect(_TextLabel label, Rect rect) {
    final painter = _buildTextPainter(label, rect.width, label.fontFactor * rect.shortestSide);
    final topLeft = _denormalize(label.position, rect);
    return topLeft & painter.size;
  }

  int? _hitTestTextLabel(Offset pos, Rect rect) {
    for (int i = _elements.length - 1; i >= 0; i--) {
      final element = _elements[i];
      if (element is! _TextLabel) continue;
      if (_labelRect(element, rect).contains(pos)) return i;
    }
    return null;
  }

  void _startTextDrag(Offset pos, Rect rect) {
    final index = _hitTestTextLabel(pos, rect);
    if (index == null) return;
    final label = _elements[index] as _TextLabel;
    setState(() {
      _draggingLabelIndex = index;
      _dragPointerOffset = _normalize(pos, rect) - label.position;
    });
  }

  void _updateTextDrag(Offset pos, Rect rect) {
    final index = _draggingLabelIndex;
    if (index == null) return;
    final normalized = _normalize(pos, rect) - (_dragPointerOffset ?? Offset.zero);
    final clamped = Offset(normalized.dx.clamp(0.0, 1.0), normalized.dy.clamp(0.0, 1.0));
    final current = _elements[index] as _TextLabel;
    setState(() {
      _elements[index] = _TextLabel(
        position: clamped,
        color: current.color,
        text: current.text,
        fontFactor: current.fontFactor,
      );
    });
  }

  void _endTextDrag() {
    if (_draggingLabelIndex == null) return;
    setState(() {
      _draggingLabelIndex = null;
      _dragPointerOffset = null;
    });
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

  Future<Uint8List?> _renderAnnotated() async {
    final image = _image;
    if (image == null) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));

    paintImage(canvas: canvas, image: image, rect: Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));

    final imageRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

    void paintStroke(_Stroke stroke) {
      final strokeWidth = stroke.widthFactor * imageRect.shortestSide;
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;

      if (stroke.tool == _EditorTool.pen) {
        final points = stroke.points.map((p) => _denormalize(p, imageRect)).toList();
        for (var i = 0; i < points.length - 1; i++) {
          canvas.drawLine(points[i], points[i + 1], paint);
        }
      } else {
        final start = _denormalize(stroke.start!, imageRect);
        final end = _denormalize(stroke.end!, imageRect);
        canvas.drawLine(start, end, paint);
        final head = _arrowHead(start, end, strokeWidth * 5);
        canvas.drawPath(head, paint..style = PaintingStyle.fill);
      }
    }

    void paintLabel(_TextLabel label) {
      final painter = _buildTextPainter(label, image.width.toDouble(), label.fontFactor * imageRect.shortestSide);

      final pos = _denormalize(label.position, imageRect);
      painter.paint(canvas, pos);
    }

    for (final element in _elements) {
      if (element is _Stroke) {
        paintStroke(element);
      } else if (element is _TextLabel) {
        paintLabel(element);
      }
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
                            final rect = _imageRect(size);
                            return GestureDetector(
                              onPanStart: (d) => _tool == _EditorTool.text
                                  ? _startTextDrag(d.localPosition, rect)
                                  : _startStroke(d.localPosition, rect),
                              onPanUpdate: (d) => _tool == _EditorTool.text
                                  ? _updateTextDrag(d.localPosition, rect)
                                  : _updateStroke(d.localPosition, rect),
                              onPanEnd: (_) => _tool == _EditorTool.text ? _endTextDrag() : _endStroke(),
                              onTapUp: _tool == _EditorTool.text && _draggingLabelIndex == null
                                  ? (d) => _addTextLabel(d.localPosition, rect)
                                  : null,
                              child: Container(
                                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                                child: CustomPaint(
                                  painter: _EditorPainter(
                                    image: _image!,
                                    elements: _elements,
                                    active: _activeStroke,
                                    imageRect: rect,
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
                          ChoiceChip(
                            label: Text(t.attachment_editor_text),
                            selected: _tool == _EditorTool.text,
                            onSelected: (_) => setState(() => _tool = _EditorTool.text),
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
                  if (_tool == _EditorTool.text) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(t.attachment_editor_text_size,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Slider(
                            value: _textScale,
                            onChanged: (value) => setState(() => _textScale = value),
                            min: 0.6,
                            max: 2.2,
                            divisions: 8,
                            label: '${(_textScale * 100).round()}%',
                          ),
                        ),
                      ],
                    ),
                  ],
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
  _EditorPainter({required this.image, required this.elements, required this.active, required this.imageRect});

  final ui.Image image;
  final List<_Drawable> elements;
  final _Stroke? active;
  final Rect imageRect;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(canvas: canvas, image: image, rect: imageRect, fit: BoxFit.contain);

    for (final element in [...elements, if (active != null) active!]) {
      if (element is _Stroke) {
        final stroke = element;
        final strokeWidth = stroke.widthFactor * imageRect.shortestSide;
        final paint = Paint()
          ..color = stroke.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth;

        if (stroke.tool == _EditorTool.pen) {
          if (stroke.points.length < 2) continue;
          final points = stroke.points
              .map((p) => Offset(imageRect.left + p.dx * imageRect.width, imageRect.top + p.dy * imageRect.height))
              .toList();
          for (var i = 0; i < points.length - 1; i++) {
            canvas.drawLine(points[i], points[i + 1], paint);
          }
        } else {
          if (stroke.start == null || stroke.end == null) continue;
          final start = Offset(
            imageRect.left + stroke.start!.dx * imageRect.width,
            imageRect.top + stroke.start!.dy * imageRect.height,
          );
          final end = Offset(
            imageRect.left + stroke.end!.dx * imageRect.width,
            imageRect.top + stroke.end!.dy * imageRect.height,
          );
          canvas.drawLine(start, end, paint);
          final head = _arrowHead(start, end, strokeWidth * 5);
          canvas.drawPath(head, paint..style = PaintingStyle.fill);
        }
      } else if (element is _TextLabel) {
        final painter = TextPainter(
          text: TextSpan(
            text: element.text,
            style: TextStyle(
              color: element.color,
              fontSize: element.fontFactor * imageRect.shortestSide,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )
          ..layout(maxWidth: imageRect.width);

        final pos = Offset(
          imageRect.left + element.position.dx * imageRect.width,
          imageRect.top + element.position.dy * imageRect.height,
        );
        painter.paint(canvas, pos);
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
      oldDelegate.image != image ||
      oldDelegate.elements != elements ||
      oldDelegate.active != active ||
      oldDelegate.imageRect != imageRect;
}
