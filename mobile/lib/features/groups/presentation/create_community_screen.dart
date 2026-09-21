import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../contacts/data/social_api.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});
  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final name = TextEditingController();
  final description = TextEditingController();
  bool saving = false;

  @override
  void dispose() { name.dispose(); description.dispose(); super.dispose(); }

  Future<void> _create() async {
    if (name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Community name minimum 2 characters ka hona chahiye.')));
      return;
    }
    setState(() => saving = true);
    try {
      final id = await SocialApi.instance.createCommunity(name: name.text.trim(), description: description.text.trim());
      if (mounted) Navigator.pop(context, id);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Community create nahi hui. Retry karein.')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Create Community')),
    body: GroopXBackground(child: ListView(padding: const EdgeInsets.fromLTRB(18, 24, 18, 32), children: [
      Center(child: Container(width: 86, height: 86, decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(28)), child: const Icon(Icons.hub_outlined, size: 44, color: AppColors.purple))),
      const SizedBox(height: 18),
      const Text('Bring related groups together', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.text)),
      const SizedBox(height: 8),
      const Text('A community keeps multiple private groups organized in one place.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.4)),
      const SizedBox(height: 24),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(controller: name, textCapitalization: TextCapitalization.words, maxLength: 80, decoration: const InputDecoration(labelText: 'Community name', hintText: 'Example: Project X', prefixIcon: Icon(Icons.hub_outlined))),
        const SizedBox(height: 13),
        TextField(controller: description, maxLength: 200, maxLines: 4, decoration: const InputDecoration(labelText: 'Description', hintText: 'What is this community for?', prefixIcon: Icon(Icons.notes_outlined), alignLabelWithHint: true)),
      ]))),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: saving ? null : _create, icon: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add), label: Text(saving ? 'Creating…' : 'Create Community')),
    ])),
  );
}
