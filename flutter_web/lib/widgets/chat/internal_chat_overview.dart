import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/portal_user.dart';
import '../../services/chat_service.dart';

class InternalChatOverview extends StatefulWidget {
  final ChatService chatService;
  final ValueChanged<ChatConversationSummary> onSelect;
  final VoidCallback? onClose;
  final String currentUserId;

  const InternalChatOverview({
    super.key,
    required this.chatService,
    required this.onSelect,
    this.onClose,
    required this.currentUserId,
  });

  @override
  State<InternalChatOverview> createState() => _InternalChatOverviewState();
}

class _InternalChatOverviewState extends State<InternalChatOverview> {
  late Future<List<ChatConversationSummary>> _loader;
  Future<List<PortalUserSummary>>? _staffLoader;

  @override
  void initState() {
    super.initState();
    _loader = widget.chatService.fetchConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OverviewHeader(onClose: widget.onClose, onStartConversation: _startNewConversation),
        Expanded(
          child: FutureBuilder<List<ChatConversationSummary>>(
            future: _loader,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snapshot.data ?? const [];
              if (list.isEmpty) {
                return _EmptyState(
                  onStartConversation: _startNewConversation,
                );
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
                    onDelete: () => _deleteConversation(item),
                    currentUserId: widget.currentUserId,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _deleteConversation(ChatConversationSummary item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konversation löschen'),
        content: const Text('Wirklich löschen? Dieser Vorgang kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          )
        ],
      ),
    );

    if (confirmed != true) return;
    await widget.chatService.deleteConversation(item.contextId);
    setState(() {
      _loader = widget.chatService.fetchConversations();
    });
  }

  Future<void> _startNewConversation() async {
    final selected = await _pickStaffUser();
    if (selected == null) return;
    final contextId = widget.chatService.directContextId(widget.currentUserId, selected.email);
    final meta = ChatContextMeta(
      contextId: contextId,
      type: ChatContextType.dm,
      reference: selected.displayName.isNotEmpty ? selected.displayName : 'Unbekannter Nutzer',
      updatedAt: null,
      lastMessage: null,
      lastAuthor: null,
    );
    widget.onSelect(
      ChatConversationSummary(
        contextId: contextId,
        meta: meta,
        lastRead: null,
        unread: false,
        participants: [
          ChatParticipant(userId: widget.currentUserId, displayName: ''),
          ChatParticipant(userId: ChatService.normalizeUserId(selected.email), displayName: selected.displayName),
        ],
      ),
    );
  }

  Future<PortalUserSummary?> _pickStaffUser() async {
    _staffLoader ??= widget.chatService.fetchStaffUsers();
    return showDialog<PortalUserSummary>(
      context: context,
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Neue Konversation'),
              content: SizedBox(
                width: 420,
                child: FutureBuilder<List<PortalUserSummary>>(
                  future: _staffLoader,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final users = snapshot.data ?? const [];
                    final filtered = users
                        .where((u) {
                          final name = (u.displayName.isNotEmpty ? u.displayName : u.label).toLowerCase();
                          return name.contains(query);
                        })
                        .toList();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Mitarbeiter suchen',
                            prefixIcon: Icon(Icons.search),
                          ),
                          autofocus: true,
                          onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final user = filtered[index];
                              final subtitle = _userSubtitle(user);
                              return ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(user.displayName.isNotEmpty ? user.displayName : 'Unbekannter Nutzer'),
                                subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                                onTap: () => Navigator.of(context).pop(user),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Abbrechen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _userSubtitle(PortalUserSummary user) {
    if (user.assignedDepartments.isNotEmpty) {
      return user.assignedDepartments.join(' • ');
    }
    if (user.role.isNotEmpty) return user.role;
    return '';
  }
}

class _OverviewHeader extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback onStartConversation;

  const _OverviewHeader({this.onClose, required this.onStartConversation});

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
          TextButton.icon(
            onPressed: onStartConversation,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Neue Konversation'),
          ),
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
  final VoidCallback? onDelete;
  final String currentUserId;

  const _ConversationTile({required this.item, required this.onTap, required this.currentUserId, this.onDelete});

  IconData _iconForType(ChatContextType? type) {
    switch (type) {
      case ChatContextType.dm:
        return Icons.forum_outlined;
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
    final type = meta?.type ?? (item.participants.isNotEmpty ? ChatContextType.dm : null);
    final ts = meta?.updatedAt != null
        ? '${meta!.updatedAt!.toLocal()}'
        : '—';
    final subtitle = meta?.lastMessage ?? 'Keine Nachrichten';

    final title = item.titleFor(currentUserId);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: Icon(_iconForType(type), color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(ts, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.unread) const _UnreadBadge(),
          PopupMenuButton<String>(
            tooltip: 'Aktionen',
            onSelected: (value) {
              if (value == 'delete' && onDelete != null) onDelete!();
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Konversation löschen'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
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

class _EmptyState extends StatelessWidget {
  final VoidCallback onStartConversation;

  const _EmptyState({required this.onStartConversation});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined, size: 42),
          const SizedBox(height: 12),
          const Text('Keine Konversationen vorhanden.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onStartConversation,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Neue Konversation'),
          ),
        ],
      ),
    );
  }
}
