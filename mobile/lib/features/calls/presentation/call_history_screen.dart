import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/call_api.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});
  @override State<CallHistoryScreen> createState()=>_CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen>{
  List<CallHistoryItem> items=const[];bool loading=true;String? error;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{setState((){loading=true;error=null;});try{final value=await CallApi.instance.history();if(mounted)setState(()=>items=value);}catch(_){if(mounted)setState(()=>error='Call history load nahi hui.');}finally{if(mounted)setState(()=>loading=false);}}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:AppColors.background,appBar:AppBar(title:const Text('Calls'),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),body:GroopXBackground(child:loading?const Center(child:CircularProgressIndicator()):error!=null?GroopXEmptyState(icon:Icons.phone_disabled_outlined,title:'Calls unavailable',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load):RefreshIndicator(onRefresh:_load,child:items.isEmpty?ListView(children:const[SizedBox(height:130),GroopXEmptyState(icon:Icons.call_outlined,title:'No calls yet',message:'Audio aur video call history yahan dikhai degi.')]):ListView.separated(padding:const EdgeInsets.all(16),itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,index){final item=items[index];final failed=item.status=='missed'||item.status=='declined';return Card(child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:7),leading:GroopXAvatar(label:item.title,imageUrl:item.avatarUrl),title:Text(item.title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Row(children:[Icon(failed?Icons.call_received:Icons.call_made,size:14,color:failed?Colors.red:Colors.green),const SizedBox(width:5),Expanded(child:Text('${_label(item.status)} · ${_time(item.startedAt)}',overflow:TextOverflow.ellipsis))]),trailing:IconButton(tooltip:item.kind=='video'?'Video call':'Audio call',onPressed:()=>context.push('/call/${item.kind}/${item.conversationId}'),icon:Icon(item.kind=='video'?Icons.videocam_outlined:Icons.call_outlined,color:AppColors.purple)));}))));
  String _label(String value)=>switch(value){'missed'=>'Missed','declined'=>'Declined','answered'=>'Answered','ringing'=>'Ringing',_=>'Ended'};
  String _time(DateTime value)=>'${value.day.toString().padLeft(2,'0')}/${value.month.toString().padLeft(2,'0')}/${value.year} · ${value.hour.toString().padLeft(2,'0')}:${value.minute.toString().padLeft(2,'0')}';
}
