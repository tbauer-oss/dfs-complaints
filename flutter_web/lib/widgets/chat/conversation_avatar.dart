import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import 'group_icon_picker.dart';

class ConversationAvatar extends StatelessWidget {
  final ChatConversationSummary conversation;
  final String label;
  final String? avatarUrl;
  final double radius;
  final double? iconSize;
  final TextStyle? textStyle;

  const ConversationAvatar({
    super.key,
    required this.conversation,
    required this.label,
    this.avatarUrl,
    this.radius = 20,
    this.iconSize,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = label.trim();
    final fallback = trimmed.isNotEmpty ? trimmed.characters.first.toUpperCase() : '?';
    final groupIcon =
        conversation.isGroup ? iconForGroupIconId(conversation.groupIconId) : null;
    if (groupIcon != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: Icon(groupIcon, size: iconSize ?? radius),
      );
    }

    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    if (hasAvatar) {
      final diameter = radius * 2;
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.surfaceVariant,
        child: ClipOval(
          child: Image.network(
            avatarUrl!,
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: Text(
        fallback,
        style: textStyle ??
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
