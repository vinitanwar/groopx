import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/chat_api.dart';

class DisappearingMessagesScreen extends StatefulWidget{
  const DisappearingMessagesScreen({super.key,required this.conversationId});
  final String conversationId;
  @override State<DisappearingMessagesScreen> createState()=>_DisappearingMessagesScreenState();
}

class _DisappearingMessagesScreenState extends State<DisappearingMessagesScreen>{
  int? selected;bool saving=false;String? error;
  static const options=<int,String>{0:'Off',86400:'24 hours',604800:'7 days',7776000:'90 days'};
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{try{final value=await ChatApi.instance.conversation(widget.conversationId);if(mounted)setState((){selected=value.disappearingSeconds;error=null;});}catch(_){if(mounted)setState(()=>error='Timer setting load nahi hui');}}
  Future<void> _set(int value)async{if(saving||value==selected)return;setState(()=>saving=true);try{await ChatApi.instance.updateDisappearing(widget.conversationId,value);if(mounted){setState(()=>selected=value);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value==0?'Disappearing messages off':'New messages ${options[value]} baad disappear honge')));}}catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Timer update nahi hua. Group mein admin permission zaroori hai.')));}finally{if(mounted)setState(()=>saving=false);}}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:AppColors.background,appBar:AppBar(title:const Text('Disappearing messages')),body:GroopXBackground(child:selected==null?(error==null?const Center(child:CircularProgressIndicator(color:AppColors.purple)):GroopXEmptyState(icon:Icons.timer_off_outlined,title:'Unable to load',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load)):ListView(padding:const EdgeInsets.all(18),children:[const Icon(Icons.timer_outlined,size:72,color:AppColors.purple),const SizedBox(height:16),const Text('Choose how long new messages stay in this chat.',textAlign:TextAlign.center,style:TextStyle(fontSize:16,fontWeight:FontWeight.w700)),const SizedBox(height:8),const Text('Existing messages will not be affected. In groups, only admins can change this setting.',textAlign:TextAlign.center,style:TextStyle(color:AppColors.muted,height:1.4)),const SizedBox(height:22),Card(child:Column(children:options.entries.map((entry)=>RadioListTile<int>(value:entry.key,groupValue:selected,onChanged:saving?null:(value)=>_set(value!),title:Text(entry.value),secondary:Icon(entry.key==0?Icons.timer_off_outlined:Icons.timer_outlined,color:selected==entry.key?AppColors.purple:AppColors.muted))).toList())),if(saving)const Padding(padding:EdgeInsets.all(16),child:LinearProgressIndicator(color:AppColors.purple))])));
}
