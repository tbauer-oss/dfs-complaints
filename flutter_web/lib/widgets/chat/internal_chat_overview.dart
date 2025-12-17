import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/chat_service.dart';

class InternalChatOverview extends StatefulWidget {
  final ChatService chatService;
  final ValueChanged<ChatConversationSummary> onSelect;
  final VoidCallback? onClose;

  const InternalChatOverview({
    super.key,
    required this.chatService,
    required this.onSelect,
    this.onClose,
  });

  @override
  State<InternalChatOverview> createState() => _InternalChatOverviewState();
}

class _InternalChatOverviewState extends State<InternalChatOverview> {
  late Future<List<ChatConversationSummary>> _loader;

  @override
  void initState() {
    super.initState();
    _loader = widget.chatService.fetchConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OverviewHeader(onClose: widget.onClose),
        Expanded(
          child: FutureBuilder<List<ChatConversationSummary>>(
            future: _loader,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snapshot.data ?? const [];
              if (list.isEmpty) {
                return const Center(child: Text('Keine Konversationen vorhanden.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final item = list[index];
                  return _ConversationTile(
                    item: item,
                    onTap: () => widget.onSelect(item),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  final VoidCallback? onClose;

  const _OverviewHeader({this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Row(
        children: [
          const Icon(Icons.forum_outlined, size: 18),
          const SizedBox(width: 8),
          Text(
            'Konversationen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
          )
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ChatConversationSummary item;
  final VoidCallback onTap;

  const _ConversationTile({required this.item, required this.onTap});

  IconData _iconForType(ChatContextType? type) {
    switch (type) {
      case ChatContextType.capa:
        return Icons.fact_check_outlined;
      case ChatContextType.audit:
        return Icons.search_outlined;
      case ChatContextType.doc:
        return Icons.description_outlined;
      case ChatContextType.general:
        return Icons.apartment_outlined;
      case ChatContextType.complaint:
      default:
        return Icons.report_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = item.meta;
    final ts = meta?.updatedAt != null
        ? '${meta!.updatedAt!.toLocal()}'
        : '—';
    final subtitle = meta?.lastMessage ?? 'Keine Nachrichten';

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: Icon(_iconForType(meta?.type), color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(meta?.reference ?? item.contextId),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(ts, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      trailing: item.unread ? const _UnreadBadge() : null,
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Neu',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}
