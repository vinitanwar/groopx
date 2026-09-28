import 'package:dio/dio.dart';
import '../../auth/data/auth_api.dart';
import '../domain/chat_models.dart';

class ChatApi {
  ChatApi._() {
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
  static final instance = ChatApi._();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1'),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  Future<List<ChatSummary>> conversations({bool archived = false}) async {
    final response = await _dio.get<Map<String, dynamic>>('/conversations', queryParameters: {'archived': archived});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => ChatSummary.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<MessagePage> messagePage(String conversationId, {String? before}) async {
    final response = await _dio.get<Map<String, dynamic>>('/conversations/$conversationId/messages', queryParameters: {if (before != null) 'before': before});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return MessagePage(items: items.map((item) => ChatMessage.fromJson(item as Map<String, dynamic>)).toList().reversed.toList(), nextCursor: response.data?['next_cursor'] as String?);
  }
  Future<List<ChatMessage>> messages(String conversationId) async => (await messagePage(conversationId)).items;
  Future<List<ChatMessage>> searchMessages(String conversationId, String query) async {
    if (query.trim().length < 2) return const [];
    final response = await _dio.get<Map<String, dynamic>>('/conversations/$conversationId/messages/search', queryParameters: {'q':query.trim()});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => ChatMessage.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<List<ChatMessage>> starredMessages(String conversationId)async{final response=await _dio.get<Map<String,dynamic>>('/conversations/$conversationId/messages/starred');return(response.data?['items']as List<dynamic>? ?? const[]).map((item)=>ChatMessage.fromJson(item as Map<String,dynamic>)).toList();}
  Future<List<ChatMessage>> pinnedMessages(String conversationId)async{final response=await _dio.get<Map<String,dynamic>>('/conversations/$conversationId/messages/pinned');return(response.data?['items']as List<dynamic>? ?? const[]).map((item)=>ChatMessage.fromJson(item as Map<String,dynamic>)).toList();}
  Future<ConversationDetails> conversation(String conversationId) async {
    final response = await _dio.get<Map<String, dynamic>>('/conversations/$conversationId');
    return ConversationDetails.fromJson(response.data ?? <String, dynamic>{});
  }
  Future<List<SharedMediaItem>> sharedMedia(String conversationId) async {
    final response=await _dio.get<Map<String,dynamic>>('/conversations/$conversationId/media');
    return (response.data?['items'] as List<dynamic>? ?? const []).map((item)=>SharedMediaItem.fromJson(item as Map<String,dynamic>)).toList();
  }
  Future<void> markRead(String conversationId) async {
    await _dio.post('/conversations/$conversationId/read');
  }
  Future<ChatMessage> sendMessage(String conversationId, String text, {String? replyToId}) async {
    final response=await _dio.post<Map<String,dynamic>>('/conversations/$conversationId/messages',data:{'text':text,if(replyToId!=null)'reply_to_id':replyToId});
    return ChatMessage.fromJson(response.data!);
  }
  Future<ChatMessage> sendLocation(String conversationId,{required double latitude,required double longitude,String label='Shared location'}) async {
    final response=await _dio.post<Map<String,dynamic>>('/conversations/$conversationId/location',data:{'latitude':latitude,'longitude':longitude,'label':label});
    return ChatMessage.fromJson(response.data!);
  }
  Future<void> archive(String conversationId, bool archived) async {
    if (archived) { await _dio.post('/conversations/$conversationId/archive'); } else { await _dio.delete('/conversations/$conversationId/archive'); }
  }
  Future<void> deleteConversation(String conversationId) => _dio.delete('/conversations/$conversationId');
  Future<void> updatePreferences(String conversationId, {bool? favorite, bool? muted}) => _dio.patch('/conversations/$conversationId/preferences', data: {if (favorite != null) 'favorite': favorite, if (muted != null) 'muted': muted});
  Future<void> updateDisappearing(String conversationId,int seconds)=>_dio.patch('/conversations/$conversationId/disappearing',data:{'seconds':seconds});
  Future<void> editMessage(String messageId, String text) => _dio.patch('/messages/$messageId', data: {'text': text});
  Future<void> deleteMessage(String messageId) => _dio.delete('/messages/$messageId');
  Future<void> react(String messageId, String emoji, {required bool add}) async {
    if (add) { await _dio.post('/messages/$messageId/reactions', data: {'emoji': emoji}); } else { await _dio.delete('/messages/$messageId/reactions', data: {'emoji': emoji}); }
  }
  Future<void> setStarred(String messageId,bool starred)async{if(starred){await _dio.post('/messages/$messageId/star');}else{await _dio.delete('/messages/$messageId/star');}}
  Future<void> setPinned(String messageId,bool pinned)async{if(pinned){await _dio.post('/messages/$messageId/pin');}else{await _dio.delete('/messages/$messageId/pin');}}
  Future<MessageInfo> messageInfo(String messageId)async{final response=await _dio.get<Map<String,dynamic>>('/messages/$messageId/info');return MessageInfo.fromJson(response.data!);}
  Future<int> forwardMessage(String messageId,List<String> conversationIds)async{final response=await _dio.post<Map<String,dynamic>>('/messages/$messageId/forward',data:{'conversation_ids':conversationIds});return response.data?['forwarded_count'] as int? ?? 0;}
}

class MessageInfo{
  const MessageInfo({required this.text,required this.kind,required this.createdAt,required this.recipients});
  factory MessageInfo.fromJson(Map<String,dynamic> json)=>MessageInfo(text:json['text'] as String? ?? '',kind:json['kind'] as String? ?? 'text',createdAt:DateTime.parse(json['created_at'] as String).toLocal(),recipients:(json['recipients'] as List<dynamic>? ?? const[]).map((item)=>MessageReceipt.fromJson(item as Map<String,dynamic>)).toList());
  final String text,kind;final DateTime createdAt;final List<MessageReceipt> recipients;
}

class MessageReceipt{
  const MessageReceipt({required this.name,required this.avatarUrl,this.deliveredAt,this.readAt});
  factory MessageReceipt.fromJson(Map<String,dynamic> json)=>MessageReceipt(name:json['name'] as String? ?? 'GroopX user',avatarUrl:json['avatar_url'] as String? ?? '',deliveredAt:DateTime.tryParse(json['delivered_at'] as String? ?? '')?.toLocal(),readAt:DateTime.tryParse(json['read_at'] as String? ?? '')?.toLocal());
  final String name,avatarUrl;final DateTime? deliveredAt,readAt;
}

class MessagePage {
  const MessagePage({required this.items, this.nextCursor});
  final List<ChatMessage> items;
  final String? nextCursor;
}
