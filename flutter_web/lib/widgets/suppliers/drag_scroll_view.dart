import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class DragScrollView extends StatefulWidget {
  final ScrollController verticalController;
  final ScrollController horizontalController;
  final Widget child;
  final double dragThreshold;

  const DragScrollView({
    super.key,
    required this.verticalController,
    required this.horizontalController,
    required this.child,
    this.dragThreshold = 6,
  });

  @override
  State<DragScrollView> createState() => _DragScrollViewState();
}

class _DragScrollViewState extends State<DragScrollView> {
  bool _pointerDown = false;
  bool _dragging = false;
  Offset _startPosition = Offset.zero;
  double _startVerticalOffset = 0;
  double _startHorizontalOffset = 0;

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons != kPrimaryMouseButton) return;
    _pointerDown = true;
    _dragging = false;
    _startPosition = event.position;
    _startVerticalOffset = widget.verticalController.hasClients ? widget.verticalController.offset : 0;
    _startHorizontalOffset = widget.horizontalController.hasClients ? widget.horizontalController.offset : 0;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointerDown) return;
    final delta = event.position - _startPosition;
    if (!_dragging && delta.distance < widget.dragThreshold) return;
    _dragging = true;

    if (widget.verticalController.hasClients) {
      final maxV = widget.verticalController.position.maxScrollExtent;
      final nextV = (_startVerticalOffset - delta.dy).clamp(0.0, maxV);
      widget.verticalController.jumpTo(nextV);
    }
    if (widget.horizontalController.hasClients) {
      final maxH = widget.horizontalController.position.maxScrollExtent;
      final nextH = (_startHorizontalOffset - delta.dx).clamp(0.0, maxH);
      widget.horizontalController.jumpTo(nextH);
    }
  }

  void _endDrag() {
    _pointerDown = false;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _endDrag(),
      onPointerCancel: (_) => _endDrag(),
      child: widget.child,
    );
  }
}
