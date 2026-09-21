import 'dart:async';
import 'package:flutter/material.dart';
import '../data/chat_api.dart';
import '../domain/chat_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final query = TextEditingController();
  Timer? debounce;
  List<ChatMessage> results = const [];
  bool searching = false;
  String? error;

  @override
  void dispose() { debounce?.cancel(); query.dispose(); super.dispose(); }

  void _changed(String value) {
    debounce?.cancel();
    if (value.trim().length < 2) { setState(() { results = const []; searching = false; }); return; }
    setState(() { searching = true; error = null; });
    debounce = Timer(const Duration(milliseconds: 350), () async {
      try { final items = await ChatApi.instance.searchMessages(widget.conversationId, value); if (mounted && query.text == value) setState(() { results = items; searching = false; }); }
      catch (_) { if (mounted) setState(() { searching=false; error='Search complete nahi hui'; }); }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor:AppColors.background,appBar: AppBar(title: const Text('Search Messages')),body:GroopXBackground(child:Column(children:[Padding(padding:const EdgeInsets.all(16),child:TextField(controller:query,autofocus:true,onChanged:_changed,style:const TextStyle(color:AppColors.text),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search in this conversation'))),if(searching)const LinearProgressIndicator(),Expanded(child:error!=null?GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Search unavailable',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:()=>_changed(query.text)):query.text.trim().length<2?const GroopXEmptyState(icon:Icons.manage_search,title:'Search messages',message:'Kam se kam 2 characters type karein.'):results.isEmpty?const GroopXEmptyState(icon:Icons.search_off,title:'No messages found',message:'Kisi dusre word ya phrase se search karein.'):ListView.separated(padding:const EdgeInsets.fromLTRB(16,0,16,24),itemCount:results.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,index){final message=results[index];return Card(child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:7),leading:CircleAvatar(backgroundColor:const Color(0xFFEEE9FF),child:Icon(message.mine?Icons.north_east:Icons.south_west,size:18,color:AppColors.purple)),title:Text(message.text,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:AppColors.text,fontWeight:FontWeight.w600)),subtitle:Padding(padding:const EdgeInsets.only(top:5),child:Text('${message.mine?'You':'Contact'} · ${message.time}',style:const TextStyle(color:AppColors.muted)))));}))])));
}
