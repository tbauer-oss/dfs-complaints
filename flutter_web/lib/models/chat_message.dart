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
  final int? memberCount;
  final List<String> membersPreview;
  final bool isArchived;
  final Map<String, dynamic>? meta;

  const ChatConversationSummary({
    required this.conversationId,
    required this.type,
    required this.title,
    required this.participants,
    this.lastMessage,
    this.lastMessagePreview,
    this.lastAuthor,
    this.lastMessageAt,
    this.memberCount,
    this.membersPreview = const [],
    this.isArchived = false,
    this.meta,
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    final participants = (json['participants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatParticipant.fromJson)
        .toList();
    final meta = json['meta'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['meta'] as Map<String, dynamic>)
        : null;
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
      memberCount: json['memberCount'] is num ? (json['memberCount'] as num).toInt() : null,
      membersPreview: (json['membersPreview'] as List<dynamic>? ?? const [])
          .map((v) => v.toString())
          .where((v) => v.isNotEmpty)
          .toList(growable: false),
      isArchived: json['isArchived'] == true || json['archived'] == true,
      meta: meta,
    );
  }

  ChatConversationSummary copyWith({
    String? conversationId,
    String? type,
    String? title,
    List<ChatParticipant>? participants,
    String? lastMessage,
    String? lastMessagePreview,
    String? lastAuthor,
    DateTime? lastMessageAt,
    int? memberCount,
    List<String>? membersPreview,
    bool? isArchived,
    Map<String, dynamic>? meta,
  }) {
    return ChatConversationSummary(
      conversationId: conversationId ?? this.conversationId,
      type: type ?? this.type,
      title: title ?? this.title,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastAuthor: lastAuthor ?? this.lastAuthor,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      memberCount: memberCount ?? this.memberCount,
      membersPreview: membersPreview ?? this.membersPreview,
      isArchived: isArchived ?? this.isArchived,
      meta: meta ?? this.meta,
    );
  }

  bool get isGroup => type == 'group' || conversationId.startsWith('grp:');

  String? get groupIconId {
    final icon = meta?['groupIcon'];
    if (icon == null) return null;
    final value = icon.toString().trim();
    return value.isEmpty ? null : value;
  }

  String titleFor(String currentUserId) {
    if (title.isNotEmpty) {
      return title.contains('@') ? deriveDisplayNameFromEmail(title) : title;
    }
    if (type == 'group') return _groupTitle(currentUserId);
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

  String? membersLabelFor(String userId) {
    if (type != 'group') return null;
    final names = memberDisplayNames(excludeUserId: userId);
    if (names.isEmpty) return null;
    return 'Mitglieder: ${names.join(', ')}';
  }

  List<String> memberDisplayNames({String? excludeUserId}) =>
      _memberDisplayNames(excludeUserId: excludeUserId);

  String _groupTitle(String currentUserId) {
    final names = memberDisplayNames(excludeUserId: currentUserId);
    if (names.isEmpty) return 'Gruppe';
    return names.join(', ');
  }

  List<String> _memberDisplayNames({String? excludeUserId}) {
    final byProfile = participants
        .where((p) => excludeUserId == null || p.userId != excludeUserId)
        .map((p) => p.displayName.isNotEmpty ? p.displayName : (p.email ?? p.userId))
        .whereType<String>()
        .map((value) => deriveDisplayName(value, email: value))
        .toList();

    final fromPreview = membersPreview
        .where((email) => excludeUserId == null || email != excludeUserId)
        .map((email) => deriveDisplayName(null, email: email))
        .where((name) => name.isNotEmpty)
        .toList();

    final combined = [...byProfile, ...fromPreview];
    final seen = <String>{};
    final result = <String>[];
    for (final name in combined) {
      final normalized = name.trim();
      if (normalized.isEmpty) continue;
      final key = normalized.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(normalized);
    }
    return result;
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String authorId;
  final String authorName;
  final String? authorEmail;
  final String? authorUid;
  final String? sender;
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
    this.authorEmail,
    this.authorUid,
    this.sender,
    this.senderEmail,
    this.pending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: (json['id'] ?? json['msgId'] ?? '').toString(),
        conversationId: (json['convId'] ?? json['conversationId'] ?? '').toString(),
        authorId: (json['authorId'] ?? json['senderUid'] ?? '').toString(),
        authorName: _extractAuthorName(json),
        authorEmail: (json['authorEmail'] ?? json['senderEmail'])?.toString(),
        authorUid: json['authorUid']?.toString(),
        sender: json['sender']?.toString(),
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
        authorEmail: authorEmail,
        authorUid: authorUid,
        sender: sender,
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
