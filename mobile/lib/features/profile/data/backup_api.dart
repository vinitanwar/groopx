import 'package:dio/dio.dart';
import '../../auth/data/auth_api.dart';

class BackupInfo {
  const BackupInfo({required this.id, required this.createdAt, required this.conversations, required this.messages});
  factory BackupInfo.fromJson(Map<String,dynamic> json)=>BackupInfo(id:json['id'] as String,createdAt:DateTime.parse(json['created_at'] as String).toLocal(),conversations:json['conversation_count'] as int? ?? 0,messages:json['message_count'] as int? ?? 0);
  final String id; final DateTime createdAt; final int conversations,messages;
}
class BackupApi {
  BackupApi._(){_dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)async{final token=await AuthSession.instance.accessToken;if(token!=null)options.headers['Authorization']='Bearer $token';handler.next(options);}));}
  static final instance=BackupApi._();
  final Dio _dio=Dio(BaseOptions(baseUrl:const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080/api/v1'),connectTimeout:const Duration(seconds:15),receiveTimeout:const Duration(seconds:30)));
  Future<BackupInfo?> latest()async{final response=await _dio.get<Map<String,dynamic>>('/backups/latest');final value=response.data?['backup'];return value is Map<String,dynamic>?BackupInfo.fromJson(value):null;}
  Future<BackupInfo> create()async{final response=await _dio.post<Map<String,dynamic>>('/backups');return BackupInfo.fromJson(response.data!['backup'] as Map<String,dynamic>);}
  Future<void> restore(String id)=>_dio.post('/backups/$id/restore');
}
