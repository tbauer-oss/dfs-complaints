import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../models/chat_message.dart';
import '../../services/chat_service.dart';

class InternalChatPanel extends StatefulWidget {
  final ChatService chatService;
  final ChatConversationSummary conversation;
  final String currentUserId;
  final VoidCallback onBack;

  const InternalChatPanel({
    super.key,
    required this.chatService,
    required this.conversation,
    required this.currentUserId,
    required this.onBack,
  });

  @override
  State<InternalChatPanel> createState() => _InternalChatPanelState();
}

class _InternalChatPanelState extends State<InternalChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollTimer;
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _hasMoreBefore = false;
  String? _errorMessage;

  String get _convId => widget.conversation.conversationId;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _startPolling();
  }

  @override
  void didUpdateWidget(covariant InternalChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.conversationId != widget.conversation.conversationId) {
      _stopPolling();
      _messages = const [];
      _loading = true;
      _hasMoreBefore = false;
      _errorMessage = null;
      _loadInitial();
      _startPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final timeline = await widget.chatService.fetchMessages(_convId, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages = _mergeMessages(timeline.messages);
        _hasMoreBefore = timeline.hasMoreBefore;
        _loading = false;
        _errorMessage = null;
      });
      _scrollToBottom();
    } catch (err) {
      _handleLoadError(err);
    }
  }

  void _startPolling() {
    if (_errorMessage != null) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollNewMessages());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _handleLoadError(Object err, {bool showSnackBar = true}) {
    String message = 'Fehler beim Laden der Nachrichten';
    if (err is ApiError && (err.status == 401 || err.status == 403)) {
      message = 'Keine Berechtigung';
    }

    _stopPolling();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _errorMessage = message;
    });

    if (showSnackBar && message != 'Keine Berechtigung') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _pollNewMessages() async {
    try {
      if (_messages.isEmpty) {
        await _loadInitial();
        return;
      }
      final lastTs = _messages.last.timestamp.millisecondsSinceEpoch;
      final timeline = await widget.chatService.fetchMessages(_convId, afterTs: lastTs, limit: 50);
      if (timeline.messages.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _messages = _mergeMessages([..._messages, ...timeline.messages]);
      });
      _scrollToBottom();
    } catch (err) {
      _handleLoadError(err, showSnackBar: false);
    }
  }

  List<ChatMessage> _mergeMessages(List<ChatMessage> items) {
    final map = <String, ChatMessage>{};
    for (final m in items) {
      map[m.id] = m;
    }
    final merged = map.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }

  Future<void> _loadOlder() async {
    if (_messages.isEmpty || !_hasMoreBefore) return;
    try {
      final before = _messages.first.timestamp.millisecondsSinceEpoch;
      final timeline = await widget.chatService.fetchMessages(_convId, beforeTs: before, limit: 30);
      if (timeline.messages.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _messages = _mergeMessages([...timeline.messages, ..._messages]);
        _hasMoreBefore = timeline.hasMoreBefore;
      });
    } catch (err) {
      _handleLoadError(err);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final tempId = widget.chatService.buildMessageId(_convId);
    final authorName = _displayNameForCurrentUser();
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: _convId,
      authorId: widget.currentUserId,
      authorName: authorName,
      timestamp: DateTime.now(),
      body: text,
      pending: true,
    );

    setState(() {
      _messages = _mergeMessages([..._messages, optimistic]);
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final saved = await widget.chatService.sendMessage(_convId, text, msgId: tempId);
      setState(() {
        _messages = _mergeMessages([
          ..._messages.where((m) => m.id != tempId),
          saved,
        ]);
      });
      _scrollToBottom();
    } catch (err) {
      setState(() {
        _messages = _messages.where((m) => m.id != tempId).toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Senden fehlgeschlagen: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _displayNameFor(ChatMessage msg) {
    final directName = msg.authorName.trim();
    if (directName.isNotEmpty && directName != 'Unbekannt') return directName;
    final participantName = widget.conversation.displayNameFor(msg.authorId);
    if (participantName.isNotEmpty && participantName != 'Unbekannt') return participantName;
    if (msg.senderEmail != null && msg.senderEmail!.isNotEmpty) return msg.senderEmail!;
    if (msg.authorId.isNotEmpty) return msg.authorId;
    return 'Unbekannter Nutzer';
  }

  String _displayNameForCurrentUser() {
    final candidate = widget.conversation.displayNameFor(widget.currentUserId);
    if (candidate.isNotEmpty && candidate != 'Unbekannt') return candidate;
    return 'Du';
  }

  bool _isOwnMessage(ChatMessage msg) {
    final senderEmail = msg.senderEmail?.toLowerCase();
    final current = widget.currentUserId.toLowerCase();
    if (senderEmail != null && senderEmail.isNotEmpty && senderEmail == current) return true;
    return msg.authorId.toLowerCase() == current;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.conversation.titleFor(widget.currentUserId);
    return Column(
      children: [
        _PanelHeader(title: title, onBack: widget.onBack),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(child: Text(_errorMessage!))
              : Column(
                  children: [
                    if (_hasMoreBefore)
                      TextButton.icon(
                        onPressed: _loadOlder,
                        icon: const Icon(Icons.history),
                        label: const Text('Ältere Nachrichten laden'),
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = _isOwnMessage(msg);
                          return Row(
                            mainAxisAlignment:
                                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 520),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? Theme.of(context).colorScheme.primaryContainer
                                        : Theme.of(context).colorScheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    child: Column(
                                      crossAxisAlignment:
                                          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                      children: [
                                        if (!isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 4),
                                            child: Text(
                                              _displayNameFor(msg),
                                              style: Theme.of(context).textTheme.labelMedium,
                                            ),
                                          ),
                                        Text(msg.body),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _formatTime(msg.timestamp),
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                            if (msg.pending)
                                              const Padding(
                                                padding: EdgeInsets.only(left: 6),
                                                child: Icon(Icons.watch_later, size: 14),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        _InputBar(
          controller: _controller,
          sending: _sending,
          onSend: _send,
        ),
      ],
    );
  }

  String _formatTime(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _PanelHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Nachricht',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: sending ? null : onSend,
              icon: const Icon(Icons.send),
              label: const Text('Senden'),
            ),
          ],
        ),
      ),
    );
  }
}
