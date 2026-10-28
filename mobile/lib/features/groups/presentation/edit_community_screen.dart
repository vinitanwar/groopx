import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../contacts/data/social_api.dart';

class EditCommunityScreen extends StatefulWidget {
  const EditCommunityScreen({super.key, required this.communityId});
  final String communityId;

  @override
  State<EditCommunityScreen> createState() => _EditCommunityScreenState();
}

class _EditCommunityScreenState extends State<EditCommunityScreen> {
  final name = TextEditingController();
  final description = TextEditingController();
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final community = await SocialApi.instance.community(widget.communityId);
      if (!mounted) return;
      if (community.role != 'admin') {
        setState(() {
          error = 'Only community admins can edit community info.';
          loading = false;
        });
        return;
      }
      name.text = community.name;
      description.text = community.description;
      setState(() {
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Community details load nahi hui.';
          loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final cleanName = name.text.trim();
    if (cleanName.runes.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Community name minimum 2 characters ka hona chahiye.')));
      return;
    }
    setState(() => saving = true);
    try {
      await SocialApi.instance.updateCommunity(widget.communityId, name: cleanName, description: description.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Community update nahi hui. Retry karein.')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Edit Community')),
    body: GroopXBackground(
      child: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : error != null
              ? GroopXEmptyState(
                  icon: Icons.lock_outline,
                  title: 'Unable to edit',
                  message: error!,
                  actionLabel: 'Retry',
                  actionIcon: Icons.refresh,
                  onAction: () {
                    setState(() {
                      loading = true;
                      error = null;
                    });
                    _load();
                  },
                )
              : ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
                  children: [
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(28)),
                        child: const Icon(Icons.hub_outlined, size: 44, color: AppColors.purple),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Community info', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.text)),
                    const SizedBox(height: 8),
                    const Text('Name aur description community members ke chat aur community list mein update honge.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.4)),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          TextField(
                            controller: name,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 80,
                            decoration: const InputDecoration(labelText: 'Community name', prefixIcon: Icon(Icons.hub_outlined)),
                          ),
                          const SizedBox(height: 13),
                          TextField(
                            controller: description,
                            maxLength: 200,
                            maxLines: 4,
                            decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.notes_outlined), alignLabelWithHint: true),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: saving ? null : _save,
                      icon: saving
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: Text(saving ? 'Saving…' : 'Save Changes'),
                    ),
                  ],
                ),
    ),
  );
}
