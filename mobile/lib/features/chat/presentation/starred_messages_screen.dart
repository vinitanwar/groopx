import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/chat_api.dart';
import '../domain/chat_models.dart';

class StarredMessagesScreen extends StatefulWidget{
  const StarredMessagesScreen({super.key,required this.conversationId});
  final String conversationId;
  @override State<StarredMessagesScreen> createState()=>_StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen>{
  List<ChatMessage> items=const[];bool loading=true;String? error;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{setState((){loading=true;error=null;});try{final value=await ChatApi.instance.starredMessages(widget.conversationId);if(mounted)setState(()=>items=value);}catch(_){if(mounted)setState(()=>error='Starred messages load nahi hue');}finally{if(mounted)setState(()=>loading=false);}}
  Future<void> _remove(ChatMessage item)async{try{await ChatApi.instance.setStarred(item.id,false);if(mounted)setState(()=>items=items.where((value)=>value.id!=item.id).toList());}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Message unstar nahi hua')));}}
  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:AppColors.background,
    appBar:AppBar(title:const Text('Starred messages')),
    body:GroopXBackground(
      child:loading
        ?const Center(child:CircularProgressIndicator(color:AppColors.purple))
        :error!=null
          ?GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to load',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load)
          :items.isEmpty
            ?const GroopXEmptyState(icon:Icons.star_border,title:'No starred messages',message:'Important message ko long-press karke star karein.')
            :RefreshIndicator(
              onRefresh:_load,
              child:ListView.separated(
                padding:const EdgeInsets.all(16),
                itemCount:items.length,
                separatorBuilder:(_,__)=>const SizedBox(height:8),
                itemBuilder:(_,index){
                  final item=items[index];
                  final label=item.viewOnce?item.text:item.kind=='text'?item.text:(item.attachment?['file_name']?.toString()??item.text);
                  final url=item.attachment?['url']?.toString()??'';
                  return Card(child:ListTile(
                    onTap:url.isNotEmpty?()=>context.push('/attachment',extra:<String,String>{'kind':item.kind,'name':label,'url':url}):null,
                    leading:const CircleAvatar(backgroundColor:Color(0xFFFFF3D5),child:Icon(Icons.star,color:Color(0xFFFFB300))),
                    title:Text(label,maxLines:3,overflow:TextOverflow.ellipsis),
                    subtitle:Text('${item.mine?'You':(item.senderName.isEmpty?'Contact':item.senderName)} · ${item.time}'),
                    trailing:IconButton(tooltip:'Unstar',onPressed:()=>_remove(item),icon:const Icon(Icons.star_outline)),
                  ));
                },
              ),
            ),
    ),
  );
}
