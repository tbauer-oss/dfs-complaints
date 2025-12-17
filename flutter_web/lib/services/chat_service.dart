// lib/services/chat_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../models/chat_message.dart';
import '../models/portal_user.dart';

class ChatService {
  final ApiClient api;

  ChatService(this.api);

  String directContextId(String userA, String userB) {
    final sorted = [userA.trim().toLowerCase(), userB.trim().toLowerCase()]..sort();
    return 'dm:${sorted.first}:${sorted.last}';
  }

  Future<List<PortalUserSummary>> fetchStaffUsers() async {
    final uri = api.buildUri('/api/admin/users', query: {'scope': 'staff', 'includeInactive': 'false'});
    final response = await http.get(uri, headers: api.portalHeaders());
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonBody['users'] as List<dynamic>? ?? const [];
    final users = list
        .whereType<Map<String, dynamic>>()
        .map(PortalUserSummary.fromJson)
        .toList(growable: false);
    users.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return users;
  }

  Future<List<ChatConversationSummary>> fetchConversations() async {
    final uri = api.buildUri('/api/admin/chat/conversations');
    final response = await http.get(uri, headers: api.portalHeaders());
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonBody['contexts'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ChatConversationSummary.fromJson)
        .toList(growable: false);
  }

  Future<ChatTimelineResponse> fetchMessages(String contextId, {int limit = 50, String? before}) async {
    final query = <String, dynamic>{'limit': '$limit'};
    if (before != null) query['before'] = before;
    final uri = api.buildUri('/api/admin/chat/$contextId', query: query);
    final response = await http.get(uri, headers: api.portalHeaders());
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = (jsonBody['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return ChatTimelineResponse(
      messages: messages,
      hasMore: jsonBody['hasMore'] == true,
      lastRead: jsonBody['lastRead'] as String?,
    );
  }

  Future<ChatMessage> sendMessage(String contextId, String body, {List<String>? mentions, List<String>? flags}) async {
    final uri = api.buildUri('/api/admin/chat/$contextId');
    final payload = {
      'body': body,
      'mentions': mentions ?? const <String>[],
      'flags': flags ?? const <String>[],
    };
    final response = await http.post(uri, headers: api.portalHeaders(), body: jsonEncode(payload));
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(jsonBody['message'] as Map<String, dynamic>);
  }

  Future<void> deleteConversation(String contextId, {bool hard = false}) async {
    final query = <String, dynamic>{if (hard) 'mode': 'hard'};
    final uri = api.buildUri('/api/admin/chat/$contextId', query: query.isEmpty ? null : query);
    final response = await http.delete(uri, headers: api.portalHeaders());
    api.assertSuccess(response);
  }
}

class ChatTimelineResponse {
  final List<ChatMessage> messages;
  final bool hasMore;
  final String? lastRead;

  ChatTimelineResponse({
    required this.messages,
    required this.hasMore,
    required this.lastRead,
  });
}
