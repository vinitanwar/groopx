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
  Future<void> archive(String conversationId, bool archived) async {
    if (archived) { await _dio.post('/conversations/$conversationId/archive'); } else { await _dio.delete('/conversations/$conversationId/archive'); }
  }
  Future<void> deleteConversation(String conversationId) => _dio.delete('/conversations/$conversationId');
  Future<void> updatePreferences(String conversationId, {bool? favorite, bool? muted}) => _dio.patch('/conversations/$conversationId/preferences', data: {if (favorite != null) 'favorite': favorite, if (muted != null) 'muted': muted});
  Future<void> editMessage(String messageId, String text) => _dio.patch('/messages/$messageId', data: {'text': text});
  Future<void> deleteMessage(String messageId) => _dio.delete('/messages/$messageId');
  Future<void> react(String messageId, String emoji, {required bool add}) async {
    if (add) { await _dio.post('/messages/$messageId/reactions', data: {'emoji': emoji}); } else { await _dio.delete('/messages/$messageId/reactions', data: {'emoji': emoji}); }
  }
}

class MessagePage {
  const MessagePage({required this.items, this.nextCursor});
  final List<ChatMessage> items;
  final String? nextCursor;
}
