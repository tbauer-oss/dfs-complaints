import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../models/chat_message.dart';
import '../../services/chat_service.dart';
import '../../utils/display_name_from_email.dart';

class InternalChatPanel extends StatefulWidget {
  final ChatService chatService;
  final ChatConversationSummary conversation;
  final String currentUserId;
  final VoidCallback onBack;
  final void Function(String convId, int? lastMessageTs)? onMarkAsRead;

  const InternalChatPanel({
    super.key,
    required this.chatService,
    required this.conversation,
    required this.currentUserId,
    required this.onBack,
    this.onMarkAsRead,
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
  String _myId = '';

  String get _convId => widget.conversation.conversationId;

  @override
  void initState() {
    super.initState();
    _myId = _normalizeId(widget.currentUserId);
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
    final normalizedId = _normalizeId(widget.currentUserId);
    if (normalizedId.isNotEmpty && normalizedId != _myId) {
      setState(() => _myId = normalizedId);
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
        _messages = timeline.messages;
        _hasMoreBefore = timeline.hasMoreBefore;
        _loading = false;
        _errorMessage = null;
      });
      _scrollToBottom();
      _notifySeen();
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
      _notifySeen();
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
    if (text.isEmpty || _sending || _myId.isEmpty) return;
    setState(() => _sending = true);
    final tempId = widget.chatService.buildMessageId(_convId);
    final authorName = _displayNameForCurrentUser();
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: _convId,
      authorId: widget.currentUserId,
      authorName: authorName,
      authorEmail: _myId,
      authorUid: widget.currentUserId,
      sender: widget.currentUserId,
      senderEmail: _myId,
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
      _notifySeen();
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
    if (msg.senderEmail != null && msg.senderEmail!.isNotEmpty) {
      return displayNameFromEmail(msg.senderEmail!);
    }
    if (msg.authorId.isNotEmpty) return msg.authorId;
    return 'Unbekannter Nutzer';
  }

  bool _isMessageFromCurrentUser(ChatMessage msg) {
    final author = _firstNonEmpty([
      _normalizeId(msg.authorEmail),
      _normalizeId(msg.authorUid),
      _normalizeId(msg.sender),
      _normalizeId(msg.senderEmail),
      _normalizeId(msg.authorId),
    ]);
    final isMe = author.isNotEmpty && _myId.isNotEmpty && author == _myId;
    return isMe;
  }

  String _displayNameForCurrentUser() {
    final candidate = widget.conversation.displayNameFor(widget.currentUserId);
    if (candidate.isNotEmpty && candidate != 'Unbekannt') return candidate;
    return 'Du';
  }

  void _notifySeen() {
    if (widget.onMarkAsRead == null) return;
    final lastTs = _messages.isNotEmpty ? _messages.last.timestamp.millisecondsSinceEpoch : null;
    widget.onMarkAsRead!(widget.conversation.conversationId, lastTs);
  }

  String _normalizeId(String? value) => (value ?? '').trim().toLowerCase();

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  void _showMembersDialog(List<String> members) {
    if (members.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mitglieder anzeigen'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, minWidth: 360),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: members.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) => ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline),
              title: Text(members[index]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.conversation.titleFor(widget.currentUserId);
    final memberNames = widget.conversation.memberDisplayNames(excludeUserId: widget.currentUserId);
    final membersLabel = memberNames.isEmpty ? null : widget.conversation.membersLabelFor(widget.currentUserId);
    if (_myId.isEmpty) {
      return Column(
        children: [
          _PanelHeader(
            title: title,
            subtitle: membersLabel,
            onBack: widget.onBack,
            onShowMembers: memberNames.isEmpty ? null : () => _showMembersDialog(memberNames),
          ),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    final theme = Theme.of(context);
    return Column(
      children: [
        _PanelHeader(
          title: title,
          subtitle: membersLabel,
          onBack: widget.onBack,
          onShowMembers: memberNames.isEmpty ? null : () => _showMembersDialog(memberNames),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.06),
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(child: Text(_errorMessage!))
                      : Column(
                          children: [
                            if (_hasMoreBefore)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: TextButton.icon(
                                  onPressed: _loadOlder,
                                  icon: const Icon(Icons.history),
                                  label: const Text('Ältere Nachrichten laden'),
                                ),
                              ),
                            Expanded(
                              child: Scrollbar(
                                controller: _scrollController,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final msg = _messages[index];
                                    final isMe = _isMessageFromCurrentUser(msg);
                                    final bubbleWidth = MediaQuery.of(context).size.width * 0.72;
                                    final timeString = _formatTime(msg.timestamp);
                                    final backgroundColor = isMe
                                        ? theme.colorScheme.primaryContainer.withOpacity(0.32)
                                        : theme.colorScheme.surfaceVariant.withOpacity(0.4);
                                    final radius = BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                                      bottomRight: Radius.circular(isMe ? 4 : 16),
                                    );

                                    return Align(
                                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: bubbleWidth),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: backgroundColor,
                                              borderRadius: radius,
                                              border: Border.all(
                                                color: theme.colorScheme.outlineVariant.withOpacity(0.25),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: theme.shadowColor.withOpacity(0.06),
                                                blurRadius: 10,
                                                offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                            child: Column(
                                              crossAxisAlignment:
                                                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (!isMe)
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: 4),
                                                    child: Text(
                                                      _displayNameFor(msg),
                                                      style: theme.textTheme.labelMedium?.copyWith(
                                                        fontWeight: FontWeight.w700,
                                                        color: theme.colorScheme.onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ),
                                                Text(
                                                  msg.body,
                                                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      timeString,
                                                      style: theme.textTheme.labelSmall?.copyWith(
                                                        color: theme.colorScheme.onSurfaceVariant,
                                                      ),
                                                    ),
                                                    if (msg.pending)
                                                      Padding(
                                                        padding: const EdgeInsets.only(left: 6),
                                                        child: Icon(
                                                          Icons.watch_later,
                                                          size: 14,
                                                          color: theme.colorScheme.onSurfaceVariant,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
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
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback? onShowMembers;

  const _PanelHeader({required this.title, required this.onBack, this.subtitle, this.onShowMembers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Zur Übersicht',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Text(title.isNotEmpty ? title.characters.first.toUpperCase() : '?'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                if (subtitle != null)
                  GestureDetector(
                    onTap: onShowMembers,
                    child: Tooltip(
                      message: onShowMembers != null ? 'Mitglieder anzeigen' : null,
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Chat durchsuchen (UI)',
            icon: Icon(Icons.search_rounded, color: theme.colorScheme.onSurfaceVariant),
            onPressed: () {},
          ),
          IconButton(
            tooltip: 'Mitglieder anzeigen',
            icon: const Icon(Icons.group_outlined),
            onPressed: onShowMembers,
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
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Datei anhängen (UI)',
              icon: Icon(Icons.attach_file_outlined, color: theme.colorScheme.onSurfaceVariant),
              onPressed: () {},
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Nachricht eingeben...',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.45),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                  ),
                  prefixIcon: Icon(Icons.message_outlined, color: theme.colorScheme.onSurfaceVariant),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: sending ? null : onSend,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Senden'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
