import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../contacts/data/social_api.dart';

class EditGroupScreen extends StatefulWidget{
  const EditGroupScreen({super.key,required this.groupId});final String groupId;
  @override State<EditGroupScreen> createState()=>_EditGroupScreenState();
}
class _EditGroupScreenState extends State<EditGroupScreen>{
  final name=TextEditingController(),description=TextEditingController();String privacy='private';bool loading=true,saving=false;String? error;
  @override void initState(){super.initState();_load();}
  @override void dispose(){name.dispose();description.dispose();super.dispose();}
  Future<void> _load()async{try{final group=await SocialApi.instance.group(widget.groupId);name.text=group.name;description.text=group.description;if(mounted)setState((){privacy=group.privacy;loading=false;});}catch(_){if(mounted)setState((){error='Group details load nahi hui.';loading=false;});}}
  Future<void> _save()async{if(name.text.trim().length<2){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Group name minimum 2 characters ka hona chahiye.')));return;}setState(()=>saving=true);try{await SocialApi.instance.updateGroup(widget.groupId,name:name.text.trim(),description:description.text.trim(),privacy:privacy);if(mounted)Navigator.pop(context,true);}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Group update nahi hua.')));}finally{if(mounted)setState(()=>saving=false);}}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:AppColors.background,appBar:AppBar(title:const Text('Edit Group')),body:GroopXBackground(child:loading?const Center(child:CircularProgressIndicator()):error!=null?GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to edit',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:(){setState((){loading=true;error=null;});_load();}):ListView(padding:const EdgeInsets.all(18),children:[Center(child:Container(width:88,height:88,decoration:BoxDecoration(color:const Color(0xFFEEE9FF),borderRadius:BorderRadius.circular(28)),child:const Icon(Icons.groups_rounded,size:48,color:AppColors.purple))),const SizedBox(height:24),TextField(controller:name,maxLength:50,decoration:const InputDecoration(labelText:'Group name',prefixIcon:Icon(Icons.group_outlined))),const SizedBox(height:12),TextField(controller:description,maxLength:200,maxLines:3,decoration:const InputDecoration(labelText:'Description',prefixIcon:Icon(Icons.notes_outlined),alignLabelWithHint:true)),const SizedBox(height:12),DropdownButtonFormField<String>(value:privacy,decoration:const InputDecoration(labelText:'Privacy',prefixIcon:Icon(Icons.lock_outline)),items:const[DropdownMenuItem(value:'private',child:Text('Private group')),DropdownMenuItem(value:'public',child:Text('Public group'))],onChanged:(value)=>setState(()=>privacy=value??'private')),const SizedBox(height:26),FilledButton.icon(onPressed:saving?null:_save,icon:saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.check),label:Text(saving?'Saving…':'Save Changes'))])));
}
