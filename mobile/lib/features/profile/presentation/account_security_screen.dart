import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../auth/data/auth_api.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});
  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  Map<String, dynamic>? profile;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try { final value = await AuthApi.instance.currentUser(); if (mounted) setState(() => profile = value); }
    catch (_) { if (mounted) setState(() => error = 'Account details load nahi hui.'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Log out of GroopX?'),
      content: const Text('Is device se aapka secure session remove ho jayega.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out'))],
    ));
    if (confirmed != true) return;
    await AuthApi.instance.logout();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Account & Security')),
    body: GroopXBackground(child: loading
      ? const Center(child: CircularProgressIndicator())
      : error != null
        ? GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Unable to load', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
        : ListView(padding: const EdgeInsets.all(18), children: [
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFE8F7F1), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.verified_user_outlined, color: Color(0xFF169B69))),
            const SizedBox(width: 14),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Your account is protected', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text)), SizedBox(height: 4), Text('Secure OTP login and encrypted session storage are active.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4))])),
          ]))),
          const SizedBox(height: 14),
          Card(child: Column(children: [
            ListTile(leading: const Icon(Icons.phone_outlined, color: AppColors.purple), title: const Text('Registered phone'), subtitle: Text(profile?['phone']?.toString() ?? 'Not available')),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.alternate_email, color: AppColors.purple), title: const Text('Username'), subtitle: Text('@${profile?['username'] ?? ''}')),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(leading: const Icon(Icons.devices_outlined, color: AppColors.purple), title: const Text('Linked devices', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('Review and securely log out active sessions'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/profile/devices')),
          ])),
          const SizedBox(height: 14),
          Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Log out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)), subtitle: const Text('Remove this device session safely'), trailing: const Icon(Icons.chevron_right), onTap: _logout)),
        ])),
  );
}
