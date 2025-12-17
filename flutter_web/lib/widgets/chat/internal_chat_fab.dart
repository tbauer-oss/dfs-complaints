import 'package:flutter/material.dart';

class InternalChatFab extends StatelessWidget {
  final VoidCallback onTap;

  const InternalChatFab({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FloatingActionButton.small(
          heroTag: 'internal-chat',
          onPressed: onTap,
          backgroundColor: Theme.of(context).colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.primary,
          child: const Icon(Icons.chat_bubble_outline),
        ),
      ),
    );
  }
}
