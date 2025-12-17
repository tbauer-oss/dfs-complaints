// lib/models/chat_user.dart

class ChatUserSummary {
  final String userId;
  final String displayName;
  final String? avatarUrl;

  const ChatUserSummary({required this.userId, required this.displayName, this.avatarUrl});

  factory ChatUserSummary.fromJson(Map<String, dynamic> json) => ChatUserSummary(
        userId: (json['userId'] ?? json['uid'] ?? '').toString(),
        displayName: (json['displayName'] ?? '').toString(),
        avatarUrl: json['avatar']?.toString() ?? json['avatarUrl']?.toString(),
      );
}
