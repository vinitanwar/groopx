import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/notification_api.dart';

class NotificationDetailScreen extends StatelessWidget{
  const NotificationDetailScreen({super.key,required this.item});final NotificationItem item;
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:AppColors.background,appBar:AppBar(title:const Text('Notification')),body:GroopXBackground(child:ListView(padding:const EdgeInsets.all(18),children:[Card(child:Padding(padding:const EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(width:52,height:52,decoration:BoxDecoration(color:const Color(0xFFEEE9FF),borderRadius:BorderRadius.circular(16)),child:Icon(item.type=='announcement'?Icons.campaign_outlined:Icons.notifications_outlined,color:AppColors.purple)),const SizedBox(height:18),Text(item.title,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w800)),const SizedBox(height:10),Text(item.body,style:const TextStyle(fontSize:15,height:1.55,color:AppColors.muted)),const SizedBox(height:20),Text(_time(item.createdAt),style:const TextStyle(fontSize:12,color:AppColors.muted))])))])));
  String _time(DateTime value)=>'${value.day.toString().padLeft(2,'0')}/${value.month.toString().padLeft(2,'0')}/${value.year} · ${value.hour.toString().padLeft(2,'0')}:${value.minute.toString().padLeft(2,'0')}';
}
