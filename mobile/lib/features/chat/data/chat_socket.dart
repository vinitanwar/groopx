import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../auth/data/auth_api.dart';

class ChatSocket {
  ChatSocket._(this._channel);
  final WebSocketChannel _channel;

  static Future<ChatSocket> connect(String conversationId) async {
    final token = await AuthSession.instance.accessToken;
    if (token == null) throw StateError('Authentication is required');
    final base = const String.fromEnvironment('WS_BASE_URL', defaultValue: 'ws://10.0.2.2:8080');
    final uri = Uri.parse('$base/api/v1/ws').replace(queryParameters: {
      'conversation_id': conversationId,
      'access_token': token,
    });
    return ChatSocket._(WebSocketChannel.connect(uri));
  }

  Stream<Map<String, dynamic>> get events => _channel.stream.map((event) {
    final json = jsonDecode(event as String) as Map<String, dynamic>;
    if (json['type'] == 'error') throw StateError(json['error'] as String? ?? 'Chat error');
    return json;
  });

  void send(String text, {String? replyToId}) => _channel.sink.add(jsonEncode({'type': 'message', 'text': text, if (replyToId != null) 'reply_to_id': replyToId}));
  void sendTyping(bool typing) => _channel.sink.add(jsonEncode({'type': 'typing', 'typing': typing}));
  Future<void> close() => _channel.sink.close();
}
