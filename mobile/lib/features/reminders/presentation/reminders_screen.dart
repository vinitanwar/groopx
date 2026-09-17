import 'package:flutter/material.dart';
import '../../auth/presentation/auth_components.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final reminders = <({String title, String detail, IconData icon, Color color})>[
    (title: 'Project X Team Meeting', detail: 'Today • 4:00 PM • Project X Team', icon: Icons.videocam_outlined, color: authPurple),
    (title: 'Send design feedback', detail: 'Today • 6:30 PM • Vikram Mehta', icon: Icons.notifications_none, color: Color(0xFF17BFAE)),
    (title: 'Weekend plan discussion', detail: 'Tomorrow • 11:00 AM • Weekend Plans', icon: Icons.groups_outlined, color: Color(0xFFE16AC5)),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(backgroundColor: Colors.white, title: const Text('Reminder / Meeting', style: TextStyle(fontWeight: FontWeight.w700, color: authInk)), actions: [IconButton(onPressed: _showCreate, icon: const Icon(Icons.add_circle_outline, color: authPurple))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(18), child: Row(children: ['Upcoming', 'Completed', 'All'].map((label) => Expanded(child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: label == 'Upcoming' ? const Color(0xFFF0EBFF) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE7E5ED))), child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: label == 'Upcoming' ? authPurple : authMuted))))).toList())),
      Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 18), itemCount: reminders.length, itemBuilder: (_, i) { final item = reminders[i]; return Container(margin: const EdgeInsets.only(bottom: 13), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFE8E7EE)), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10)]), child: Row(children: [CircleAvatar(backgroundColor: item.color.withValues(alpha: .12), child: Icon(item.icon, color: item.color)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, color: authInk)), const SizedBox(height: 6), Text(item.detail, style: const TextStyle(fontSize: 11, color: authMuted))])), const Icon(Icons.more_vert, color: authMuted)])); })),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _showCreate, backgroundColor: authPurple, foregroundColor: Colors.white, icon: const Icon(Icons.add), label: const Text('New Reminder')),
  );

  void _showCreate() => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (context) => Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Center(child: Text('Create Reminder', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: authInk))), const SizedBox(height: 22), const TextField(decoration: InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title))), const SizedBox(height: 12), const TextField(decoration: InputDecoration(labelText: 'Date & Time', prefixIcon: Icon(Icons.calendar_month))), const SizedBox(height: 12), const TextField(decoration: InputDecoration(labelText: 'Chat or Group', prefixIcon: Icon(Icons.chat_outlined))), const SizedBox(height: 20), PurpleButton(label: 'Create Reminder', onPressed: () => Navigator.pop(context))])));
}

