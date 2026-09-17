import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../domain/chat_models.dart';

const _purple = Color(0xFF6335FF);
const _ink = Color(0xFF080C25);
const _muted = Color(0xFF626A80);

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String filter = 'All';
  final chats = const [
    ChatSummary(id: 'project-x', name: 'Project X Team', preview: 'Rohan: Please check the latest design and share your feedback.', time: '9:41 AM', unread: 3, group: true),
    ChatSummary(id: 'ananya', name: 'Ananya Sharma', preview: 'Hey! Are we still on for the meeting today?', time: '9:30 AM', unread: 1, online: true, color: 0xFF282D38),
    ChatSummary(id: 'vikram', name: 'Vikram Mehta', preview: 'Got it! Thanks for the update.', time: 'Yesterday', online: true, color: 0xFF37474F),
    ChatSummary(id: 'weekend', name: 'Weekend Plans', preview: 'Riya: How about a trip this weekend?', time: 'Yesterday', unread: 5, group: true, color: 0xFFE16AC5),
    ChatSummary(id: 'neha', name: 'Neha Verma', preview: 'Can you send me the documents?', time: 'Mon', unread: 2, online: true, color: 0xFF5F6C3A),
    ChatSummary(id: 'design', name: 'Design Squad', preview: 'Arjun: Shared a file', time: 'Mon', group: true, color: 0xFF22BBB8),
    ChatSummary(id: 'rahul', name: 'Rahul Singh', preview: 'Okay, talk to you tomorrow!', time: 'Sun', online: true, color: 0xFF343434),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(19, 18, 19, 12), child: Row(children: [
            const Text('Chats', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            IconButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use the search field below'))), icon: const Icon(Icons.search, color: _purple)),
            IconButton(onPressed: () => context.go('/contacts/new'), icon: const Icon(Icons.edit_outlined, color: _purple)),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 19), child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 20), hintText: 'Search chats, people or groups...', filled: true, fillColor: const Color(0xFFF7F7FA), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(13))))),
          const SizedBox(height: 20),
          SizedBox(height: 35, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 19), children: ['All', 'Groups', 'Direct', 'Unread', 'Favorites'].map((item) => Padding(padding: const EdgeInsets.only(right: 12), child: ChoiceChip(label: Text(item), selected: filter == item, onSelected: (_) => setState(() => filter = item), selectedColor: const Color(0xFFF0EBFF), labelStyle: TextStyle(color: filter == item ? _purple : _muted), side: const BorderSide(color: Color(0xFFE8E8F0))))).toList())),
          const SizedBox(height: 8),
          Expanded(child: ListView.builder(itemCount: chats.length, itemBuilder: (_, index) => _ChatTile(chat: chats[index], onTap: () => context.go('/chat/${chats[index].id}')))),
        ])),
        bottomNavigationBar: const _BottomNav(),
      );
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.onTap});
  final ChatSummary chat;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: SizedBox(height: 73, child: Row(children: [
          Stack(children: [
            CircleAvatar(radius: 25, backgroundColor: Color(chat.color), child: Icon(chat.group ? Icons.groups_rounded : Icons.person, color: Colors.white, size: 29)),
            if (chat.online) const Positioned(right: 0, bottom: 1, child: CircleAvatar(radius: 5, backgroundColor: Color(0xFF16C653))),
          ]),
          const SizedBox(width: 13),
          Expanded(child: Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F4)))), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)), const SizedBox(height: 5), Text(chat.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.35, color: _muted))])),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(chat.time, style: TextStyle(fontSize: 11, color: chat.unread > 0 ? _purple : _muted)), if (chat.unread > 0) ...[const SizedBox(height: 8), CircleAvatar(radius: 10, backgroundColor: _purple, child: Text('${chat.unread}', style: const TextStyle(fontSize: 10, color: Colors.white)))]])
          ]))),
        ]))),
      );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();
  @override
  Widget build(BuildContext context) => SafeArea(child: Container(height: 66, margin: const EdgeInsets.fromLTRB(14, 0, 14, 9), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
    const _NavItem(Icons.chat_bubble, 'Chat', true), _NavItem(Icons.groups_outlined, 'Group', false, onTap: () => context.go('/groups/new')), _NavItem(Icons.add_circle_outline, 'New Chat', false, onTap: () => context.go('/contacts/new')), _NavItem(Icons.calendar_month_outlined, 'Reminder/Meeting', false, onTap: () => context.go('/reminders')), const _NavItem(Icons.person_outline, 'Profile', false),
  ])));
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.icon, this.label, this.selected, {this.onTap});
  final IconData icon; final String label; final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: selected ? _purple : _muted, size: 22), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 8, color: selected ? _purple : _muted))])));
}
