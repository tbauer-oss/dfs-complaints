import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/client.dart';
import '../../models/chat_message.dart';
import '../../models/chat_user.dart';
import '../../services/chat_service.dart';
import '../../utils/display_name_from_email.dart';

const String _chatArchiveKeyPrefix = 'chat:archived:';

Future<Set<String>> loadArchivedConvIds(String userEmail) async {
  if (userEmail.trim().isEmpty) return <String>{};
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_chatArchiveKeyPrefix${userEmail.toLowerCase()}');
    if (raw == null || raw.isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    }
  } catch (_) {
    try {
      final raw = html.window.localStorage['$_chatArchiveKeyPrefix${userEmail.toLowerCase()}'];
      if (raw == null || raw.isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
      }
    } catch (_) {}
  }
  return <String>{};
}

Future<void> saveArchivedConvIds(String userEmail, Set<String> ids) async {
  if (userEmail.trim().isEmpty) return;
  final key = '$_chatArchiveKeyPrefix${userEmail.toLowerCase()}';
  final payload = jsonEncode(ids.toList(growable: false));
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, payload);
  } catch (_) {
    try {
      html.window.localStorage[key] = payload;
    } catch (_) {}
  }
}

Future<Set<String>> toggleArchived(String userEmail, String convId) async {
  final ids = await loadArchivedConvIds(userEmail);
  if (ids.contains(convId)) {
    ids.remove(convId);
  } else {
    ids.add(convId);
  }
  await saveArchivedConvIds(userEmail, ids);
  return ids;
}

class InternalChatSidebar extends StatefulWidget {
  final ChatService chatService;
  final String currentUserId;
  final ValueChanged<ChatConversationSummary> onSelect;
  final ValueChanged<List<ChatConversationSummary>>? onConversationsLoaded;
  final ValueNotifier<List<ChatConversationSummary>>? conversationListNotifier;
  final bool showHeaderActions;

  const InternalChatSidebar({
    super.key,
    required this.chatService,
    required this.currentUserId,
    required this.onSelect,
    this.onConversationsLoaded,
    this.conversationListNotifier,
    this.showHeaderActions = true,
  });

  @override
  State<InternalChatSidebar> createState() => _InternalChatSidebarState();
}

class _InternalChatSidebarState extends State<InternalChatSidebar> {
  late Future<List<ChatConversationSummary>> _loader;
  final TextEditingController _searchController = TextEditingController();
  List<ChatConversationSummary> _conversations = const [];
  bool _loading = true;
  final Set<String> _deletingIds = {};
  bool _notifierPushInProgress = false;
  Set<String> _archivedIds = {};
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loader = _loadConversations();
    _searchController.addListener(() => setState(() {}));
    widget.conversationListNotifier?.addListener(_syncFromNotifier);
    _loadArchive();
  }

  @override
  void dispose() {
    widget.conversationListNotifier?.removeListener(_syncFromNotifier);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadArchive() async {
    final ids = await loadArchivedConvIds(widget.currentUserId);
    if (!mounted) return;
    setState(() {
      _archivedIds = ids;
      _conversations = _applyArchiveState(_conversations);
    });
    _pushToNotifier(_conversations);
  }

  Future<List<ChatConversationSummary>> _loadConversations() async {
    setState(() => _loading = true);
    final convs = await widget.chatService.fetchConversations();
    final updated = _applyArchiveState(convs);
    _setConversations(updated);
    setState(() => _loading = false);
    return _conversations;
  }

  Future<void> _refresh() async {
    await _loadConversations();
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
      await _refresh();
      widget.onSelect(result);
    }
  }

  void _syncFromNotifier() {
    if (_notifierPushInProgress) return;
    final incoming = widget.conversationListNotifier?.value;
    if (incoming == null) return;
    final normalized = _sorted(_applyArchiveState(incoming));
    if (_listMatches(normalized)) return;
    setState(() => _conversations = normalized);
  }

  void _setConversations(List<ChatConversationSummary> next) {
    final sorted = _sorted(next);
    setState(() => _conversations = sorted);
    _pushToNotifier(sorted);
    widget.onConversationsLoaded?.call(sorted);
  }

  void _pushToNotifier(List<ChatConversationSummary> next) {
    if (widget.conversationListNotifier == null) return;
    _notifierPushInProgress = true;
    widget.conversationListNotifier!.value = [...next];
    _notifierPushInProgress = false;
  }

  List<ChatConversationSummary> _applyArchiveState(List<ChatConversationSummary> items) {
    return items
        .map((c) => c.copyWith(isArchived: _archivedIds.contains(c.conversationId)))
        .toList(growable: false);
  }

  List<ChatConversationSummary> _sorted(List<ChatConversationSummary> items) {
    final copy = [...items];
    copy.sort((a, b) {
      final aDate = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return copy;
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

  List<ChatConversationSummary> get _filteredConversations {
    final query = _searchController.text.trim().toLowerCase();
    final archivedFiltered = _conversations
        .where((c) => _activeTabIndex == 1 ? c.isArchived == true : (c.isArchived != true))
        .toList(growable: false);
    if (query.isEmpty) return archivedFiltered;
    return archivedFiltered
        .where((c) => c.titleFor(widget.currentUserId).toLowerCase().contains(query))
        .toList(growable: false);
  }

  int get _activeCount => _conversations.where((c) => c.isArchived != true).length;
  int get _archivedCount => _conversations.where((c) => c.isArchived == true).length;

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

  Future<void> _toggleArchive(ChatConversationSummary conversation) async {
    final updatedIds = await toggleArchived(widget.currentUserId, conversation.conversationId);
    if (!mounted) return;
    final updatedList = _conversations
        .map((c) => c.conversationId == conversation.conversationId
            ? c.copyWith(isArchived: !c.isArchived)
            : c.copyWith(isArchived: updatedIds.contains(c.conversationId)))
        .toList(growable: false);
    setState(() {
      _archivedIds = updatedIds;
      _conversations = _sorted(updatedList);
    });
    _pushToNotifier(_conversations);
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SegmentedButton<int>(
                          segments: [
                            ButtonSegment(value: 0, label: Text('Aktiv (${_activeCount})')),
                            ButtonSegment(value: 1, label: Text('Archiv (${_archivedCount})')),
                          ],
                          selected: {_activeTabIndex},
                          onSelectionChanged: (value) => setState(() => _activeTabIndex = value.first),
                        ),
                        const SizedBox(width: 12),
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
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<ChatConversationSummary>>(
              future: _loader,
              builder: (context, snapshot) {
                if (_loading && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final convs = snapshot.data ?? _filteredConversations;
                if (convs.isEmpty) {
                  return ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Noch keine Chats. Starte eine neue Konversation.')),
                      ),
                    ],
                  );
                }
                final displayList = _filteredConversations;
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
                                child: Text(
                                  title.isNotEmpty ? title.characters.first.toUpperCase() : '?',
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                              Column(
                                children: [
                                  IconButton(
                                    icon: isDeleting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Icon(item.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
                                    onPressed: isDeleting ? null : () => _toggleArchive(item),
                                    tooltip: item.isArchived ? 'Konversation wiederherstellen' : 'Konversation archivieren',
                                  ),
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
        width: 540,
        height: 520,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Direktnachricht'),
                Tab(text: 'Gruppe'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
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

class InternalChatPanel extends StatefulWidget {
  final ChatService chatService;
  final ChatConversationSummary conversation;
  final String currentUserId;
  final VoidCallback onBack;
  final void Function(String convId, int? lastMessageTs)? onMarkAsRead;
  final ValueNotifier<List<ChatConversationSummary>>? conversationListNotifier;

  const InternalChatPanel({
    super.key,
    required this.chatService,
    required this.conversation,
    required this.currentUserId,
    required this.onBack,
    this.onMarkAsRead,
    this.conversationListNotifier,
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

  String get _convId => _activeSummary.conversationId;

  @override
  void initState() {
    super.initState();
    _activeSummary = widget.conversation;
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
    try {
      final timeline = await widget.chatService.fetchMessages(_convId, limit: 50);
      if (!mounted) return;
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
      _updateConversationSummary(_messages.last);
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
      body: composed,
      pending: true,
    );

    setState(() {
      _messages = _mergeMessages([..._messages, optimistic]);
      _controller.clear();
      _pendingAttachments = const [];
    });
    _updateConversationSummary(optimistic);
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
    final lastTs = _messages.isNotEmpty ? _messages.last.timestamp.millisecondsSinceEpoch : null;
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
    final next = _activeSummary.copyWith(
      lastMessage: latest.body,
      lastMessagePreview: latest.body,
      lastAuthor: latest.authorId,
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
    final notifier = widget.conversationListNotifier;
    if (notifier == null) return;
    final current = List<ChatConversationSummary>.from(notifier.value);
    final merged = [summary, ...current.where((c) => c.conversationId != summary.conversationId)];
    merged.sort((a, b) {
      final aDate = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    notifier.value = [...merged];
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
    final title = _activeSummary.titleFor(widget.currentUserId);
    final memberNames = _activeSummary.memberDisplayNames(excludeUserId: widget.currentUserId);
    final membersLabel = memberNames.isEmpty ? null : _activeSummary.membersLabelFor(widget.currentUserId);
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
        if (_pendingAttachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_pendingAttachments.length, (index) {
                  final file = _pendingAttachments[index];
                  return Chip(
                    avatar: const Icon(Icons.attach_file_outlined, size: 18),
                    label: Text(file.name, overflow: TextOverflow.ellipsis),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () => _removeAttachment(index),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }),
              ),
            ),
          ),
        _InputBar(
          controller: _controller,
          sending: _sending,
          onSend: _send,
          onPickAttachment: _pickAttachments,
          hasPendingAttachments: _pendingAttachments.isNotEmpty,
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
  final VoidCallback onPickAttachment;
  final bool hasPendingAttachments;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPickAttachment,
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
            IconButton(
              tooltip: 'Datei anhängen (UI)',
              icon: Icon(
                Icons.attach_file_outlined,
                color: hasPendingAttachments
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: sending ? null : onPickAttachment,
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
