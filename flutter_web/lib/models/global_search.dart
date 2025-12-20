// lib/models/global_search.dart
import 'package:flutter/material.dart';

enum GlobalSearchType {
  content,
  message,
  file,
  user,
}

class GlobalSearchResult {
  final String id;
  final GlobalSearchType type;
  final String title;
  final String snippet;
  final DateTime date;
  final String sender;
  final String routeTarget;
  final String category;
  final Object? payload;

  const GlobalSearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.snippet,
    required this.date,
    required this.sender,
    required this.routeTarget,
    required this.category,
    this.payload,
  });

  String get typeLabel {
    switch (type) {
      case GlobalSearchType.content:
        return 'Inhalt';
      case GlobalSearchType.message:
        return 'Nachricht';
      case GlobalSearchType.file:
        return 'Datei';
      case GlobalSearchType.user:
        return 'Nutzer';
    }
  }

  IconData get typeIcon {
    switch (type) {
      case GlobalSearchType.content:
        return Icons.article_outlined;
      case GlobalSearchType.message:
        return Icons.chat_bubble_outline;
      case GlobalSearchType.file:
        return Icons.insert_drive_file_outlined;
      case GlobalSearchType.user:
        return Icons.person_outline;
    }
  }
}
