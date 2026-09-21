import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/chat_api.dart';
import '../domain/chat_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

const _purple = Color(0xFF6335FF);
const _ink = Color(0xFF080C25);
const _muted = Color(0xFF626A80);

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final searchFocus = FocusNode();
  String filter = 'All';
  String query = '';
  List<ChatSummary> chats = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() { searchFocus.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final items = await ChatApi.instance.conversations(archived: filter == 'Archived');
      if (mounted) setState(() => chats = items);
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load conversations');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<ChatSummary> get visibleChats => chats.where((chat) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isNotEmpty && !chat.name.toLowerCase().contains(normalized) && !chat.preview.toLowerCase().contains(normalized)) return false;
    if (filter == 'Groups') return chat.group;
    if (filter == 'Direct') return !chat.group;
    if (filter == 'Unread') return chat.unread > 0;
    if (filter == 'Favorites') return chat.favorite;
    return true;
  }).toList();

  Future<void> _setFilter(String value) async {
    final changedArchiveMode = (filter == 'Archived') != (value == 'Archived');
    setState(() => filter = value);
    if (changedArchiveMode) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: GroopXBackground(child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(19, 18, 19, 12), child: Row(children: [
            const Text('Chats', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            IconButton(onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_none, color: _purple)),
            IconButton(onPressed: () => searchFocus.requestFocus(), tooltip: 'Search chats', icon: const Icon(Icons.search, color: _purple)),
            IconButton(onPressed: () => context.go('/contacts/new'), icon: const Icon(Icons.edit_outlined, color: _purple)),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 19), child: TextField(focusNode:searchFocus,onChanged: (value) => setState(() => query = value), decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 20), hintText: 'Search chats, people or groups...', filled: true, fillColor: const Color(0xFFF7F7FA), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(13))))),
          const SizedBox(height: 20),
          SizedBox(height: 35, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 19), children: ['All', 'Groups', 'Direct', 'Unread', 'Favorites', 'Archived'].map((item) => Padding(padding: const EdgeInsets.only(right: 12), child: ChoiceChip(label: Text(item), selected: filter == item, onSelected: (_) => _setFilter(item), selectedColor: const Color(0xFFF0EBFF), labelStyle: TextStyle(color: filter == item ? _purple : _muted), side: const BorderSide(color: Color(0xFFE8E8F0))))).toList())),
          const SizedBox(height: 8),
          Expanded(child: loading
              ? const Center(child: CircularProgressIndicator(color: _purple))
              : error != null
                  ? GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Chats unavailable', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
                  : visibleChats.isEmpty
                      ? GroopXEmptyState(icon: Icons.chat_bubble_outline, title: query.isEmpty ? 'No conversations yet' : 'No matching chats', message: query.isEmpty ? 'New message button se kisi user ko search karke conversation start karein.' : 'Search text ya selected filter change karke dekhein.', actionLabel: query.isEmpty ? 'New message' : null, onAction: query.isEmpty ? () => context.go('/contacts/new') : null)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            itemCount: visibleChats.length,
                            itemBuilder: (_, index) {
                              final chat = visibleChats[index];
                              return _ChatTile(chat: chat, onTap: () async {
                                await context.push('/chat/${chat.id}');
                                _load();
                              }, onManage: () => _manage(chat));
                            },
                          ),
                        )),
        ]))),
        bottomNavigationBar: const _BottomNav(),
      );

  Future<void> _manage(ChatSummary chat) async {
    final action = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: Icon(chat.favorite ? Icons.star : Icons.star_border), title: Text(chat.favorite ? 'Remove from favorites' : 'Add to favorites'), onTap: () => Navigator.pop(context, 'favorite')),
      ListTile(leading: Icon(chat.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined), title: Text(chat.muted ? 'Unmute notifications' : 'Mute notifications'), onTap: () => Navigator.pop(context, 'mute')),
      ListTile(leading: Icon(chat.archived ? Icons.unarchive_outlined : Icons.archive_outlined), title: Text(chat.archived ? 'Restore conversation' : 'Archive conversation'), onTap: () => Navigator.pop(context, 'archive')),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Remove from my chats', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'delete')),
    ])));
    if (action == null) return;
    if (action == 'favorite') { await ChatApi.instance.updatePreferences(chat.id, favorite: !chat.favorite); }
    if (action == 'mute') { await ChatApi.instance.updatePreferences(chat.id, muted: !chat.muted); }
    if (action == 'archive') { await ChatApi.instance.archive(chat.id, !chat.archived); }
    if (action == 'delete') { await ChatApi.instance.deleteConversation(chat.id); }
    await _load();
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.onTap, required this.onManage});
  final ChatSummary chat;
  final VoidCallback onTap, onManage;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        onLongPress: onManage,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: SizedBox(height: 73, child: Row(children: [
          Stack(children: [
            CircleAvatar(radius: 25, backgroundColor: Color(chat.color), foregroundImage: (chat.avatarUrl?.isNotEmpty ?? false) ? NetworkImage(chat.avatarUrl!) : null, child: Icon(chat.group ? Icons.groups_rounded : Icons.person, color: Colors.white, size: 29)),
            if (chat.online) const Positioned(right: 0, bottom: 1, child: CircleAvatar(radius: 5, backgroundColor: Color(0xFF16C653))),
          ]),
          const SizedBox(width: 13),
          Expanded(child: Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F4)))), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [Flexible(child: Text(chat.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink))), if (chat.favorite) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.star, size: 14, color: Color(0xFFFFB300))), if (chat.muted) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.notifications_off, size: 13, color: _muted))]), const SizedBox(height: 5), Text(chat.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.35, color: _muted))])),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(chat.time, style: TextStyle(fontSize: 11, color: chat.unread > 0 ? _purple : _muted)), if (chat.unread > 0) ...[const SizedBox(height: 8), CircleAvatar(radius: 10, backgroundColor: _purple, child: Text('${chat.unread}', style: const TextStyle(fontSize: 10, color: Colors.white)))]])
          ]))),
        ]))),
      );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      height: 72,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 9),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18)],
      ),
      child: Row(children: [
        const Expanded(child: _NavItem(Icons.chat_bubble, 'Chat', true)),
        Expanded(child: _NavItem(Icons.groups_outlined, 'Group', false, onTap: () => context.go('/communities'))),
        Expanded(child: _NavItem(Icons.add_circle_outline, 'New Chat', false, emphasized: true, onTap: () => context.push('/contacts/new'))),
        Expanded(child: _NavItem(Icons.calendar_month_outlined, 'Reminder/Meeting', false, onTap: () => context.go('/reminders'))),
        Expanded(child: _NavItem(Icons.person_outline, 'Profile', false, onTap: () => context.go('/profile'))),
      ]),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.icon, this.label, this.selected, {this.onTap, this.emphasized = false});
  final IconData icon; final String label; final bool selected;
  final VoidCallback? onTap;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: selected ? _purple : _muted, size: emphasized ? 28 : 22),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: TextStyle(fontSize: 10, color: selected ? _purple : _muted)),
            ),
          ),
        ]),
      ),
    ),
  );
}
