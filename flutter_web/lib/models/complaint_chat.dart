// lib/models/complaint_chat.dart
import 'package:flutter/material.dart';

enum ComplaintChatRole { rep, admin }

enum ComplaintChatAttachmentType { image, video }

class ComplaintChatAttachment {
  final String name;
  final ComplaintChatAttachmentType type;
  final String url;
  final Duration? duration;

  const ComplaintChatAttachment({
    required this.name,
    required this.type,
    required this.url,
    this.duration,
  });
}

class ComplaintChatMessage {
  final String id;
  final ComplaintChatRole author;
  final String text;
  final DateTime createdAt;
  final List<ComplaintChatAttachment> attachments;
  final List<ComplaintChatMessage> replies;
  final Set<ComplaintChatRole> readBy;

  const ComplaintChatMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.attachments = const [],
    this.replies = const [],
    this.readBy = const {},
  });

  ComplaintChatMessage copyWith({
    String? id,
    ComplaintChatRole? author,
    String? text,
    DateTime? createdAt,
    List<ComplaintChatAttachment>? attachments,
    List<ComplaintChatMessage>? replies,
    Set<ComplaintChatRole>? readBy,
  }) {
    return ComplaintChatMessage(
      id: id ?? this.id,
      author: author ?? this.author,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      attachments: attachments ?? this.attachments,
      replies: replies ?? this.replies,
      readBy: readBy ?? this.readBy,
    );
  }
}

class ComplaintChatConversation {
  final String id;
  final String subject;
  final String contactLabel;
  final String repLabel;
  final String adminLabel;
  final String? ticketNumber;
  final String? internalNumber;
  final DateTime createdAt;
  final List<ComplaintChatMessage> messages;

  const ComplaintChatConversation({
    required this.id,
    required this.subject,
    required this.contactLabel,
    required this.createdAt,
    this.repLabel = '',
    this.adminLabel = '',
    this.ticketNumber,
    this.internalNumber,
    this.messages = const [],
  });

  ComplaintChatConversation copyWith({
    String? id,
    String? subject,
    String? contactLabel,
    String? repLabel,
    String? adminLabel,
    String? ticketNumber,
    String? internalNumber,
    DateTime? createdAt,
    List<ComplaintChatMessage>? messages,
  }) {
    return ComplaintChatConversation(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      contactLabel: contactLabel ?? this.contactLabel,
      repLabel: repLabel ?? this.repLabel,
      adminLabel: adminLabel ?? this.adminLabel,
      ticketNumber: ticketNumber ?? this.ticketNumber,
      internalNumber: internalNumber ?? this.internalNumber,
      createdAt: createdAt ?? this.createdAt,
      messages: messages ?? this.messages,
    );
  }

  int unreadCount(ComplaintChatRole role) {
    return messages
        .where((m) => m.author != role && !m.readBy.contains(role))
        .length;
  }

  DateTime get lastActivity =>
      messages.isEmpty ? createdAt : messages.last.createdAt;
}

class ComplaintChatInboxState {
  static final ValueNotifier<int> unreadForRep = ValueNotifier<int>(0);
  static final ValueNotifier<int> unreadForAdmin = ValueNotifier<int>(0);

  static void syncUnread(List<ComplaintChatConversation> conversations) {
    int rep = 0;
    int admin = 0;

    for (final c in conversations) {
      rep += c.unreadCount(ComplaintChatRole.rep);
      admin += c.unreadCount(ComplaintChatRole.admin);
    }

    if (unreadForRep.value != rep) unreadForRep.value = rep;
    if (unreadForAdmin.value != admin) unreadForAdmin.value = admin;
  }
}
