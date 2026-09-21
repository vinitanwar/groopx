import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../auth/data/auth_api.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? profile;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final value = await AuthApi.instance.currentUser();
      if (mounted) setState(() => profile = value);
    } catch (_) {
      if (mounted) setState(() => error = 'Profile load nahi ho saka.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(String route) async { await context.push(route); await _load(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Profile'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/chats'))),
    body: GroopXBackground(child: loading
      ? const Center(child: CircularProgressIndicator())
      : error != null
        ? GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Profile unavailable', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 34), children: [
            _profileCard(),
            const SizedBox(height: 22),
            const GroopXSectionTitle('Settings'),
            const SizedBox(height: 10),
            Card(child: Column(children: [
              _menu(Icons.person_outline, 'Edit profile', 'Photo, name, username, bio and personal details', () => _open('/profile/edit')),
              const Divider(height: 1, indent: 58),
              _menu(Icons.lock_outline, 'Privacy', 'Online status and read receipts', () => _open('/profile/privacy')),
              const Divider(height: 1, indent: 58),
              _menu(Icons.notifications_none, 'Notifications', 'Messages, calls and reminder alerts', () => _open('/profile/notifications')),
              const Divider(height: 1, indent: 58),
              _menu(Icons.block_outlined, 'Blocked users', 'Review and unblock people', () => _open('/blocked-users')),
              const Divider(height: 1, indent: 58),
              _menu(Icons.security_outlined, 'Account & security', 'Phone number, secure session and logout', () => _open('/profile/account')),
              const Divider(height: 1, indent: 58),
              _menu(Icons.call_outlined, 'Calls', 'Audio and video call history', () => _open('/calls')),
              const Divider(height: 1, indent: 58),
              _menu(Icons.storage_outlined, 'Storage & data', 'Media, network and local storage information', () => _open('/profile/storage')),
              const Divider(height: 1, indent: 58),
              _menu(Icons.help_outline, 'Help & about', 'Privacy, terms and application information', () => _open('/profile/help')),
            ])),
            const SizedBox(height: 18),
            const Center(child: Text('GroopX · Privacy first', style: TextStyle(color: AppColors.muted, fontSize: 12))),
          ]))),
  );

  Widget _profileCard() {
    final name = profile?['full_name']?.toString().trim() ?? '';
    final username = profile?['username']?.toString().trim() ?? '';
    final bio = profile?['bio']?.toString().trim() ?? '';
    final avatar = profile?['avatar_url']?.toString() ?? '';
    return Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      GestureDetector(onTap:()=>context.push('/profile/avatar',extra:<String,String>{'name':name.isEmpty?'GroopX user':name,'url':avatar}),child:GroopXAvatar(label: name.isNotEmpty ? name : 'GroopX', imageUrl: avatar, radius: 42)),
      const SizedBox(height: 13),
      Text(name.isNotEmpty ? name : 'GroopX user', textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.text)),
      if (username.isNotEmpty) ...[const SizedBox(height: 4), Text('@$username', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600))],
      if (bio.isNotEmpty) ...[const SizedBox(height: 10), Text(bio, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4))],
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: () => _open('/profile/edit'), icon: const Icon(Icons.edit_outlined), label: const Text('Edit Profile')),
    ])));
  }

  Widget _menu(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.purple, size: 21)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
    subtitle: Padding(padding: const EdgeInsets.only(top: 3), child: Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
    trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
    onTap: onTap,
  );
}
