import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/chat_service.dart';

class InternalChatPanel extends StatefulWidget {
  final ChatService chatService;
  final String contextId;
  final String? title;
  final VoidCallback? onClose;

  const InternalChatPanel({
    super.key,
    required this.chatService,
    required this.contextId,
    this.title,
    this.onClose,
  });

  @override
  State<InternalChatPanel> createState() => _InternalChatPanelState();
}

class _InternalChatPanelState extends State<InternalChatPanel> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  bool _sending = false;
  bool _hasMore = false;
  bool _loadingOlder = false;
  List<ChatMessage> _messages = const [];
  String? _cursorBefore;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMessages();
  }

  @override
  void didUpdateWidget(covariant InternalChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextId != widget.contextId) {
      _resetAndLoad();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool older = false}) async {
    if (older && (_loadingOlder || !_hasMore)) return;
    setState(() {
      if (!older) {
        _loading = true;
      } else {
        _loadingOlder = true;
      }
    });
    final response = await widget.chatService.fetchMessages(widget.contextId, limit: 50, before: _cursorBefore);
    if (!mounted) return;
    setState(() {
      _hasMore = response.hasMore;
      _cursorBefore = response.hasMore && response.messages.isNotEmpty
          ? response.messages.first.timestamp.toIso8601String()
          : null;
      _messages = _mergeMessages(response.messages);
      _loading = false;
      _loadingOlder = false;
    });
  }

  List<ChatMessage> _mergeMessages(List<ChatMessage> incoming) {
    final map = <String, ChatMessage>{
      for (final msg in _messages) msg.id: msg,
    };
    for (final msg in incoming) {
      map[msg.id] = msg;
    }
    final merged = map.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }

  void _resetAndLoad() {
    setState(() {
      _loading = true;
      _loadingOlder = false;
      _hasMore = false;
      _messages = const [];
      _cursorBefore = null;
      _composer.clear();
    });
    _loadMessages();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final sent = await widget.chatService.sendMessage(widget.contextId, text);
      setState(() {
        _messages = [..._messages, sent];
        _composer.clear();
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingOlder || !_hasMore) return;
    if (_scrollController.position.pixels <= 24) {
      _loadMessages(older: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _PanelHeader(title: widget.title ?? 'Interner Chat', onClose: widget.onClose),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: Column(
              children: [
                if (_hasMore)
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: () => _loadMessages(older: true),
                      icon: const Icon(Icons.history),
                      label: const Text('Ältere Nachrichten laden'),
                    ),
                  ),
                if (_loadingOlder)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    controller: _scrollController,
                    itemCount: _messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _ChatMessageTile(message: msg);
                    },
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Nachricht eingeben…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                color: theme.colorScheme.primary,
                onPressed: _sending ? null : _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onClose;

  const _PanelHeader({required this.title, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onClose,
          )
        ],
      ),
    );
  }
}

class _ChatMessageTile extends StatelessWidget {
  final ChatMessage message;

  const _ChatMessageTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final ts = TimeOfDay.fromDateTime(message.timestamp).format(context);
    final headline = Text.rich(
      TextSpan(
        text: message.authorName,
        style: const TextStyle(fontWeight: FontWeight.w600),
        children: [
          const TextSpan(text: ' • '),
          TextSpan(text: ts, style: const TextStyle(fontWeight: FontWeight.w400)),
        ],
      ),
    );

    final flags = message.flags;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headline,
          const SizedBox(height: 4),
          Text(message.body),
          if (message.mentions.isNotEmpty || flags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in message.mentions)
                  Chip(
                    label: Text('@$m'),
                    avatar: const Icon(Icons.alternate_email, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                for (final f in flags)
                  Chip(
                    label: Text(f.toUpperCase()),
                    backgroundColor: Colors.amber.shade100,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            )
          ]
        ],
      ),
    );
  }
}
