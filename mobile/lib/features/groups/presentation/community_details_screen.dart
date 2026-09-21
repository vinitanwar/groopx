import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class CommunityDetailsScreen extends StatefulWidget {
  const CommunityDetailsScreen({super.key,required this.communityId});
  final String communityId;
  @override
  State<CommunityDetailsScreen> createState()=>_CommunityDetailsScreenState();
}

class _CommunityDetailsScreenState extends State<CommunityDetailsScreen>{
  CommunityDetails? community;String? error;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{try{final value=await SocialApi.instance.community(widget.communityId);if(mounted)setState((){community=value;error=null;});}catch(_){if(mounted)setState(()=>error='Community load nahi hui');}}

  @override Widget build(BuildContext context){final value=community;final admin=value?.role=='admin';return Scaffold(backgroundColor:AppColors.background,appBar:AppBar(title:const Text('Community')),body:GroopXBackground(child:value==null?(error==null?const Center(child:CircularProgressIndicator(color:authPurple)):GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to load',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load)):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
    Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(children:[Row(children:[const CircleAvatar(radius:32,backgroundColor:authPurple,child:Icon(Icons.hub_outlined,color:Colors.white,size:34)),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(value.name,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700,color:authInk)),if(value.description.isNotEmpty)Padding(padding:const EdgeInsets.only(top:5),child:Text(value.description,style:const TextStyle(color:authMuted)))]))]),const SizedBox(height:14),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>context.push('/chat/${widget.communityId}'),icon:const Icon(Icons.chat_bubble_outline),label:const Text('Community Chat'))),if(admin)...[const SizedBox(width:10),Expanded(child:OutlinedButton.icon(onPressed:_invite,icon:const Icon(Icons.link),label:const Text('Invite')))]])]))),
    const SizedBox(height:14),Row(children:[const Text('Groups',style:TextStyle(fontSize:17,fontWeight:FontWeight.w700)),const Spacer(),if(admin)TextButton.icon(onPressed:_addGroup,icon:const Icon(Icons.add),label:const Text('Add group'))]),
    if(value.groups.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(28),child:Text('No groups linked yet.',textAlign:TextAlign.center,style:TextStyle(color:authMuted)))) else ...value.groups.map((group)=>Card(child:ListTile(onTap:()=>context.push('/groups/${group.id}'),leading:const CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.groups,color:authPurple)),title:Text(group.name,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text('${group.memberCount} members'),trailing:admin?IconButton(onPressed:()=>_remove(group),icon:const Icon(Icons.remove_circle_outline,color:Colors.red)):const Icon(Icons.chevron_right)))),
  ]))));}

  Future<void> _addGroup()async{try{final groups=await SocialApi.instance.manageableGroups();final linked=community!.groups.map((item)=>item.id).toSet();final choices=groups.where((item)=>!linked.contains(item.id)).toList();if(!mounted)return;if(choices.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Add karne ke liye koi admin-managed group available nahi hai.')));return;}final selected=await showModalBottomSheet<CommunityGroup>(context:context,builder:(context)=>SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(12),children:[const ListTile(title:Text('Select group',style:TextStyle(fontWeight:FontWeight.w700))),...choices.map((group)=>ListTile(leading:const Icon(Icons.groups_outlined,color:authPurple),title:Text(group.name),subtitle:Text('${group.memberCount} members'),onTap:()=>Navigator.pop(context,group)))])));if(selected==null)return;await SocialApi.instance.addCommunityGroup(widget.communityId,selected.id);await _load();}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Group community mein add nahi hua')));}}
  Future<void> _remove(CommunityGroup group)async{try{await SocialApi.instance.removeCommunityGroup(widget.communityId,group.id);await _load();}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Group remove nahi hua')));}}
  Future<void> _invite()async{try{final link=await SocialApi.instance.createGroupInvite(widget.communityId);await Clipboard.setData(ClipboardData(text:link));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Community invite link copied')));}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Invite create nahi hua')));}}
}
