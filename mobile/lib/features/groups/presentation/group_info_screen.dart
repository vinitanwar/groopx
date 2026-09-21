import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

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
    final amAdmin = value?.members.any((member) => member.mine && member.role == 'admin') ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Group Info', style: TextStyle(fontWeight: FontWeight.w700)),actions:[if(amAdmin)IconButton(tooltip:'Edit group',onPressed:()async{final changed=await context.push<bool>('/groups/${widget.groupId}/edit');if(changed==true)_load();},icon:const Icon(Icons.edit_outlined))]),
      body: GroopXBackground(child:value == null
          ? (error == null ? const Center(child:CircularProgressIndicator(color: authPurple)) : GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to load',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load))
          : RefreshIndicator(onRefresh:_load,child:ListView(padding: const EdgeInsets.all(16), children: [
              Card(child:Padding(padding:const EdgeInsets.all(18),child:
              Row(children: [
                const CircleAvatar(radius: 28, backgroundColor: authPurple, child: Icon(Icons.groups, color: Colors.white, size: 31)),
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
              const SizedBox(height:12),
              Card(child:ListTile(leading:const Icon(Icons.perm_media_outlined,color:authPurple),title:const Text('Media, links & documents',style:TextStyle(fontWeight:FontWeight.w600)),trailing:const Icon(Icons.chevron_right),onTap:()=>context.push('/chat/${widget.groupId}/media'))),
              if (amAdmin) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _createInvite, icon: const Icon(Icons.link, color: authPurple), label: const Text('Create Invite Link')),
              ],
              const Divider(height: 32),
              Row(children: [
                const Text('Members', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (amAdmin) TextButton.icon(onPressed: _addMember, icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Add')),
                Text('${value.members.length}', style: const TextStyle(color: authMuted)),
              ]),
              ...value.members.map((member) => Card(margin:const EdgeInsets.only(bottom:7),child:ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal:12,vertical:4),
                leading: GroopXAvatar(label:member.name),
                title: Text(member.mine ? '${member.name} (You)' : member.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(member.username.isEmpty ? '' : '@${member.username}'),
                trailing: amAdmin && !member.mine
                    ? PopupMenuButton<String>(onSelected: (action) => _memberAction(member, action), itemBuilder: (_) => [
                        PopupMenuItem(value: 'role', child: ListTile(leading: Icon(member.role == 'admin' ? Icons.person_outline : Icons.admin_panel_settings_outlined), title: Text(member.role == 'admin' ? 'Remove admin' : 'Make group admin'))),
                        const PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.person_remove_outlined, color: Colors.red), title: Text('Remove member', style: TextStyle(color: Colors.red)))),
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
    final selected=await showModalBottomSheet<UserOption>(context:context,isScrollControlled:true,builder:(_)=>const _MemberPickerSheet());
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
    try {
      await SocialApi.instance.removeGroupMember(widget.groupId, member.id);
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member could not be removed')));
    }
  }

  Future<void> _memberAction(GroupMember member, String action) async {
    if (action == 'remove') return _removeMember(member);
    try {
      await SocialApi.instance.updateGroupMemberRole(widget.groupId, member.id, member.role == 'admin' ? 'member' : 'admin');
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(member.role == 'admin' ? 'Admin access removed' : '${member.name} is now an admin')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin role update nahi hua. Group mein kam se kam ek admin zaroori hai.')));
    }
  }

  Future<void> _createInvite() async {
    try {
      final link = await SocialApi.instance.createGroupInvite(widget.groupId);
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Invite link created'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Link clipboard mein copy ho gaya. Yeh 24 hours tak valid hai.'), const SizedBox(height: 12), SelectableText(link, style: const TextStyle(color: authPurple))]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite link create nahi hua')));
    }
  }
}

class _MemberPickerSheet extends StatefulWidget{const _MemberPickerSheet();@override State<_MemberPickerSheet> createState()=>_MemberPickerSheetState();}
class _MemberPickerSheetState extends State<_MemberPickerSheet>{final search=TextEditingController();List<UserOption> results=const[];bool loading=false;String? error;
  @override void dispose(){search.dispose();super.dispose();}
  Future<void> _find()async{final query=search.text.trim();if(query.length<2){setState(()=>error='Minimum 2 characters type karein.');return;}setState((){loading=true;error=null;});try{final users=await SocialApi.instance.searchUsers(query);if(mounted)setState(()=>results=users);}catch(_){if(mounted)setState(()=>error='Users search nahi hue.');}finally{if(mounted)setState(()=>loading=false);}}
  @override Widget build(BuildContext context)=>Padding(padding:EdgeInsets.fromLTRB(18,18,18,MediaQuery.viewInsetsOf(context).bottom+24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Add Group Member',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800,color:AppColors.text)),const SizedBox(height:16),TextField(controller:search,autofocus:true,textInputAction:TextInputAction.search,onSubmitted:(_)=>_find(),decoration:InputDecoration(labelText:'Name, username or phone',prefixIcon:const Icon(Icons.search),suffixIcon:IconButton(onPressed:_find,icon:const Icon(Icons.arrow_forward)))),if(loading)const LinearProgressIndicator(),if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:Colors.red))),if(!loading&&results.isEmpty&&error==null)const Padding(padding:EdgeInsets.symmetric(vertical:22),child:Text('Search karke exact member select karein.',style:TextStyle(color:AppColors.muted))),if(results.isNotEmpty)Flexible(child:ListView.separated(shrinkWrap:true,padding:const EdgeInsets.only(top:12),itemCount:results.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(_,index){final user=results[index];return ListTile(leading:GroopXAvatar(label:user.name),title:Text(user.name,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(user.username.isEmpty?'GroopX user':'@${user.username}'),trailing:const Icon(Icons.add_circle_outline,color:AppColors.purple),onTap:()=>Navigator.pop(context,user));}))]));
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
