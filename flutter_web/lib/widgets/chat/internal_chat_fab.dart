import 'package:flutter/material.dart';

class InternalChatFab extends StatelessWidget {
  final VoidCallback onTap;

  const InternalChatFab({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.large(
      heroTag: 'internal-chat',
      onPressed: onTap,
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.primary,
      child: const Icon(Icons.chat_bubble_outline, size: 32),
    );
  }
}
