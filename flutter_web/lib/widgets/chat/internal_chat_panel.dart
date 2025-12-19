import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import '../../api/client.dart';
import '../../models/chat_message.dart';
import '../../services/chat_service.dart';
import '../../utils/display_name_from_email.dart';
import 'conversation_avatar.dart';
import 'group_icon_picker.dart';

class InternalChatPanel extends StatefulWidget {
  final ChatService chatService;
  final ChatConversationSummary conversation;
  final String currentUserId;
  final VoidCallback onBack;
  final void Function(String convId, int? lastMessageTs)? onMarkAsRead;
  final ValueNotifier<List<ChatConversationSummary>>? conversationListNotifier;
  final bool showBackButton;
  final Map<String, String> avatarByEmail;

  const InternalChatPanel({
    super.key,
    required this.chatService,
    required this.conversation,
    required this.currentUserId,
    required this.onBack,
    this.onMarkAsRead,
    this.conversationListNotifier,
    this.showBackButton = false,
    this.avatarByEmail = const {},
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
  late ChatConversationSummary _activeSummary;
  List<PlatformFile> _pendingAttachments = const [];
  bool _showEmojiPicker = false;

  String get _convId => _activeSummary.conversationId;

  String? _resolveAvatarByEmail(String? email, String? fallbackAvatar) {
    final normalized = _normalizeId(email);
    final resolved = normalized.isNotEmpty ? widget.avatarByEmail[normalized] : null;
    if (resolved != null && resolved.isNotEmpty) return resolved;
    if (fallbackAvatar == null || fallbackAvatar.isEmpty) return null;
    return fallbackAvatar;
  }

  String? _conversationAvatarUrl() {
    if (_activeSummary.participants.isEmpty) return null;
    final participant = _activeSummary.participants.firstWhere(
      (p) => _myId.isEmpty || p.userId != _myId,
      orElse: () => _activeSummary.participants.first,
    );
    return _resolveAvatarByEmail(participant.email ?? participant.userId, participant.avatar);
  }

  @override
  void initState() {
    super.initState();
    _activeSummary = widget.conversation;
    _myId = _normalizeId(widget.currentUserId);
    _controller.addListener(() => setState(() {}));
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
      _activeSummary = widget.conversation;
      _loadInitial();
      _startPolling();
    }
    final normalizedId = _normalizeId(widget.currentUserId);
    if (normalizedId.isNotEmpty && normalizedId != _myId) {
      setState(() => _myId = normalizedId);
    }
    if (oldWidget.conversation != widget.conversation) {
      setState(() => _activeSummary = widget.conversation);
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
    final convId = _convId;
    try {
      final timeline = await widget.chatService.fetchMessages(convId, limit: 50);
      if (!mounted || convId != _convId) return;
      setState(() {
        _messages = timeline.messages;
        _hasMoreBefore = timeline.hasMoreBefore;
        _loading = false;
        _errorMessage = null;
      });
      if (_messages.isNotEmpty) {
        _updateConversationSummary(_messages.last);
      }
      _scrollToBottom();
      _notifySeen();
    } catch (err) {
      if (!mounted || convId != _convId) return;
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
    final convId = _convId;
    try {
      if (_messages.isEmpty) {
        await _loadInitial();
        return;
      }
      final lastTs = _messages.last.timestamp.millisecondsSinceEpoch;
      final timeline = await widget.chatService.fetchMessages(convId, afterTs: lastTs, limit: 50);
      if (timeline.messages.isEmpty) return;
      if (!mounted || convId != _convId) return;
      setState(() {
        _messages = _mergeMessages([..._messages, ...timeline.messages]);
      });
      _updateConversationSummary(_messages.last);
      _scrollToBottom();
      _notifySeen();
    } catch (err) {
      if (!mounted || convId != _convId) return;
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
    final convId = _convId;
    try {
      final before = _messages.first.timestamp.millisecondsSinceEpoch;
      final timeline = await widget.chatService.fetchMessages(convId, beforeTs: before, limit: 30);
      if (timeline.messages.isEmpty) return;
      if (!mounted || convId != _convId) return;
      setState(() {
        _messages = _mergeMessages([...timeline.messages, ..._messages]);
        _hasMoreBefore = timeline.hasMoreBefore;
      });
    } catch (err) {
      if (!mounted || convId != _convId) return;
      _handleLoadError(err);
    }
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;
      if (!mounted) return;
      setState(() {
        _pendingAttachments = result.files;
      });
    } catch (_) {}
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    setState(() {
      _pendingAttachments = [
        ..._pendingAttachments.take(index),
        ..._pendingAttachments.skip(index + 1),
      ];
    });
  }

  Future<void> _send() async {
    if (_sending || _myId.isEmpty) return;
    final text = _controller.text.trim();
    final attachmentLabel = _pendingAttachments.isEmpty
        ? ''
        : _pendingAttachments.map((f) => '📎 ${f.name}').join('\n');
    final composed = [if (text.isNotEmpty) text, if (attachmentLabel.isNotEmpty) attachmentLabel]
        .join('\n')
        .trim();
    if (composed.isEmpty) return;

    setState(() {
      _sending = true;
      _showEmojiPicker = false;
    });
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
      body: composed,
      pending: true,
    );

    setState(() {
      _messages = _mergeMessages([..._messages, optimistic]);
      _controller.clear();
      _pendingAttachments = const [];
    });
    _updateConversationSummary(optimistic);
    _notifySeen();
    _scrollToBottom();

    try {
      final saved = await widget.chatService.sendMessage(_convId, composed, msgId: tempId);
      setState(() {
        _messages = _mergeMessages([
          ..._messages.where((m) => m.id != tempId),
          saved,
        ]);
      });
      _updateConversationSummary(saved);
      await _refreshSidebarConversations();
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

  void _toggleEmojiPicker([bool? next]) {
    setState(() => _showEmojiPicker = next ?? !_showEmojiPicker);
  }

  void _insertEmoji(String emoji) {
    final value = _controller.value;
    final selection = value.selection;
    final safeStart = selection.start >= 0 ? selection.start : value.text.length;
    final safeEnd = selection.end >= 0 ? selection.end : value.text.length;
    final newText = value.text.replaceRange(safeStart, safeEnd, emoji);
    _controller.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: safeStart + emoji.length),
      composing: TextRange.empty,
    );
    setState(() => _showEmojiPicker = false);
  }

  String _displayNameFor(ChatMessage msg) {
    final directName = msg.authorName.trim();
    if (directName.isNotEmpty && directName != 'Unbekannt') return directName;
    final participantName = _activeSummary.displayNameFor(msg.authorId);
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
    final candidate = _activeSummary.displayNameFor(widget.currentUserId);
    if (candidate.isNotEmpty && candidate != 'Unbekannt') return candidate;
    return 'Du';
  }

  void _notifySeen() {
    if (widget.onMarkAsRead == null) return;
    final lastTs = _messages.isNotEmpty
        ? _messages.last.timestamp.millisecondsSinceEpoch
        : _activeSummary.lastMessageAt?.millisecondsSinceEpoch;
    widget.onMarkAsRead!(_activeSummary.conversationId, lastTs);
  }

  String _normalizeId(String? value) => (value ?? '').trim().toLowerCase();

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  void _updateConversationSummary(ChatMessage latest) {
    final lastAuthor = _firstNonEmpty([
      latest.authorEmail ?? '',
      latest.authorUid ?? '',
      latest.senderEmail ?? '',
      latest.sender ?? '',
      latest.authorId,
    ]);
    final next = _activeSummary.copyWith(
      lastMessage: latest.body,
      lastMessagePreview: latest.body,
      lastAuthor: lastAuthor.isNotEmpty ? lastAuthor : latest.authorId,
      lastMessageAt: latest.timestamp,
    );
    if (mounted) {
      setState(() => _activeSummary = next);
    } else {
      _activeSummary = next;
    }
    _pushConversationUpdate(next);
  }

  void _pushConversationUpdate(ChatConversationSummary summary) {
    upsertConversation(summary);
  }

  void upsertConversation(ChatConversationSummary meta) {
    final notifier = widget.conversationListNotifier;
    if (notifier == null) return;
    final normalized = meta.copyWith(
      lastMessageAt: meta.lastMessageAt ?? DateTime.now(),
      isArchived: meta.isArchived == true ? true : false,
    );
    final current = List<ChatConversationSummary>.from(notifier.value);
    final merged = [
      normalized,
      ...current.where((c) => c.conversationId != normalized.conversationId),
    ];
    merged.sort((a, b) => _conversationSortDate(b).compareTo(_conversationSortDate(a)));
    notifier.value = [...merged];
  }

  DateTime _conversationSortDate(ChatConversationSummary conv) {
    final meta = conv.meta ?? const {};
    final updated = _parseDate(meta['updatedAt']) ?? _parseDate(meta['lastMsgAt']);
    final created = _parseDate(meta['createdAt']);
    return conv.lastMessageAt ?? updated ?? created ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Future<void> _refreshSidebarConversations() async {
    final notifier = widget.conversationListNotifier;
    if (notifier == null) return;
    try {
      final convs = await widget.chatService.fetchConversations();
      final deduped = <String, ChatConversationSummary>{};
      for (final conv in convs) {
        deduped[conv.conversationId] = conv;
      }
      final sorted = deduped.values.toList()
        ..sort((a, b) => _conversationSortDate(b).compareTo(_conversationSortDate(a)));
      notifier.value = [...sorted];
    } catch (_) {}
  }

  void _applyMetaUpdate(Map<String, dynamic> nextMeta) {
    final updated = _activeSummary.copyWith(meta: nextMeta);
    if (mounted) {
      setState(() => _activeSummary = updated);
    } else {
      _activeSummary = updated;
    }
    _pushConversationUpdate(updated);
  }

  Future<void> _changeGroupIcon() async {
    if (!_activeSummary.isGroup) return;
    final selection = await showGroupIconPicker(
      context,
      initialIconId: _activeSummary.groupIconId,
    );
    if (selection == null) return;
    final previousMeta = {...?_activeSummary.meta};
    final selectedIcon = selection.isEmpty ? null : selection;
    final optimisticMeta = {...previousMeta};
    if (selectedIcon == null) {
      optimisticMeta.remove('groupIcon');
    } else {
      optimisticMeta['groupIcon'] = selectedIcon;
    }

    _applyMetaUpdate(optimisticMeta);

    try {
      final savedMeta = await widget.chatService.updateConversationGroupIcon(_convId, selectedIcon);
      final mergedMeta = {...previousMeta, ...savedMeta};
      if (savedMeta['groupIcon'] == null) {
        mergedMeta.remove('groupIcon');
      }
      _applyMetaUpdate(mergedMeta);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gruppen-Icon aktualisiert')),
        );
      }
    } catch (err) {
      _applyMetaUpdate(previousMeta);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gruppen-Icon konnte nicht gespeichert werden: $err')),
      );
    }
  }

  void _showMembersDialog(List<ChatParticipant> members, {List<String> fallbackNames = const []}) {
    if (members.isEmpty && fallbackNames.isEmpty) return;
    final theme = Theme.of(context);
    final effectiveMembers = members.isNotEmpty
        ? members
        : fallbackNames
            .map((name) => ChatParticipant(userId: name, displayName: name))
            .toList(growable: false);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mitglieder anzeigen'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, minWidth: 360),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: effectiveMembers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) => ListTile(
              dense: true,
              leading: _buildAvatar(
                theme,
                avatarUrl: _resolveAvatarByEmail(
                  effectiveMembers[index].email ?? effectiveMembers[index].userId,
                  effectiveMembers[index].avatar,
                ),
                label: effectiveMembers[index].displayName.isNotEmpty
                    ? effectiveMembers[index].displayName
                    : (effectiveMembers[index].email ?? effectiveMembers[index].userId),
              ),
              title: Text(
                effectiveMembers[index].displayName.isNotEmpty
                    ? effectiveMembers[index].displayName
                    : (effectiveMembers[index].email ?? 'Unbekannt'),
              ),
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
    final title = _activeSummary.titleFor(widget.currentUserId);
    final memberNames = _activeSummary.memberDisplayNames(excludeUserId: widget.currentUserId);
    final membersLabel = memberNames.isEmpty ? null : _activeSummary.membersLabelFor(widget.currentUserId);
    final memberParticipants = _activeSummary.participants
        .where((p) => p.userId != widget.currentUserId)
        .toList(growable: false);
    final headerAvatarUrl = _conversationAvatarUrl();
    final changeGroupIcon = _activeSummary.isGroup ? _changeGroupIcon : null;
    if (_myId.isEmpty) {
      return Column(
        children: [
          _PanelHeader(
            title: title,
            subtitle: membersLabel,
            onBack: widget.onBack,
            showBackButton: widget.showBackButton,
            conversation: _activeSummary,
            avatarUrl: headerAvatarUrl,
            onShowMembers: memberParticipants.isEmpty && memberNames.isEmpty
                ? null
                : () => _showMembersDialog(memberParticipants, fallbackNames: memberNames),
            onChangeGroupIcon: changeGroupIcon,
          ),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                if (_showEmojiPicker) {
                  _toggleEmojiPicker(false);
                }
                return null;
              },
            ),
          },
          child: Stack(
            children: [
              Column(
                children: [
                  _PanelHeader(
                    title: title,
                    subtitle: membersLabel,
                    onBack: widget.onBack,
                    showBackButton: widget.showBackButton,
                    conversation: _activeSummary,
                    avatarUrl: headerAvatarUrl,
                    onShowMembers: memberParticipants.isEmpty && memberNames.isEmpty
                        ? null
                        : () => _showMembersDialog(memberParticipants, fallbackNames: memberNames),
                    onChangeGroupIcon: changeGroupIcon,
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.surfaceVariant.withOpacity(0.2),
                            theme.colorScheme.surface,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _errorMessage != null
                              ? Center(child: Text(_errorMessage!))
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                                  child: Column(
                                    children: [
                                      if (_hasMoreBefore)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              side: BorderSide(color: theme.colorScheme.outlineVariant),
                                            ),
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
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            itemCount: _messages.length,
                                            itemBuilder: (context, index) {
                                              final msg = _messages[index];
                                              final isMe = _isMessageFromCurrentUser(msg);
                                              final bubbleWidth = MediaQuery.of(context).size.width * 0.72;
                                              final timeString = _formatTime(msg.timestamp);
                                              final backgroundColor = isMe
                                                  ? theme.colorScheme.primaryContainer.withOpacity(0.8)
                                                  : theme.colorScheme.surface;
                                              final textColor = isMe
                                                  ? theme.colorScheme.onPrimaryContainer
                                                  : theme.colorScheme.onSurface;
                                              final radius = BorderRadius.only(
                                                topLeft: const Radius.circular(18),
                                                topRight: const Radius.circular(18),
                                                bottomLeft: Radius.circular(isMe ? 18 : 6),
                                                bottomRight: Radius.circular(isMe ? 6 : 18),
                                              );

                                              return Align(
                                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                                child: ConstrainedBox(
                                                  constraints: BoxConstraints(maxWidth: bubbleWidth),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        color: backgroundColor,
                                                        borderRadius: radius,
                                                        border: Border.all(
                                                          color: theme.colorScheme.outlineVariant.withOpacity(0.2),
                                                        ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: theme.shadowColor.withOpacity(0.06),
                                                            blurRadius: 12,
                                                            offset: const Offset(0, 4),
                                                          ),
                                                        ],
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                                        child: Column(
                                                          crossAxisAlignment: isMe
                                                              ? CrossAxisAlignment.end
                                                              : CrossAxisAlignment.start,
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
                                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                                height: 1.35,
                                                                color: textColor,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 6),
                                                            Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                Text(
                                                                  timeString,
                                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                                    color: isMe
                                                                        ? theme.colorScheme.onPrimaryContainer
                                                                            .withOpacity(0.9)
                                                                        : theme.colorScheme.onSurfaceVariant,
                                                                  ),
                                                                ),
                                                                if (msg.pending)
                                                                  Padding(
                                                                    padding: const EdgeInsets.only(left: 6),
                                                                    child: Icon(
                                                                      Icons.watch_later,
                                                                      size: 14,
                                                                      color: isMe
                                                                          ? theme.colorScheme.onPrimaryContainer
                                                                          : theme.colorScheme.onSurfaceVariant,
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
                                      if (_pendingAttachments.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8, top: 4),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: _pendingAttachments
                                                  .map((file) => Chip(
                                                        label: Text(file.name),
                                                        deleteIcon: const Icon(Icons.close_rounded),
                                                        onDeleted: () {
                                                          setState(() {
                                                            _pendingAttachments = _pendingAttachments
                                                                .where((f) => f.identifier != file.identifier)
                                                                .toList();
                                                          });
                                                        },
                                                      ))
                                                  .toList(),
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
                    onPickAttachment: _pickAttachments,
                    onToggleEmojiPicker: _toggleEmojiPicker,
                    showEmojiPicker: _showEmojiPicker,
                    canSend: _controller.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty,
                    hasPendingAttachments: _pendingAttachments.isNotEmpty,
                  ),
                ],
              ),
              if (_showEmojiPicker)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _toggleEmojiPicker(false),
                    child: const SizedBox.expand(),
                  ),
                ),
              if (_showEmojiPicker)
                Positioned(
                  bottom: 86,
                  left: 24,
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: 360,
                      height: 360,
                      child: EmojiPicker(
                        onEmojiSelected: (_, emoji) => _insertEmoji(emoji.emoji),
                        config: Config(
                          emojiViewConfig: EmojiViewConfig(
                            emojiSizeMax: 28,
                            columns: 7,
                            backgroundColor: theme.colorScheme.surface,
                          ),
                          categoryViewConfig: const CategoryViewConfig(
                            iconColorSelected: Colors.blueGrey,
                            iconColor: Colors.blueGrey,
                            indicatorColor: Colors.blueGrey,
                            dividerColor: Colors.transparent,
                          ),
                          bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                          searchViewConfig: const SearchViewConfig(hintText: 'Emoji suchen'),
                          skinToneConfig: const SkinToneConfig(enabled: true),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

Widget _buildAvatar(
  ThemeData theme, {
  String? avatarUrl,
  required String label,
  double radius = 20,
  IconData? icon,
}) {
  final trimmed = label.trim();
  final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
  final fallback = trimmed.isNotEmpty ? trimmed.characters.first.toUpperCase() : '?';
  return CircleAvatar(
    radius: radius,
    backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
    backgroundColor: hasAvatar ? null : theme.colorScheme.primaryContainer,
    foregroundColor: hasAvatar ? null : theme.colorScheme.onPrimaryContainer,
    child: hasAvatar
        ? null
        : icon != null
            ? Icon(icon)
            : Text(fallback),
  );
}

enum _PanelHeaderAction { showMembers, changeIcon }

class _PanelHeader extends StatelessWidget {
  final ChatConversationSummary conversation;
  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final bool showBackButton;
  final VoidCallback? onShowMembers;
  final String? avatarUrl;
  final VoidCallback? onChangeGroupIcon;

  const _PanelHeader({
    required this.conversation,
    required this.title,
    required this.onBack,
    required this.showBackButton,
    this.subtitle,
    this.onShowMembers,
    this.avatarUrl,
    this.onChangeGroupIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              tooltip: 'Zur Übersicht',
              icon: Icon(
                Icons.arrow_back_rounded,
                color: theme.colorScheme.onSurface,
              ),
              onPressed: onBack,
            )
          else
            const SizedBox(width: 8),
          ConversationAvatar(
            conversation: conversation,
            avatarUrl: avatarUrl,
            label: title,
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
          if (onShowMembers != null || onChangeGroupIcon != null)
            PopupMenuButton<_PanelHeaderAction>(
              icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurfaceVariant),
              onSelected: (action) {
                switch (action) {
                  case _PanelHeaderAction.showMembers:
                    onShowMembers?.call();
                    break;
                  case _PanelHeaderAction.changeIcon:
                    onChangeGroupIcon?.call();
                    break;
                }
              },
              itemBuilder: (_) => [
                if (onShowMembers != null)
                  const PopupMenuItem(
                    value: _PanelHeaderAction.showMembers,
                    child: Text('Mitglieder anzeigen'),
                  ),
                if (onChangeGroupIcon != null)
                  const PopupMenuItem(
                    value: _PanelHeaderAction.changeIcon,
                    child: Text('Gruppen-Icon ändern'),
                  ),
              ],
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
  final VoidCallback onPickAttachment;
  final VoidCallback onToggleEmojiPicker;
  final bool showEmojiPicker;
  final bool hasPendingAttachments;
  final bool canSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPickAttachment,
    required this.onToggleEmojiPicker,
    required this.showEmojiPicker,
    required this.canSend,
    this.hasPendingAttachments = false,
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
            Tooltip(
              message: 'Anhänge noch nicht verfügbar',
              child: IconButton(
                tooltip: 'Anhänge (noch nicht verfügbar)',
                icon: Icon(
                  Icons.attach_file_outlined,
                  color: hasPendingAttachments
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: null,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: showEmojiPicker ? 'Emoji-Auswahl schließen' : 'Emoji hinzufügen',
              icon: Icon(
                Icons.emoji_emotions_outlined,
                color: showEmojiPicker ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: onToggleEmojiPicker,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Shortcuts(
                shortcuts: {
                  LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
                  LogicalKeySet(
                    LogicalKeyboardKey.shift,
                    LogicalKeyboardKey.enter,
                  ): const DoNothingIntent(),
                },
                child: Actions(
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        if (canSend && !sending) {
                          onSend();
                        }
                        return null;
                      },
                    ),
                    DoNothingIntent: CallbackAction<DoNothingIntent>(
                      onInvoke: (_) {
                        final value = controller.value;
                        final selection = value.selection;
                        final newText = value.text.replaceRange(
                          selection.start,
                          selection.end,
                          '\n',
                        );
                        controller.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(
                            offset: selection.start + 1,
                          ),
                        );
                        return null;
                      },
                    ),
                  },
                  child: Focus(
                    autofocus: true,
                    child: TextField(
                      controller: controller,
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
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
                        prefixIcon:
                            Icon(Icons.message_outlined, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: (!canSend || sending) ? null : onSend,
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
