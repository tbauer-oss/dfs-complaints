// lib/models/chat_message.dart

class ChatParticipant {
  final String userId;
  final String displayName;
  final String? avatar;

  const ChatParticipant({required this.userId, required this.displayName, this.avatar});

  factory ChatParticipant.fromJson(Map<String, dynamic> json) => ChatParticipant(
        userId: (json['userId'] ?? '').toString(),
        displayName: (json['displayName'] ?? '').toString(),
        avatar: json['avatar']?.toString(),
      );
}

class ChatConversationSummary {
  final String conversationId;
  final String type;
  final String title;
  final List<ChatParticipant> participants;
  final String? lastMessage;
  final String? lastAuthor;
  final DateTime? lastMessageAt;

  const ChatConversationSummary({
    required this.conversationId,
    required this.type,
    required this.title,
    required this.participants,
    this.lastMessage,
    this.lastAuthor,
    this.lastMessageAt,
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    final participants = (json['participants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatParticipant.fromJson)
        .toList();
    return ChatConversationSummary(
      conversationId: (json['convId'] ?? json['conversationId'] ?? '').toString(),
      type: (json['type'] ?? 'dm').toString(),
      title: (json['title'] ?? '').toString(),
      participants: participants,
      lastMessage: json['lastMessage']?.toString(),
      lastAuthor: json['lastAuthor']?.toString(),
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.tryParse(json['lastMessageAt'].toString())
          : null,
    );
  }

  String titleFor(String currentUserId) {
    if (title.isNotEmpty) return title;
    final match = participants.firstWhere(
      (p) => p.userId != currentUserId,
      orElse: () => participants.isNotEmpty
          ? participants.first
          : ChatParticipant(userId: currentUserId, displayName: 'Unbekannt'),
    );
    return match.displayName.isEmpty ? 'Unbekannt' : match.displayName;
  }

  String displayNameFor(String userId) {
    final match = participants.firstWhere(
      (p) => p.userId == userId,
      orElse: () => participants.isNotEmpty
          ? participants.first
          : ChatParticipant(userId: userId, displayName: 'Unbekannt'),
    );
    return match.displayName.isEmpty ? 'Unbekannt' : match.displayName;
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String authorId;
  final String authorName;
  final DateTime timestamp;
  final String body;
  final bool pending;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.authorId,
    required this.authorName,
    required this.timestamp,
    required this.body,
    this.pending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: (json['id'] ?? json['msgId'] ?? '').toString(),
        conversationId: (json['convId'] ?? json['conversationId'] ?? '').toString(),
        authorId: (json['authorId'] ?? '').toString(),
        authorName: (json['authorDisplayName'] ?? json['authorName'] ?? json['author'] ?? '').toString(),
        timestamp: DateTime.tryParse((json['timestamp'] ?? json['ts']).toString()) ?? DateTime.now(),
        body: (json['body'] ?? '').toString(),
        pending: false,
      );

  ChatMessage copyWith({bool? pending}) => ChatMessage(
        id: id,
        conversationId: conversationId,
        authorId: authorId,
        authorName: authorName,
        timestamp: timestamp,
        body: body,
        pending: pending ?? this.pending,
      );
}

class ChatTimelineResponse {
  final List<ChatMessage> messages;
  final bool hasMoreBefore;
  final bool hasMoreAfter;

  ChatTimelineResponse({
    required this.messages,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
  });
}
