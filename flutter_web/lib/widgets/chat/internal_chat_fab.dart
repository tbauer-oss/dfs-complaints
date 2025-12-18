import 'package:flutter/material.dart';

class InternalChatFab extends StatefulWidget {
  final VoidCallback onTap;
  final bool hasUnread;

  const InternalChatFab({super.key, required this.onTap, this.hasUnread = false});

  @override
  State<InternalChatFab> createState() => _InternalChatFabState();
}

class _InternalChatFabState extends State<InternalChatFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant InternalChatFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasUnread != widget.hasUnread) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.hasUnread) {
      _blinkController.repeat(reverse: true);
    } else {
      _blinkController
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.large(
      heroTag: 'internal-chat',
      onPressed: widget.onTap,
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.primary,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Center(child: Icon(Icons.chat_bubble_outline, size: 32)),
          if (widget.hasUnread)
            Positioned(
              top: 6,
              right: 6,
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _blinkController,
                  curve: Curves.easeInOut,
                ),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
