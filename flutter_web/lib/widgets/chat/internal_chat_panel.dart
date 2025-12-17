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
  bool _loading = true;
  bool _sending = false;
  bool _hasMore = false;
  List<ChatMessage> _messages = const [];
  String? _cursorBefore;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages({bool older = false}) async {
    setState(() {
      if (!older) _loading = true;
    });
    final response = await widget.chatService.fetchMessages(widget.contextId, limit: 50, before: _cursorBefore);
    setState(() {
      _hasMore = response.hasMore;
      _cursorBefore = response.hasMore && response.messages.isNotEmpty
          ? response.messages.first.timestamp.toIso8601String()
          : null;
      _messages = older ? [...response.messages, ..._messages] : response.messages;
      _loading = false;
    });
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
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
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
