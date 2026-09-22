import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/backup_api.dart';

class DataStorageScreen extends StatefulWidget { const DataStorageScreen({super.key}); @override State<DataStorageScreen> createState()=>_DataStorageScreenState(); }
class _DataStorageScreenState extends State<DataStorageScreen> {
  BackupInfo? backup; BackupFrequency frequency=BackupFrequency.off; bool loading=true,busy=false; String? error;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{try{final values=await Future.wait<dynamic>([BackupApi.instance.latest(),BackupPreferences.instance.frequency]);if(mounted)setState((){backup=values[0] as BackupInfo?;frequency=values[1] as BackupFrequency;});}catch(_){if(mounted)setState(()=>error='Backup status load nahi hua');}finally{if(mounted)setState(()=>loading=false);}}
  Future<void> _create()async{setState(()=>busy=true);try{final value=await BackupApi.instance.create();if(mounted){setState(()=>backup=value);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Chat backup complete')));}}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Backup create nahi hua. Retry karein.')));}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> _restore()async{if(backup==null)return;setState(()=>busy=true);try{await BackupApi.instance.restore(backup!.id);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Backup restore complete')));}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Backup restore nahi hua.')));}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:AppColors.background,appBar:AppBar(title:const Text('Storage & Data')),body:GroopXBackground(child:ListView(padding:const EdgeInsets.all(18),children:[
    const GroopXSectionTitle('Chat backup'),const SizedBox(height:10),
    Card(child:Padding(padding:const EdgeInsets.all(18),child:loading?const Center(child:CircularProgressIndicator()):Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Row(children:[Icon(Icons.cloud_done_outlined,color:AppColors.purple),SizedBox(width:10),Expanded(child:Text('Secure GroopX backup',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16)))]),const SizedBox(height:12),
      Text(backup==null?'Abhi koi backup nahi bana.':'Last backup: ${_date(backup!.createdAt)}\n${backup!.conversations} chats · ${backup!.messages} messages',style:const TextStyle(color:AppColors.muted,height:1.5)),
      const SizedBox(height:8),Text('Automatic backup: ${frequency.name[0].toUpperCase()}${frequency.name.substring(1)}',style:const TextStyle(fontWeight:FontWeight.w600)),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(error!,style:const TextStyle(color:Colors.red))),const SizedBox(height:14),
      SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy?null:_create,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.backup_outlined),label:const Text('Back up now'))),
      if(backup!=null)SizedBox(width:double.infinity,child:TextButton.icon(onPressed:busy?null:_restore,icon:const Icon(Icons.restore),label:const Text('Restore this backup'))),
      SizedBox(width:double.infinity,child:TextButton.icon(onPressed:busy?null:()=>context.push('/backup-setup?next=${Uri.encodeQueryComponent('/profile/storage')}').then((_)=>_load()),icon:const Icon(Icons.schedule),label:const Text('Change backup schedule'))),
    ]))),const SizedBox(height:22),const GroopXSectionTitle('Media storage'),const SizedBox(height:10),Card(child:Column(children:[_item(Icons.photo_outlined,'Photos','Secure object storage'),const Divider(height:1,indent:58),_item(Icons.movie_outlined,'Videos','Original supported format'),const Divider(height:1,indent:58),_item(Icons.description_outlined,'Documents','Up to 200 MB per file')])),const SizedBox(height:18),const Text('Latest 5 chat backups server par securely rakhe jaate hain.',style:TextStyle(color:AppColors.muted,height:1.5))])));
  String _date(DateTime d)=>'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  Widget _item(IconData icon,String title,String subtitle)=>ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:6),leading:Container(width:40,height:40,decoration:BoxDecoration(color:const Color(0xFFEEE9FF),borderRadius:BorderRadius.circular(12)),child:Icon(icon,color:AppColors.purple)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(subtitle));
}
