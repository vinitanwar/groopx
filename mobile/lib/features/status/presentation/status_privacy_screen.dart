import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/status_api.dart';

class StatusPrivacyScreen extends StatefulWidget {
  const StatusPrivacyScreen({super.key});

  @override
  State<StatusPrivacyScreen> createState() => _StatusPrivacyScreenState();
}

class _StatusPrivacyScreenState extends State<StatusPrivacyScreen> {
  final search = TextEditingController();
  List<StatusPrivacyContact> contacts = const [];
  Set<String> selected = <String>{};
  String audience = 'contacts';
  String query = '';
  String? error;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await StatusApi.instance.privacy();
      if (!mounted) return;
      setState(() {
        audience = value.audience;
        contacts = value.contacts;
        selected = value.selectedUserIds;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Status privacy load nahi hui.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _selectAudience(String value) {
    if (saving || audience == value) return;
    setState(() {
      audience = value;
      selected = <String>{};
    });
  }

  void _toggleContact(String id) {
    if (saving) return;
    setState(() {
      if (!selected.add(id)) selected.remove(id);
    });
  }

  void _toggleVisible(List<StatusPrivacyContact> visible) {
    if (saving || visible.isEmpty) return;
    final allSelected = visible.every((contact) => selected.contains(contact.id));
    setState(() {
      if (allSelected) {
        selected.removeAll(visible.map((contact) => contact.id));
      } else {
        selected.addAll(visible.map((contact) => contact.id));
      }
    });
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await StatusApi.instance.updatePrivacy(
        audience: audience,
        userIds: audience == 'contacts' ? <String>{} : selected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status privacy saved.')));
      context.pop(true);
    } catch (failure) {
      if (!mounted) return;
      var message = 'Status privacy save nahi hui. Retry karein.';
      if (failure is DioException && failure.response?.data is Map && (failure.response!.data as Map)['error'] != null) {
        message = (failure.response!.data as Map)['error'].toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final visible = contacts.where((contact) {
      if (normalizedQuery.isEmpty) return true;
      return contact.name.toLowerCase().contains(normalizedQuery) || contact.username.toLowerCase().contains(normalizedQuery);
    }).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Status privacy'),
        actions: [
          TextButton(
            onPressed: loading || error != null || saving ? null : _save,
            child: saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('SAVE', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GroopXBackground(
        child: loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
            : error != null
                ? GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Privacy unavailable', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(17),
                          child: Row(children: [
                            Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.privacy_tip_outlined, color: AppColors.purple)),
                            const SizedBox(width: 14),
                            const Expanded(child: Text('Choose who can see the text, photo and video statuses you post.', style: TextStyle(color: AppColors.muted, height: 1.4))),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const GroopXSectionTitle('Who can see my status'),
                      const SizedBox(height: 10),
                      Card(
                        child: Column(children: [
                          _audienceTile('contacts', Icons.people_outline, 'My contacts', 'All contacts saved by you'),
                          const Divider(height: 1, indent: 64),
                          _audienceTile('contacts_except', Icons.person_remove_outlined, 'My contacts except…', 'Hide updates from selected contacts'),
                          const Divider(height: 1, indent: 64),
                          _audienceTile('only_share_with', Icons.how_to_reg_outlined, 'Only share with…', 'Only selected contacts can see updates'),
                        ]),
                      ),
                      if (audience != 'contacts') ...[
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(child: GroopXSectionTitle(audience == 'contacts_except' ? 'Hide from (${selected.length})' : 'Share with (${selected.length})')),
                          TextButton(onPressed: () => _toggleVisible(visible), child: Text(visible.isNotEmpty && visible.every((contact) => selected.contains(contact.id)) ? 'Clear' : 'Select all')),
                        ]),
                        const SizedBox(height: 8),
                        TextField(
                          controller: search,
                          onChanged: (value) => setState(() => query = value),
                          decoration: InputDecoration(
                            hintText: 'Search contacts',
                            prefixIcon: const Icon(Icons.search, color: AppColors.purple),
                            suffixIcon: query.isEmpty ? null : IconButton(onPressed: () { search.clear(); setState(() => query = ''); }, icon: const Icon(Icons.close)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (audience == 'only_share_with' && selected.isEmpty)
                          const Card(child: ListTile(leading: Icon(Icons.info_outline, color: AppColors.purple), title: Text('No contacts selected'), subtitle: Text('New statuses will stay private until you select at least one contact.'))),
                        if (contacts.isEmpty)
                          const Card(child: ListTile(leading: Icon(Icons.person_add_alt_outlined, color: AppColors.purple), title: Text('No saved contacts'), subtitle: Text('Add GroopX contacts first, then choose them here.')))
                        else if (visible.isEmpty)
                          const Card(child: ListTile(leading: Icon(Icons.search_off, color: AppColors.muted), title: Text('No contact found')))
                        else
                          Card(
                            child: Column(children: [
                              for (var index = 0; index < visible.length; index++) ...[
                                _contactTile(visible[index]),
                                if (index < visible.length - 1) const Divider(height: 1, indent: 70),
                              ],
                            ]),
                          ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _audienceTile(String value, IconData icon, String title, String subtitle) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        onTap: () => _selectAudience(value),
        leading: Icon(icon, color: audience == value ? AppColors.purple : AppColors.muted),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        trailing: Radio<String>(value: value, groupValue: audience, activeColor: AppColors.purple, onChanged: (next) { if (next != null) _selectAudience(next); }),
      );

  Widget _contactTile(StatusPrivacyContact contact) => CheckboxListTile(
        value: selected.contains(contact.id),
        activeColor: AppColors.purple,
        onChanged: (_) => _toggleContact(contact.id),
        controlAffinity: ListTileControlAffinity.trailing,
        secondary: GroopXAvatar(label: contact.name, imageUrl: contact.avatarUrl),
        title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
        subtitle: contact.username.isEmpty ? null : Text('@${contact.username}', style: const TextStyle(color: AppColors.muted)),
      );
}
