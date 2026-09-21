import 'package:flutter/material.dart';

class AvatarPreviewScreen extends StatelessWidget{
  const AvatarPreviewScreen({super.key,required this.name,required this.url});final String name,url;
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:Colors.black,appBar:AppBar(backgroundColor:Colors.black,foregroundColor:Colors.white,title:Text(name)),body:Center(child:url.isEmpty?Column(mainAxisSize:MainAxisSize.min,children:[const CircleAvatar(radius:82,backgroundColor:Color(0xFF6D31FF),child:Icon(Icons.person,size:95,color:Colors.white)),const SizedBox(height:18),Text(name,style:const TextStyle(color:Colors.white,fontSize:21,fontWeight:FontWeight.w700))]):InteractiveViewer(minScale:.7,maxScale:4,child:Image.network(url,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image_outlined,color:Colors.white,size:70)))));
}
