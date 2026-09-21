class ChatSummary {
  const ChatSummary({required this.id, required this.name, required this.preview, required this.time, this.avatarUrl, this.unread = 0, this.group = false, this.online = false, this.favorite = false, this.muted = false, this.archived = false, this.color = 0xFF6633FF});
  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    final rawTime = json['last_message_at'] as String?;
    final date = rawTime == null ? null : DateTime.tryParse(rawTime)?.toLocal();
    return ChatSummary(
      id: json['id'] as String,
      name: json['title'] as String? ?? 'Conversation',
      preview: json['preview'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      time: date == null ? '' : _displayTime(date),
      unread: json['unread'] as int? ?? 0,
      group: json['kind'] != 'direct',
      favorite: json['favorite'] as bool? ?? false,
      muted: json['muted'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
    );
  }
  final String id;
  final String name;
  final String preview;
  final String time;
  final String? avatarUrl;
  final int unread;
  final bool group;
  final bool online;
  final bool favorite;
  final bool muted;
  final bool archived;
  final int color;
}

class ConversationDetails {
  const ConversationDetails({required this.title, required this.group, required this.online, required this.memberCount, this.avatarUrl, this.lastSeen, this.otherUserId, this.blockedByMe = false, this.communicationBlocked = false});
  factory ConversationDetails.fromJson(Map<String, dynamic> json) => ConversationDetails(
    title: json['title'] as String? ?? 'Conversation',
    group: json['kind'] != 'direct',
    online: json['online'] as bool? ?? false,
    memberCount: json['member_count'] as int? ?? 0,
    avatarUrl: json['avatar_url'] as String?,
    lastSeen: DateTime.tryParse(json['last_seen_at'] as String? ?? '')?.toLocal(),
    otherUserId: json['other_user_id'] as String?,
    blockedByMe: json['blocked_by_me'] as bool? ?? false,
    communicationBlocked: json['communication_blocked'] as bool? ?? false,
  );
  final String title;
  final bool group;
  final bool online;
  final int memberCount;
  final String? avatarUrl;
  final DateTime? lastSeen;
  final String? otherUserId;
  final bool blockedByMe;
  final bool communicationBlocked;
}

class MessageReaction {
  const MessageReaction({required this.emoji, required this.count, required this.mine});
  factory MessageReaction.fromJson(Map<String, dynamic> json) => MessageReaction(emoji: json['emoji'] as String, count: json['count'] as int? ?? 0, mine: json['mine'] as bool? ?? false);
  final String emoji;
  final int count;
  final bool mine;
}

class ReplyPreview {
  const ReplyPreview({required this.id, required this.text, required this.mine});
  factory ReplyPreview.fromJson(Map<String, dynamic> json) => ReplyPreview(id: json['id'] as String, text: json['text'] as String? ?? 'Message', mine: json['mine'] as bool? ?? false);
  final String id;
  final String text;
  final bool mine;
}

class ChatMessage {
  const ChatMessage({required this.id, required this.text, required this.time, required this.mine, this.status = 'sent', this.kind = 'text', this.attachment, this.edited = false, this.reactions = const [], this.reply});
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawTime = json['created_at'] as String?;
    final date = rawTime == null ? null : DateTime.tryParse(rawTime)?.toLocal();
    return ChatMessage(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      time: date == null ? '' : _displayTime(date),
      mine: json['mine'] as bool? ?? false,
      status: json['status'] as String? ?? 'sent',
      kind: json['kind'] as String? ?? 'text',
      attachment: json['attachment'] as Map<String, dynamic>?,
      edited: json['edited'] as bool? ?? false,
      reactions: (json['reactions'] as List<dynamic>? ?? const []).map((item) => MessageReaction.fromJson(item as Map<String, dynamic>)).toList(),
      reply: json['reply'] is Map<String, dynamic> ? ReplyPreview.fromJson(json['reply'] as Map<String, dynamic>) : null,
    );
  }
  final String id;
  final String text;
  final String time;
  final bool mine;
  final String status;
  final String kind;
  final Map<String, dynamic>? attachment;
  final bool edited;
  final List<MessageReaction> reactions;
  final ReplyPreview? reply;
  bool get isAttachment => kind != 'text' && attachment != null;
  bool get read => status == 'read';
  bool get delivered => status == 'delivered' || status == 'read';
}

class SharedMediaItem {
  const SharedMediaItem({required this.id,required this.kind,required this.attachment,required this.createdAt});
  factory SharedMediaItem.fromJson(Map<String,dynamic> json)=>SharedMediaItem(id:json['id'] as String,kind:json['kind'] as String? ?? 'file',attachment:json['attachment'] as Map<String,dynamic>? ?? const {},createdAt:DateTime.parse(json['created_at'] as String).toLocal());
  final String id,kind;
  final Map<String,dynamic> attachment;
  final DateTime createdAt;
  String get url=>attachment['url']?.toString() ?? '';
  String get name=>attachment['name']?.toString() ?? attachment['file_name']?.toString() ?? 'Shared ${kind.toLowerCase()}';
}

String _displayTime(DateTime value) {
  final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
  final minute = value.minute.toString().padLeft(2, '0');
  return '${hour}:${minute} ${value.hour >= 12 ? 'PM' : 'AM'}';
}
