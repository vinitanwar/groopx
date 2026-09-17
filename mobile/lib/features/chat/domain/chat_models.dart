class ChatSummary {
  const ChatSummary({required this.id, required this.name, required this.preview, required this.time, this.unread = 0, this.group = false, this.online = false, this.color = 0xFF6633FF});
  final String id;
  final String name;
  final String preview;
  final String time;
  final int unread;
  final bool group;
  final bool online;
  final int color;
}

class ChatMessage {
  const ChatMessage({required this.id, required this.text, required this.time, required this.mine, this.read = true});
  final String id;
  final String text;
  final String time;
  final bool mine;
  final bool read;
}

