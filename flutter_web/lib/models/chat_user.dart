// lib/models/chat_user.dart

import '../utils/display_name.dart';

class ChatUserSummary {
  final String userId;
  final String displayName;
  final String email;
  final String? avatarUrl;

  const ChatUserSummary({
    required this.userId,
    required this.displayName,
    required this.email,
    this.avatarUrl,
  });

  factory ChatUserSummary.fromJson(Map<String, dynamic> json) => ChatUserSummary(
        userId: (json['userId'] ?? json['uid'] ?? '').toString(),
        displayName:
            deriveDisplayName((json['displayName'] ?? '').toString(), email: (json['email'] ?? '').toString()),
        email: (json['email'] ?? '').toString(),
        avatarUrl: json['avatar']?.toString() ?? json['avatarUrl']?.toString(),
      );
}
