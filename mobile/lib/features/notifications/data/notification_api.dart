import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../auth/data/auth_api.dart';

class NotificationItem {
  const NotificationItem({required this.id, required this.type, required this.title, required this.body, required this.createdAt, required this.read, required this.data});
  factory NotificationItem.fromJson(Map<String,dynamic> json) => NotificationItem(id:json['id'] as String,type:json['type'] as String,title:json['title'] as String,body:json['body'] as String,createdAt:DateTime.parse(json['created_at'] as String).toLocal(),read:json['read'] as bool? ?? false,data:json['data'] as Map<String,dynamic>? ?? const {});
  final String id,type,title,body;
  final DateTime createdAt;
  final bool read;
  final Map<String,dynamic> data;
}

class NotificationResult {
  const NotificationResult(this.items,this.unread);
  final List<NotificationItem> items;
  final int unread;
}

class NotificationApi {
  NotificationApi._(){_dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)async{final token=await AuthSession.instance.accessToken;if(token!=null)options.headers['Authorization']='Bearer $token';handler.next(options);},onError:(error,handler)async{if(error.response?.statusCode==401&&error.requestOptions.extra['retried']!=true){try{await AuthApi.instance.refresh();error.requestOptions.headers['Authorization']='Bearer ${await AuthSession.instance.accessToken}';error.requestOptions.extra['retried']=true;return handler.resolve(await _dio.fetch(error.requestOptions));}catch(_){}}handler.next(error);}));}
  static final instance=NotificationApi._();
  final Dio _dio=Dio(BaseOptions(baseUrl:const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080/api/v1'),connectTimeout:const Duration(seconds:10),receiveTimeout:const Duration(seconds:10)));
  Future<NotificationResult> list()async{final response=await _dio.get<Map<String,dynamic>>('/notifications');final data=response.data??const <String,dynamic>{};final items=(data['items'] as List<dynamic>? ?? const []).map((item)=>NotificationItem.fromJson(item as Map<String,dynamic>)).toList();final result=NotificationResult(items,data['unread'] as int? ?? 0);NotificationCenter.instance.setUnread(result.unread);return result;}
  Future<int> unreadCount()async{final response=await _dio.get<Map<String,dynamic>>('/notifications/unread');final count=response.data?['unread'] as int? ?? 0;NotificationCenter.instance.setUnread(count);return count;}
  Future<void> markRead(String id)async{await _dio.post('/notifications/$id/read');NotificationCenter.instance.decrement();}
  Future<void> markAllRead()async{await _dio.post('/notifications/read-all');NotificationCenter.instance.setUnread(0);}
  Future<void> delete(String id)=>_dio.delete('/notifications/$id');
  Future<void> clearRead()=>_dio.delete('/notifications/read');
  Future<void> registerDevice(String token,String platform)=>_dio.post('/devices',data:{'token':token,'platform':platform});
  Future<void> unregisterDevice(String token)=>_dio.delete('/devices',data:{'token':token});
}

class NotificationCenter {
  NotificationCenter._();
  static final instance=NotificationCenter._();
  final ValueNotifier<int> unread=ValueNotifier<int>(0);
  void setUnread(int value){unread.value=value<0?0:value;}
  void decrement(){if(unread.value>0)unread.value--;}
  Future<void> refresh()async{try{await NotificationApi.instance.unreadCount();}catch(_){}}
}
