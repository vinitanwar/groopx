import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';

class CommunityDetailsScreen extends StatefulWidget {
  const CommunityDetailsScreen({super.key, required this.communityId});
  final String communityId;

  @override
  State<CommunityDetailsScreen> createState() => _CommunityDetailsScreenState();
}

class _CommunityDetailsScreenState extends State<CommunityDetailsScreen> {
  CommunityDetails? community;
  final busyGroups = <String>{};
  String? error;
  bool addingGroup = false;
  bool leaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await SocialApi.instance.community(widget.communityId);
      if (mounted) {
        setState(() {
          community = value;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Community load nahi hui. Retry karein.');
    }
  }

  Future<void> _openAndRefresh(String route) async {
    await context.push(route);
    if (mounted) await _load();
  }

  Future<void> _edit() async {
    final changed = await context.push<bool>('/communities/${widget.communityId}/edit');
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final value = community;
    final admin = value?.role == 'admin';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Community'),
        actions: [
          if (admin) IconButton(tooltip: 'Edit community', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: GroopXBackground(
        child: value == null
            ? (error == null
                ? const Center(child: CircularProgressIndicator(color: authPurple))
                : GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Unable to load', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.purple,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _header(value),
                    const SizedBox(height: 14),
                    _actions(admin),
                    const SizedBox(height: 22),
                    GroopXSectionTitle(
                      'Linked Groups',
                      trailing: admin
                          ? TextButton.icon(
                              onPressed: addingGroup ? null : _addGroup,
                              icon: addingGroup
                                  ? const SizedBox.square(dimension: 15, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.add),
                              label: const Text('Add group'),
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    if (value.groups.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(26),
                          child: Column(children: [
                            const Icon(Icons.account_tree_outlined, color: AppColors.muted, size: 34),
                            const SizedBox(height: 9),
                            const Text('No groups linked yet.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                            if (admin) ...[
                              const SizedBox(height: 5),
                              const Text('Apne admin-managed groups ko community mein organize karein.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                            ],
                          ]),
                        ),
                      )
                    else
                      ...value.groups.map(_groupCard),
                    const SizedBox(height: 22),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Membership', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 5),
                          Text(
                            admin
                                ? 'Agar aur members hain, exit se pehle kisi aur member ko admin banana zaroori hai.'
                                : 'Exit karne ke baad community chat aur linked groups ka hub aapki list se hat jayega.',
                            style: const TextStyle(color: AppColors.muted, height: 1.35),
                          ),
                          const SizedBox(height: 13),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: leaving ? null : _leave,
                              icon: leaving
                                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.logout),
                              label: Text(leaving ? 'Exiting…' : 'Exit Community'),
                              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD24B5A)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(CommunityDetails value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CircleAvatar(radius: 34, backgroundColor: authPurple, child: Icon(Icons.hub_outlined, color: Colors.white, size: 36)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: authInk)),
              if (value.description.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(value.description, style: const TextStyle(color: authMuted, height: 1.35)),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 7, children: [
                _InfoChip(icon: Icons.people_outline, label: '${value.memberCount} members'),
                _InfoChip(icon: Icons.groups_outlined, label: '${value.groups.length} groups'),
                _InfoChip(icon: value.role == 'admin' ? Icons.shield_outlined : Icons.person_outline, label: value.role == 'admin' ? 'Admin' : 'Member'),
              ]),
            ]),
          ),
        ]),
      ]),
    ),
  );

  Widget _actions(bool admin) => Row(children: [
    Expanded(
      child: _ActionCard(
        icon: Icons.chat_bubble_outline,
        label: 'Chat',
        onTap: () => context.push('/chat/${widget.communityId}'),
      ),
    ),
    const SizedBox(width: 9),
    Expanded(
      child: _ActionCard(
        icon: Icons.people_outline,
        label: 'Members',
        onTap: () => _openAndRefresh('/communities/${widget.communityId}/members'),
      ),
    ),
    if (admin) ...[
      const SizedBox(width: 9),
      Expanded(
        child: _ActionCard(
          icon: Icons.link,
          label: 'Invite Links',
          onTap: () => _openAndRefresh('/communities/${widget.communityId}/invites'),
        ),
      ),
    ],
  ]);

  Widget _groupCard(CommunityGroup group) {
    final working = busyGroups.contains(group.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        onTap: working ? null : () => _openAndRefresh('/groups/${group.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: const CircleAvatar(backgroundColor: Color(0xFFEEE9FF), child: Icon(Icons.groups, color: authPurple)),
        title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${group.memberCount} members', style: const TextStyle(color: AppColors.muted)),
        trailing: community?.role == 'admin'
            ? IconButton(
                tooltip: 'Unlink group',
                onPressed: working ? null : () => _remove(group),
                icon: working
                    ? const SizedBox.square(dimension: 19, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.link_off_outlined, color: Color(0xFFD24B5A)),
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  Future<void> _addGroup() async {
    setState(() => addingGroup = true);
    try {
      final groups = await SocialApi.instance.manageableGroups();
      final linked = community!.groups.map((item) => item.id).toSet();
      final choices = groups.where((item) => !linked.contains(item.id)).toList();
      if (!mounted) return;
      if (choices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add karne ke liye koi aur admin-managed group available nahi hai.')));
        return;
      }
      final selected = await showModalBottomSheet<CommunityGroup>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              const ListTile(title: Text('Link a group', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Aap community aur selected group dono ke admin hone chahiye.')),
              ...choices.map((group) => ListTile(
                leading: const Icon(Icons.groups_outlined, color: authPurple),
                title: Text(group.name),
                subtitle: Text('${group.memberCount} members'),
                trailing: const Icon(Icons.add_link),
                onTap: () => Navigator.pop(context, group),
              )),
            ],
          ),
        ),
      );
      if (selected == null) return;
      await SocialApi.instance.addCommunityGroup(widget.communityId, selected.id);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selected.name} linked to community.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group community mein link nahi hua. Retry karein.')));
    } finally {
      if (mounted) setState(() => addingGroup = false);
    }
  }

  Future<void> _remove(CommunityGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlink group?'),
        content: Text('${group.name} community hub se hat jayega. Group aur uske messages delete nahi honge.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD24B5A)),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busyGroups.add(group.id));
    try {
      await SocialApi.instance.removeCommunityGroup(widget.communityId, group.id);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${group.name} unlinked.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group unlink nahi hua. Retry karein.')));
    } finally {
      if (mounted) setState(() => busyGroups.remove(group.id));
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exit community?'),
        content: const Text('Community chat aur member access aapki account se remove ho jayega. Linked groups ki membership change nahi hogi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD24B5A)),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => leaving = true);
    try {
      await SocialApi.instance.leaveGroup(widget.communityId);
      if (mounted) context.go('/communities');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Community exit nahi hui. Agar aap only admin hain, pehle kisi aur member ko admin banayein.')));
    } finally {
      if (mounted) setState(() => leaving = false);
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: AppColors.purple),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.purple)),
    ]),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 14),
        child: Column(children: [
          Icon(icon, color: AppColors.purple),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    ),
  );
}
