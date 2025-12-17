import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/portal_user.dart';
import '../../services/chat_service.dart';

class InternalChatOverview extends StatefulWidget {
  final ChatService chatService;
  final String currentUserId;
  final ValueChanged<ChatConversationSummary> onSelect;
  final VoidCallback onClose;

  const InternalChatOverview({
    super.key,
    required this.chatService,
    required this.currentUserId,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<InternalChatOverview> createState() => _InternalChatOverviewState();
}

class _InternalChatOverviewState extends State<InternalChatOverview> {
  late Future<List<ChatConversationSummary>> _loader;
  List<ChatConversationSummary> _conversations = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loader = _loadConversations();
  }

  Future<List<ChatConversationSummary>> _loadConversations() async {
    setState(() => _loading = true);
    final convs = await widget.chatService.fetchConversations();
    setState(() {
      _conversations = convs;
      _loading = false;
    });
    return convs;
  }

  Future<void> _refresh() async {
    await _loadConversations();
  }

  Future<void> _startConversation(PortalUserSummary? user) async {
    if (user == null) return;
    final conversation = await widget.chatService.ensureDirectConversation(
      user.email,
      user.label,
    );
    await _refresh();
    widget.onSelect(conversation);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(onClose: widget.onClose),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _StaffPicker(
            chatService: widget.chatService,
            onPick: _startConversation,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<ChatConversationSummary>>(
              future: _loader,
              builder: (context, snapshot) {
                if (_loading && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final convs = snapshot.data ?? _conversations;
                if (convs.isEmpty) {
                  return ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Noch keine Chats. Starte eine Direktnachricht.')),
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  itemCount: convs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = convs[index];
                    final title = item.titleFor(widget.currentUserId);
                    final subtitle = item.lastMessage ?? 'Keine Nachrichten';
                    final timestamp = item.lastMessageAt;
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(title.isNotEmpty ? title.characters.first.toUpperCase() : '?'),
                      ),
                      title: Text(title),
                      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: timestamp != null
                          ? Text(_formatTime(timestamp), style: Theme.of(context).textTheme.labelMedium)
                          : null,
                      onTap: () => widget.onSelect(item),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime ts) {
    final now = DateTime.now();
    final sameDay = now.year == ts.year && now.month == ts.month && now.day == ts.day;
    if (sameDay) {
      return '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    }
    return '${ts.day.toString().padLeft(2, '0')}.${ts.month.toString().padLeft(2, '0')}';
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Interner Chat',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _StaffPicker extends StatelessWidget {
  final ChatService chatService;
  final ValueChanged<PortalUserSummary?> onPick;

  const _StaffPicker({required this.chatService, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PortalUserSummary>>(
      future: chatService.fetchStaffUsers(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <PortalUserSummary>[];
        return Autocomplete<PortalUserSummary>(
          displayStringForOption: (option) => option.label,
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.toLowerCase();
            if (query.isEmpty) return const Iterable.empty();
            return users.where((u) => u.label.toLowerCase().contains(query));
          },
          onSelected: onPick,
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Direktnachricht starten',
                hintText: 'Name eingeben',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => onSubmitted(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: SizedBox(
                  width: 320,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        title: Text(option.label),
                        subtitle: Text(option.role),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
