import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/backup_api.dart';

class BackupSetupScreen extends StatefulWidget {
  const BackupSetupScreen({super.key, this.nextRoute = '/chats'});
  final String nextRoute;

  @override
  State<BackupSetupScreen> createState() => _BackupSetupScreenState();
}

class _BackupSetupScreenState extends State<BackupSetupScreen> {
  BackupFrequency frequency = BackupFrequency.daily;
  bool busy = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Chat backup')),
    body: GroopXBackground(child: SafeArea(child: ListView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      children: [
        const SizedBox(height: 22),
        Center(child: Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(30)),
          child: const Icon(Icons.cloud_upload_outlined, size: 55, color: AppColors.purple),
        )),
        const SizedBox(height: 28),
        const Text('Keep your chats safe', textAlign: TextAlign.center, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text('Messages aur chat history ka secure backup banayein. Phone change ya reinstall ke baad backup restore kar sakte hain.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.55)),
        const SizedBox(height: 30),
        const Text('Automatic backup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Card(child: Column(children: [
          _option(BackupFrequency.daily, 'Daily', 'Recommended'),
          const Divider(height: 1, indent: 56),
          _option(BackupFrequency.weekly, 'Weekly', 'Every 7 days'),
          const Divider(height: 1, indent: 56),
          _option(BackupFrequency.off, 'Off', 'Only back up manually'),
        ])),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : _continue,
          icon: busy ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.backup_outlined),
          label: Text(busy ? 'Creating backup…' : 'Back up now & continue'),
        ),
        TextButton(onPressed: busy ? null : _skip, child: const Text('Skip for now')),
        const SizedBox(height: 12),
        const Text('Backup frequency baad mein Profile → Storage & Data se change ki ja sakti hai.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
      ],
    ))),
  );

  Widget _option(BackupFrequency value, String title, String subtitle) => RadioListTile<BackupFrequency>(
    value: value,
    groupValue: frequency,
    activeColor: AppColors.purple,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    onChanged: busy ? null : (selected) => setState(() => frequency = selected!),
  );

  Future<void> _continue() async {
    setState(() => busy = true);
    try {
      await BackupPreferences.instance.save(frequency);
      if (frequency != BackupFrequency.off) {
        await BackupApi.instance.create();
        await BackupPreferences.instance.markAttempt();
      }
      if (mounted) context.go(widget.nextRoute);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup create nahi hua. Internet check karke retry karein.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _skip() async {
    await BackupPreferences.instance.save(BackupFrequency.off);
    if (mounted) context.go(widget.nextRoute);
  }
}
