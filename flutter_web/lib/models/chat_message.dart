// lib/models/chat_message.dart

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

  const ChatConversationSummary({
    required this.contextId,
    required this.meta,
    required this.lastRead,
    required this.unread,
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    final metaJson = json['meta'];
    return ChatConversationSummary(
      contextId: json['contextId'] as String,
      meta: metaJson is Map<String, dynamic> ? ChatContextMeta.fromJson(metaJson) : null,
      lastRead: json['lastRead'] != null ? DateTime.tryParse(json['lastRead'] as String) : null,
      unread: json['unread'] == true,
    );
  }
}
