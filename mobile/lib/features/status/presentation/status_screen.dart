import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../chat/data/chat_api.dart';
import '../../chat/domain/chat_models.dart';
import '../../contacts/data/social_api.dart';
import '../data/status_api.dart';

const _purple=Color(0xFF6335FF),_ink=Color(0xFF080C25),_muted=Color(0xFF687086);
const _textStatusPalette=<String>['#6335FF','#E91E63','#0F8B8D','#1565C0','#F57C00','#263238','#7B1FA2','#2E7D32'];
const _statusReactionChoices=<String>['😂','😮','😢','🙏','👏'];

Color _statusColor(String value){
  final normalized=value.replaceFirst('#','');
  final rgb=int.tryParse(normalized,radix:16);
  return rgb==null||normalized.length!=6?_purple:Color(0xFF000000|rgb);
}

class _StatusGroup{
  const _StatusGroup(this.items);
  final List<StatusItem> items;
  StatusItem get latest=>items.last;
  String get userId=>latest.userId;
  String get userName=>latest.userName;
  String get avatarUrl=>latest.avatarUrl;
  bool get mine=>latest.mine;
  bool get muted=>latest.muted;
  int get unseenCount=>mine?0:items.where((item)=>!item.viewed).length;
  int get startIndex{
    if(mine)return 0;
    final firstUnseen=items.indexWhere((item)=>!item.viewed);
    return firstUnseen<0?0:firstUnseen;
  }
}

class StatusScreen extends StatefulWidget{const StatusScreen({super.key});@override State<StatusScreen> createState()=>_StatusScreenState();}
class _StatusScreenState extends State<StatusScreen>{List<StatusItem> items=const[];bool loading=true,uploading=false;double uploadProgress=0;String? error;
  List<_StatusGroup> get recentGroups=>_groupStatuses(items.where((item)=>item.mine||!item.muted),unseenFirst:true);
  List<_StatusGroup> get mutedGroups=>_groupStatuses(items.where((item)=>!item.mine&&item.muted));
  List<_StatusGroup> _groupStatuses(Iterable<StatusItem> source,{bool unseenFirst=false}){
    final grouped=<String,List<StatusItem>>{};
    for(final item in source){(grouped[item.userId]??=<StatusItem>[]).add(item);}
    final result=grouped.values.map((groupItems){
      groupItems.sort((first,second)=>first.createdAt.compareTo(second.createdAt));
      return _StatusGroup(List<StatusItem>.unmodifiable(groupItems));
    }).toList();
    result.sort((first,second){
      if(first.mine!=second.mine)return first.mine?-1:1;
      if(unseenFirst&&first.unseenCount!=second.unseenCount){
        if(first.unseenCount==0)return 1;
        if(second.unseenCount==0)return -1;
      }
      return second.latest.createdAt.compareTo(first.latest.createdAt);
    });
    return result;
  }
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{setState((){loading=true;error=null;});try{final value=await StatusApi.instance.list();if(mounted)setState(()=>items=value);}catch(_){if(mounted)setState(()=>error='Statuses load nahi hue');}finally{if(mounted)setState(()=>loading=false);}}
  Future<void> _createMedia(bool video,StatusMediaSource source)async{
    if(uploading)return;
    try{
      setState((){uploading=true;uploadProgress=0;});
      final draft=await StatusApi.instance.pickMedia(video:video,source:source);
      if(draft==null||!mounted)return;
      final caption=await Navigator.push<String>(context,MaterialPageRoute(fullscreenDialog:true,builder:(_)=>_StatusMediaComposer(draft:draft)));
      if(caption==null||!mounted)return;
      await StatusApi.instance.uploadMedia(draft,caption:caption,onProgress:(value){if(mounted)setState(()=>uploadProgress=value);});
      await _load();
    }catch(failure){
      if(mounted){
        String message='Status upload nahi hua';
        if(failure is StateError)message=failure.message.toString();
        if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
      }
    }finally{if(mounted)setState(()=>uploading=false);}
  }
  Future<void> _createText()async{
    if(uploading)return;
    final draft=await showModalBottomSheet<_TextStatusDraft>(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(_)=>const _TextStatusComposer());
    if(draft==null)return;
    try{
      setState((){uploading=true;uploadProgress=0;});
      await StatusApi.instance.createText(text:draft.text,backgroundColor:draft.backgroundColor);
      await _load();
    }catch(failure){
      if(mounted){
        var message='Text status post nahi hua. Retry karein.';
        if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
      }
    }finally{if(mounted)setState(()=>uploading=false);}
  }
  Future<void> _toggleMute(StatusItem item)async{final next=!item.muted;setState(()=>items=items.map((value)=>value.userId==item.userId?value.copyWith(muted:next):value).toList());try{if(next){await StatusApi.instance.mute(item.userId);}else{await StatusApi.instance.unmute(item.userId);}if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(next?'${item.userName} ke status updates muted.':'${item.userName} ke status updates unmuted.')));}catch(_){if(mounted){setState(()=>items=items.map((value)=>value.userId==item.userId?value.copyWith(muted:!next):value).toList());ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Status preference save nahi hui. Retry karein.')));}}}
  Future<void> _openViewer(_StatusGroup group)async{
    final sequence=group.mine
      ?<_StatusGroup>[group]
      :(group.muted?mutedGroups:recentGroups.where((candidate)=>!candidate.mine).toList());
    if(sequence.isEmpty)return;
    final selected=sequence.indexWhere((candidate)=>candidate.userId==group.userId);
    final selectedIndex=selected<0?0:selected;
    final start=sequence.take(selectedIndex).fold<int>(0,(total,candidate)=>total+candidate.items.length)+sequence[selectedIndex].startIndex;
    final viewerItems=sequence.expand((candidate)=>candidate.items).toList(growable:false);
    final message=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>StatusViewer(items:viewerItems,start:start)));
    await _load();
    if(message!=null&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  }
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:AppColors.background,
    appBar:AppBar(
      title:const Text('Status'),
      leading:IconButton(onPressed:()=>context.go('/chats'),icon:const Icon(Icons.arrow_back)),
      actions:[IconButton(onPressed:uploading?null:()=>context.push('/statuses/privacy'),tooltip:'Status privacy',icon:const Icon(Icons.privacy_tip_outlined,color:_purple)),IconButton(onPressed:uploading?null:()=>_createMedia(false,StatusMediaSource.camera),tooltip:'Camera status',icon:const Icon(Icons.camera_alt_outlined,color:_purple)),PopupMenuButton<String>(
        enabled:!uploading,
        tooltip:'Add status',
        icon:const Icon(Icons.add_circle_outline,color:_purple),
        onSelected:(value){
          if(value=='text'){_createText();return;}
          _createMedia(value.endsWith('video'),value.startsWith('camera')?StatusMediaSource.camera:StatusMediaSource.gallery);
        },
        itemBuilder:(_)=>const[
          PopupMenuItem(value:'text',child:ListTile(leading:Icon(Icons.text_fields),title:Text('Text status'))),
          PopupMenuDivider(),
          PopupMenuItem(value:'camera_photo',child:ListTile(leading:Icon(Icons.photo_camera_outlined),title:Text('Take photo'))),
          PopupMenuItem(value:'camera_video',child:ListTile(leading:Icon(Icons.videocam_outlined),title:Text('Record video'))),
          PopupMenuItem(value:'gallery_photo',child:ListTile(leading:Icon(Icons.image_outlined),title:Text('Gallery photo'))),
          PopupMenuItem(value:'gallery_video',child:ListTile(leading:Icon(Icons.video_library_outlined),title:Text('Gallery video'))),
        ],
      )],
    ),
    bottomNavigationBar:uploading?SafeArea(child:LinearProgressIndicator(value:uploadProgress>0?uploadProgress:null,color:_purple,minHeight:5)):null,
    body:GroopXBackground(child:loading
      ?const Center(child:CircularProgressIndicator(color:_purple))
      :error!=null
        ?GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Statuses unavailable',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load)
        :RefreshIndicator(
          onRefresh:_load,
          child:items.isEmpty
            ?ListView(children:[SizedBox(height:MediaQuery.sizeOf(context).height*.16),GroopXEmptyState(icon:Icons.auto_awesome_outlined,title:'No active statuses',message:'Friends ke text, photo aur video updates yahan dikhai denge.',actionLabel:'Write status',onAction:_createText)])
            :ListView(padding:const EdgeInsets.fromLTRB(18,18,18,30),children:[
              const GroopXSectionTitle('Recent updates'),
              const SizedBox(height:12),
              if(recentGroups.isEmpty)const Card(child:ListTile(leading:Icon(Icons.notifications_off_outlined,color:_muted),title:Text('No recent updates'),subtitle:Text('Muted updates are available below.'))),
              ...recentGroups.map((group)=>Card(
                margin:const EdgeInsets.only(bottom:9),
                child:_StatusGroupTile(group:group,onTap:()=>_openViewer(group),onMuteToggle:()=>_toggleMute(group.latest)),
              )),
              if(mutedGroups.isNotEmpty)...[
                const SizedBox(height:12),
                Card(child:ExpansionTile(leading:const Icon(Icons.volume_off_outlined,color:_muted),title:Text('Muted updates (${mutedGroups.length})',style:const TextStyle(fontWeight:FontWeight.w700,color:_ink)),children:[for(var index=0;index<mutedGroups.length;index++)...[_StatusGroupTile(group:mutedGroups[index],onTap:()=>_openViewer(mutedGroups[index]),onMuteToggle:()=>_toggleMute(mutedGroups[index].latest)),if(index<mutedGroups.length-1)const Divider(height:1,indent:72)]])),
              ],
            ]),
        )),
  );
}

class _StatusMediaComposer extends StatefulWidget{
  const _StatusMediaComposer({required this.draft});
  final StatusMediaDraft draft;
  @override State<_StatusMediaComposer> createState()=>_StatusMediaComposerState();
}

class _StatusMediaComposerState extends State<_StatusMediaComposer>{
  final caption=TextEditingController();
  VideoPlayerController? video;
  bool videoFailed=false;

  @override
  void initState(){
    super.initState();
    if(widget.draft.video)unawaited(_prepareVideo());
  }

  Future<void> _prepareVideo()async{
    try{
      final controller=VideoPlayerController.file(File(widget.draft.path));
      video=controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if(mounted)setState((){});
    }catch(_){if(mounted)setState(()=>videoFailed=true);}
  }

  void _toggleVideo(){
    final controller=video;
    if(controller==null||!controller.value.isInitialized)return;
    if(controller.value.isPlaying){unawaited(controller.pause());}else{unawaited(controller.play());}
  }

  Widget _preview(){
    if(!widget.draft.video){
      return InteractiveViewer(minScale:.8,maxScale:5,child:Image.file(File(widget.draft.path),fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Center(child:Icon(Icons.broken_image_outlined,color:Colors.white,size:68))));
    }
    if(videoFailed)return const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.videocam_off_outlined,color:Colors.white70,size:68),SizedBox(height:14),Text('Video preview load nahi hua',style:TextStyle(color:Colors.white))]));
    final controller=video;
    if(controller==null||!controller.value.isInitialized)return const Center(child:CircularProgressIndicator(color:_purple));
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable:controller,
      builder:(_,value,__)=>GestureDetector(
        behavior:HitTestBehavior.opaque,
        onTap:_toggleVideo,
        child:Center(child:Stack(alignment:Alignment.center,children:[
          AspectRatio(aspectRatio:value.aspectRatio,child:VideoPlayer(controller)),
          if(!value.isPlaying)const Icon(Icons.play_circle_fill_rounded,color:Colors.white70,size:72),
        ])),
      ),
    );
  }

  @override
  void dispose(){caption.dispose();video?.dispose();super.dispose();}

  @override
  Widget build(BuildContext context){
    final ready=!widget.draft.video||(video?.value.isInitialized==true&&!videoFailed);
    return Scaffold(
      resizeToAvoidBottomInset:false,
      backgroundColor:Colors.black,
      body:SafeArea(child:Stack(children:[
        Positioned.fill(child:_preview()),
        Positioned(top:6,left:6,right:12,child:Row(children:[
          IconButton.filledTonal(onPressed:()=>Navigator.pop(context),style:IconButton.styleFrom(backgroundColor:Colors.black45),icon:const Icon(Icons.close,color:Colors.white)),
          const SizedBox(width:8),
          Expanded(child:Text(widget.draft.video?'Video status':'Photo status',style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w800))),
          Text(widget.draft.video?'Max 30 sec':'Preview',style:const TextStyle(color:Colors.white70,fontSize:12)),
        ])),
        Align(alignment:Alignment.bottomCenter,child:AnimatedPadding(
          duration:const Duration(milliseconds:180),
          padding:EdgeInsets.only(bottom:MediaQuery.of(context).viewInsets.bottom),
          child:Container(
            width:double.infinity,
            padding:const EdgeInsets.fromLTRB(16,40,12,14),
            decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,Color(0xE6000000)])),
            child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
              Expanded(child:TextField(controller:caption,maxLength:500,minLines:1,maxLines:4,style:const TextStyle(color:Colors.white),decoration:InputDecoration(counterText:'',hintText:'Add a caption…',hintStyle:const TextStyle(color:Colors.white60),filled:true,fillColor:const Color(0xB8171827),contentPadding:const EdgeInsets.symmetric(horizontal:17,vertical:12),border:OutlineInputBorder(borderRadius:BorderRadius.circular(25),borderSide:const BorderSide(color:Colors.white38)),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(25),borderSide:const BorderSide(color:Colors.white38)),focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(25),borderSide:const BorderSide(color:_purple,width:2))))),
              const SizedBox(width:10),
              IconButton.filled(onPressed:ready?()=>Navigator.pop(context,caption.text.trim()):null,style:IconButton.styleFrom(backgroundColor:_purple,disabledBackgroundColor:Colors.white24,minimumSize:const Size(52,52)),tooltip:'Post status',icon:const Icon(Icons.send_rounded,color:Colors.white)),
            ]),
          ),
        )),
      ])),
    );
  }
}

class _TextStatusDraft{
  const _TextStatusDraft(this.text,this.backgroundColor);
  final String text,backgroundColor;
}

class _TextStatusComposer extends StatefulWidget{
  const _TextStatusComposer();
  @override State<_TextStatusComposer> createState()=>_TextStatusComposerState();
}

class _TextStatusComposerState extends State<_TextStatusComposer>{
  final controller=TextEditingController();
  String backgroundColor=_textStatusPalette.first;

  @override void initState(){super.initState();controller.addListener(_changed);}
  void _changed()=>setState((){});
  @override void dispose(){controller.removeListener(_changed);controller.dispose();super.dispose();}

  @override
  Widget build(BuildContext context){
    final text=controller.text.trim();
    return AnimatedPadding(
      duration:const Duration(milliseconds:180),
      padding:EdgeInsets.only(bottom:MediaQuery.of(context).viewInsets.bottom),
      child:SafeArea(top:false,child:Container(
        padding:const EdgeInsets.fromLTRB(18,12,18,18),
        decoration:const BoxDecoration(color:Colors.white,borderRadius:BorderRadius.vertical(top:Radius.circular(28))),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          Container(width:42,height:4,decoration:BoxDecoration(color:const Color(0xFFD7D8DE),borderRadius:BorderRadius.circular(8))),
          const SizedBox(height:14),
          const Row(children:[Icon(Icons.text_fields,color:_purple),SizedBox(width:9),Text('Create text status',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800,color:_ink))]),
          const SizedBox(height:14),
          AnimatedContainer(
            duration:const Duration(milliseconds:180),
            height:190,
            width:double.infinity,
            padding:const EdgeInsets.all(20),
            decoration:BoxDecoration(color:_statusColor(backgroundColor),borderRadius:BorderRadius.circular(22)),
            child:Center(child:TextField(controller:controller,autofocus:true,maxLength:700,minLines:1,maxLines:7,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:25,fontWeight:FontWeight.w700,height:1.25),decoration:const InputDecoration(counterStyle:TextStyle(color:Colors.white70),hintText:'Type a status',hintStyle:TextStyle(color:Colors.white70),border:InputBorder.none))),
          ),
          const SizedBox(height:14),
          SizedBox(height:42,child:ListView.separated(
            scrollDirection:Axis.horizontal,
            itemCount:_textStatusPalette.length,
            separatorBuilder:(_,__)=>const SizedBox(width:10),
            itemBuilder:(_,index){
              final value=_textStatusPalette[index];
              final selected=value==backgroundColor;
              return InkWell(
                onTap:()=>setState(()=>backgroundColor=value),
                borderRadius:BorderRadius.circular(24),
                child:AnimatedContainer(
                  duration:const Duration(milliseconds:150),
                  width:42,
                  height:42,
                  padding:EdgeInsets.all(selected?3:0),
                  decoration:BoxDecoration(shape:BoxShape.circle,border:selected?Border.all(color:_ink,width:2):null),
                  child:DecoratedBox(decoration:BoxDecoration(shape:BoxShape.circle,color:_statusColor(value)),child:selected?const Icon(Icons.check,color:Colors.white,size:20):null),
                ),
              );
            },
          )),
          const SizedBox(height:16),
          Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel'))),const SizedBox(width:12),Expanded(child:FilledButton.icon(onPressed:text.isEmpty?null:()=>Navigator.pop(context,_TextStatusDraft(text,backgroundColor)),icon:const Icon(Icons.send_rounded),label:const Text('Post status')))]),
        ]),
      )),
    );
  }
}

class _StatusGroupTile extends StatelessWidget{
  const _StatusGroupTile({required this.group,required this.onTap,required this.onMuteToggle});
  final _StatusGroup group;
  final VoidCallback onTap,onMuteToggle;

  @override
  Widget build(BuildContext context){
    final count=group.items.length;
    final latest=group.latest;
    final updateLabel=count==1
      ?'${latest.mediaType=='text'?'Text update · ':''}${_ago(latest.createdAt)}'
      :'$count updates · ${_ago(latest.createdAt)}';
    final viewedSegments=group.items.map((item)=>group.muted||(!group.mine&&item.viewed)).toList();
    return ListTile(
      contentPadding:const EdgeInsets.only(left:0,right:4,top:4,bottom:4),
      onTap:onTap,
      leading:CustomPaint(
        painter:_StatusRingPainter(viewedSegments),
        child:Padding(
          padding:const EdgeInsets.all(5),
          child:CircleAvatar(radius:25,foregroundImage:group.avatarUrl.isEmpty?null:NetworkImage(group.avatarUrl),child:const Icon(Icons.person)),
        ),
      ),
      title:Text(group.mine?'My status':group.userName,style:const TextStyle(fontWeight:FontWeight.w700,color:_ink)),
      subtitle:Text(updateLabel,style:const TextStyle(color:_muted)),
      trailing:group.mine
        ?Padding(padding:const EdgeInsets.only(right:10),child:Text('$count ${count==1?'update':'updates'}',style:const TextStyle(fontSize:12,color:_muted)))
        :Row(mainAxisSize:MainAxisSize.min,children:[
          if(group.unseenCount>0)Container(
            constraints:const BoxConstraints(minWidth:24,minHeight:24),
            padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),
            decoration:BoxDecoration(color:group.muted?_muted:_purple,borderRadius:BorderRadius.circular(13)),
            child:Text('${group.unseenCount}',textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w800)),
          )else const Icon(Icons.check_circle_outline,color:_muted,size:19),
          PopupMenuButton<String>(tooltip:'Status options',onSelected:(_)=>onMuteToggle(),itemBuilder:(_)=>[PopupMenuItem(value:'toggle',child:ListTile(leading:Icon(group.muted?Icons.volume_up_outlined:Icons.volume_off_outlined),title:Text(group.muted?'Unmute status updates':'Mute status updates')))])
        ]),
    );
  }
}

class _StatusRingPainter extends CustomPainter{
  const _StatusRingPainter(this.viewedSegments);
  final List<bool> viewedSegments;

  @override
  void paint(Canvas canvas,Size size){
    if(viewedSegments.isEmpty)return;
    final count=viewedSegments.length;
    final segmentSweep=math.pi*2/count;
    final gap=count==1?0.0:math.min(.11,segmentSweep*.18).toDouble();
    final rect=Offset.zero&size;
    final ring=rect.deflate(1.8);
    final paint=Paint()..style=PaintingStyle.stroke..strokeWidth=3..strokeCap=StrokeCap.round;
    for(var index=0;index<count;index++){
      paint.color=viewedSegments[index]?_muted:_purple;
      canvas.drawArc(ring,-math.pi/2+segmentSweep*index+gap/2,count==1?math.pi*2:segmentSweep-gap,false,paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StatusRingPainter oldDelegate){
    if(oldDelegate.viewedSegments.length!=viewedSegments.length)return true;
    for(var index=0;index<viewedSegments.length;index++){
      if(oldDelegate.viewedSegments[index]!=viewedSegments[index])return true;
    }
    return false;
  }
}
String _ago(DateTime time){final duration=DateTime.now().difference(time.toLocal());if(duration.inMinutes<1)return'Just now';if(duration.inHours<1)return'${duration.inMinutes} min ago';return'${duration.inHours} hr ago';}

class StatusViewer extends StatefulWidget{const StatusViewer({super.key,required this.items,required this.start});final List<StatusItem> items;final int start;@override State<StatusViewer> createState()=>_StatusViewerState();}
class _StatusViewerState extends State<StatusViewer> with WidgetsBindingObserver{
  late final PageController controller;
  late final TextEditingController replyController;
  late final FocusNode replyFocus;
  final Stopwatch playbackClock=Stopwatch();
  final ValueNotifier<double> playbackProgress=ValueNotifier<double>(0);
  late final Set<String> mutedUserIds;
  late final Set<String> likedStatusIds;
  late final Map<String,int> likeCounts;
  late int index;
  Timer? timer;
  bool sendingReply=false,likingStatus=false;
  String sendingReaction='';
  bool holding=false,viewerSheetOpen=false,statusMenuOpen=false,statusActionRunning=false,transitioning=false,appInactive=false,draggingStatus=false;
  double verticalDrag=0,dismissOffset=0;
  int restartToken=0;

  bool get playbackBlocked=>holding||viewerSheetOpen||statusMenuOpen||statusActionRunning||transitioning||appInactive||draggingStatus||replyFocus.hasFocus||sendingReply||likingStatus||sendingReaction.isNotEmpty;
  Duration get currentDuration=>Duration(seconds:widget.items[index].mediaType=='text'?7:5);

  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    index=widget.start;
    mutedUserIds=widget.items.where((item)=>item.muted).map((item)=>item.userId).toSet();
    likedStatusIds=widget.items.where((item)=>item.liked).map((item)=>item.id).toSet();
    likeCounts={for(final item in widget.items)item.id:item.likeCount};
    controller=PageController(initialPage:index);
    replyController=TextEditingController();
    replyFocus=FocusNode()..addListener(_replyFocusChanged);
    _activate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(!mounted)return;
    final inactive=state!=AppLifecycleState.resumed;
    if(inactive)_pausePlayback();
    if(appInactive!=inactive)setState(()=>appInactive=inactive);
    if(!inactive)_resumePlayback();
  }

  void _replyFocusChanged(){
    if(!mounted)return;
    if(replyFocus.hasFocus)_pausePlayback();
    setState((){});
    if(!replyFocus.hasFocus)_resumePlayback();
  }

  void _activate(){
    _pausePlayback();
    playbackClock.reset();
    playbackProgress.value=0;
    final item=widget.items[index];
    if(!item.mine)unawaited(StatusApi.instance.viewed(item.id));
    _resumePlayback();
  }

  void _startStaticProgress(){
    if(playbackBlocked||widget.items[index].mediaType=='video')return;
    timer?.cancel();
    playbackClock.start();
    timer=Timer.periodic(const Duration(milliseconds:50),(activeTimer){
      if(!mounted||playbackBlocked||widget.items[index].mediaType=='video'){
        _pausePlayback();
        return;
      }
      final total=currentDuration.inMilliseconds;
      final value=total<=0?1.0:(playbackClock.elapsedMilliseconds/total).clamp(0.0,1.0).toDouble();
      playbackProgress.value=value;
      if(value>=1){
        playbackClock.stop();
        activeTimer.cancel();
        timer=null;
        _next();
      }
    });
  }

  void _pausePlayback(){
    timer?.cancel();
    timer=null;
    playbackClock.stop();
  }

  void _resumePlayback(){
    if(!mounted||playbackBlocked)return;
    if(widget.items[index].mediaType!='video')_startStaticProgress();
  }

  void _next(){
    if(!mounted||playbackBlocked)return;
    _pausePlayback();
    if(index>=widget.items.length-1){Navigator.pop(context);return;}
    setState(()=>transitioning=true);
    controller.nextPage(duration:const Duration(milliseconds:250),curve:Curves.easeOut);
  }

  void _previous(){
    if(!mounted||playbackBlocked)return;
    _pausePlayback();
    if(index>0){
      setState(()=>transitioning=true);
      controller.previousPage(duration:const Duration(milliseconds:250),curve:Curves.easeOut);
      return;
    }
    restartToken++;
    setState((){});
    _activate();
  }

  void _tapStatus(int page,TapUpDetails details,double width){
    if(page!=index||playbackBlocked)return;
    if(details.localPosition.dx<width*.38){_previous();}else{_next();}
  }

  void _holdStatus(int page){
    if(page!=index||playbackBlocked)return;
    _pausePlayback();
    setState(()=>holding=true);
  }

  void _releaseStatus(){
    if(!holding||!mounted)return;
    setState(()=>holding=false);
    _resumePlayback();
  }

  void _startStatusDrag(int page){
    if(page!=index||playbackBlocked)return;
    _pausePlayback();
    setState((){draggingStatus=true;verticalDrag=0;dismissOffset=0;});
  }

  void _updateStatusDrag(int page,DragUpdateDetails details){
    if(page!=index||!draggingStatus)return;
    setState((){
      verticalDrag+=details.delta.dy;
      dismissOffset=verticalDrag.clamp(0.0,260.0).toDouble();
    });
  }

  void _endStatusDrag(DragEndDetails details){
    if(!draggingStatus)return;
    final velocity=details.primaryVelocity??0;
    if(verticalDrag>110||velocity>800){Navigator.pop(context);return;}
    final openReply=!widget.items[index].mine&&(verticalDrag< -70||velocity< -800);
    setState((){draggingStatus=false;verticalDrag=0;dismissOffset=0;});
    if(openReply){replyFocus.requestFocus();}else{_resumePlayback();}
  }

  void _cancelStatusDrag(){
    if(!draggingStatus)return;
    setState((){draggingStatus=false;verticalDrag=0;dismissOffset=0;});
    _resumePlayback();
  }

  Future<void> _sendReply()async{
    final text=replyController.text.trim();
    if(text.isEmpty||sendingReply||sendingReaction.isNotEmpty||widget.items[index].mine)return;
    _pausePlayback();
    setState(()=>sendingReply=true);
    try{
      final result=await StatusApi.instance.reply(widget.items[index].id,text);
      if(!mounted)return;
      final router=GoRouter.of(context);
      replyController.clear();
      replyFocus.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:const Text('Status reply sent'),action:result.conversationId.isEmpty?null:SnackBarAction(label:'Open chat',onPressed:()=>router.go('/chat/${result.conversationId}'))));
    }catch(failure){
      if(!mounted)return;
      var message='Status reply send nahi hua. Retry karein.';
      if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
    }finally{
      if(mounted){setState(()=>sendingReply=false);_resumePlayback();}
    }
  }

  Future<void> _sendReaction(String emoji)async{
    if(sendingReply||sendingReaction.isNotEmpty||widget.items[index].mine)return;
    _pausePlayback();
    setState(()=>sendingReaction=emoji);
    try{
      final result=await StatusApi.instance.react(widget.items[index].id,emoji);
      if(!mounted)return;
      final router=GoRouter.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$emoji reaction sent'),action:result.conversationId.isEmpty?null:SnackBarAction(label:'Open chat',onPressed:()=>router.go('/chat/${result.conversationId}'))));
    }catch(failure){
      if(!mounted)return;
      var message='Status reaction send nahi hua. Retry karein.';
      if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
    }finally{
      if(mounted){setState(()=>sendingReaction='');_resumePlayback();}
    }
  }

  Future<void> _toggleLike()async{
    final item=widget.items[index];
    if(item.mine||likingStatus||sendingReply||sendingReaction.isNotEmpty)return;
    final next=!likedStatusIds.contains(item.id);
    _pausePlayback();
    setState((){
      likingStatus=true;
      if(next){likedStatusIds.add(item.id);}else{likedStatusIds.remove(item.id);}
    });
    try{
      await StatusApi.instance.setLiked(item.id,next);
    }catch(failure){
      if(!mounted)return;
      setState((){if(next){likedStatusIds.remove(item.id);}else{likedStatusIds.add(item.id);}});
      var message='Status like save nahi hua. Retry karein.';
      if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
    }finally{
      if(mounted){setState(()=>likingStatus=false);_resumePlayback();}
    }
  }

  Future<void> _showViewers()async{
    final item=widget.items[index];
    _pausePlayback();
    setState(()=>viewerSheetOpen=true);
    try{
      final managePrivacy=await showModalBottomSheet<bool>(context:context,isScrollControlled:true,builder:(_)=>_StatusViewersSheet(statusId:item.id));
      if(managePrivacy==true&&mounted)await context.push('/profile/privacy');
    }finally{
      if(mounted){setState(()=>viewerSheetOpen=false);_resumePlayback();}
    }
  }

  Future<void> _shareCurrentStatus()async{
    if(statusActionRunning||!widget.items[index].mine)return;
    final item=widget.items[index];
    _pausePlayback();
    setState(()=>statusActionRunning=true);
    try{
      final chats=await ChatApi.instance.conversations();
      if(!mounted)return;
      if(chats.isEmpty){
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Share karne ke liye koi active chat nahi hai.')));
        return;
      }
      final selected=await showDialog<List<String>>(context:context,builder:(_)=>_StatusShareDialog(chats:chats));
      if(!mounted||selected==null||selected.isEmpty)return;
      final count=await StatusApi.instance.share(item.id,selected);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Status $count ${count==1?'chat':'chats'} mein share ho gaya.')));
    }catch(failure){
      if(mounted){
        var message='Status share nahi hua. Retry karein.';
        if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
      }
    }finally{
      if(mounted){setState(()=>statusActionRunning=false);_resumePlayback();}
    }
  }

  Future<void> _deleteCurrentStatus()async{
    if(statusActionRunning||!widget.items[index].mine)return;
    final item=widget.items[index];
    _pausePlayback();
    setState(()=>statusActionRunning=true);
    var viewerClosed=false;
    try{
      final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
        title:const Text('Delete status?'),
        content:const Text('Yeh status sab contacts ke liye remove ho jayega. Chat mein pehle share ki hui copy available rahegi.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(style:FilledButton.styleFrom(backgroundColor:Colors.red),onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Delete'))],
      ));
      if(confirmed!=true)return;
      await StatusApi.instance.delete(item.id);
      if(!mounted)return;
      viewerClosed=true;
      Navigator.pop(context,'Status deleted.');
    }catch(failure){
      if(mounted){
        var message='Status delete nahi hua. Retry karein.';
        if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
      }
    }finally{
      if(mounted&&!viewerClosed){setState(()=>statusActionRunning=false);_resumePlayback();}
    }
  }

  void _openStatusMenu(){
    _pausePlayback();
    if(mounted)setState(()=>statusMenuOpen=true);
  }

  void _cancelStatusMenu(){
    if(!mounted)return;
    setState(()=>statusMenuOpen=false);
    _resumePlayback();
  }

  Future<void> _handleStatusOption(String action)async{
    if(statusActionRunning||widget.items[index].mine)return;
    setState(()=>statusActionRunning=true);
    var viewerClosed=false;
    try{
      if(action=='mute')await _toggleCurrentMute();
      if(action=='report')await _reportCurrentStatus();
      if(action=='block')viewerClosed=await _blockCurrentUser();
    }catch(failure){
      if(mounted){
        var message=action=='block'?'User block nahi hua. Retry karein.':action=='report'?'Report submit nahi hui. Retry karein.':'Status preference save nahi hui. Retry karein.';
        if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
      }
    }finally{
      if(mounted&&!viewerClosed){
        setState((){statusActionRunning=false;statusMenuOpen=false;});
        _resumePlayback();
      }
    }
  }

  Future<void> _toggleCurrentMute()async{
    final item=widget.items[index];
    final next=!mutedUserIds.contains(item.userId);
    if(next){await StatusApi.instance.mute(item.userId);}else{await StatusApi.instance.unmute(item.userId);}
    if(!mounted)return;
    setState((){if(next){mutedUserIds.add(item.userId);}else{mutedUserIds.remove(item.userId);}});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(next?'${item.userName} ke status updates muted.':'${item.userName} ke status updates unmuted.')));
  }

  Future<void> _reportCurrentStatus()async{
    final item=widget.items[index];
    var reason='inappropriate';
    final note=TextEditingController();
    final submit=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(_,setDialogState)=>AlertDialog(
      title:const Text('Report status'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Why are you reporting ${item.userName}\'s status?',style:const TextStyle(color:_muted)),
        const SizedBox(height:16),
        DropdownButtonFormField<String>(value:reason,decoration:const InputDecoration(labelText:'Reason'),items:const[
          DropdownMenuItem(value:'inappropriate',child:Text('Inappropriate content')),
          DropdownMenuItem(value:'spam',child:Text('Spam')),
          DropdownMenuItem(value:'harassment',child:Text('Harassment')),
          DropdownMenuItem(value:'impersonation',child:Text('Impersonation')),
          DropdownMenuItem(value:'other',child:Text('Other')),
        ],onChanged:(value)=>setDialogState(()=>reason=value??reason)),
        const SizedBox(height:10),
        TextField(controller:note,maxLength:420,maxLines:3,decoration:const InputDecoration(labelText:'Details (optional)',hintText:'Review team ke liye details')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Submit'))],
    )));
    final details=note.text.trim();
    note.dispose();
    if(submit!=true)return;
    await SocialApi.instance.reportUser(item.userId,conversationId:'',reason:reason,details:'Status ${item.id}${details.isEmpty?'':': $details'}');
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Status report review ke liye submit ho gayi.')));
  }

  Future<bool> _blockCurrentUser()async{
    final item=widget.items[index];
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
      title:Text('Block ${item.userName}?'),
      content:const Text('Unke status, messages aur calls aapko nahi milenge. Aap Privacy settings se baad mein unblock kar sakte hain.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(style:FilledButton.styleFrom(backgroundColor:Colors.red),onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Block'))],
    ));
    if(confirmed!=true)return false;
    await SocialApi.instance.setBlocked(item.userId,true);
    if(!mounted)return true;
    Navigator.pop(context,'${item.userName} blocked. Unke status aur chats hide ho gaye.');
    return true;
  }

  int get currentContactStart{
    final userId=widget.items[index].userId;
    var start=index;
    while(start>0&&widget.items[start-1].userId==userId)start--;
    return start;
  }

  int get currentContactEnd{
    final userId=widget.items[index].userId;
    var end=index;
    while(end<widget.items.length-1&&widget.items[end+1].userId==userId)end++;
    return end;
  }

  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);_pausePlayback();playbackProgress.dispose();replyFocus.removeListener(_replyFocusChanged);replyFocus.dispose();replyController.dispose();controller.dispose();super.dispose();}

  @override
  Widget build(BuildContext context){
    final current=widget.items[index];
    final liked=likedStatusIds.contains(current.id);
    final currentLikes=likeCounts[current.id]??current.likeCount;
    final viewSummary='${current.viewCount} ${current.viewCount==1?'view':'views'} · $currentLikes ${currentLikes==1?'like':'likes'}';
    return Scaffold(backgroundColor:Colors.black,body:SafeArea(child:AnimatedContainer(
      duration:draggingStatus?Duration.zero:const Duration(milliseconds:180),
      curve:Curves.easeOutCubic,
      transform:Matrix4.translationValues(0,dismissOffset,0),
      child:Stack(children:[
      PageView.builder(
        controller:controller,
        physics:playbackBlocked?const NeverScrollableScrollPhysics():null,
        itemCount:widget.items.length,
        onPageChanged:(value){setState((){index=value;transitioning=false;});replyController.clear();replyFocus.unfocus();_activate();},
        itemBuilder:(context,i)=>GestureDetector(
          behavior:HitTestBehavior.opaque,
          onTapUp:(details)=>_tapStatus(i,details,MediaQuery.sizeOf(context).width),
          onLongPressStart:(_)=>_holdStatus(i),
          onLongPressEnd:(_)=>_releaseStatus(),
          onVerticalDragStart:(_)=>_startStatusDrag(i),
          onVerticalDragUpdate:(details)=>_updateStatusDrag(i,details),
          onVerticalDragEnd:_endStatusDrag,
          onVerticalDragCancel:_cancelStatusDrag,
          child:_StatusMedia(
            item:widget.items[i],
            bottomInset:widget.items[i].mine?64:165,
            active:i==index,
            paused:playbackBlocked,
            restartToken:restartToken,
            onProgress:i==index?(value){if(mounted&&i==index)playbackProgress.value=value;}:null,
            onCompleted:i==index?_next:null,
          ),
        ),
      ),
      if(holding)const IgnorePointer(child:Center(child:Icon(Icons.pause_circle_filled_rounded,color:Colors.white70,size:66))),
      Positioned(top:8,left:10,right:10,child:Column(children:[
        ValueListenableBuilder<double>(valueListenable:playbackProgress,builder:(_,value,__){
          final start=currentContactStart,end=currentContactEnd;
          return Row(children:List.generate(end-start+1,(slot){
            final itemIndex=start+slot;
            return Expanded(child:_StatusProgressBar(value:itemIndex<index?1:itemIndex==index?value:0));
          }));
        }),
        const SizedBox(height:5),
        Row(children:[IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.arrow_back,color:Colors.white)),CircleAvatar(radius:18,foregroundImage:current.avatarUrl.isEmpty?null:NetworkImage(current.avatarUrl)),const SizedBox(width:10),Expanded(child:Text(current.mine?'My status':current.userName,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700))),if(statusActionRunning)const SizedBox(width:48,height:48,child:Center(child:SizedBox(width:21,height:21,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))))else if(current.mine)...[IconButton(onPressed:_shareCurrentStatus,tooltip:'Share status',icon:const Icon(Icons.send_outlined,color:Colors.white)),IconButton(onPressed:_deleteCurrentStatus,tooltip:'Delete status',icon:const Icon(Icons.delete_outline,color:Colors.white))]else PopupMenuButton<String>(tooltip:'Status options',icon:const Icon(Icons.more_vert,color:Colors.white),color:const Color(0xFF202235),onOpened:_openStatusMenu,onCanceled:_cancelStatusMenu,onSelected:(value)=>unawaited(_handleStatusOption(value)),itemBuilder:(_)=>[
          PopupMenuItem(value:'mute',child:ListTile(leading:Icon(mutedUserIds.contains(current.userId)?Icons.volume_up_outlined:Icons.volume_off_outlined,color:Colors.white),title:Text(mutedUserIds.contains(current.userId)?'Unmute status updates':'Mute status updates',style:const TextStyle(color:Colors.white)))),
          const PopupMenuItem(value:'report',child:ListTile(leading:Icon(Icons.flag_outlined,color:Colors.orangeAccent),title:Text('Report status',style:TextStyle(color:Colors.white)))),
          const PopupMenuItem(value:'block',child:ListTile(leading:Icon(Icons.block,color:Colors.redAccent),title:Text('Block user',style:TextStyle(color:Colors.redAccent)))),
        ])])
      ])),
      if(current.mine)Positioned(bottom:20,left:0,right:0,child:Center(child:TextButton.icon(onPressed:_showViewers,icon:const Icon(Icons.visibility_outlined,color:Colors.white),label:Text(viewSummary,style:const TextStyle(color:Colors.white))))),
      if(!current.mine)Positioned(bottom:12,left:14,right:14,child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(!replyFocus.hasFocus)Container(
          margin:const EdgeInsets.only(bottom:9),
          padding:const EdgeInsets.symmetric(horizontal:8,vertical:7),
          decoration:BoxDecoration(color:const Color(0xD9171827),borderRadius:BorderRadius.circular(28),border:Border.all(color:Colors.white24)),
          child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[
            Tooltip(message:liked?'Unlike status':'Like status',child:InkResponse(onTap:sendingReply||likingStatus||sendingReaction.isNotEmpty?null:_toggleLike,radius:23,child:SizedBox(width:38,height:38,child:Center(child:likingStatus?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):Icon(liked?Icons.favorite_rounded:Icons.favorite_border_rounded,color:liked?const Color(0xFFFF5C7A):Colors.white,size:28))))),
            for(final emoji in _statusReactionChoices)Tooltip(message:'React $emoji',child:InkResponse(onTap:sendingReply||likingStatus||sendingReaction.isNotEmpty?null:()=>_sendReaction(emoji),radius:23,child:SizedBox(width:38,height:38,child:Center(child:sendingReaction==emoji?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):Text(emoji,style:const TextStyle(fontSize:25))))))
          ]),
        ),
        Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Expanded(child:TextField(controller:replyController,focusNode:replyFocus,maxLength:1000,minLines:1,maxLines:4,textInputAction:TextInputAction.newline,style:const TextStyle(color:Colors.white),decoration:InputDecoration(counterText:'',hintText:'Reply to ${current.userName}…',hintStyle:const TextStyle(color:Colors.white60),filled:true,fillColor:const Color(0xCC171827),contentPadding:const EdgeInsets.symmetric(horizontal:17,vertical:12),border:OutlineInputBorder(borderRadius:BorderRadius.circular(25),borderSide:const BorderSide(color:Colors.white38)),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(25),borderSide:const BorderSide(color:Colors.white38)),focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(25),borderSide:const BorderSide(color:_purple,width:2))))),
          const SizedBox(width:8),
          ValueListenableBuilder<TextEditingValue>(valueListenable:replyController,builder:(_,value,__)=>IconButton.filled(onPressed:value.text.trim().isEmpty||sendingReply||likingStatus||sendingReaction.isNotEmpty?null:_sendReply,style:IconButton.styleFrom(backgroundColor:_purple,disabledBackgroundColor:Colors.white24,minimumSize:const Size(48,48)),icon:sendingReply?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.send_rounded,color:Colors.white)))
        ])
      ])),
    ]))));
  }
}

class _StatusShareDialog extends StatefulWidget{
  const _StatusShareDialog({required this.chats});
  final List<ChatSummary> chats;
  @override State<_StatusShareDialog> createState()=>_StatusShareDialogState();
}

class _StatusShareDialogState extends State<_StatusShareDialog>{
  final search=TextEditingController();
  final selected=<String>{};

  List<ChatSummary> get visible{
    final query=search.text.trim().toLowerCase();
    if(query.isEmpty)return widget.chats;
    return widget.chats.where((chat)=>chat.name.toLowerCase().contains(query)||chat.displayPreview.toLowerCase().contains(query)).toList();
  }

  void _toggle(String id){
    setState((){
      if(selected.contains(id)){selected.remove(id);return;}
      if(selected.length<5)selected.add(id);
    });
  }

  @override void dispose(){search.dispose();super.dispose();}

  @override
  Widget build(BuildContext context)=>AlertDialog(
    title:const Text('Share status'),
    content:SizedBox(width:420,height:math.min(470.0,MediaQuery.sizeOf(context).height*.62),child:Column(children:[
      TextField(controller:search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search chats',isDense:true)),
      const SizedBox(height:9),
      Align(alignment:Alignment.centerLeft,child:Text('${selected.length}/5 chats selected',style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:selected.length==5?Colors.orange:_muted))),
      const SizedBox(height:5),
      Expanded(child:visible.isEmpty
        ?const Center(child:Text('Koi matching chat nahi mili.',style:TextStyle(color:_muted)))
        :ListView.builder(itemCount:visible.length,itemBuilder:(_,chatIndex){
          final chat=visible[chatIndex];
          final checked=selected.contains(chat.id);
          final disabled=!checked&&selected.length>=5;
          return ListTile(
            enabled:!disabled,
            contentPadding:EdgeInsets.zero,
            onTap:()=>_toggle(chat.id),
            leading:CircleAvatar(foregroundImage:chat.avatarUrl?.isNotEmpty==true?NetworkImage(chat.avatarUrl!):null,child:Icon(chat.group?Icons.groups_rounded:Icons.person)),
            title:Text(chat.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700)),
            subtitle:Text(chat.displayPreview.isEmpty?(chat.group?'Group chat':'Direct chat'):chat.displayPreview,maxLines:1,overflow:TextOverflow.ellipsis),
            trailing:Checkbox(value:checked,onChanged:disabled?null:(_)=>_toggle(chat.id),activeColor:_purple),
          );
        })),
    ])),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton.icon(onPressed:selected.isEmpty?null:()=>Navigator.pop(context,selected.toList()),icon:const Icon(Icons.send_outlined,size:18),label:Text('Share (${selected.length})'))],
  );
}

class _StatusViewersSheet extends StatefulWidget{
  const _StatusViewersSheet({required this.statusId});
  final String statusId;
  @override State<_StatusViewersSheet> createState()=>_StatusViewersSheetState();
}

class _StatusViewersSheetState extends State<_StatusViewersSheet>{
  late Future<StatusViewerResult> request;

  @override void initState(){super.initState();request=StatusApi.instance.viewers(widget.statusId);}
  void _retry()=>setState(()=>request=StatusApi.instance.viewers(widget.statusId));

  @override
  Widget build(BuildContext context)=>SafeArea(child:SizedBox(
    height:MediaQuery.sizeOf(context).height*.58,
    child:FutureBuilder<StatusViewerResult>(
      future:request,
      builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(color:_purple));
        if(snapshot.hasError)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_outlined,color:_muted,size:48),const SizedBox(height:12),const Text('Viewers load nahi hue'),const SizedBox(height:12),OutlinedButton.icon(onPressed:_retry,icon:const Icon(Icons.refresh),label:const Text('Retry'))]));
        final result=snapshot.data!;
        if(!result.readReceiptsEnabled)return GroopXEmptyState(
          icon:Icons.visibility_off_outlined,
          title:'Read receipts are off',
          message:'Status viewers dekhne aur apna view share karne ke liye read receipts on karein.',
          actionLabel:'Privacy settings',
          actionIcon:Icons.lock_outline,
          onAction:()=>Navigator.pop(context,true),
        );
        final viewers=result.items;
        final reactions=viewers.where((viewer)=>viewer.reaction.isNotEmpty).length;
        final likes=viewers.where((viewer)=>viewer.liked).length;
        return Column(children:[
          Container(width:42,height:4,margin:const EdgeInsets.only(top:10,bottom:6),decoration:BoxDecoration(color:const Color(0xFFD7D8DE),borderRadius:BorderRadius.circular(8))),
          ListTile(
            leading:const CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.visibility_outlined,color:_purple)),
            title:Text('${viewers.length} ${viewers.length==1?'view':'views'}',style:const TextStyle(fontWeight:FontWeight.w800,color:_ink)),
            subtitle:Text(likes==0&&reactions==0?'No likes or reactions yet':'$likes ${likes==1?'like':'likes'} · $reactions ${reactions==1?'reaction':'reactions'}',style:const TextStyle(color:_muted)),
          ),
          const Divider(height:1),
          Expanded(child:viewers.isEmpty
            ?const Center(child:Text('Abhi kisi ne status nahi dekha.',style:TextStyle(color:_muted)))
            :ListView.separated(
              itemCount:viewers.length,
              separatorBuilder:(_,__)=>const Divider(height:1,indent:72),
              itemBuilder:(_,index){
                final viewer=viewers[index];
                return ListTile(
                  leading:CircleAvatar(foregroundImage:viewer.avatarUrl.isEmpty?null:NetworkImage(viewer.avatarUrl),child:const Icon(Icons.person)),
                  title:Text(viewer.name,style:const TextStyle(fontWeight:FontWeight.w600,color:_ink)),
                  subtitle:Text(_ago(viewer.viewedAt),style:const TextStyle(color:_muted)),
                  trailing:!viewer.liked&&viewer.reaction.isEmpty?null:Row(mainAxisSize:MainAxisSize.min,children:[
                    if(viewer.liked)const Padding(padding:EdgeInsets.symmetric(horizontal:8),child:Icon(Icons.favorite_rounded,color:Color(0xFFFF5C7A),size:22)),
                    if(viewer.reaction.isNotEmpty)Container(
                      width:44,height:36,alignment:Alignment.center,
                      decoration:BoxDecoration(color:const Color(0xFFEEE9FF),borderRadius:BorderRadius.circular(18)),
                      child:Text(viewer.reaction,style:const TextStyle(fontSize:21)),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]);
      },
    ),
  ));
}

class _StatusProgressBar extends StatelessWidget{
  const _StatusProgressBar({required this.value});
  final double value;
  @override
  Widget build(BuildContext context)=>Container(
    height:3,
    margin:const EdgeInsets.symmetric(horizontal:2),
    decoration:BoxDecoration(color:Colors.white38,borderRadius:BorderRadius.circular(4)),
    clipBehavior:Clip.antiAlias,
    child:FractionallySizedBox(
      alignment:Alignment.centerLeft,
      widthFactor:value.clamp(0.0,1.0).toDouble(),
      child:const ColoredBox(color:Colors.white),
    ),
  );
}

class _StatusMedia extends StatefulWidget{
  const _StatusMedia({required this.item,required this.bottomInset,required this.active,required this.paused,required this.restartToken,this.onProgress,this.onCompleted});
  final StatusItem item;
  final double bottomInset;
  final bool active,paused;
  final int restartToken;
  final ValueChanged<double>? onProgress;
  final VoidCallback? onCompleted;
  @override State<_StatusMedia> createState()=>_StatusMediaState();
}
class _StatusMediaState extends State<_StatusMedia>{
  VideoPlayerController? video;
  bool completed=false;

  @override
  void initState(){
    super.initState();
    if(widget.active)_ensureVideo();
  }

  @override
  void didUpdateWidget(covariant _StatusMedia oldWidget){
    super.didUpdateWidget(oldWidget);
    if(widget.active&&!oldWidget.active){
      completed=false;
      _ensureVideo(restart:true);
      widget.onProgress?.call(0);
      return;
    }else if(widget.active&&widget.restartToken!=oldWidget.restartToken){
      completed=false;
      _ensureVideo(restart:true);
      widget.onProgress?.call(0);
      return;
    }
    _syncPlayback();
  }

  void _ensureVideo({bool restart=false}){
    if(widget.item.mediaType!='video')return;
    final existing=video;
    if(existing!=null){
      if(restart)unawaited(existing.seekTo(Duration.zero).then((_){if(mounted)_syncPlayback();}));
      return;
    }
    final controller=VideoPlayerController.networkUrl(Uri.parse(widget.item.mediaUrl));
    video=controller;
    unawaited(controller.initialize().then((_){
      if(!mounted)return;
      controller.addListener(_listen);
      setState((){});
      _syncPlayback();
    }));
  }

  void _syncPlayback(){
    final controller=video;
    if(controller==null||!controller.value.isInitialized)return;
    if(widget.active&&!widget.paused){
      unawaited(controller.play());
    }else{
      unawaited(controller.pause());
    }
  }

  void _listen(){
    final value=video?.value;
    if(!widget.active||value==null||!value.isInitialized||value.duration.inMilliseconds<=0)return;
    final duration=value.duration.inMilliseconds;
    final position=value.position.inMilliseconds;
    widget.onProgress?.call((position/duration).clamp(0.0,1.0).toDouble());
    if(!completed&&position>=duration-100){completed=true;widget.onCompleted?.call();}
  }

  @override
  void dispose(){video?..removeListener(_listen)..dispose();super.dispose();}

  @override
  Widget build(BuildContext context)=>Stack(fit:StackFit.expand,children:[
    if(widget.item.mediaType=='text')
      ColoredBox(color:_statusColor(widget.item.backgroundColor),child:Center(child:SingleChildScrollView(padding:EdgeInsets.fromLTRB(34,100,34,widget.bottomInset+30),child:Text(widget.item.textContent,textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:widget.item.textContent.length>150?24:30,fontWeight:FontWeight.w800,height:1.3)))))
    else if(widget.item.mediaType=='image')
      InteractiveViewer(child:Image.network(widget.item.mediaUrl,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image,color:Colors.white,size:60)))
    else if(video?.value.isInitialized==true)
      Center(child:AspectRatio(aspectRatio:video!.value.aspectRatio,child:VideoPlayer(video!)))
    else
      const Center(child:CircularProgressIndicator(color:_purple)),
    if(widget.item.mediaType!='text'&&widget.item.caption.isNotEmpty)
      Align(alignment:Alignment.bottomCenter,child:Container(width:double.infinity,padding:EdgeInsets.fromLTRB(24,30,24,widget.bottomInset),decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,Colors.black87])),child:Text(widget.item.caption,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16))))
  ]);
}
