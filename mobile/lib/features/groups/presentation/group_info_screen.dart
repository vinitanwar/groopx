import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import 'group_member_picker.dart';
import 'group_member_name_dialog.dart';

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.groupId});
  final String groupId;
  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  GroupDetails? group;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final value = await SocialApi.instance.group(widget.groupId);
      if (mounted) setState(() { group = value; error = null; });
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load group');
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = group;
    final amAdmin = value?.admin == true || (value?.members.any((member) => member.mine && member.role == 'admin') ?? false);
    final canEditInfo = amAdmin || value?.canEditInfo == true;
    final canAddMembers = amAdmin || value?.canAddMembers == true;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Group Info', style: TextStyle(fontWeight: FontWeight.w700)),actions:[if(canEditInfo)IconButton(tooltip:'Edit group',onPressed:()async{final changed=await context.push<bool>('/groups/${widget.groupId}/edit');if(changed==true)_load();},icon:const Icon(Icons.edit_outlined))]),
      body: GroopXBackground(child:value == null
          ? (error == null ? const Center(child:CircularProgressIndicator(color: authPurple)) : GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to load',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load))
          : RefreshIndicator(onRefresh:_load,child:ListView(padding: const EdgeInsets.all(16), children: [
              Card(child:Padding(padding:const EdgeInsets.all(18),child:
              Row(children: [
                CircleAvatar(radius:28,backgroundColor:authPurple,foregroundImage:value.avatarUrl.isEmpty?null:NetworkImage(value.avatarUrl),child:value.avatarUrl.isEmpty?const Icon(Icons.groups,color:Colors.white,size:31):null),
                const SizedBox(width: 15),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: authInk)),
                  Text('${value.members.length} members · ${value.privacy}', style: const TextStyle(fontSize: 12, color: authMuted)),
                  if (value.description.isNotEmpty) Text(value.description, style: const TextStyle(fontSize: 11, color: authMuted)),
                ])),
              ]))),
              const SizedBox(height: 17),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Action(Icons.call, 'Audio Call', () => context.push('/call/audio/${widget.groupId}')),
                _Action(Icons.videocam, 'Video Call', () => context.push('/call/video/${widget.groupId}')),
                _Action(Icons.chat_bubble_outline, 'Open Chat', () => context.go('/chat/${widget.groupId}')),
              ]),
              if (value.announcementOnly) ...[
                const SizedBox(height: 12),
                const Card(child:ListTile(
                  leading: CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.campaign_outlined,color:authPurple)),
                  title: Text('Announcement mode',style:TextStyle(fontWeight:FontWeight.w700)),
                  subtitle: Text('Only admins can send messages. Members can read, react and vote.'),
                )),
              ],
              if (value.joinApprovalRequired) ...[
                const SizedBox(height: 12),
                const Card(child:ListTile(
                  leading: CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.how_to_reg_outlined,color:authPurple)),
                  title: Text('New members need approval',style:TextStyle(fontWeight:FontWeight.w700)),
                  subtitle: Text('Invite link se aane wale members ko admin approve karega.'),
                )),
              ],
              const SizedBox(height: 12),
              Card(child:ListTile(
                leading: const CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.admin_panel_settings_outlined,color:authPurple)),
                title: const Text('Group permissions',style:TextStyle(fontWeight:FontWeight.w700)),
                subtitle: Text('${value.announcementOnly ? 'Only admins' : 'All members'} can send messages\n${value.membersCanEditInfo ? 'Members' : 'Only admins'} can edit group info\n${value.membersCanAddMembers ? 'Members' : 'Only admins'} can add participants'),
              )),
              if (amAdmin && (value.joinApprovalRequired || value.pendingJoinRequests > 0)) ...[
                const SizedBox(height: 12),
                Card(child:ListTile(
                  leading: const Icon(Icons.pending_actions_outlined,color:authPurple),
                  title: const Text('Join requests',style:TextStyle(fontWeight:FontWeight.w700)),
                  subtitle: Text(value.pendingJoinRequests == 0 ? 'No pending requests' : '${value.pendingJoinRequests} waiting for approval'),
                  trailing: Row(mainAxisSize:MainAxisSize.min,children:[
                    if(value.pendingJoinRequests>0)Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:authPurple,borderRadius:BorderRadius.circular(12)),child:Text('${value.pendingJoinRequests}',style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w700))),
                    const SizedBox(width:4),
                    const Icon(Icons.chevron_right),
                  ]),
                  onTap:()async{await context.push('/groups/${widget.groupId}/join-requests');if(mounted)_load();},
                )),
              ],
              const SizedBox(height:12),
              Card(child:ListTile(leading:const Icon(Icons.perm_media_outlined,color:authPurple),title:const Text('Media, links & documents',style:TextStyle(fontWeight:FontWeight.w600)),trailing:const Icon(Icons.chevron_right),onTap:()=>context.push('/chat/${widget.groupId}/media'))),
              if (amAdmin) ...[
                const SizedBox(height: 12),
                Card(child:ListTile(
                  leading: const Icon(Icons.link,color:authPurple),
                  title: const Text('Invite links',style:TextStyle(fontWeight:FontWeight.w700)),
                  subtitle: const Text('Create, view usage, reset or revoke'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:()=>context.push('/groups/${widget.groupId}/invites'),
                )),
              ],
              const Divider(height: 32),
              Row(children: [
                Text('Members (${value.members.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(onPressed:()async{await context.push('/groups/${widget.groupId}/members');if(mounted)_load();},child:const Text('View all')),
                if (canAddMembers) IconButton(tooltip:'Add member',onPressed: _addMember, icon: const Icon(Icons.person_add_alt, size: 20)),
              ]),
              ...value.members.map((member) => Card(margin:const EdgeInsets.only(bottom:7),child:ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal:12,vertical:4),
                leading: GroopXAvatar(label:member.name,imageUrl:member.avatarUrl),
                title: Text(member.mine ? '${member.name} (You)' : member.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(groupMemberSubtitle(member)),
                trailing: amAdmin
                    ? PopupMenuButton<String>(onSelected: (action) => _memberAction(member, action), itemBuilder: (_) => [
                        const PopupMenuItem(value: 'name', child: ListTile(leading: Icon(Icons.badge_outlined), title: Text('Edit member name'))),
                        if (!member.mine) PopupMenuItem(value: 'role', child: ListTile(leading: Icon(member.role == 'admin' ? Icons.person_outline : Icons.admin_panel_settings_outlined), title: Text(member.role == 'admin' ? 'Remove admin' : 'Make group admin'))),
                        if (!member.mine) const PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.person_remove_outlined, color: Colors.red), title: Text('Remove member', style: TextStyle(color: Colors.red)))),
                      ])
                    : Text(member.role == 'admin' ? 'Admin' : 'Member', style: TextStyle(fontSize: 11, color: member.role == 'admin' ? authPurple : authMuted)),
              ))),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _leave,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Exit Group', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, side: const BorderSide(color: Color(0xFFF0E4E8))),
              ),
            ]))),
    );
  }

  Future<void> _leave() async {
    try {
      await SocialApi.instance.leaveGroup(widget.groupId);
      if (mounted) context.go('/chats');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not exit the group')));
    }
  }

  Future<void> _addMember() async {
    final selected=await showGroupMemberPicker(context,excludedIds:group?.members.map((member)=>member.id).toSet()??const <String>{});
    if(selected==null)return;
    try {
      await SocialApi.instance.addGroupMembers(widget.groupId, [selected.id]);
      await _load();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${selected.name} added to group')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matching user found')));
    }
  }

  Future<void> _removeMember(GroupMember member) async {
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(title:const Text('Remove member?'),content:Text('${member.name} ko group se remove karna hai?'),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Remove',style:TextStyle(color:Colors.red)))]));
    if(confirmed!=true||!mounted)return;
    try {
      await SocialApi.instance.removeGroupMember(widget.groupId, member.id);
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member could not be removed')));
    }
  }

  Future<void> _memberAction(GroupMember member, String action) async {
    if (action == 'name') {
      final displayName = await showGroupMemberNameEditor(context, member);
      if (displayName == null || !mounted) return;
      try {
        await SocialApi.instance.updateGroupMemberDisplayName(widget.groupId, member.id, displayName);
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(displayName.isEmpty ? 'Member name reset ho gaya.' : '${member.profileName} ka group name update ho gaya.')));
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group display name update nahi hua. Retry karein.')));
      }
      return;
    }
    if (action == 'remove') return _removeMember(member);
    try {
      await SocialApi.instance.updateGroupMemberRole(widget.groupId, member.id, member.role == 'admin' ? 'member' : 'admin');
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(member.role == 'admin' ? 'Admin access removed' : '${member.name} is now an admin')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin role update nahi hua. Group mein kam se kam ek admin zaroori hai.')));
    }
  }

}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(width: 82, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10)]), child: Column(children: [Icon(icon, color: authPurple), const SizedBox(height: 5), Text(label, style: const TextStyle(fontSize: 9))])),
  );
}
