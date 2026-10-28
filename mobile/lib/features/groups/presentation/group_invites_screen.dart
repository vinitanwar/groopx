import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class GroupInvitesScreen extends StatefulWidget {
  const GroupInvitesScreen({super.key, required this.groupId, this.title = 'Group Invite Links', this.scopeLabel = 'group'});
  final String groupId, title, scopeLabel;

  @override
  State<GroupInvitesScreen> createState() => _GroupInvitesScreenState();
}

class _GroupInvitesScreenState extends State<GroupInvitesScreen> {
  List<GroupInvite>? invites;
  final Map<String, String> sessionLinks = {};
  String? error;
  String? busyInviteId;
  bool creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await SocialApi.instance.groupInvites(widget.groupId);
      if (mounted) setState(() { invites = value; error = null; });
    } catch (_) {
      if (mounted) setState(() => error = 'Invite links load nahi hue.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = invites;
    final activeCount = value?.where((invite) => invite.active).length ?? 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: GroopXBackground(
        child: value == null
          ? (error == null
              ? const Center(child: CircularProgressIndicator(color: authPurple))
              : GroopXEmptyState(icon: Icons.link_off_outlined, title: 'Unable to load links', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const CircleAvatar(backgroundColor: Color(0xFFEEE9FF), child: Icon(Icons.link, color: authPurple)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Invite people securely', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('$activeCount active link${activeCount == 1 ? '' : 's'}', style: const TextStyle(color: authMuted)),
                        ])),
                      ]),
                      const SizedBox(height: 12),
                      const Text('Har link ki expiry aur usage limit set karein. Reset karne par sabhi active links turant band ho jayenge.', style: TextStyle(color: authMuted, height: 1.35)),
                      const SizedBox(height: 16),
                      SizedBox(width: double.infinity, child: FilledButton.icon(
                        onPressed: creating ? null : () => _create(reset: false),
                        icon: creating ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_link),
                        label: const Text('Create New Link'),
                      )),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        onPressed: creating || activeCount == 0 ? null : () => _create(reset: true),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset Active Links'),
                      )),
                    ]),
                  )),
                  const SizedBox(height: 22),
                  Row(children: [
                    const Text('Link history', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const Spacer(),
                    Text('${value.length}', style: const TextStyle(color: authMuted)),
                  ]),
                  const SizedBox(height: 10),
                  if (value.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(24), child: Column(children: [
                      Icon(Icons.link_off_outlined, color: authMuted, size: 34),
                      SizedBox(height: 8),
                      Text('Abhi koi invite link nahi hai.', style: TextStyle(color: authMuted)),
                    ])))
                  else
                    ...value.map(_inviteCard),
                  const SizedBox(height: 30),
                ],
              ),
            ),
      ),
    );
  }

  Widget _inviteCard(GroupInvite invite) {
    final link = sessionLinks[invite.id];
    final statusColor = switch (invite.status) {
      'active' => const Color(0xFF168A55),
      'revoked' => const Color(0xFFD24B5A),
      _ => authMuted,
    };
    final statusLabel = switch (invite.status) {
      'active' => 'Active',
      'revoked' => 'Revoked',
      'exhausted' => 'Used up',
      _ => 'Expired',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Created by ${invite.creatorName}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 5),
          Text('Created ${_formatDate(invite.createdAt)}', style: const TextStyle(color: authMuted, fontSize: 12)),
          Text('Expires ${_formatDate(invite.expiresAt)}', style: const TextStyle(color: authMuted, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: invite.maxUses == 0 ? 0.0 : (invite.useCount / invite.maxUses).clamp(0, 1).toDouble(), minHeight: 7, backgroundColor: const Color(0xFFEAE7F3)),
            )),
            const SizedBox(width: 12),
            Text('${invite.useCount}/${invite.maxUses} used', style: const TextStyle(fontSize: 12, color: authMuted)),
          ]),
          const SizedBox(height: 11),
          if (link != null && invite.active)
            Row(children: [
              const Expanded(child: Text('Link available on this screen', style: TextStyle(fontSize: 12, color: authMuted))),
              TextButton.icon(onPressed: () => _copy(link), icon: const Icon(Icons.copy_outlined, size: 17), label: const Text('Copy')),
            ])
          else if (invite.active)
            const Text('Security ke liye existing link text server par store nahi hota. Naya copy chahiye to reset karein.', style: TextStyle(fontSize: 11, color: authMuted, height: 1.3)),
          if (invite.active) ...[
            const Divider(height: 18),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(
              onPressed: busyInviteId == invite.id ? null : () => _revoke(invite),
              icon: busyInviteId == invite.id ? const SizedBox.square(dimension: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_off_outlined),
              label: const Text('Revoke'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFD24B5A)),
            )),
          ],
        ]),
      ),
    );
  }

  Future<void> _create({required bool reset}) async {
    final settings = await _inviteSettings(reset: reset);
    if (settings == null || !mounted) return;
    setState(() => creating = true);
    try {
      final created = reset
        ? await SocialApi.instance.resetGroupInvites(widget.groupId, expiresInHours: settings.hours, maxUses: settings.maxUses)
        : await SocialApi.instance.createGroupInviteDetails(widget.groupId, expiresInHours: settings.hours, maxUses: settings.maxUses);
      if (reset) sessionLinks.clear();
      sessionLinks[created.id] = created.link;
      await Clipboard.setData(ClipboardData(text: created.link));
      await _load();
      if (mounted) await _showCreated(created, reset: reset);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reset ? 'Invite links reset nahi hue.' : 'Invite link create nahi hua.')));
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<_InviteSettings?> _inviteSettings({required bool reset}) async {
    var hours = 24;
    var maxUses = 50;
    return showDialog<_InviteSettings>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(reset ? 'Reset invite links?' : 'Create invite link'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (reset) ...[
          const Text('All currently active links will stop working.', style: TextStyle(color: Color(0xFFD24B5A), fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
        ],
        DropdownButtonFormField<int>(
          value: hours,
          decoration: const InputDecoration(labelText: 'Link expires after'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1 hour')),
            DropdownMenuItem(value: 24, child: Text('24 hours')),
            DropdownMenuItem(value: 72, child: Text('3 days')),
            DropdownMenuItem(value: 168, child: Text('7 days')),
          ],
          onChanged: (value) => setDialogState(() => hours = value ?? 24),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: maxUses,
          decoration: const InputDecoration(labelText: 'Maximum joins'),
          items: const [10, 25, 50, 100, 500].map((value) => DropdownMenuItem(value: value, child: Text('$value people'))).toList(),
          onChanged: (value) => setDialogState(() => maxUses = value ?? 50),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, _InviteSettings(hours, maxUses)), child: Text(reset ? 'Reset & Create' : 'Create')),
      ],
    )));
  }

  Future<void> _showCreated(CreatedGroupInvite created, {required bool reset}) async {
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(reset ? 'New link is ready' : 'Invite link created'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Link clipboard mein copy ho gaya.'),
        const SizedBox(height: 12),
        SelectableText(created.link, style: const TextStyle(color: authPurple, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text('Expires ${_formatDate(created.expiresAt)} · Up to ${created.maxUses} joins', style: const TextStyle(color: authMuted, fontSize: 12)),
      ]),
      actions: [
        TextButton.icon(onPressed: () => _copy(created.link), icon: const Icon(Icons.copy_outlined), label: const Text('Copy')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done')),
      ],
    ));
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite link copied')));
  }

  Future<void> _revoke(GroupInvite invite) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Revoke this link?'),
      content: Text('Is link se naye members ${widget.scopeLabel} join nahi kar payenge.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD24B5A)), child: const Text('Revoke')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => busyInviteId = invite.id);
    try {
      await SocialApi.instance.revokeGroupInvite(widget.groupId, invite.id);
      sessionLinks.remove(invite.id);
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite link revoke nahi hua.')));
    } finally {
      if (mounted) setState(() => busyInviteId = null);
    }
  }

  String _formatDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${two(value.day)}/${two(value.month)}/${value.year}, $hour:${two(value.minute)} $period';
  }
}

class _InviteSettings {
  const _InviteSettings(this.hours, this.maxUses);
  final int hours, maxUses;
}
