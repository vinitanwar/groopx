import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../auth/data/auth_api.dart';

class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  List<AccountSession> sessions = const [];
  bool loading = true;
  bool revokingOthers = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final value = await AuthApi.instance.sessions();
      if (mounted) setState(() => sessions = value);
    } catch (_) {
      if (mounted) setState(() => error = 'Linked devices load nahi hue.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _revoke(AccountSession session) async {
    if (session.current) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Log out this device?'),
      content: Text('${session.deviceName} ko GroopX account se securely log out kar diya jayega.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
      ],
    ));
    if (confirmed != true) return;
    try {
      await AuthApi.instance.revokeSession(session.id);
      if (mounted) setState(() => sessions = sessions.where((item) => item.id != session.id).toList());
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device log out nahi hua. Retry karein.')));
    }
  }

  Future<void> _revokeOthers() async {
    final others = sessions.where((item) => !item.current).length;
    if (others == 0 || revokingOthers) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Log out all other devices?'),
      content: Text('$others other active ${others == 1 ? 'device' : 'devices'} ko log out kiya jayega. This device signed in rahega.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out devices')),
      ],
    ));
    if (confirmed != true) return;
    setState(() => revokingOthers = true);
    try {
      final count = await AuthApi.instance.revokeOtherSessions();
      if (mounted) {
        setState(() => sessions = sessions.where((item) => item.current).toList());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count other ${count == 1 ? 'device' : 'devices'} logged out.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Other devices log out nahi hue.')));
    } finally {
      if (mounted) setState(() => revokingOthers = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Linked Devices')),
    body: GroopXBackground(child: loading
      ? const Center(child: CircularProgressIndicator())
      : error != null
        ? GroopXEmptyState(icon: Icons.devices_other, title: 'Unable to load devices', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 30), children: [
            Card(child: const Padding(padding: EdgeInsets.all(18), child: Row(children: [
              _SecurityIcon(),
              SizedBox(width: 14),
              Expanded(child: Text('Yahan har active GroopX login dikhaya gaya hai. Unknown device ko turant log out karein.', style: TextStyle(color: AppColors.muted, height: 1.45))),
            ]))),
            const SizedBox(height: 22),
            const GroopXSectionTitle('Active sessions'),
            const SizedBox(height: 10),
            Card(child: Column(children: [
              for (var index = 0; index < sessions.length; index++) ...[
                _sessionTile(sessions[index]),
                if (index < sessions.length - 1) const Divider(height: 1, indent: 66),
              ],
            ])),
            if (sessions.any((item) => !item.current)) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: revokingOthers ? null : _revokeOthers,
                icon: revokingOthers ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.phonelink_erase),
                label: const Text('Log out all other devices'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Color(0xFFFFC7CA)), padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
          ]))),
  );

  Widget _sessionTile(AccountSession session) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
    leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: session.current ? const Color(0xFFE8F7F1) : const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(13)), child: Icon(session.current ? Icons.smartphone : Icons.devices, color: session.current ? const Color(0xFF169B69) : AppColors.purple)),
    title: Row(children: [Expanded(child: Text(session.deviceName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))), if (session.current) const _CurrentBadge()]),
    subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text('${_relative(session.lastSeenAt)}${session.ipAddress.isEmpty ? '' : ' · ${session.ipAddress}'}', style: const TextStyle(fontSize: 12, color: AppColors.muted))),
    trailing: session.current ? null : IconButton(tooltip: 'Log out device', onPressed: () => _revoke(session), icon: const Icon(Icons.logout, color: Colors.red)),
  );

  String _relative(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 2) return 'Active now';
    if (difference.inHours < 1) return 'Active ${difference.inMinutes} min ago';
    if (difference.inDays < 1) return 'Active ${difference.inHours} hr ago';
    return 'Active ${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
}

class _SecurityIcon extends StatelessWidget {
  const _SecurityIcon();
  @override
  Widget build(BuildContext context) => Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.security, color: AppColors.purple));
}

class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge();
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFE8F7F1), borderRadius: BorderRadius.circular(20)), child: const Text('This device', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF16845D))));
}
