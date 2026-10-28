import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';

import '../../auth/data/auth_api.dart';

enum StatusMediaSource{camera,gallery}

class StatusMediaDraft{
  const StatusMediaDraft({required this.path,required this.name,required this.contentType,required this.size,required this.video});
  final String path,name,contentType;
  final int size;
  final bool video;
}

class StatusItem {
  const StatusItem({required this.id, required this.userId, required this.userName, required this.avatarUrl, required this.mediaUrl, required this.mediaType, required this.caption, required this.textContent, required this.backgroundColor, required this.mine, required this.viewed, required this.liked, required this.muted, required this.viewCount, required this.likeCount, required this.createdAt});
  final String id, userId, userName, avatarUrl, mediaUrl, mediaType, caption, textContent, backgroundColor;
  final bool mine, viewed, liked, muted;
  final int viewCount,likeCount;
  final DateTime createdAt;
  factory StatusItem.fromJson(Map<String,dynamic> json)=>StatusItem(id:json['id'].toString(),userId:json['user_id'].toString(),userName:json['user_name']?.toString()??'GroopX user',avatarUrl:json['avatar_url']?.toString()??'',mediaUrl:json['media_url']?.toString()??'',mediaType:json['media_type']?.toString()??'image',caption:json['caption']?.toString()??'',textContent:json['text_content']?.toString()??'',backgroundColor:json['background_color']?.toString()??'#6335FF',mine:json['mine']==true,viewed:json['viewed']==true,liked:json['liked']==true,muted:json['muted']==true,viewCount:(json['view_count'] as num?)?.toInt()??0,likeCount:(json['like_count'] as num?)?.toInt()??0,createdAt:DateTime.tryParse(json['created_at']?.toString()??'')??DateTime.now());
  StatusItem copyWith({bool? muted,bool? viewed,bool? liked,int? likeCount})=>StatusItem(id:id,userId:userId,userName:userName,avatarUrl:avatarUrl,mediaUrl:mediaUrl,mediaType:mediaType,caption:caption,textContent:textContent,backgroundColor:backgroundColor,mine:mine,viewed:viewed??this.viewed,liked:liked??this.liked,muted:muted??this.muted,viewCount:viewCount,likeCount:likeCount??this.likeCount,createdAt:createdAt);
}

class StatusViewerItem {
  const StatusViewerItem({required this.userId,required this.name,required this.avatarUrl,required this.viewedAt,required this.reaction,required this.liked});
  factory StatusViewerItem.fromJson(Map<String,dynamic> json)=>StatusViewerItem(userId:json['user_id'].toString(),name:json['name']?.toString()??'GroopX user',avatarUrl:json['avatar_url']?.toString()??'',viewedAt:DateTime.tryParse(json['viewed_at']?.toString()??'')?.toLocal()??DateTime.now(),reaction:json['reaction']?.toString()??'',liked:json['liked']==true);
  final String userId,name,avatarUrl,reaction;
  final bool liked;
  final DateTime viewedAt;
}

class StatusViewerResult {
  const StatusViewerResult({required this.readReceiptsEnabled,required this.items});
  factory StatusViewerResult.fromJson(Map<String,dynamic> json)=>StatusViewerResult(readReceiptsEnabled:json['read_receipts_enabled']!=false,items:(json['items'] as List<dynamic>? ?? const[]).map((item)=>StatusViewerItem.fromJson(item as Map<String,dynamic>)).toList());
  final bool readReceiptsEnabled;
  final List<StatusViewerItem> items;
}

class StatusReplyResult {
  const StatusReplyResult({required this.conversationId,required this.messageId});
  factory StatusReplyResult.fromJson(Map<String,dynamic> json)=>StatusReplyResult(conversationId:json['conversation_id']?.toString()??'',messageId:json['id']?.toString()??'');
  final String conversationId,messageId;
}

class StatusPrivacyContact {
  const StatusPrivacyContact({required this.id,required this.name,required this.username,required this.avatarUrl,required this.selected});
  factory StatusPrivacyContact.fromJson(Map<String,dynamic> json)=>StatusPrivacyContact(id:json['id'].toString(),name:json['name']?.toString()??'GroopX user',username:json['username']?.toString()??'',avatarUrl:json['avatar_url']?.toString()??'',selected:json['selected']==true);
  final String id,name,username,avatarUrl;
  final bool selected;
}

class StatusPrivacySettings {
  const StatusPrivacySettings({required this.audience,required this.contacts});
  factory StatusPrivacySettings.fromJson(Map<String,dynamic> json)=>StatusPrivacySettings(audience:json['audience']?.toString()??'contacts',contacts:(json['contacts'] as List<dynamic>? ?? const[]).map((item)=>StatusPrivacyContact.fromJson(item as Map<String,dynamic>)).toList());
  final String audience;
  final List<StatusPrivacyContact> contacts;
  Set<String> get selectedUserIds=>contacts.where((contact)=>contact.selected).map((contact)=>contact.id).toSet();
}

class StatusApi {
  StatusApi._(){_dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)async{final token=await AuthSession.instance.accessToken;if(token!=null)options.headers['Authorization']='Bearer $token';handler.next(options);},onError:(error,handler)async{if(error.response?.statusCode==401&&error.requestOptions.extra['retried']!=true){try{await AuthApi.instance.refresh();error.requestOptions.headers['Authorization']='Bearer ${await AuthSession.instance.accessToken}';error.requestOptions.extra['retried']=true;return handler.resolve(await _dio.fetch(error.requestOptions));}catch(_){}}handler.next(error);}));}
  static final instance=StatusApi._();
  final Dio _dio=Dio(BaseOptions(baseUrl:const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080/api/v1'),connectTimeout:const Duration(seconds:15),receiveTimeout:const Duration(seconds:30)));
  final ImagePicker _picker=ImagePicker();

  Future<List<StatusItem>> list()async{final response=await _dio.get<Map<String,dynamic>>('/statuses');return (response.data?['items'] as List<dynamic>? ?? const []).map((item)=>StatusItem.fromJson(item as Map<String,dynamic>)).toList();}
  Future<void> createText({required String text,required String backgroundColor})=>_dio.post('/statuses/text',data:{'text':text,'background_color':backgroundColor});
  Future<StatusMediaDraft?> pickMedia({required bool video,required StatusMediaSource source})async{
    final pickerSource=source==StatusMediaSource.camera?ImageSource.camera:ImageSource.gallery;
    try{
      final XFile? picked=video
        ?await _picker.pickVideo(source:pickerSource,maxDuration:const Duration(seconds:30))
        :await _picker.pickImage(source:pickerSource,imageQuality:85,maxWidth:1920);
      if(picked==null)return null;
      final size=await File(picked.path).length();
      if(size>200*1024*1024)throw StateError('Status file 200 MB se chhoti honi chahiye');
      return StatusMediaDraft(path:picked.path,name:picked.name,contentType:_contentType(picked.name,video),size:size,video:video);
    }on PlatformException catch(failure){
      final denied=failure.code.contains('denied')||failure.code.contains('permission')||failure.code.contains('restricted');
      if(denied)throw StateError(source==StatusMediaSource.camera?'Camera permission allow karke dobara try karein.':'Photos permission allow karke dobara try karein.');
      rethrow;
    }
  }

  Future<void> uploadMedia(StatusMediaDraft draft,{String caption='',void Function(double)? onProgress})async{
    final file=File(draft.path);
    try{
      final presign=await _dio.post<Map<String,dynamic>>('/media/presign',data:{'file_name':draft.name,'content_type':draft.contentType,'size':draft.size});final uploadURL=presign.data?['upload_url']?.toString();final objectKey=presign.data?['object_key']?.toString();if(uploadURL==null||objectKey==null)throw StateError('Upload prepare nahi hua');
      await Dio().put<void>(uploadURL,data:file.openRead(),options:Options(headers:{'Content-Type':draft.contentType,'Content-Length':draft.size}),onSendProgress:(sent,total)=>onProgress?.call(total<=0?0:sent/total));
      await _dio.post('/statuses',data:{'object_key':objectKey,'file_name':draft.name,'content_type':draft.contentType,'size':draft.size,'caption':caption});
    }on DioException catch(failure){
      if(failure.response?.statusCode!=503)rethrow;
      if(draft.size>25*1024*1024)throw StateError('External storage configure hone tak status maximum 25 MB ho sakta hai');
      final form=FormData.fromMap({'caption':caption,'file':await MultipartFile.fromFile(draft.path,filename:draft.name,contentType:MediaType.parse(draft.contentType))});
      await _dio.post('/statuses/upload',data:form,options:Options(sendTimeout:const Duration(minutes:5),receiveTimeout:const Duration(minutes:5)),onSendProgress:(sent,total)=>onProgress?.call(total<=0?0:sent/total));
    }
    onProgress?.call(1);
  }
  Future<void> viewed(String id)=>_dio.post('/statuses/$id/view');
  Future<void> setLiked(String id,bool liked)async{if(liked){await _dio.post('/statuses/$id/like');}else{await _dio.delete('/statuses/$id/like');}}
  Future<StatusReplyResult> reply(String id,String text)async{final response=await _dio.post<Map<String,dynamic>>('/statuses/$id/reply',data:{'text':text});return StatusReplyResult.fromJson(response.data??const<String,dynamic>{});}
  Future<StatusReplyResult> react(String id,String emoji)async{final response=await _dio.post<Map<String,dynamic>>('/statuses/$id/reaction',data:{'emoji':emoji});return StatusReplyResult.fromJson(response.data??const<String,dynamic>{});}
  Future<int> share(String id,List<String> conversationIds)async{final response=await _dio.post<Map<String,dynamic>>('/statuses/$id/share',data:{'conversation_ids':conversationIds});return(response.data?['shared_count'] as num?)?.toInt()??0;}
  Future<StatusViewerResult> viewers(String id)async{final response=await _dio.get<Map<String,dynamic>>('/statuses/$id/views');return StatusViewerResult.fromJson(response.data??const<String,dynamic>{});}
  Future<void> delete(String id)=>_dio.delete('/statuses/$id');
  Future<StatusPrivacySettings> privacy()async{final response=await _dio.get<Map<String,dynamic>>('/status-privacy');return StatusPrivacySettings.fromJson(response.data??const<String,dynamic>{});}
  Future<void> updatePrivacy({required String audience,required Set<String> userIds})=>_dio.patch('/status-privacy',data:{'audience':audience,'user_ids':userIds.toList()..sort()});
  Future<void> mute(String userId)=>_dio.post('/status-mutes/$userId');
  Future<void> unmute(String userId)=>_dio.delete('/status-mutes/$userId');
  String _contentType(String name,bool video){final lower=name.toLowerCase();if(video)return lower.endsWith('.mov')?'video/quicktime':'video/mp4';if(lower.endsWith('.png'))return'image/png';if(lower.endsWith('.webp'))return'image/webp';return'image/jpeg';}
}
