import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/auth_components.dart';

class AddContactScreen extends StatelessWidget {
  const AddContactScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.white, appBar: AppBar(backgroundColor: Colors.white, title: const Text('Add New Contact', style: TextStyle(fontWeight: FontWeight.w700))), body: ListView(padding: const EdgeInsets.all(16), children: [
    const CircleAvatar(radius: 32, backgroundColor: authPurple, child: Icon(Icons.person_add_alt_1, color: Colors.white, size: 34)),
    const SizedBox(height: 22), _label('Save to'), _field('Phone Contacts', Icons.person_outline),
    _label('Contact Information'), _field('Full Name', Icons.person_outline), _field('Username (Optional)', Icons.alternate_email),
    Row(children: [SizedBox(width: 110, child: _field('🇮🇳  +91', Icons.phone_outlined)), const SizedBox(width: 8), Expanded(child: _field('Mobile Number', null))]),
    _field('Notes (Optional)', Icons.note_alt_outlined),
    const SizedBox(height: 12), _label('Add to Groups (Optional)'), _field('Search groups', Icons.search),
    ...['Project X Team', 'Design Squad', 'Weekend Plans'].indexed.map((item) => CheckboxListTile(contentPadding: EdgeInsets.zero, secondary: CircleAvatar(backgroundColor: item.$1 == 0 ? authPurple : item.$1 == 1 ? const Color(0xFF16BFAF) : const Color(0xFFE16AC5), child: const Icon(Icons.groups, color: Colors.white)), title: Text(item.$2), value: item.$1 == 0, onChanged: (_) {})),
    const SizedBox(height: 18), SizedBox(height: 52, child: FilledButton(onPressed: () => context.go('/chats'), style: FilledButton.styleFrom(backgroundColor: authPurple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))), child: const Text('Save Contact'))),
  ]));

  static Widget _label(String text) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
  static Widget _field(String hint, IconData? icon) => Padding(padding: const EdgeInsets.only(bottom: 11), child: TextField(decoration: InputDecoration(prefixIcon: icon == null ? null : Icon(icon, color: authPurple, size: 20), hintText: hint, enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFE0E2EA)), borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: authPurple), borderRadius: BorderRadius.circular(8)))));
}
