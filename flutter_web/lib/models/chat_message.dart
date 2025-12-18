// lib/models/chat_message.dart

import '../utils/display_name.dart';

class ChatParticipant {
  final String userId;
  final String displayName;
  final String? email;
  final String? avatar;

  const ChatParticipant({required this.userId, required this.displayName, this.email, this.avatar});

  factory ChatParticipant.fromJson(Map<String, dynamic> json) => ChatParticipant(
        userId: (json['userId'] ?? '').toString(),
        displayName: deriveDisplayName((json['displayName'] ?? '').toString(), email: json['email']?.toString()),
        email: json['email']?.toString(),
        avatar: json['avatar']?.toString(),
      );
}

class ChatConversationSummary {
  final String conversationId;
  final String type;
  final String title;
  final List<ChatParticipant> participants;
  final String? lastMessage;
  final String? lastMessagePreview;
  final String? lastAuthor;
  final DateTime? lastMessageAt;

  const ChatConversationSummary({
    required this.conversationId,
    required this.type,
    required this.title,
    required this.participants,
    this.lastMessage,
    this.lastMessagePreview,
    this.lastAuthor,
    this.lastMessageAt,
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    final participants = (json['participants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatParticipant.fromJson)
        .toList();
    return ChatConversationSummary(
      conversationId: (json['id'] ?? json['convId'] ?? json['conversationId'] ?? '').toString(),
      type: (json['type'] ?? 'dm').toString(),
      title: (json['title'] ?? '').toString(),
      participants: participants,
      lastMessage: json['lastMessage']?.toString() ?? json['lastMessagePreview']?.toString(),
      lastMessagePreview: json['lastMessagePreview']?.toString() ?? json['lastMsgPreview']?.toString(),
      lastAuthor: json['lastAuthor']?.toString(),
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.tryParse(json['lastMessageAt'].toString())
          : null,
    );
  }

  String titleFor(String currentUserId) {
    if (title.isNotEmpty) {
      return title.contains('@') ? deriveDisplayNameFromEmail(title) : title;
    }
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
  final String? senderEmail;
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
    this.senderEmail,
    this.pending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: (json['id'] ?? json['msgId'] ?? '').toString(),
        conversationId: (json['convId'] ?? json['conversationId'] ?? '').toString(),
        authorId: (json['authorId'] ?? json['senderUid'] ?? '').toString(),
        authorName: _extractAuthorName(json),
        senderEmail: json['senderEmail']?.toString(),
        timestamp: _parseTimestamp(json['timestamp'] ?? json['ts'] ?? json['tsMs']),
        body: (json['body'] ?? json['text'] ?? '').toString(),
        pending: false,
      );

  ChatMessage copyWith({bool? pending}) => ChatMessage(
        id: id,
        conversationId: conversationId,
        authorId: authorId,
        authorName: authorName,
        senderEmail: senderEmail,
        timestamp: timestamp,
        body: body,
        pending: pending ?? this.pending,
      );
}

String _extractAuthorName(Map<String, dynamic> json) {
  final senderName = json['senderName']?.toString();
  if (senderName != null && senderName.trim().isNotEmpty) return senderName.trim();
  final authorDisplayName = json['authorDisplayName']?.toString();
  if (authorDisplayName != null && authorDisplayName.trim().isNotEmpty) return authorDisplayName.trim();
  final authorName = json['authorName']?.toString();
  if (authorName != null && authorName.trim().isNotEmpty) return authorName.trim();
  final author = json['author']?.toString();
  if (author != null && author.trim().isNotEmpty) {
    final normalized = author.trim();
    return normalized.contains('@') ? deriveDisplayNameFromEmail(normalized) : normalized;
  }
  final email = json['senderEmail']?.toString();
  if (email != null && email.trim().isNotEmpty) return deriveDisplayNameFromEmail(email.trim());
  return 'Unbekannt';
}

DateTime _parseTimestamp(dynamic raw) {
  if (raw == null) return DateTime.now();
  if (raw is num) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } catch (_) {}
  }
  final parsedNumber = num.tryParse(raw.toString());
  if (parsedNumber != null) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(parsedNumber.toInt());
    } catch (_) {}
  }
  return DateTime.tryParse(raw.toString()) ?? DateTime.now();
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
