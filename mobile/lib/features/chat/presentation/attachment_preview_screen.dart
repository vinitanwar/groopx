import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_theme.dart';

class AttachmentPreviewScreen extends StatefulWidget {
  const AttachmentPreviewScreen({super.key,required this.kind,required this.name,required this.url,this.oneTime=false});
  final String kind,name,url;
  final bool oneTime;
  @override State<AttachmentPreviewScreen> createState()=>_AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<AttachmentPreviewScreen> {
  static const screenSecurity=MethodChannel('com.futureittouch.groopx/screen_security');
  VideoPlayerController? controller; bool loading=false; String? error;
  @override void initState(){super.initState();if(widget.oneTime)unawaited(_setSecure(true));if(widget.kind=='video')_initVideo();}
  Future<void> _setSecure(bool enabled)async{try{await screenSecurity.invokeMethod<void>('setSecure',enabled);}catch(_){}}
  Future<void> _initVideo()async{setState(()=>loading=true);try{final value=VideoPlayerController.networkUrl(Uri.parse(widget.url));await value.initialize();controller=value;if(mounted)setState((){});}catch(_){if(mounted)setState(()=>error='Video load nahi hua.');}finally{if(mounted)setState(()=>loading=false);}}
  Future<void> _open()async{final uri=Uri.tryParse(widget.url);if(uri==null||!await launchUrl(uri,mode:LaunchMode.externalApplication)){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('File open nahi hui.')));}}
  @override void dispose(){if(widget.oneTime)unawaited(_setSecure(false));controller?.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:widget.kind=='image'||widget.kind=='video'?Colors.black:AppColors.background,appBar:AppBar(backgroundColor:widget.kind=='image'||widget.kind=='video'?Colors.black:Colors.white,foregroundColor:widget.kind=='image'||widget.kind=='video'?Colors.white:AppColors.text,title:Text(widget.name,overflow:TextOverflow.ellipsis),actions:[if(!widget.oneTime)IconButton(onPressed:_open,tooltip:'Open externally',icon:const Icon(Icons.open_in_new))]),body:Stack(children:[Positioned.fill(child:Center(child:_body())),if(widget.oneTime)Positioned(left:18,right:18,bottom:24,child:SafeArea(top:false,child:Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),decoration:BoxDecoration(color:const Color(0xCC171322),borderRadius:BorderRadius.circular(12)),child:const Row(mainAxisAlignment:MainAxisAlignment.center,children:[CircleAvatar(radius:12,backgroundColor:AppColors.purple,child:Text('1',style:TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w800))),SizedBox(width:9),Flexible(child:Text('Close karne ke baad dobara open nahi hoga',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w600)))]))))]));
  Widget _body(){if(widget.url.isEmpty)return const Text('Attachment URL unavailable',style:TextStyle(color:AppColors.muted));if(widget.kind=='image')return InteractiveViewer(minScale:.8,maxScale:5,child:Image.network(widget.url,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Text('Image load nahi hui',style:TextStyle(color:Colors.white))));if(widget.kind=='video'){if(loading)return const CircularProgressIndicator(color:AppColors.purple);if(error!=null)return Text(error!,style:const TextStyle(color:Colors.white));final value=controller;if(value==null)return const SizedBox();return Stack(alignment:Alignment.center,children:[AspectRatio(aspectRatio:value.value.aspectRatio,child:VideoPlayer(value)),IconButton.filled(onPressed:(){value.value.isPlaying?value.pause():value.play();setState((){});},iconSize:40,icon:Icon(value.value.isPlaying?Icons.pause:Icons.play_arrow))]);}return Padding(padding:const EdgeInsets.all(28),child:Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(widget.kind=='audio'?Icons.audio_file_outlined:Icons.description_outlined,size:70,color:AppColors.purple),const SizedBox(height:18),Text(widget.name,textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700)),const SizedBox(height:20),FilledButton.icon(onPressed:_open,icon:const Icon(Icons.open_in_new),label:const Text('Open file'))]))));}
}
