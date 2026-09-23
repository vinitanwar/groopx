import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../data/status_api.dart';

const _purple=Color(0xFF6335FF),_ink=Color(0xFF080C25),_muted=Color(0xFF687086);

class StatusScreen extends StatefulWidget{const StatusScreen({super.key});@override State<StatusScreen> createState()=>_StatusScreenState();}
class _StatusScreenState extends State<StatusScreen>{List<StatusItem> items=const[];bool loading=true;String? error;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{setState((){loading=true;error=null;});try{final value=await StatusApi.instance.list();if(mounted)setState(()=>items=value);}catch(_){if(mounted)setState(()=>error='Statuses load nahi hue');}finally{if(mounted)setState(()=>loading=false);}}
  Future<void> _create(bool video)async{final caption=await showDialog<String>(context:context,builder:(context){final controller=TextEditingController();return AlertDialog(title:Text(video?'Add video status':'Add photo status'),content:TextField(controller:controller,maxLength:500,decoration:const InputDecoration(hintText:'Caption (optional)')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,controller.text.trim()),child:const Text('Choose media'))]);});if(caption==null)return;try{final done=await StatusApi.instance.pickAndUpload(video:video,caption:caption);if(done)await _load();}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Status upload nahi hua')));}}
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:AppColors.background,
    appBar:AppBar(
      title:const Text('Status'),
      leading:IconButton(onPressed:()=>context.go('/chats'),icon:const Icon(Icons.arrow_back)),
      actions:[PopupMenuButton<bool>(
        tooltip:'Add status',
        icon:const Icon(Icons.add_circle_outline,color:_purple),
        onSelected:_create,
        itemBuilder:(_)=>const[
          PopupMenuItem(value:false,child:ListTile(leading:Icon(Icons.image_outlined),title:Text('Photo status'))),
          PopupMenuItem(value:true,child:ListTile(leading:Icon(Icons.video_library_outlined),title:Text('Video status'))),
        ],
      )],
    ),
    body:GroopXBackground(child:loading
      ?const Center(child:CircularProgressIndicator(color:_purple))
      :error!=null
        ?GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Statuses unavailable',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load)
        :RefreshIndicator(
          onRefresh:_load,
          child:items.isEmpty
            ?ListView(children:[SizedBox(height:MediaQuery.sizeOf(context).height*.16),GroopXEmptyState(icon:Icons.auto_awesome_outlined,title:'No active statuses',message:'Friends ke photo aur video updates yahan dikhai denge.',actionLabel:'Add status',onAction:()=>_create(false))])
            :ListView(padding:const EdgeInsets.fromLTRB(18,18,18,30),children:[
              const GroopXSectionTitle('Recent updates'),
              const SizedBox(height:12),
              ...items.map((item)=>Card(
                margin:const EdgeInsets.only(bottom:9),
                child:_StatusTile(item:item,onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>StatusViewer(items:items,start:items.indexOf(item)))).then((_)=>_load())),
              )),
            ]),
        )),
  );
}

class _StatusTile extends StatelessWidget{const _StatusTile({required this.item,required this.onTap});final StatusItem item;final VoidCallback onTap;@override Widget build(BuildContext context)=>ListTile(contentPadding:const EdgeInsets.symmetric(vertical:4),onTap:onTap,leading:Container(padding:const EdgeInsets.all(3),decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:item.viewed?_muted:_purple,width:2.5)),child:CircleAvatar(radius:25,foregroundImage:item.avatarUrl.isEmpty?null:NetworkImage(item.avatarUrl),child:const Icon(Icons.person))),title:Text(item.mine?'My status':item.userName,style:const TextStyle(fontWeight:FontWeight.w700,color:_ink)),subtitle:Text(_ago(item.createdAt),style:const TextStyle(color:_muted)),trailing:item.mine?Text('${item.viewCount} views',style:const TextStyle(fontSize:12,color:_muted)):Icon(item.viewed?Icons.check_circle_outline:Icons.circle,color:item.viewed?_muted:_purple,size:16));}
String _ago(DateTime time){final duration=DateTime.now().difference(time.toLocal());if(duration.inMinutes<1)return'Just now';if(duration.inHours<1)return'${duration.inMinutes} min ago';return'${duration.inHours} hr ago';}

class StatusViewer extends StatefulWidget{const StatusViewer({super.key,required this.items,required this.start});final List<StatusItem> items;final int start;@override State<StatusViewer> createState()=>_StatusViewerState();}
class _StatusViewerState extends State<StatusViewer>{late final PageController controller;late int index;Timer? timer;
  @override void initState(){super.initState();index=widget.start;controller=PageController(initialPage:index);_activate();}
  void _activate(){timer?.cancel();final item=widget.items[index];if(!item.mine)StatusApi.instance.viewed(item.id);if(item.mediaType=='image')timer=Timer(const Duration(seconds:5),_next);}
  void _next(){if(!mounted)return;if(index>=widget.items.length-1){Navigator.pop(context);return;}controller.nextPage(duration:const Duration(milliseconds:250),curve:Curves.easeOut);}
  Future<void> _showViewers()async{final item=widget.items[index];showModalBottomSheet<void>(context:context,builder:(context)=>FutureBuilder<List<StatusViewerItem>>(future:StatusApi.instance.viewers(item.id),builder:(context,snapshot){if(snapshot.connectionState!=ConnectionState.done)return const SizedBox(height:220,child:Center(child:CircularProgressIndicator()));if(snapshot.hasError)return const SizedBox(height:220,child:Center(child:Text('Viewers load nahi hue')));final viewers=snapshot.data??const[];return SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.55,child:Column(children:[ListTile(title:Text('${viewers.length} views',style:const TextStyle(fontWeight:FontWeight.w800))),Expanded(child:viewers.isEmpty?const Center(child:Text('Abhi kisi ne status nahi dekha.',style:TextStyle(color:_muted))):ListView.builder(itemCount:viewers.length,itemBuilder:(_,i){final viewer=viewers[i];return ListTile(leading:CircleAvatar(foregroundImage:viewer.avatarUrl.isEmpty?null:NetworkImage(viewer.avatarUrl),child:const Icon(Icons.person)),title:Text(viewer.name),subtitle:Text(_ago(viewer.viewedAt)));}))])));}));}
  @override void dispose(){timer?.cancel();controller.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:Colors.black,body:SafeArea(child:Stack(children:[PageView.builder(controller:controller,itemCount:widget.items.length,onPageChanged:(value){setState(()=>index=value);_activate();},itemBuilder:(_,i)=>_StatusMedia(item:widget.items[i],onCompleted:i==index?_next:null)),Positioned(top:8,left:10,right:10,child:Column(children:[Row(children:List.generate(widget.items.length,(i)=>Expanded(child:Container(height:3,margin:const EdgeInsets.symmetric(horizontal:2),decoration:BoxDecoration(color:i<=index?Colors.white:Colors.white38,borderRadius:BorderRadius.circular(4)))))),const SizedBox(height:5),Row(children:[IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.arrow_back,color:Colors.white)),CircleAvatar(radius:18,foregroundImage:widget.items[index].avatarUrl.isEmpty?null:NetworkImage(widget.items[index].avatarUrl)),const SizedBox(width:10),Expanded(child:Text(widget.items[index].mine?'My status':widget.items[index].userName,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700))),if(widget.items[index].mine)IconButton(onPressed:()async{await StatusApi.instance.delete(widget.items[index].id);if(mounted)Navigator.pop(context);},icon:const Icon(Icons.delete_outline,color:Colors.white))])])),if(widget.items[index].mine)Positioned(bottom:20,left:0,right:0,child:Center(child:TextButton.icon(onPressed:_showViewers,icon:const Icon(Icons.visibility_outlined,color:Colors.white),label:Text('${widget.items[index].viewCount} views',style:const TextStyle(color:Colors.white)))))])));
}
class _StatusMedia extends StatefulWidget{const _StatusMedia({required this.item,this.onCompleted});final StatusItem item;final VoidCallback? onCompleted;@override State<_StatusMedia> createState()=>_StatusMediaState();}
class _StatusMediaState extends State<_StatusMedia>{VideoPlayerController? video;bool completed=false;@override void initState(){super.initState();if(widget.item.mediaType=='video'){video=VideoPlayerController.networkUrl(Uri.parse(widget.item.mediaUrl))..initialize().then((_){if(mounted){setState((){});video?..addListener(_listen)..play();}});}}void _listen(){final value=video?.value;if(!completed&&value!=null&&value.isInitialized&&value.position>=value.duration){completed=true;widget.onCompleted?.call();}}@override void dispose(){video?..removeListener(_listen)..dispose();super.dispose();}@override Widget build(BuildContext context)=>Stack(fit:StackFit.expand,children:[if(widget.item.mediaType=='image')InteractiveViewer(child:Image.network(widget.item.mediaUrl,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image,color:Colors.white,size:60)))else if(video?.value.isInitialized==true)Center(child:AspectRatio(aspectRatio:video!.value.aspectRatio,child:VideoPlayer(video!)))else const Center(child:CircularProgressIndicator(color:_purple)),if(widget.item.caption.isNotEmpty)Align(alignment:Alignment.bottomCenter,child:Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(24,30,24,24),decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,Colors.black87])),child:Text(widget.item.caption,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16))))]);}
