import 'package:dio/dio.dart';

import '../../auth/data/auth_api.dart';

class CallSession {
  const CallSession({required this.id, required this.url, required this.token, required this.room, required this.kind});
  factory CallSession.fromJson(Map<String, dynamic> json) => CallSession(id: json['id'] as String, url: json['url'] as String, token: json['token'] as String, room: json['room'] as String, kind: json['kind'] as String);
  final String id, url, token, room, kind;
}

class CallHistoryItem {
  const CallHistoryItem({required this.id,required this.conversationId,required this.title,required this.kind,required this.status,required this.startedAt,required this.avatarUrl});
  factory CallHistoryItem.fromJson(Map<String,dynamic> json)=>CallHistoryItem(id:json['id'] as String,conversationId:json['conversation_id'] as String,title:json['title'] as String? ?? 'GroopX call',kind:json['kind'] as String? ?? 'audio',status:json['status'] as String? ?? 'ended',startedAt:DateTime.parse(json['started_at'] as String).toLocal(),avatarUrl:json['avatar_url'] as String? ?? '');
  final String id,conversationId,title,kind,status,avatarUrl;
  final DateTime startedAt;
}

class CallApi {
  CallApi._() {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await AuthSession.instance.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }, onError: (error, handler) async {
      if (error.response?.statusCode == 401 && error.requestOptions.extra['retried'] != true) {
        try {
          await AuthApi.instance.refresh();
          error.requestOptions.headers['Authorization'] = 'Bearer ${await AuthSession.instance.accessToken}';
          error.requestOptions.extra['retried'] = true;
          return handler.resolve(await _dio.fetch(error.requestOptions));
        } catch (_) {}
      }
      handler.next(error);
    }));
  }
  static final instance = CallApi._();
  final Dio _dio = Dio(BaseOptions(baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1'), connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 15)));

  Future<CallSession> start({required String conversationId, required bool video}) async {
    final response = await _dio.post<Map<String, dynamic>>('/calls/token', data: {'conversation_id':conversationId,'kind':video ? 'video' : 'audio'});
    return CallSession.fromJson(response.data!);
  }
  Future<CallSession> join(String callId) async {
    final response = await _dio.post<Map<String, dynamic>>('/calls/$callId/join');
    return CallSession.fromJson(response.data!);
  }
  Future<List<CallHistoryItem>> history() async {
    final response=await _dio.get<Map<String,dynamic>>('/calls');
    return (response.data?['items'] as List<dynamic>? ?? const []).map((item)=>CallHistoryItem.fromJson(item as Map<String,dynamic>)).toList();
  }
  Future<void> end(String callId) => _dio.post('/calls/$callId/end');
  Future<void> decline(String callId) => _dio.post('/calls/$callId/decline');
}
