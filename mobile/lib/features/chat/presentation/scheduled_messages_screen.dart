import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/chat_api.dart';
import '../domain/chat_models.dart';

class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key,required this.conversationId});
  final String conversationId;

  @override
  State<ScheduledMessagesScreen> createState()=>_ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  List<ScheduledChatMessage> items=const[];
  final Set<String> busy=<String>{};
  Timer? refreshTimer;
  bool loading=true;
  String? error;

  @override
  void initState(){super.initState();unawaited(_load());refreshTimer=Timer.periodic(const Duration(seconds:15),(_){if(busy.isEmpty)unawaited(_refreshSilently());});}

  @override
  void dispose(){refreshTimer?.cancel();super.dispose();}

  Future<void> _load()async{
    if(mounted)setState((){loading=true;error=null;});
    try{
      final value=await ChatApi.instance.scheduledMessages(widget.conversationId);
      if(mounted)setState(()=>items=value);
    }catch(failure){
      if(mounted)setState(()=>error=_errorText(failure,'Scheduled messages load nahi hue.'));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  Future<void> _refreshSilently()async{
    try{final value=await ChatApi.instance.scheduledMessages(widget.conversationId);if(mounted)setState((){items=value;error=null;});}catch(_){}
  }

  Future<void> _edit(ScheduledChatMessage item)async{
    final controller=TextEditingController(text:item.text);
    final text=await showDialog<String>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Edit scheduled message'),
      content:TextField(controller:controller,autofocus:true,maxLines:5,maxLength:10000,decoration:const InputDecoration(hintText:'Message')),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,controller.text.trim()),child:const Text('Save'))],
    ));
    controller.dispose();
    if(text==null||text.isEmpty||text==item.text)return;
    await _update(item,()=>ChatApi.instance.updateScheduledMessage(item.id,text:text));
  }

  Future<void> _reschedule(ScheduledChatMessage item)async{
    final now=DateTime.now();
    final initial=item.scheduledAt.isAfter(now)?item.scheduledAt:now.add(const Duration(hours:1));
    final date=await showDatePicker(context:context,initialDate:initial,firstDate:DateTime(now.year,now.month,now.day),lastDate:now.add(const Duration(days:365)));
    if(date==null||!mounted)return;
    final selectedTime=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(initial));
    if(selectedTime==null)return;
    final scheduledAt=DateTime(date.year,date.month,date.day,selectedTime.hour,selectedTime.minute);
    if(!scheduledAt.isAfter(DateTime.now().add(const Duration(seconds:30)))){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Future date and time select karein.')));
      return;
    }
    await _update(item,()=>ChatApi.instance.updateScheduledMessage(item.id,scheduledAt:scheduledAt));
  }

  Future<void> _update(ScheduledChatMessage item,Future<ScheduledChatMessage> Function() operation)async{
    setState(()=>busy.add(item.id));
    try{
      final updated=await operation();
      if(mounted)setState((){final index=items.indexWhere((value)=>value.id==item.id);if(index>=0){final next=[...items];next[index]=updated;next.sort((first,second)=>first.scheduledAt.compareTo(second.scheduledAt));items=next;}});
    }catch(failure){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_errorText(failure,'Scheduled message update nahi hua.'))));
    }finally{
      if(mounted)setState(()=>busy.remove(item.id));
    }
  }

  Future<void> _cancel(ScheduledChatMessage item)async{
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Cancel scheduled message?'),
      content:const Text('Yeh message send nahi hoga.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Keep')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('Cancel message'))],
    ));
    if(confirmed!=true||!mounted)return;
    setState(()=>busy.add(item.id));
    try{
      await ChatApi.instance.cancelScheduledMessage(item.id);
      if(mounted)setState(()=>items=items.where((value)=>value.id!=item.id).toList());
    }catch(failure){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_errorText(failure,'Scheduled message cancel nahi hua.'))));
    }finally{
      if(mounted)setState(()=>busy.remove(item.id));
    }
  }

  Future<void> _action(String action,ScheduledChatMessage item)async{
    if(action=='edit')await _edit(item);
    if(action=='reschedule')await _reschedule(item);
    if(action=='cancel')await _cancel(item);
  }

  String _errorText(Object failure,String fallback){
    if(failure is DioException){final data=failure.response?.data;if(data is Map&&data['error']!=null)return data['error'].toString();}
    return fallback;
  }

  String _dateTime(DateTime value){
    final now=DateTime.now(),tomorrow=DateTime.now().add(const Duration(days:1));
    final sameDay=value.year==now.year&&value.month==now.month&&value.day==now.day;
    final nextDay=value.year==tomorrow.year&&value.month==tomorrow.month&&value.day==tomorrow.day;
    final day=sameDay?'Today':nextDay?'Tomorrow':'${value.day.toString().padLeft(2,'0')}/${value.month.toString().padLeft(2,'0')}/${value.year}';
    final hour=value.hour==0?12:value.hour>12?value.hour-12:value.hour;
    return '$day at $hour:${value.minute.toString().padLeft(2,'0')} ${value.hour>=12?'PM':'AM'}';
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:AppColors.background,
    appBar:AppBar(title:const Text('Scheduled messages')),
    body:GroopXBackground(child:loading
      ?const Center(child:CircularProgressIndicator(color:AppColors.purple))
      :error!=null
        ?GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to load',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load)
        :items.isEmpty
          ?const GroopXEmptyState(icon:Icons.schedule_send_outlined,title:'No scheduled messages',message:'Message type karke schedule icon se baad mein automatically send karein.')
          :RefreshIndicator(onRefresh:_load,child:ListView.separated(
            physics:const AlwaysScrollableScrollPhysics(),
            padding:const EdgeInsets.all(16),
            itemCount:items.length,
            separatorBuilder:(_,__)=>const SizedBox(height:10),
            itemBuilder:(_,index){
              final item=items[index],working=busy.contains(item.id);
              return Card(child:Padding(padding:const EdgeInsets.fromLTRB(14,13,8,10),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                const CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.schedule_send_outlined,color:AppColors.purple)),
                const SizedBox(width:12),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  if(item.reply!=null)Container(width:double.infinity,margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(8),decoration:const BoxDecoration(color:Color(0xFFF3F0FA),border:Border(left:BorderSide(color:AppColors.purple,width:3))),child:Text('Reply to ${item.reply!.mine?'yourself':(item.reply!.senderName.isEmpty?'message':item.reply!.senderName)}: ${item.reply!.text}',maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:AppColors.muted))),
                  Text(item.text,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w600,color:AppColors.text),maxLines:5,overflow:TextOverflow.ellipsis),
                  const SizedBox(height:8),
                  Row(children:[const Icon(Icons.schedule,size:15,color:AppColors.purple),const SizedBox(width:5),Expanded(child:Text('Send ${_dateTime(item.scheduledAt)}',style:const TextStyle(fontSize:12,color:AppColors.purple,fontWeight:FontWeight.w700)))]),
                ])),
                working?const Padding(padding:EdgeInsets.all(12),child:SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2))):PopupMenuButton<String>(tooltip:'Scheduled message options',onSelected:(action)=>_action(action,item),itemBuilder:(_)=>const[
                  PopupMenuItem(value:'edit',child:ListTile(leading:Icon(Icons.edit_outlined),title:Text('Edit message'))),
                  PopupMenuItem(value:'reschedule',child:ListTile(leading:Icon(Icons.event_repeat_outlined),title:Text('Reschedule'))),
                  PopupMenuItem(value:'cancel',child:ListTile(leading:Icon(Icons.cancel_schedule_send_outlined,color:Colors.red),title:Text('Cancel',style:TextStyle(color:Colors.red)))),
                ]),
              ])));
            },
          )),
    ),
  );
}
