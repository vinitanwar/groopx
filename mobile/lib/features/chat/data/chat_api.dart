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
  Future<List<ChatMessage>> exportMessages(String conversationId)async{final all=<ChatMessage>[];String? cursor;do{final page=await messagePage(conversationId,before:cursor);all.insertAll(0,page.items);cursor=page.nextCursor;}while(cursor!=null&&all.length<10000);return all;}
  Future<List<ChatMessage>> searchMessages(String conversationId, String query) async {
    if (query.trim().length < 2) return const [];
    final response = await _dio.get<Map<String, dynamic>>('/conversations/$conversationId/messages/search', queryParameters: {'q':query.trim()});
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => ChatMessage.fromJson(item as Map<String, dynamic>)).toList();
  }
  Future<List<GlobalMessageSearchResult>> searchAllMessages(String query)async{
    if(query.trim().length<2)return const[];
    final response=await _dio.get<Map<String,dynamic>>('/messages/search',queryParameters:{'q':query.trim()});
    return(response.data?['items'] as List<dynamic>? ?? const[]).map((item)=>GlobalMessageSearchResult.fromJson(item as Map<String,dynamic>)).toList();
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
  Future<void> setUnread(String conversationId,bool unread) async { await _dio.patch('/conversations/$conversationId/read-state',data:{'unread':unread}); }
  Future<ChatMessage> sendMessage(String conversationId, String text, {String? replyToId,String? clientMessageId,List<String> mentionUserIds=const[]}) async {
    final response=await _dio.post<Map<String,dynamic>>('/conversations/$conversationId/messages',data:{'text':text,if(replyToId!=null)'reply_to_id':replyToId,if(clientMessageId!=null)'client_message_id':clientMessageId,if(mentionUserIds.isNotEmpty)'mention_user_ids':mentionUserIds});
    return ChatMessage.fromJson(response.data!);
  }
  Future<List<ScheduledChatMessage>> scheduledMessages(String conversationId)async{
    final response=await _dio.get<Map<String,dynamic>>('/conversations/$conversationId/scheduled-messages');
    return(response.data?['items'] as List<dynamic>? ?? const[]).map((item)=>ScheduledChatMessage.fromJson(item as Map<String,dynamic>)).toList();
  }
  Future<ScheduledChatMessage> scheduleMessage(String conversationId,String text,DateTime scheduledAt,{String? replyToId})async{
    final response=await _dio.post<Map<String,dynamic>>('/conversations/$conversationId/scheduled-messages',data:{'text':text,'scheduled_at':scheduledAt.toUtc().toIso8601String(),if(replyToId!=null)'reply_to_id':replyToId});
    return ScheduledChatMessage.fromJson(response.data!);
  }
  Future<ScheduledChatMessage> updateScheduledMessage(String id,{String? text,DateTime? scheduledAt})async{
    final response=await _dio.patch<Map<String,dynamic>>('/scheduled-messages/$id',data:{if(text!=null)'text':text,if(scheduledAt!=null)'scheduled_at':scheduledAt.toUtc().toIso8601String()});
    return ScheduledChatMessage.fromJson(response.data!);
  }
  Future<void> cancelScheduledMessage(String id)=>_dio.delete('/scheduled-messages/$id');
  Future<ChatMessage> sendLocation(String conversationId,{required double latitude,required double longitude,String label='Shared location'}) async {
    final response=await _dio.post<Map<String,dynamic>>('/conversations/$conversationId/location',data:{'latitude':latitude,'longitude':longitude,'label':label});
    return ChatMessage.fromJson(response.data!);
  }
  Future<ChatMessage> sendContact(String conversationId,{required String name,required String phone})async{
    final response=await _dio.post<Map<String,dynamic>>('/conversations/$conversationId/contact',data:{'name':name,'phone':phone});
    return ChatMessage.fromJson(response.data!);
  }
  Future<ChatMessage> createPoll(String conversationId,{required String question,required List<String> options,required bool allowMultiple})async{
    final response=await _dio.post<Map<String,dynamic>>('/conversations/$conversationId/polls',data:{'question':question,'options':options,'allow_multiple':allowMultiple});
    return ChatMessage.fromJson(response.data!);
  }
  Future<Map<String,dynamic>> setPollVotes(String pollId,List<String> optionIds)async{
    final response=await _dio.put<Map<String,dynamic>>('/polls/$pollId/votes',data:{'option_ids':optionIds});
    return Map<String,dynamic>.from(response.data?['attachment'] as Map? ?? const <String,dynamic>{});
  }
  Future<Map<String,dynamic>> closePoll(String pollId)async{
    final response=await _dio.post<Map<String,dynamic>>('/polls/$pollId/close');
    return Map<String,dynamic>.from(response.data?['attachment'] as Map? ?? const <String,dynamic>{});
  }
  Future<LiveLocationStartResult> startLiveLocation(String conversationId,{required double latitude,required double longitude,required double accuracyMeters,required int durationSeconds,required String trackingKey})async{
    final response=await _dio.post<Map<String,dynamic>>('/conversations/$conversationId/live-location',data:{'latitude':latitude,'longitude':longitude,'accuracy_meters':accuracyMeters,'duration_seconds':durationSeconds,'tracking_key':trackingKey});
    final data=response.data!;
    return LiveLocationStartResult(session:LiveLocationSession.fromJson(Map<String,dynamic>.from(data['live_location'] as Map)),message:ChatMessage.fromJson(Map<String,dynamic>.from(data['message'] as Map)));
  }
  Future<List<LiveLocationSession>> activeLiveLocations(String trackingKey)async{
    final response=await _dio.get<Map<String,dynamic>>('/live-locations/active',options:Options(headers:{'X-Live-Location-Device':trackingKey}));
    return(response.data?['items'] as List<dynamic>? ?? const[]).map((item)=>LiveLocationSession.fromJson(Map<String,dynamic>.from(item as Map))).toList();
  }
  Future<List<LiveLocationSession>> updateActiveLiveLocations({required double latitude,required double longitude,required double accuracyMeters,required String trackingKey})async{
    final response=await _dio.patch<Map<String,dynamic>>('/live-locations/active',data:{'latitude':latitude,'longitude':longitude,'accuracy_meters':accuracyMeters},options:Options(headers:{'X-Live-Location-Device':trackingKey}));
    return(response.data?['items'] as List<dynamic>? ?? const[]).map((item)=>LiveLocationSession.fromJson(Map<String,dynamic>.from(item as Map))).toList();
  }
  Future<void> stopActiveLiveLocations(String trackingKey)=>_dio.delete('/live-locations/active',options:Options(headers:{'X-Live-Location-Device':trackingKey}));
  Future<void> stopLiveLocation(String id)=>_dio.delete('/live-locations/$id');
  Future<void> archive(String conversationId, bool archived) async {
    if (archived) { await _dio.post('/conversations/$conversationId/archive'); } else { await _dio.delete('/conversations/$conversationId/archive'); }
  }
  Future<void> deleteConversation(String conversationId) => _dio.delete('/conversations/$conversationId');
  Future<void> clearConversation(String conversationId) => _dio.post('/conversations/$conversationId/clear');
  Future<void> updatePreferences(String conversationId, {bool? favorite, bool? pinned, bool? muted,int? muteSeconds}) => _dio.patch('/conversations/$conversationId/preferences', data: {if (favorite != null) 'favorite': favorite,if(pinned!=null)'pinned':pinned, if (muted != null) 'muted': muted,if(muteSeconds!=null)'mute_seconds':muteSeconds});
  Future<void> updateDisappearing(String conversationId,int seconds)=>_dio.patch('/conversations/$conversationId/disappearing',data:{'seconds':seconds});
  Future<void> editMessage(String messageId, String text) => _dio.patch('/messages/$messageId', data: {'text': text});
  Future<void> deleteMessage(String messageId,{required bool forEveryone}) => _dio.delete('/messages/$messageId',queryParameters:{'scope':forEveryone?'everyone':'me'});
  Future<void> react(String messageId, String emoji, {required bool add}) async {
    if (add) { await _dio.post('/messages/$messageId/reactions', data: {'emoji': emoji}); } else { await _dio.delete('/messages/$messageId/reactions', data: {'emoji': emoji}); }
  }
  Future<List<MessageReactionDetail>> reactionDetails(String messageId)async{final response=await _dio.get<Map<String,dynamic>>('/messages/$messageId/reactions');return(response.data?['items'] as List<dynamic>? ?? const[]).map((item)=>MessageReactionDetail.fromJson(item as Map<String,dynamic>)).toList();}
  Future<void> setStarred(String messageId,bool starred)async{if(starred){await _dio.post('/messages/$messageId/star');}else{await _dio.delete('/messages/$messageId/star');}}
  Future<void> setPinned(String messageId,bool pinned)async{if(pinned){await _dio.post('/messages/$messageId/pin');}else{await _dio.delete('/messages/$messageId/pin');}}
  Future<MessageInfo> messageInfo(String messageId)async{final response=await _dio.get<Map<String,dynamic>>('/messages/$messageId/info');return MessageInfo.fromJson(response.data!);}
  Future<int> forwardMessage(String messageId,List<String> conversationIds)async{final response=await _dio.post<Map<String,dynamic>>('/messages/$messageId/forward',data:{'conversation_ids':conversationIds});return response.data?['forwarded_count'] as int? ?? 0;}
  Future<Map<String,dynamic>> openViewOnce(String messageId)async{final response=await _dio.post<Map<String,dynamic>>('/messages/$messageId/view-once/open');return Map<String,dynamic>.from(response.data??const <String,dynamic>{});}
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
