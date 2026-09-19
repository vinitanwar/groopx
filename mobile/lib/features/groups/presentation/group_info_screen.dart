import 'package:flutter/material.dart';
import '../../auth/presentation/auth_components.dart';

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.groupId});
  final String groupId;
  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final members = <String>['Rohan', 'Ananya Sharma', 'Vikram Mehta', 'Arjun', 'Neha Verma', 'Priya Singh', 'Karan Singh', 'Mehul Shah'];
  final usernames = const ['@rohan_k', '@ananya_s', '@vikram_m', '@arjun_dev', '@neha_v', '@priya_s', '@karan_s', '@mehul_s'];
  final aliases = <int, String>{};

  Future<void> editAlias(int index) async {
    final controller = TextEditingController(text: aliases[index] ?? members[index]);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Edit name for this group'),
      content: TextField(controller: controller, maxLength: 50, decoration: const InputDecoration(labelText: 'Group display name', helperText: 'Only members of this group will see this name')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save'))],
    ));
    controller.dispose();
    if (value != null && value.isNotEmpty && mounted) setState(() => aliases[index] = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, title: const Text('Group Info', style: TextStyle(fontWeight: FontWeight.w700))), body: ListView(padding: const EdgeInsets.all(16), children: [
      const Row(children: [CircleAvatar(radius: 28, backgroundColor: authPurple, child: Icon(Icons.groups, color: Colors.white, size: 31)), SizedBox(width: 15), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Project X Team  ✓', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: authInk)), Text('12 members, 5 online', style: TextStyle(fontSize: 12, color: authMuted))])]),
      const SizedBox(height: 17),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_Action(Icons.call, 'Audio Call'), _Action(Icons.videocam, 'Video Call'), _Action(Icons.search, 'Search')]),
      const SizedBox(height: 15),
      ...[(Icons.notifications_none, 'Notifications', 'All'), (Icons.photo_outlined, 'Media, Links and Files', '245'), (Icons.push_pin_outlined, 'Pinned Messages', '3'), (Icons.palette_outlined, 'Chat Theme', 'Default'), (Icons.lock_outline, 'Privacy & Security', '')].map((item) => ListTile(dense: true, leading: Icon(item.$1, color: authPurple), title: Text(item.$2), trailing: Text('${item.$3}  ›', style: const TextStyle(color: authMuted)))),
      const Divider(),
      Row(children: [const Text('Members', style: TextStyle(fontWeight: FontWeight.w700)), const Spacer(), TextButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add_alt), label: const Text('Add / Invite Members'))]),
      const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Private group: phone numbers and direct-message shortcuts are hidden.', style: TextStyle(fontSize: 11, color: authMuted))),
      ...members.indexed.map((entry) => ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundColor: entry.$1 < 5 ? const Color(0xFF263238) : authPurple, child: Text((aliases[entry.$1] ?? entry.$2).substring(0, 1), style: const TextStyle(color: Colors.white))), title: Text(aliases[entry.$1] ?? entry.$2, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(usernames[entry.$1]), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(entry.$1 < 2 ? 'Admin' : entry.$1 < 5 ? 'Online' : 'Offline', style: TextStyle(fontSize: 11, color: entry.$1 < 2 ? authPurple : entry.$1 < 5 ? Colors.green : authMuted)), IconButton(tooltip: 'Edit group name', onPressed: () => editAlias(entry.$1), icon: const Icon(Icons.edit_outlined, size: 18, color: authPurple))]))),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.logout, color: Colors.red), label: const Text('Exit Group', style: TextStyle(color: Colors.red)), style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, side: const BorderSide(color: Color(0xFFF0E4E8)))),
    ]));
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label); final IconData icon; final String label;
  @override
  Widget build(BuildContext context) => Container(width: 82, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10)]), child: Column(children: [Icon(icon, color: authPurple), const SizedBox(height: 5), Text(label, style: const TextStyle(fontSize: 9))]));
}
