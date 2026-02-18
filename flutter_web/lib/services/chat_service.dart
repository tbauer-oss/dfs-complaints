// lib/services/chat_service.dart
import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../models/chat_message.dart';
import '../models/portal_user.dart';
import '../models/chat_user.dart';

class ChatService {
  final ApiClient api;
  Future<List<PortalUserSummary>>? _staffUsersFuture;
  Future<bool>? _refreshPromise;
  final Set<void Function()> _pollingStopCallbacks = <void Function()>{};
  bool _hardLogoutTriggered = false;

  ChatService(this.api);

  void registerPollingStopCallback(void Function() callback) {
    _pollingStopCallbacks.add(callback);
  }

  void unregisterPollingStopCallback(void Function() callback) {
    _pollingStopCallbacks.remove(callback);
  }

  bool get hasValidPortalToken => !_isTokenExpiringSoon(api.portalToken, skewSeconds: 0);

  static String normalizeUserId(String value) {
    final trimmed = value.trim().toLowerCase();
    if (!trimmed.contains('@')) return trimmed;
    return base64Url.encode(utf8.encode(trimmed)).replaceAll('=', '');
  }

  String buildMessageId(String convId) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$convId:$ts';
  }

  Future<List<PortalUserSummary>> fetchStaffUsers({bool forceRefresh = false}) {
    if (_staffUsersFuture != null && !forceRefresh) return _staffUsersFuture!;
    _staffUsersFuture = _loadStaffUsers();
    return _staffUsersFuture!;
  }

  Future<List<PortalUserSummary>> _loadStaffUsers() async {
    const path = '/api/admin/users';
    final response = await _fetchWithAuth('GET', path, query: {'scope': 'staff', 'includeInactive': 'true'});
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
    const path = '/api/chat/v1/conversations';
    final response = await _fetchWithAuth('GET', path, query: {'limit': '50'});
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonBody['conversations'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ChatConversationSummary.fromJson)
        .toList(growable: false);
  }

  Future<ChatConversationSummary> ensureDirectConversation(
    String participantEmail,
    String participantDisplayName,
    {String? currentUserId, String? currentUserDisplayName}
  ) async {
    const path = '/api/chat/v1/dm';
    final payload = {
      'peerEmail': participantEmail,
    };
    final response = await _fetchWithAuth('POST', path, body: payload);
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final convId = (jsonBody['convId'] ?? jsonBody['conversationId'] ?? '').toString();
    if (convId.isEmpty) throw Exception('invalid conversation response');

    try {
      final conversations = await fetchConversations();
      final found = conversations.firstWhere(
        (c) => c.conversationId == convId,
        orElse: () => ChatConversationSummary(
          conversationId: convId,
          type: 'dm',
          title: participantDisplayName,
          participants: [
            ChatParticipant(userId: participantEmail, displayName: participantDisplayName, email: participantEmail),
            if (currentUserId != null)
              ChatParticipant(
                userId: currentUserId,
                displayName: currentUserDisplayName ?? 'Du',
              ),
          ],
          lastMessage: null,
          lastAuthor: null,
          lastMessageAt: null,
        ),
      );
      return found;
    } catch (_) {
      return ChatConversationSummary(
        conversationId: convId,
        type: 'dm',
        title: participantDisplayName,
        participants: [
          ChatParticipant(userId: participantEmail, displayName: participantDisplayName, email: participantEmail),
          if (currentUserId != null)
            ChatParticipant(userId: currentUserId, displayName: currentUserDisplayName ?? 'Du'),
        ],
        lastMessage: null,
        lastAuthor: null,
        lastMessageAt: null,
      );
    }
  }

  Future<ChatConversationSummary> createGroup({
    required String title,
    required List<String> memberUids,
    String? initialMessage,
    String? groupIcon,
  }) async {
    const path = '/api/chat/v1/groups';
    final payload = {
      'title': title,
      'memberUids': memberUids,
      if (initialMessage != null && initialMessage.trim().isNotEmpty) 'initialMessage': initialMessage,
      if (groupIcon != null) 'meta': {'groupIcon': groupIcon},
    };
    final response = await _fetchWithAuth('POST', path, body: payload);
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final data = jsonBody['conversation'] as Map<String, dynamic>;
    return ChatConversationSummary.fromJson(data);
  }

  Future<List<ChatUserSummary>> searchUsers(String query) async {
    const path = '/api/chat/v1/users';
    final response = await _fetchWithAuth('GET', path, query: {'query': query, 'limit': '50'});
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonBody['users'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(ChatUserSummary.fromJson).toList(growable: false);
  }

  Future<ChatTimelineResponse> fetchMessages(
    String convId, {
    int limit = 50,
    int? afterTs,
    int? beforeTs,
  }) async {
    final query = <String, dynamic>{'limit': '$limit'};
    if (afterTs != null) query['afterTs'] = '$afterTs';
    if (beforeTs != null) query['beforeTs'] = '$beforeTs';
    final path = '/api/chat/v1/conversations/$convId/messages';
    final response = await _fetchWithAuth('GET', path, query: query);
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = (jsonBody['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList(growable: false);
    return ChatTimelineResponse(
      messages: messages,
      hasMoreBefore: jsonBody['hasMoreBefore'] == true,
      hasMoreAfter: jsonBody['hasMoreAfter'] == true,
    );
  }

  Future<ChatMessage> sendMessage(String convId, String body, {String? msgId}) async {
    final path = '/api/chat/v1/conversations/$convId/messages';
    final payload = {
      'body': body,
      if (msgId != null) 'msgId': msgId,
    };
    final response = await _fetchWithAuth('POST', path, body: payload);
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(jsonBody['message'] as Map<String, dynamic>);
  }

  Future<ChatMessage> updateMessage(String messageId, String body) async {
    final path = '/api/chat/v1/messages/$messageId';
    final payload = {'body': body};
    final response = await _fetchWithAuth('PATCH', path, body: payload);
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(jsonBody['message'] as Map<String, dynamic>);
  }

  Future<ChatMessage> deleteMessage(String messageId) async {
    final path = '/api/chat/v1/messages/$messageId';
    final response = await _fetchWithAuth('DELETE', path);
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(jsonBody['message'] as Map<String, dynamic>);
  }

  Future<void> deleteConversation(String convId) async {
    final path = '/api/chat/v1/conversations/$convId';
    final response = await _fetchWithAuth('DELETE', path);
    if (response.statusCode == 204) return;
    api.assertSuccess(response);
  }

  Future<Map<String, dynamic>> updateConversationGroupIcon(
    String convId,
    String? groupIcon,
  ) async {
    final path = '/api/chat/v1/conversations/$convId/meta';
    final payload = {'groupIcon': groupIcon};
    final response = await _fetchWithAuth('PATCH', path, body: payload);
    api.assertSuccess(response);
    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    if (jsonBody['meta'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(jsonBody['meta'] as Map<String, dynamic>);
    }
    return payload;
  }

  Future<http.Response> _fetchWithAuth(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool retryAfterRefresh = true,
  }) async {
    if (_isTokenExpiringSoon(api.portalToken)) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed && retryAfterRefresh) {
        await hardLogout();
        throw ApiError(401, 'Session abgelaufen');
      }
    }

    final response = await _rawRequest(method, path, query: query, body: body);
    if (response.statusCode != 401 || !retryAfterRefresh) {
      return response;
    }

    final refreshed = await _refreshAccessToken();
    if (!refreshed) {
      await hardLogout();
      throw ApiError(401, 'Session abgelaufen');
    }
    return _rawRequest(method, path, query: query, body: body);
  }

  Future<http.Response> _rawRequest(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool includeAuth = true,
  }) async {
    final uri = api.buildUri(path, query: query);
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      if (includeAuth && (api.portalToken ?? '').isNotEmpty) 'Authorization': 'Bearer ${api.portalToken!}',
    };
    final req = await html.HttpRequest.request(
      uri.toString(),
      method: method,
      requestHeaders: headers,
      sendData: body == null ? null : jsonEncode(body),
      withCredentials: true,
    );
    return http.Response(
      req.responseText ?? '',
      req.status ?? 0,
      headers: _responseHeadersToMap(req.responseHeaders),
      request: http.Request(method, uri),
    );
  }

  Map<String, String> _responseHeadersToMap(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return const <String, String>{};
    return Map<String, String>.from(headers);
  }

  Future<bool> _refreshAccessToken() async {
    final existing = _refreshPromise;
    if (existing != null) return existing;

    final refresh = _doRefreshAccessToken();
    _refreshPromise = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshPromise, refresh)) {
        _refreshPromise = null;
      }
    }
  }

  Future<bool> _doRefreshAccessToken() async {
    try {
      final response = await _rawRequest('POST', '/api/auth/refresh', includeAuth: false);
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return false;
      final accessToken = (decoded['accessToken'] ?? '').toString().trim();
      if (accessToken.isEmpty) return false;

      api.setPortalSession(
        token: accessToken,
        profile: api.portalProfile ?? const <String, dynamic>{},
        persist: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> hardLogout() async {
    if (_hardLogoutTriggered) return;
    _hardLogoutTriggered = true;

    for (final callback in _pollingStopCallbacks.toList(growable: false)) {
      try {
        callback();
      } catch (_) {}
    }

    api.clearPortalSession();
    try {
      await _rawRequest('POST', '/api/auth/logout', includeAuth: false);
    } catch (_) {}

    html.window.location.assign('/login');
  }

  bool _isTokenExpiringSoon(String? token, {int skewSeconds = 120}) {
    final normalized = token?.trim() ?? '';
    if (normalized.isEmpty) return true;
    final parts = normalized.split('.');
    if (parts.length < 2) return true;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return true;
      final expRaw = decoded['exp'];
      final expSec = expRaw is int ? expRaw : int.tryParse('$expRaw');
      if (expSec == null) return true;
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return expSec <= nowSec + skewSeconds;
    } catch (_) {
      return true;
    }
  }
}
