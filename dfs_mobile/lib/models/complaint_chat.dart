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
  final bool acknowledged;

  const ComplaintChatMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.attachments = const [],
    this.replies = const [],
    this.readBy = const {},
    this.acknowledged = false,
  });

  ComplaintChatMessage copyWith({
    String? id,
    ComplaintChatRole? author,
    String? text,
    DateTime? createdAt,
    List<ComplaintChatAttachment>? attachments,
    List<ComplaintChatMessage>? replies,
    Set<ComplaintChatRole>? readBy,
    bool? acknowledged,
  }) {
    return ComplaintChatMessage(
      id: id ?? this.id,
      author: author ?? this.author,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      attachments: attachments ?? this.attachments,
      replies: replies ?? this.replies,
      readBy: readBy ?? this.readBy,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}

class ComplaintChatCase {
  final String ticket;
  final String product;
  final String customer;
  final String statusLabel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String channelLabel;
  final Color accentColor;

  const ComplaintChatCase({
    required this.ticket,
    required this.product,
    required this.customer,
    required this.statusLabel,
    required this.createdAt,
    required this.updatedAt,
    required this.channelLabel,
    required this.accentColor,
  });
}
