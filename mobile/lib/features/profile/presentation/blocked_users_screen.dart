import 'package:flutter/material.dart';
import '../../contacts/data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<UserOption> users = const [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try { final result = await SocialApi.instance.blockedUsers(); if (mounted) setState(() { users = result; error = null; }); }
    catch (_) { if (mounted) setState(() => error = 'Blocked users load nahi hue'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _unblock(UserOption user) async {
    try {
      await SocialApi.instance.setBlocked(user.id, false);
      if (mounted) {
        setState(() => users = users.where((item) => item.id != user.id).toList());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${user.name} unblocked')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User unblock nahi hua. Retry karein.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Blocked Users')),
    body: GroopXBackground(child: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null ? GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Unable to load', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
        : users.isEmpty
            ? const GroopXEmptyState(icon: Icons.person_off_outlined, title: 'No blocked users', message: 'Aapne kisi GroopX user ko block nahi kiya hai.')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final user = users[index];
                    return Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16,vertical: 8),
                      leading: GroopXAvatar(label:user.name),
                      title: Text(user.name),
                      subtitle: Text(user.username.isEmpty ? 'GroopX user' : '@${user.username}'),
                      trailing: TextButton(onPressed: () => _unblock(user), child: const Text('Unblock')),
                    ));
                  },
                ),
              )),
  );
}
