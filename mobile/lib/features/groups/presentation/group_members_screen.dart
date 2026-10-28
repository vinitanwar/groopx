import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../contacts/data/social_api.dart';
import 'group_member_picker.dart';
import 'group_member_name_dialog.dart';

class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({super.key, required this.groupId, this.title = 'Group Members', this.scopeLabel = 'group'});
  final String groupId, title, scopeLabel;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  final search = TextEditingController();
  final busy = <String>{};
  List<GroupMember> members = const [];
  Timer? debounce;
  String role = 'all';
  String? error;
  int total = 0;
  int requestSerial = 0;
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  bool admin = false;
  bool canAddMembers = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _searchChanged(String _) {
    debounce?.cancel();
    requestSerial++;
    debounce = Timer(const Duration(milliseconds: 350), _load);
    setState(() {});
  }

  Future<void> _load({bool reset = true}) async {
    final serial = ++requestSerial;
    if (mounted) {
      setState(() {
        if (reset) {
          loading = true;
          error = null;
        } else {
          loadingMore = true;
        }
      });
    }
    try {
      final page = await SocialApi.instance.groupMembers(
        widget.groupId,
        query: search.text,
        role: role,
        offset: reset ? 0 : members.length,
      );
      if (!mounted || serial != requestSerial) return;
      final next = reset ? page.items : [...members, ...page.items.where((item) => !members.any((member) => member.id == item.id))];
      setState(() {
        members = next;
        total = page.total;
        hasMore = page.hasMore;
        admin = page.admin;
        canAddMembers = page.canAddMembers;
        loading = false;
        loadingMore = false;
        error = null;
      });
    } catch (_) {
      if (!mounted || serial != requestSerial) return;
      if (reset) {
        setState(() {
          loading = false;
          error = '${widget.scopeLabel} members load nahi hue. Retry karein.';
        });
      } else {
        setState(() => loadingMore = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('More members load nahi hue.')));
      }
    }
  }

  void _selectRole(String next) {
    if (next == role) return;
    setState(() => role = next);
    _load();
  }

  Future<void> _addMember() async {
    final selected = await showGroupMemberPicker(context, excludedIds: members.map((member) => member.id).toSet());
    if (selected == null) return;
    try {
      await SocialApi.instance.addGroupMembers(widget.groupId, [selected.id]);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selected.name} added to ${widget.scopeLabel}.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member add nahi hua. Retry karein.')));
    }
  }

  Future<void> _memberAction(GroupMember member, String action) async {
    if (action == 'name') {
      final displayName = await showGroupMemberNameEditor(context, member, scopeLabel: widget.scopeLabel);
      if (displayName == null || !mounted) return;
      setState(() => busy.add(member.id));
      try {
        await SocialApi.instance.updateGroupMemberDisplayName(widget.groupId, member.id, displayName);
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(displayName.isEmpty ? 'Member name reset ho gaya.' : '${member.profileName} ka ${widget.scopeLabel} name update ho gaya.')));
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.scopeLabel} display name update nahi hua. Retry karein.')));
      } finally {
        if (mounted) setState(() => busy.remove(member.id));
      }
      return;
    }
    if (action == 'remove') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove member?'),
          content: Text('${member.name} ko ${widget.scopeLabel} se remove karna hai?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() => busy.add(member.id));
    try {
      if (action == 'remove') {
        await SocialApi.instance.removeGroupMember(widget.groupId, member.id);
      } else {
        await SocialApi.instance.updateGroupMemberRole(widget.groupId, member.id, member.role == 'admin' ? 'member' : 'admin');
      }
      await _load();
      if (mounted) {
        final message = action == 'remove'
            ? '${member.name} removed from ${widget.scopeLabel}.'
            : member.role == 'admin'
                ? 'Admin access removed.'
                : '${member.name} is now an admin.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Member update nahi hua. ${widget.scopeLabel} mein kam se kam ek admin zaroori hai.')));
    } finally {
      if (mounted) setState(() => busy.remove(member.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: Text(total > 0 ? '${widget.title} ($total)' : widget.title),
      actions: [
        if (canAddMembers) IconButton(tooltip: 'Add member', onPressed: _addMember, icon: const Icon(Icons.person_add_alt)),
      ],
    ),
    body: GroopXBackground(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onChanged: _searchChanged,
            onSubmitted: (_) {
              debounce?.cancel();
              _load();
            },
            decoration: InputDecoration(
              hintText: 'Search members',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        debounce?.cancel();
                        search.clear();
                        _load();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _FilterChip(label: 'All', selected: role == 'all', onSelected: () => _selectRole('all')),
            _FilterChip(label: 'Admins', selected: role == 'admin', onSelected: () => _selectRole('admin')),
            _FilterChip(label: 'Members', selected: role == 'member', onSelected: () => _selectRole('member')),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: Row(children: [
            Icon(Icons.privacy_tip_outlined, size: 15, color: AppColors.muted),
            SizedBox(width: 6),
            Expanded(child: Text('Only public profile details are shown. Phone numbers stay private.', style: TextStyle(fontSize: 11, color: AppColors.muted))),
          ]),
        ),
        Expanded(child: _memberList()),
      ]),
    ),
  );

  Widget _memberList() {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppColors.purple));
    if (error != null) {
      return GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Unable to load', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load);
    }
    if (members.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.purple,
        child: ListView(children: [
          const SizedBox(height: 70),
          GroopXEmptyState(
            icon: Icons.group_off_outlined,
            title: 'No members found',
            message: search.text.trim().isEmpty ? 'Is filter mein abhi koi member nahi hai.' : 'Search ya filter change karke dekhein.',
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.purple,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        itemCount: members.length + (hasMore ? 1 : 0),
        itemBuilder: (_, index) {
          if (index == members.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: loadingMore ? null : () => _load(reset: false),
                icon: loadingMore
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more),
                label: Text(loadingMore ? 'Loading…' : 'Load more'),
              ),
            );
          }
          final member = members[index];
          final working = busy.contains(member.id);
          final subtitle = groupMemberSubtitle(member);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
              leading: GroopXAvatar(label: member.name, imageUrl: member.avatarUrl),
              title: Text(member.mine ? '${member.name} (You)' : member.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              trailing: working
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : admin
                      ? PopupMenuButton<String>(
                          onSelected: (action) => _memberAction(member, action),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'name', child: Text('Edit member name')),
                            if (!member.mine) PopupMenuItem(value: 'role', child: Text(member.role == 'admin' ? 'Remove admin' : 'Make ${widget.scopeLabel} admin')),
                            if (!member.mine) const PopupMenuDivider(),
                            if (!member.mine) const PopupMenuItem(value: 'remove', child: Text('Remove member', style: TextStyle(color: Colors.red))),
                          ],
                        )
                      : _RoleBadge(admin: member.role == 'admin'),
            ),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onSelected});
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onSelected()),
  );
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.admin});
  final bool admin;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: admin ? const Color(0xFFEEE9FF) : Colors.white, borderRadius: BorderRadius.circular(12)),
    child: Text(admin ? 'Admin' : 'Member', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: admin ? AppColors.purple : AppColors.muted)),
  );
}
