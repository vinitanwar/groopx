import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});
  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  List<CommunitySummary> items = const [];
  bool loading = true;
  String? error;

  @override
  void initState(){super.initState();_load();}

  Future<void> _load() async {
    setState(() { loading=true; error=null; });
    try { final value=await SocialApi.instance.communities();if(mounted)setState(()=>items=value); }
    catch(_){if(mounted)setState(()=>error='Communities load nahi hui');}
    finally{if(mounted)setState(()=>loading=false);}
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:AppColors.background,
    appBar:AppBar(leading:IconButton(onPressed:()=>context.go('/chats'),icon:const Icon(Icons.arrow_back)),title:const Text('Groups & Communities'),actions:[IconButton(onPressed:()=>context.push('/groups/new'),tooltip:'Create group',icon:const Icon(Icons.group_add_outlined))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:_create,backgroundColor:authPurple,foregroundColor:Colors.white,icon:const Icon(Icons.add),label:const Text('New Community')),
    body:GroopXBackground(child:loading?const Center(child:CircularProgressIndicator(color:authPurple)):error!=null?GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to load',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load):RefreshIndicator(onRefresh:_load,child:items.isEmpty?ListView(children:[SizedBox(height:MediaQuery.sizeOf(context).height*.12),GroopXEmptyState(icon:Icons.hub_outlined,title:'No communities yet',message:'Related groups ko ek private community mein organize karein.',actionLabel:'Create Community',onAction:_create)]):ListView.separated(padding:const EdgeInsets.fromLTRB(16,16,16,95),itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(_,index){final item=items[index];return Card(child:ListTile(onTap:()=>context.push('/communities/${item.id}'),contentPadding:const EdgeInsets.all(14),leading:const CircleAvatar(radius:25,backgroundColor:authPurple,child:Icon(Icons.hub_outlined,color:Colors.white)),title:Text(item.name,style:const TextStyle(fontWeight:FontWeight.w700,color:AppColors.text)),subtitle:Padding(padding:const EdgeInsets.only(top:5),child:Text(item.description.isEmpty?'${item.groupCount} groups · ${item.memberCount} members':'${item.description}\n${item.groupCount} groups · ${item.memberCount} members',maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:AppColors.muted))),trailing:const Icon(Icons.chevron_right)));}))),
  );

  Future<void> _create() async {
    final id=await context.push<String>('/communities/new');
    if(id==null||!mounted)return;
    await context.push('/communities/$id');
    await _load();
  }
}
