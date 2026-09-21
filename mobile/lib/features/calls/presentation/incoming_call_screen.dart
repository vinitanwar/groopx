import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/call_api.dart';

class IncomingCallScreen extends StatefulWidget{
  const IncomingCallScreen({super.key,required this.callId,required this.video,this.caller='GroopX user'});final String callId,caller;final bool video;
  @override State<IncomingCallScreen> createState()=>_IncomingCallScreenState();
}
class _IncomingCallScreenState extends State<IncomingCallScreen>{bool busy=false;
  Future<void> _decline()async{if(busy)return;setState(()=>busy=true);try{await CallApi.instance.decline(widget.callId);}catch(_){}if(mounted)context.go('/chats');}
  void _accept(){if(busy)return;context.go('/calls/${widget.video?'video':'audio'}/${widget.callId}/join');}
  @override Widget build(BuildContext context)=>PopScope(canPop:false,child:Scaffold(backgroundColor:const Color(0xFF080D28),body:SafeArea(child:Container(width:double.infinity,decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFF25204B),Color(0xFF080D28)])),padding:const EdgeInsets.fromLTRB(24,70,24,46),child:Column(children:[Text(widget.video?'Incoming video call':'Incoming voice call',style:const TextStyle(color:Color(0xFFC9C5DC),fontSize:15)),const SizedBox(height:38),const CircleAvatar(radius:64,backgroundColor:Color(0xFF6D31FF),child:Icon(Icons.person,size:70,color:Colors.white)),const SizedBox(height:22),Text(widget.caller,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:27,fontWeight:FontWeight.w800)),const SizedBox(height:9),const Text('GroopX private call',style:TextStyle(color:Color(0xFFA9A5B9))),const Spacer(),Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[_button(Icons.call_end,'Decline',const Color(0xFFE54555),_decline),_button(widget.video?Icons.videocam:Icons.call,'Accept',const Color(0xFF1EBB68),_accept)])]))));
  Widget _button(IconData icon,String label,Color color,VoidCallback action)=>Column(children:[InkWell(onTap:busy?null:action,borderRadius:BorderRadius.circular(38),child:CircleAvatar(radius:36,backgroundColor:color,child:busy&&label=='Decline'?const CircularProgressIndicator(color:Colors.white):Icon(icon,size:32,color:Colors.white))),const SizedBox(height:10),Text(label,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600))]);
}
