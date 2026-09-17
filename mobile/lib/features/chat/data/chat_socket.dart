import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/chat_models.dart';

class ChatSocket {
  ChatSocket(String conversationId)
      : _channel = WebSocketChannel.connect(Uri.parse('${const String.fromEnvironment('WS_BASE_URL', defaultValue: 'ws://10.0.2.2:8080')}/api/v1/ws?conversation_id=$conversationId'));
  final WebSocketChannel _channel;

  Stream<ChatMessage> get messages => _channel.stream.map((event) {
        final json = jsonDecode(event as String) as Map<String, dynamic>;
        return ChatMessage(id: json['id'] as String, text: json['text'] as String, time: json['time'] as String, mine: json['mine'] as bool? ?? false);
      });

  void send(String text) => _channel.sink.add(jsonEncode({'text': text}));
  Future<void> close() => _channel.sink.close();
}

