import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../auth/data/auth_api.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const _SettingsScreen(title: 'Privacy', icon: Icons.lock_outline, message: 'Control what other GroopX users can see.', definitions: [
    _SettingDefinition('show_online_status', 'Online status', 'Contacts ko aapka live online status aur last seen dikhai dega.'),
    _SettingDefinition('read_receipts', 'Read receipts', 'Message read karne par sender ko read indicator dikhai dega.'),
  ]);
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const _SettingsScreen(title: 'Notifications', icon: Icons.notifications_none, message: 'Choose which GroopX alerts you want to receive.', definitions: [
    _SettingDefinition('push_notifications', 'Push notifications', 'All external app notifications ka master control.'),
    _SettingDefinition('message_notifications', 'Messages', 'New direct aur group message alerts.'),
    _SettingDefinition('call_notifications', 'Voice & video calls', 'Incoming call aur missed call alerts.'),
    _SettingDefinition('reminder_notifications', 'Reminders & meetings', 'Scheduled reminder aur meeting alerts.'),
  ]);
}

class _SettingDefinition {
  const _SettingDefinition(this.keyName, this.title, this.subtitle);
  final String keyName, title, subtitle;
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({required this.title, required this.icon, required this.message, required this.definitions});
  final String title, message;
  final IconData icon;
  final List<_SettingDefinition> definitions;
  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  Map<String, bool> values = {};
  final Set<String> saving = {};
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final profile = await AuthApi.instance.currentUser();
      final settings = profile['settings'] as Map? ?? {};
      if (mounted) setState(() => values = {for (final item in widget.definitions) item.keyName: settings[item.keyName] == true});
    } catch (_) {
      if (mounted) setState(() => error = 'Settings load nahi hui.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() { values[key] = value; saving.add(key); });
    try { await AuthApi.instance.updateSettings({key: value}); }
    catch (_) {
      if (mounted) {
        setState(() => values[key] = !value);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Setting save nahi hui. Retry karein.')));
      }
    } finally { if (mounted) setState(() => saving.remove(key)); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: Text(widget.title)),
    body: GroopXBackground(child: loading
      ? const Center(child: CircularProgressIndicator())
      : error != null
        ? GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Unable to load', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
        : ListView(padding: const EdgeInsets.all(18), children: [
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(15)), child: Icon(widget.icon, color: AppColors.purple)),
              const SizedBox(width: 14),
              Expanded(child: Text(widget.message, style: const TextStyle(color: AppColors.muted, height: 1.4))),
            ]))),
            const SizedBox(height: 14),
            Card(child: Column(children: [
              for (var index = 0; index < widget.definitions.length; index++) ...[
                _tile(widget.definitions[index]),
                if (index < widget.definitions.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ])),
          ])),
  );

  Widget _tile(_SettingDefinition item) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    value: values[item.keyName] == true,
    onChanged: saving.contains(item.keyName) ? null : (value) => _toggle(item.keyName, value),
    activeColor: AppColors.purple,
    title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
    subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35))),
    secondary: saving.contains(item.keyName) ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
  );
}
