import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/chat_user.dart';
import '../../services/chat_service.dart';
import 'group_icon_picker.dart';

class InternalChatOverview extends StatefulWidget {
  final ChatService chatService;
  final String currentUserId;
  final ValueChanged<ChatConversationSummary> onSelect;
  final ValueChanged<List<ChatConversationSummary>>? onConversationsLoaded;
  final ValueNotifier<List<ChatConversationSummary>>? conversationListNotifier;
  final bool showHeaderActions;

  const InternalChatOverview({
    super.key,
    required this.chatService,
    required this.currentUserId,
    required this.onSelect,
    this.onConversationsLoaded,
    this.conversationListNotifier,
    this.showHeaderActions = true,
  });

  @override
  State<InternalChatOverview> createState() => _InternalChatOverviewState();
}

class _InternalChatOverviewState extends State<InternalChatOverview> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatConversationSummary> _conversations = const [];
  bool _loading = true;
  final Set<String> _deletingIds = {};
  bool _showArchived = false;
  bool _notifierPushInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _searchController.addListener(() => setState(() {}));
    widget.conversationListNotifier?.addListener(_syncFromNotifier);
  }

  @override
  void dispose() {
    widget.conversationListNotifier?.removeListener(_syncFromNotifier);
    _searchController.dispose();
    super.dispose();
  }

  Future<List<ChatConversationSummary>> _loadConversations() async {
    setState(() => _loading = true);
    final convs = await widget.chatService.fetchConversations();
    _setConversations(convs);
    setState(() => _loading = false);
    return _conversations;
  }

  Future<void> _refresh() async {
    await _loadConversations();
  }

  void _syncFromNotifier() {
    if (_notifierPushInProgress) return;
    final incoming = widget.conversationListNotifier?.value;
    if (incoming == null) return;
    final normalized = _sorted(incoming);
    if (_listMatches(normalized)) return;
    setState(() => _conversations = normalized);
  }

  void _setConversations(List<ChatConversationSummary> next) {
    final sorted = _sorted(next);
    setState(() => _conversations = sorted);
    _pushToNotifier(sorted);
    widget.onConversationsLoaded?.call(sorted);
  }

  void _upsertConversation(ChatConversationSummary meta) {
    final normalized = meta.copyWith(
      lastMessageAt: meta.lastMessageAt ?? DateTime.now(),
      isArchived: meta.isArchived == true ? true : false,
    );
    final filtered = _conversations
        .where((c) => c.conversationId != normalized.conversationId)
        .toList(growable: false);
    final merged = [...filtered, normalized];
    _setConversations(_sorted(merged));
  }

  void _pushToNotifier(List<ChatConversationSummary> next) {
    if (widget.conversationListNotifier == null) return;
    _notifierPushInProgress = true;
    widget.conversationListNotifier!.value = [...next];
    _notifierPushInProgress = false;
  }

  List<ChatConversationSummary> _sorted(List<ChatConversationSummary> items) {
    final copy = [...items];
    copy.sort((a, b) => _sortDateFor(b).compareTo(_sortDateFor(a)));
    return copy;
  }

  DateTime _sortDateFor(ChatConversationSummary conv) {
    final meta = conv.meta ?? const {};
    final updated = _parseDate(meta['lastMsgAt']) ?? _parseDate(meta['updatedAt']);
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

  bool _listMatches(List<ChatConversationSummary> incoming) {
    if (incoming.length != _conversations.length) return false;
    for (var i = 0; i < incoming.length; i++) {
      final a = incoming[i];
      final b = _conversations[i];
      if (a.conversationId != b.conversationId) return false;
      final aTs = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      final bTs = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      if (aTs != bTs) return false;
      if ((a.lastAuthor ?? '') != (b.lastAuthor ?? '')) return false;
      if ((a.lastMessagePreview ?? a.lastMessage ?? '') !=
          (b.lastMessagePreview ?? b.lastMessage ?? '')) return false;
      if (a.isArchived != b.isArchived) return false;
      if ((a.groupIconId ?? '') != (b.groupIconId ?? '')) return false;
    }
    return true;
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

  Future<void> _openNewConversationDialog() async {
    final result = await showDialog<ChatConversationSummary>(
      context: context,
      builder: (context) => _NewConversationDialog(
        chatService: widget.chatService,
        currentUserId: widget.currentUserId,
      ),
    );
    if (result != null) {
      _upsertConversation(result.copyWith(isArchived: false));
      widget.onSelect(result);
    }
  }

  List<ChatConversationSummary> get _filteredConversations {
    final query = _searchController.text.trim().toLowerCase();
    final archivedFiltered = _conversations.where((c) =>
        _showArchived ? c.isArchived == true : (c.isArchived != true)).toList(growable: false);
    if (query.isEmpty) return archivedFiltered;
    return archivedFiltered
        .where((c) => c.titleFor(widget.currentUserId).toLowerCase().contains(query))
        .toList(growable: false);
  }

  Future<void> _deleteConversation(ChatConversationSummary conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konversation löschen?'),
        content: Text(
          'Möchtest du die Konversation "${conversation.titleFor(widget.currentUserId)}" wirklich löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete),
            label: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deletingIds.add(conversation.conversationId));

    try {
      await widget.chatService.deleteConversation(conversation.conversationId);
      if (!mounted) return;
      _deletingIds.remove(conversation.conversationId);
      final next = _conversations
          .where((c) => c.conversationId != conversation.conversationId)
          .toList(growable: false);
      _setConversations(next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konversation gelöscht')),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _deletingIds.remove(conversation.conversationId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeaderActions)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Chats, Personen oder Gruppen suchen',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: theme.colorScheme.surface.withOpacity(0.65),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: _showArchived ? 'Archivierte Konversationen' : 'Inbox',
                      child: FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(_showArchived ? 'Archiv' : 'Inbox'),
                        selected: _showArchived,
                        onSelected: (value) => setState(() => _showArchived = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _openNewConversationDialog,
                      icon: const Icon(Icons.forum_rounded),
                      label: const Text('Neue Konversation'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: Builder(
              builder: (context) {
                if (_loading && _conversations.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                final displayList = _filteredConversations;
                if (displayList.isEmpty) {
                  return ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Noch keine Chats. Starte eine neue Konversation.')),
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  itemCount: displayList.length,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = displayList[index];
                    final title = item.titleFor(widget.currentUserId);
                    final subtitle =
                        item.lastMessagePreview ?? item.lastMessage ?? 'Keine Nachrichten';
                    final memberNames = item.memberDisplayNames(excludeUserId: widget.currentUserId);
                    final membersLabel =
                        memberNames.isNotEmpty ? item.membersLabelFor(widget.currentUserId) : null;
                    final timestamp = item.lastMessageAt;
                    final hasUnread =
                        item.lastAuthor != null && item.lastAuthor != widget.currentUserId;
                    final isDeleting = _deletingIds.contains(item.conversationId);
                    final isGroup = item.isGroup;
                    final groupIcon = iconForGroupIconId(item.groupIconId);
                    final dmPeer = !isGroup
                        ? item.participants.firstWhere(
                            (p) => p.userId != widget.currentUserId,
                            orElse: () => item.participants.isNotEmpty
                                ? item.participants.first
                                : ChatParticipant(userId: 'peer', displayName: title),
                          )
                        : null;
                    final dmFallbackInitial = (dmPeer?.displayName.trim().isNotEmpty ?? false)
                        ? dmPeer!.displayName.characters.first.toUpperCase()
                        : '?';
                    return Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      color: theme.colorScheme.surface.withOpacity(0.9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => widget.onSelect(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                foregroundColor: theme.colorScheme.onPrimaryContainer,
                                child: groupIcon != null
                                    ? Icon(groupIcon)
                                    : Text(
                                        title.isNotEmpty
                                            ? title.characters.first.toUpperCase()
                                            : '?',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                        ),
                                        if (timestamp != null)
                                          Text(
                                            _formatTime(timestamp),
                                            style: theme.textTheme.labelMedium?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (membersLabel != null)
                                      GestureDetector(
                                        onTap: () => _showMembersDialog(memberNames),
                                        child: Tooltip(
                                          message: 'Mitglieder anzeigen',
                                          child: Text(
                                            membersLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (membersLabel != null) const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (!isGroup)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundImage: (dmPeer?.avatar?.isNotEmpty ?? false)
                                        ? NetworkImage(dmPeer!.avatar!)
                                        : null,
                                    backgroundColor: (dmPeer?.avatar?.isNotEmpty ?? false)
                                        ? null
                                        : theme.colorScheme.primaryContainer,
                                    foregroundColor: (dmPeer?.avatar?.isNotEmpty ?? false)
                                        ? null
                                        : theme.colorScheme.onPrimaryContainer,
                                    child: (dmPeer?.avatar?.isNotEmpty ?? false)
                                        ? null
                                        : Text(dmFallbackInitial),
                                  ),
                                ),
                              if (!isGroup) const SizedBox(width: 6),
                              Column(
                                children: [
                                  IconButton(
                                    icon: isDeleting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.delete_outline),
                                    onPressed: isDeleting ? null : () => _deleteConversation(item),
                                    tooltip: 'Konversation löschen',
                                  ),
                                  if (hasUnread)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
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

class _NewConversationDialog extends StatefulWidget {
  final ChatService chatService;
  final String currentUserId;

  const _NewConversationDialog({required this.chatService, required this.currentUserId});

  @override
  State<_NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<_NewConversationDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _groupTitleController = TextEditingController();
  Future<List<ChatUserSummary>>? _userSearchFuture;
  final Set<String> _selectedIds = {};
  final Map<String, ChatUserSummary> _selectedUsers = {};
  Timer? _searchDebounce;
  bool _creating = false;
  String? _selectedGroupIconId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _userSearchController.addListener(_onSearchChanged);
    _runSearch(immediate: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userSearchController.dispose();
    _groupTitleController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() => _runSearch();

  void _runSearch({bool immediate = false}) {
    _searchDebounce?.cancel();
    if (immediate) {
      _performSearch();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), _performSearch);
  }

  void _performSearch() {
    setState(() {
      _userSearchFuture = widget.chatService.searchUsers(_userSearchController.text);
    });
  }

  Future<void> _pickGroupIcon() async {
    final selected = await showGroupIconPicker(context, initialIconId: _selectedGroupIconId);
    if (selected == null) return;
    setState(() {
      _selectedGroupIconId = selected.isEmpty ? null : selected;
    });
  }

  Future<void> _startDm(ChatUserSummary user) async {
    setState(() => _creating = true);
    try {
      final conversation = await widget.chatService.ensureDirectConversation(
        user.email,
        user.displayName,
        currentUserId: widget.currentUserId,
      );
      if (mounted) Navigator.of(context).pop(conversation);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chat konnte nicht gestartet werden: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _createGroup() async {
    if (_selectedIds.isEmpty) return;
    setState(() => _creating = true);
    try {
      final conversation = await widget.chatService.createGroup(
        title: _groupTitleController.text.trim().isEmpty ? 'Gruppe' : _groupTitleController.text.trim(),
        memberUids: _selectedIds.toList(growable: false),
        groupIcon: _selectedGroupIconId,
      );
      if (mounted) Navigator.of(context).pop(conversation);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neue Konversation'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Chat'),
                Tab(text: 'Gruppe'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 360,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildUserPicker(onSelect: _startDm, allowMulti: false),
                  _buildGroupPicker(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _creating ? null : () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
      ],
    );
  }

  Widget _buildUserPicker({required Function(ChatUserSummary) onSelect, required bool allowMulti}) {
    return Column(
      children: [
        TextField(
          controller: _userSearchController,
          decoration: const InputDecoration(
            labelText: 'Nutzer suchen',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<ChatUserSummary>>(
            future: _userSearchFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final users = snapshot.data ?? const [];
              if (users.isEmpty) {
                return const Center(child: Text('Keine Nutzer gefunden'));
              }
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  final selected = _selectedIds.contains(user.userId);
                  return ListTile(
                    leading: CircleAvatar(child: Text(user.displayName.characters.first.toUpperCase())),
                    title: Text(user.displayName),
                    subtitle: Text(user.email),
                    trailing: allowMulti
                        ? Checkbox(
                            value: selected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedIds.add(user.userId);
                                  _selectedUsers[user.userId] = user;
                                } else {
                                  _selectedIds.remove(user.userId);
                                  _selectedUsers.remove(user.userId);
                                }
                              });
                            },
                          )
                        : null,
                    onTap: _creating
                        ? null
                        : () {
                            if (allowMulti) {
                              setState(() {
                                if (selected) {
                                  _selectedIds.remove(user.userId);
                                  _selectedUsers.remove(user.userId);
                                } else {
                                  _selectedIds.add(user.userId);
                                  _selectedUsers[user.userId] = user;
                                }
                              });
                            } else {
                              onSelect(user);
                            }
                          },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGroupPicker() {
    return Column(
      children: [
        TextField(
          controller: _groupTitleController,
          decoration: const InputDecoration(labelText: 'Gruppenname'),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Builder(
            builder: (context) {
              final previewIcon = iconForGroupIconId(_selectedGroupIconId);
              return CircleAvatar(
                child: previewIcon != null ? Icon(previewIcon) : const Text('G'),
              );
            },
          ),
          title: const Text('Gruppen-Icon'),
          subtitle: Text(_selectedGroupIconId ?? 'Optional'),
          trailing: OutlinedButton.icon(
            onPressed: _creating ? null : _pickGroupIcon,
            icon: const Icon(Icons.image_outlined),
            label: Text(_selectedGroupIconId == null ? 'Icon wählen' : 'Icon ändern'),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedIds
                .map((id) {
                  final label = _selectedUsers[id]?.displayName ?? id;
                  return Chip(
                    label: Text(label),
                    onDeleted: () => setState(() {
                      _selectedIds.remove(id);
                      _selectedUsers.remove(id);
                    }),
                  );
                })
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildUserPicker(onSelect: (_) {}, allowMulti: true)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _creating || _selectedIds.isEmpty ? null : _createGroup,
            icon: _creating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.group_add),
            label: const Text('Gruppe erstellen'),
          ),
        ),
      ],
    );
  }
}
