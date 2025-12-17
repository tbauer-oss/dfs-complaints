// lib/models/chat_message.dart

import 'dart:convert';

enum ChatMessageType { user, system }

enum ChatContextType { complaint, capa, audit, doc, general, dm }

class ChatMessage {
  final String id;
  final String contextId;
  final String authorId;
  final String authorName;
  final DateTime timestamp;
  final ChatMessageType type;
  final String body;
  final List<String> mentions;
  final List<String> flags;

  ChatMessage({
    required this.id,
    required this.contextId,
    required this.authorId,
    required this.authorName,
    required this.timestamp,
    required this.type,
    required this.body,
    required this.mentions,
    required this.flags,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      contextId: json['contextId'] as String,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String? ?? json['author'] as String? ?? json['authorId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: (json['type'] as String) == 'system' ? ChatMessageType.system : ChatMessageType.user,
      body: json['body'] as String? ?? '',
      mentions: (json['mentions'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      flags: (json['flags'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
    );
  }
}

class ChatContextMeta {
  final String contextId;
  final ChatContextType type;
  final String reference;
  final DateTime? updatedAt;
  final String? lastMessage;
  final String? lastAuthor;

  const ChatContextMeta({
    required this.contextId,
    required this.type,
    required this.reference,
    this.updatedAt,
    this.lastMessage,
    this.lastAuthor,
  });

  factory ChatContextMeta.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] as String?) ?? '';
    final type = ChatContextType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => ChatContextType.general,
    );

    return ChatContextMeta(
      contextId: json['contextId'] as String,
      type: type,
      reference: json['reference'] as String? ?? '',
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
      lastMessage: json['lastMessage'] as String?,
      lastAuthor: json['lastAuthor'] as String?,
    );
  }
}

class ChatConversationSummary {
  final String contextId;
  final ChatContextMeta? meta;
  final DateTime? lastRead;
  final bool unread;
  final List<ChatParticipant> participants;

  const ChatConversationSummary({
    required this.contextId,
    required this.meta,
    required this.lastRead,
    required this.unread,
    this.participants = const [],
  });

  bool get isDirectMessage => meta?.type == ChatContextType.dm || participants.isNotEmpty;

  String? otherEmail(String currentUserId) {
    final normalizedCurrentUserId = currentUserId.trim();
    final normalizedCurrentEmail = _decodeUserId(normalizedCurrentUserId) ?? normalizedCurrentUserId;
    if (participants.isNotEmpty) {
      final other = participants.firstWhere(
        (p) => p.userId != normalizedCurrentUserId,
        orElse: () => participants.first,
      );
      final decoded = _decodeUserId(other.userId);
      if (decoded != null) return decoded;
    }

    if (meta?.type == ChatContextType.dm || contextId.startsWith('dm:')) {
      final parts = contextId.split(':').skip(1).toList();
      if (parts.length >= 2) {
        final cleanedParts = parts.map(_decodeUserId).whereType<String>().toList();
        if (cleanedParts.length == 2) {
          return cleanedParts.firstWhere(
            (p) => p != normalizedCurrentEmail,
            orElse: () => cleanedParts.first,
          );
        }
      }
    }

    return null;
  }

  String resolvedTitle(String currentUserId, Map<String, String> displayNameDirectory) {
    if (isDirectMessage) {
      final normalizedCurrentId = currentUserId.trim();
      if (participants.isNotEmpty) {
        final other = participants.firstWhere(
          (p) => p.userId != normalizedCurrentId,
          orElse: () => participants.first,
        );
        if (other.displayName.trim().isNotEmpty) {
          return other.displayName.trim();
        }
      }

      final email = otherEmail(normalizedCurrentId);
      if (email != null) {
        final lowerEmail = email.toLowerCase();
        final normalizedEmail = _normalizeUserId(email);
        final name =
            displayNameDirectory[lowerEmail]?.trim() ?? displayNameDirectory[normalizedEmail]?.trim();
        if (name != null && name.isNotEmpty) return name;
      }

      final reference = meta?.reference?.trim() ?? '';
      if (reference.isNotEmpty && !reference.contains('@')) return reference;

      return 'Unbekannter Nutzer';
    }

    final reference = meta?.reference?.trim() ?? '';
    if (reference.contains('@')) return 'Unbekannter Nutzer';
    if (reference.isNotEmpty) return reference;
    return 'Konversation';
  }

  String titleFor(String currentUserId) {
    final isDm = meta?.type == ChatContextType.dm || participants.isNotEmpty;
    if (isDm && participants.isNotEmpty) {
      final other = participants.firstWhere(
        (p) => p.userId != currentUserId,
        orElse: () => participants.first,
      );
      if (other.displayName.trim().isNotEmpty) return other.displayName.trim();
    }
    if (meta?.reference != null && meta!.reference.trim().isNotEmpty) {
      return meta!.reference.trim();
    }
    return 'Konversation';
  }

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    final metaJson = json['meta'];
    final participants = (json['participants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatParticipant.fromJson)
        .toList(growable: false);
    return ChatConversationSummary(
      contextId: json['contextId'] as String,
      meta: metaJson is Map<String, dynamic> ? ChatContextMeta.fromJson(metaJson) : null,
      lastRead: json['lastRead'] != null ? DateTime.tryParse(json['lastRead'] as String) : null,
      unread: json['unread'] == true,
      participants: participants,
    );
  }
}

class ChatParticipant {
  final String userId;
  final String displayName;

  const ChatParticipant({required this.userId, required this.displayName});

  factory ChatParticipant.fromJson(Map<String, dynamic> json) => ChatParticipant(
        userId: (json['userId'] ?? '').toString(),
        displayName: (json['displayName'] ?? '').toString(),
      );
}

String? _decodeUserId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.contains('@')) return trimmed.toLowerCase();
  try {
    final padded = trimmed.padRight((trimmed.length + 3) ~/ 4 * 4, '=');
    final decoded = utf8.decode(base64Url.decode(padded));
    if (decoded.contains('@')) return decoded.toLowerCase();
  } catch (_) {
    return null;
  }
  return null;
}

String _normalizeUserId(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  if (!trimmed.contains('@')) return trimmed;
  return base64Url.encode(utf8.encode(trimmed)).replaceAll('=', '');
}
