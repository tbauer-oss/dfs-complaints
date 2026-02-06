// lib/models/chat_user.dart

import '../utils/display_name.dart';

class ChatUserSummary {
  final String userId;
  final String displayName;
  final String email;
  final String? avatar;

  const ChatUserSummary({
    required this.userId,
    required this.displayName,
    required this.email,
    this.avatar,
  });

  factory ChatUserSummary.fromJson(Map<String, dynamic> json) => ChatUserSummary(
        userId: (json['userId'] ?? json['uid'] ?? '').toString(),
        displayName:
            deriveDisplayName((json['displayName'] ?? '').toString(), email: (json['email'] ?? '').toString()),
        email: (json['email'] ?? '').toString(),
        avatar: _cleanAvatar(json['avatar'] ?? json['avatarUrl'] ?? json['photoUrl']),
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'displayName': displayName,
        'email': email,
        if (avatar != null && avatar!.isNotEmpty) 'avatar': avatar,
      };
}

String? _cleanAvatar(dynamic value) {
  final str = value?.toString().trim();
  if (str == null || str.isEmpty) return null;
  return str;
}
