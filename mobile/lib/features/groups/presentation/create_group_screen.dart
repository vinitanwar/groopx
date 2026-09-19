import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/auth_components.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final name = TextEditingController();
  final description = TextEditingController();
  bool private = true;
  final selected = <int>{};
  final members = const [('Rohan', '@rohan_k'), ('Ananya Sharma', '@ananya_s'), ('Vikram Mehta', '@vikram_m'), ('Arjun', '@arjun_dev'), ('Neha Verma', '@neha_v'), ('Priya Singh', '@priya_s')];
  @override
  void dispose() { name.dispose(); description.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(backgroundColor: Colors.white, title: const Text('Create Group', style: TextStyle(fontWeight: FontWeight.w700, color: authInk)), actions: [TextButton(onPressed: _create, child: const Text('Create'))]),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 5, 20, 24), children: [
      const CircleAvatar(radius: 34, backgroundColor: authPurple, child: Icon(Icons.groups_rounded, color: Colors.white, size: 38)),
      const SizedBox(height: 8), const Center(child: Text('Add Group Photo', style: TextStyle(color: authPurple))),
      const SizedBox(height: 3), const Center(child: Text('JPG, PNG or GIF. Max size 5MB.', style: TextStyle(fontSize: 10, color: authMuted))),
      const SizedBox(height: 18),
      _label('Group Name'), TextField(controller: name, maxLength: 50, decoration: _input('Enter group name')),
      _label('Group Description (Optional)'), TextField(controller: description, maxLength: 200, maxLines: 2, decoration: _input('Add a description for your group')),
      _label('Privacy'),
      _PrivacyTile(title: 'Private Group', subtitle: 'Only invited members can join and see the group.', icon: Icons.lock, selected: private, onTap: () => setState(() => private = true)),
      const SizedBox(height: 6),
      _PrivacyTile(title: 'Public Group', subtitle: 'Anyone can find the group and join.', icon: Icons.public, selected: !private, onTap: () => setState(() => private = false)),
      const SizedBox(height: 14),
      Row(children: [const Text('Add Members', style: TextStyle(fontWeight: FontWeight.w700, color: authInk)), const Spacer(), Text('${selected.length} Selected', style: const TextStyle(fontSize: 11, color: authPurple))]),
      const SizedBox(height: 8),
      TextField(decoration: _input('Search by username').copyWith(prefixIcon: const Icon(Icons.search))),
      ...List.generate(members.length, (i) => CheckboxListTile(contentPadding: EdgeInsets.zero, secondary: CircleAvatar(backgroundColor: i.isEven ? authPurple : const Color(0xFF16BFAF), child: Text(members[i].$1.substring(0, 1), style: const TextStyle(color: Colors.white))), title: Text(members[i].$1, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(members[i].$2), value: selected.contains(i), activeColor: authPurple, onChanged: (_) => setState(() => selected.contains(i) ? selected.remove(i) : selected.add(i)))),
    ]),
  );

  InputDecoration _input(String hint) => InputDecoration(hintText: hint, counterStyle: const TextStyle(fontSize: 10), enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFDDE0E8)), borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: authPurple), borderRadius: BorderRadius.circular(8)));
  Widget _label(String value) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 7), child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: authInk)));
  void _create() { if (name.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a group name'))); return; } context.pushReplacement('/groups/new-group'); }
}

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile({required this.title, required this.subtitle, required this.icon, required this.selected, required this.onTap});
  final String title, subtitle; final IconData icon; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: selected ? authPurple : const Color(0xFFE0E2E9)), borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? authPurple : authMuted), const SizedBox(width: 12), CircleAvatar(backgroundColor: const Color(0xFFF2EDFF), child: Icon(icon, color: authPurple)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), Text(subtitle, style: const TextStyle(fontSize: 10, color: authMuted))]))])));
}
