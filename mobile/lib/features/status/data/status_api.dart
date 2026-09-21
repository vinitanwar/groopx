import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/data/auth_api.dart';

class StatusItem {
  const StatusItem({required this.id, required this.userId, required this.userName, required this.avatarUrl, required this.mediaUrl, required this.mediaType, required this.caption, required this.mine, required this.viewed, required this.viewCount, required this.createdAt});
  final String id, userId, userName, avatarUrl, mediaUrl, mediaType, caption;
  final bool mine, viewed;
  final int viewCount;
  final DateTime createdAt;
  factory StatusItem.fromJson(Map<String,dynamic> json)=>StatusItem(id:json['id'].toString(),userId:json['user_id'].toString(),userName:json['user_name']?.toString()??'GroopX user',avatarUrl:json['avatar_url']?.toString()??'',mediaUrl:json['media_url'].toString(),mediaType:json['media_type'].toString(),caption:json['caption']?.toString()??'',mine:json['mine']==true,viewed:json['viewed']==true,viewCount:json['view_count'] as int? ?? 0,createdAt:DateTime.tryParse(json['created_at']?.toString()??'')??DateTime.now());
}

class StatusApi {
  StatusApi._(){_dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)async{final token=await AuthSession.instance.accessToken;if(token!=null)options.headers['Authorization']='Bearer $token';handler.next(options);},onError:(error,handler)async{if(error.response?.statusCode==401&&error.requestOptions.extra['retried']!=true){try{await AuthApi.instance.refresh();error.requestOptions.headers['Authorization']='Bearer ${await AuthSession.instance.accessToken}';error.requestOptions.extra['retried']=true;return handler.resolve(await _dio.fetch(error.requestOptions));}catch(_){}}handler.next(error);}));}
  static final instance=StatusApi._();
  final Dio _dio=Dio(BaseOptions(baseUrl:const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080/api/v1'),connectTimeout:const Duration(seconds:15),receiveTimeout:const Duration(seconds:30)));
  final ImagePicker _picker=ImagePicker();

  Future<List<StatusItem>> list()async{final response=await _dio.get<Map<String,dynamic>>('/statuses');return (response.data?['items'] as List<dynamic>? ?? const []).map((item)=>StatusItem.fromJson(item as Map<String,dynamic>)).toList();}
  Future<bool> pickAndUpload({required bool video,String caption=''})async{
    final XFile? picked=video?await _picker.pickVideo(source:ImageSource.gallery,maxDuration:const Duration(seconds:30)):await _picker.pickImage(source:ImageSource.gallery,imageQuality:85,maxWidth:1920);
    if(picked==null)return false;final file=File(picked.path);final size=await file.length();if(size>200*1024*1024)throw StateError('Status file 200 MB se chhoti honi chahiye');final contentType=_contentType(picked.name,video);
    final presign=await _dio.post<Map<String,dynamic>>('/media/presign',data:{'file_name':picked.name,'content_type':contentType,'size':size});final uploadURL=presign.data?['upload_url']?.toString();final objectKey=presign.data?['object_key']?.toString();if(uploadURL==null||objectKey==null)throw StateError('Upload prepare nahi hua');
    await Dio().put<void>(uploadURL,data:file.openRead(),options:Options(headers:{'Content-Type':contentType,'Content-Length':size}));
    await _dio.post('/statuses',data:{'object_key':objectKey,'file_name':picked.name,'content_type':contentType,'size':size,'caption':caption});return true;
  }
  Future<void> viewed(String id)=>_dio.post('/statuses/$id/view');
  Future<void> delete(String id)=>_dio.delete('/statuses/$id');
  String _contentType(String name,bool video){final lower=name.toLowerCase();if(video)return lower.endsWith('.mov')?'video/quicktime':'video/mp4';if(lower.endsWith('.png'))return'image/png';if(lower.endsWith('.webp'))return'image/webp';return'image/jpeg';}
}
