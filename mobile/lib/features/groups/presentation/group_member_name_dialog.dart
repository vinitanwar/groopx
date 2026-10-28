import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../contacts/data/social_api.dart';

Future<String?> showGroupMemberNameEditor(BuildContext context, GroupMember member, {String scopeLabel = 'group'}) {
  final controller = TextEditingController(text: member.displayName);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Name in this $scopeLabel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile: ${member.profileName}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 5),
            Text('Ye naam sirf is $scopeLabel mein dikhega. Original profile change nahi hogi.', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Display name', hintText: member.profileName, errorText: error),
              onSubmitted: (_) => _saveGroupMemberName(dialogContext, controller, setDialogState, (message) => error = message),
            ),
          ],
        ),
        actions: [
          if (member.displayName.isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(dialogContext, ''), child: const Text('Reset name')),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => _saveGroupMemberName(dialogContext, controller, setDialogState, (message) => error = message),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}

void _saveGroupMemberName(BuildContext context, TextEditingController controller, StateSetter setDialogState, ValueChanged<String?> setError) {
  final value = controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  final length = value.runes.length;
  if (length < 2 || length > 80) {
    setDialogState(() => setError('Name 2–80 characters ka hona chahiye.'));
    return;
  }
  Navigator.pop(context, value);
}

String groupMemberSubtitle(GroupMember member) {
  final parts = <String>[];
  if (member.username.isNotEmpty) parts.add('@${member.username}');
  parts.add(member.role == 'admin' ? 'Admin' : 'Member');
  if (member.displayName.isNotEmpty) parts.add('Profile: ${member.profileName}');
  return parts.join(' · ');
}
