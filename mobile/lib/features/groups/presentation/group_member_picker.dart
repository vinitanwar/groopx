import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../contacts/data/social_api.dart';

Future<UserOption?> showGroupMemberPicker(BuildContext context, {Set<String> excludedIds = const <String>{}}) {
  return showModalBottomSheet<UserOption>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GroupMemberPickerSheet(excludedIds: excludedIds),
  );
}

class GroupMemberPickerSheet extends StatefulWidget {
  const GroupMemberPickerSheet({super.key, this.excludedIds = const <String>{}});
  final Set<String> excludedIds;

  @override
  State<GroupMemberPickerSheet> createState() => _GroupMemberPickerSheetState();
}

class _GroupMemberPickerSheetState extends State<GroupMemberPickerSheet> {
  final search = TextEditingController();
  List<UserOption> results = const [];
  bool loading = false;
  String? error;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final query = search.text.trim();
    if (query.length < 2) {
      setState(() => error = 'Minimum 2 characters type karein.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final users = await SocialApi.instance.searchUsers(query);
      if (mounted) {
        setState(() => results = users.where((user) => !widget.excludedIds.contains(user.id)).toList());
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Users search nahi hue.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Add Group Member', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text)),
      const SizedBox(height: 16),
      TextField(
        controller: search,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _find(),
        decoration: InputDecoration(
          labelText: 'Name, username or phone',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: _find, icon: const Icon(Icons.arrow_forward)),
        ),
      ),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
      if (!loading && results.isEmpty && error == null)
        const Padding(padding: EdgeInsets.symmetric(vertical: 22), child: Text('Search karke exact member select karein.', style: TextStyle(color: AppColors.muted))),
      if (results.isNotEmpty)
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.only(top: 12),
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final user = results[index];
              return ListTile(
                leading: GroopXAvatar(label: user.name, imageUrl: user.avatarUrl),
                title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(user.username.isEmpty ? 'GroopX user' : '@${user.username}'),
                trailing: const Icon(Icons.add_circle_outline, color: AppColors.purple),
                onTap: () => Navigator.pop(context, user),
              );
            },
          ),
        ),
    ]),
  );
}
