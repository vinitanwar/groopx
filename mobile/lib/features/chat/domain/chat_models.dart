class ChatSummary {
  const ChatSummary({required this.id, required this.name, required this.preview, required this.time, this.previewSenderName = '', this.previewMine = false, this.avatarUrl, this.unread = 0, this.group = false, this.online = false, this.favorite = false, this.pinned = false, this.muted = false, this.archived = false, this.color = 0xFF6633FF});
  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    final rawTime = json['last_message_at'] as String?;
    final date = rawTime == null ? null : DateTime.tryParse(rawTime)?.toLocal();
    return ChatSummary(
      id: json['id'] as String,
      name: json['title'] as String? ?? 'Conversation',
      preview: json['preview'] as String? ?? '',
      previewSenderName: json['preview_sender_name'] as String? ?? '',
      previewMine: json['preview_mine'] as bool? ?? false,
      avatarUrl: json['avatar_url'] as String?,
      time: date == null ? json['display_time'] as String? ?? '' : _displayTime(date),
      unread: json['unread'] as int? ?? 0,
      group: json['kind'] != 'direct',
      favorite: json['favorite'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      muted: json['muted'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
      online: json['online'] as bool? ?? false,
      color: json['color'] as int? ?? 0xFF6633FF,
    );
  }
  final String id;
  final String name;
  final String preview;
  final String previewSenderName;
  final bool previewMine;
  final String time;
  final String? avatarUrl;
  final int unread;
  final bool group;
  final bool online;
  final bool favorite;
  final bool pinned;
  final bool muted;
  final bool archived;
  final int color;
  String get displayPreview {
    if (!group || preview.isEmpty) return preview;
    final sender = previewMine ? 'You' : previewSenderName.trim();
    return sender.isEmpty ? preview : '$sender: $preview';
  }
  ChatSummary copyWith({bool? online})=>ChatSummary(id:id,name:name,preview:preview,time:time,previewSenderName:previewSenderName,previewMine:previewMine,avatarUrl:avatarUrl,unread:unread,group:group,online:online??this.online,favorite:favorite,pinned:pinned,muted:muted,archived:archived,color:color);
  Map<String,dynamic> toJson()=>{'id':id,'title':name,'preview':preview,'preview_sender_name':previewSenderName,'preview_mine':previewMine,'display_time':time,'avatar_url':avatarUrl,'unread':unread,'kind':group?'group':'direct','online':online,'favorite':favorite,'pinned':pinned,'muted':muted,'archived':archived,'color':color};
}

class GlobalMessageSearchResult{
  const GlobalMessageSearchResult({required this.messageId,required this.conversationId,required this.conversationTitle,required this.senderName,required this.text,required this.createdAt,required this.mine,required this.group,this.avatarUrl});
  factory GlobalMessageSearchResult.fromJson(Map<String,dynamic> json)=>GlobalMessageSearchResult(
    messageId:json['id'] as String,
    conversationId:json['conversation_id'] as String,
    conversationTitle:json['conversation_title'] as String? ?? 'Conversation',
    senderName:json['sender_name'] as String? ?? 'GroopX member',
    text:json['text'] as String? ?? '',
    createdAt:DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    mine:json['mine'] as bool? ?? false,
    group:json['conversation_kind']!='direct',
    avatarUrl:json['avatar_url'] as String?,
  );
  final String messageId,conversationId,conversationTitle,senderName,text;
  final DateTime? createdAt;
  final bool mine,group;
  final String? avatarUrl;
  String get displayTime=>createdAt==null?'':_displayTime(createdAt!);
}

class ConversationDetails {
  const ConversationDetails({required this.title, required this.group, required this.online, required this.memberCount, this.avatarUrl, this.lastSeen, this.otherUserId, this.blockedByMe = false, this.communicationBlocked = false, this.disappearingSeconds = 0, this.announcementOnly = false, this.canSend = true, this.admin = false});
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
    disappearingSeconds: json['disappearing_seconds'] as int? ?? 0,
    announcementOnly: json['announcement_only'] as bool? ?? false,
    canSend: json['can_send'] as bool? ?? true,
    admin: json['admin'] as bool? ?? false,
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
  final int disappearingSeconds;
  final bool announcementOnly;
  final bool canSend;
  final bool admin;
  ConversationDetails copyWith({bool? online, DateTime? lastSeen})=>ConversationDetails(title:title,group:group,online:online??this.online,memberCount:memberCount,avatarUrl:avatarUrl,lastSeen:lastSeen??this.lastSeen,otherUserId:otherUserId,blockedByMe:blockedByMe,communicationBlocked:communicationBlocked,disappearingSeconds:disappearingSeconds,announcementOnly:announcementOnly,canSend:canSend,admin:admin);
}

class MessageReaction {
  const MessageReaction({required this.emoji, required this.count, required this.mine});
  factory MessageReaction.fromJson(Map<String, dynamic> json) => MessageReaction(emoji: json['emoji'] as String, count: json['count'] as int? ?? 0, mine: json['mine'] as bool? ?? false);
  final String emoji;
  final int count;
  final bool mine;
  Map<String,dynamic> toJson()=>{'emoji':emoji,'count':count,'mine':mine};
}

class MessageReactionDetail {
  const MessageReactionDetail({required this.emoji,required this.userId,required this.name,required this.avatarUrl,required this.mine,required this.createdAt});
  factory MessageReactionDetail.fromJson(Map<String,dynamic> json)=>MessageReactionDetail(
    emoji:json['emoji'] as String? ?? '',
    userId:json['user_id'] as String? ?? '',
    name:json['name'] as String? ?? 'GroopX user',
    avatarUrl:json['avatar_url'] as String? ?? '',
    mine:json['mine'] as bool? ?? false,
    createdAt:DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
  );
  final String emoji,userId,name,avatarUrl;
  final bool mine;
  final DateTime? createdAt;
}

class ReplyPreview {
  const ReplyPreview({required this.id, required this.text, required this.mine, this.senderName = ''});
  factory ReplyPreview.fromJson(Map<String, dynamic> json) => ReplyPreview(id: json['id'] as String, text: json['text'] as String? ?? 'Message', mine: json['mine'] as bool? ?? false, senderName: json['sender_name'] as String? ?? '');
  final String id;
  final String text;
  final bool mine;
  final String senderName;
  Map<String,dynamic> toJson()=>{'id':id,'text':text,'mine':mine,'sender_name':senderName};
}

class StatusReplyPreview {
  const StatusReplyPreview({required this.id,required this.userId,required this.userName,required this.mediaUrl,required this.mediaType,required this.caption,required this.textContent,required this.backgroundColor,this.reaction=''});
  factory StatusReplyPreview.fromJson(Map<String,dynamic> json)=>StatusReplyPreview(
    id:json['id']?.toString()??'',
    userId:json['user_id']?.toString()??'',
    userName:json['user_name']?.toString()??'GroopX user',
    mediaUrl:json['media_url']?.toString()??'',
    mediaType:json['media_type']?.toString()??'image',
    caption:json['caption']?.toString()??'',
    textContent:json['text_content']?.toString()??'',
    backgroundColor:json['background_color']?.toString()??'#6335FF',
    reaction:json['reaction']?.toString()??'',
  );
  final String id,userId,userName,mediaUrl,mediaType,caption,textContent,backgroundColor,reaction;
  Map<String,dynamic> toJson()=>{'id':id,'user_id':userId,'user_name':userName,'media_url':mediaUrl,'media_type':mediaType,'caption':caption,'text_content':textContent,'background_color':backgroundColor,'reaction':reaction};
}

class ScheduledChatMessage {
  const ScheduledChatMessage({required this.id,required this.conversationId,required this.text,required this.scheduledAt,required this.createdAt,this.reply});
  factory ScheduledChatMessage.fromJson(Map<String,dynamic> json)=>ScheduledChatMessage(
    id:json['id'] as String,
    conversationId:json['conversation_id'] as String,
    text:json['text'] as String? ?? '',
    scheduledAt:DateTime.parse(json['scheduled_at'] as String).toLocal(),
    createdAt:DateTime.parse(json['created_at'] as String).toLocal(),
    reply:json['reply'] is Map<String,dynamic>
      ? ReplyPreview.fromJson(json['reply'] as Map<String,dynamic>)
      : null,
  );
  final String id,conversationId,text;
  final DateTime scheduledAt,createdAt;
  final ReplyPreview? reply;
}

class ChatMessage {
  const ChatMessage({required this.id, required this.text, required this.time, required this.mine, this.senderId = '', this.senderName = '', this.senderAvatarUrl = '', this.createdAt, this.status = 'sent', this.kind = 'text', this.attachment, this.edited = false, this.starred = false, this.pinned = false, this.forwarded = false, this.mentioned = false, this.mentionUserIds = const [], this.reactions = const [], this.reply, this.statusReply});
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawTime = json['created_at'] as String?;
    final date = rawTime == null ? null : DateTime.tryParse(rawTime)?.toLocal();
    return ChatMessage(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      time: date == null ? '' : _displayTime(date),
      createdAt:date,
      mine: json['mine'] as bool? ?? false,
      senderId: json['sender_id'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? '',
      senderAvatarUrl: json['sender_avatar_url'] as String? ?? '',
      status: json['status'] as String? ?? 'sent',
      kind: json['kind'] as String? ?? 'text',
      attachment: json['attachment'] as Map<String, dynamic>?,
      edited: json['edited'] as bool? ?? false,
      starred: json['starred'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      forwarded: json['forwarded'] as bool? ?? false,
      mentioned: json['mentioned'] as bool? ?? false,
      mentionUserIds: (json['mention_user_ids'] as List<dynamic>? ?? const []).map((item)=>item.toString()).toList(),
      reactions: (json['reactions'] as List<dynamic>? ?? const []).map((item) => MessageReaction.fromJson(item as Map<String, dynamic>)).toList(),
      reply: json['reply'] is Map<String, dynamic> ? ReplyPreview.fromJson(json['reply'] as Map<String, dynamic>) : null,
      statusReply: json['status_reply'] is Map ? StatusReplyPreview.fromJson(Map<String,dynamic>.from(json['status_reply'] as Map)) : null,
    );
  }
  final String id;
  final String text;
  final String time;
  final DateTime? createdAt;
  final bool mine;
  final String senderId;
  final String senderName;
  final String senderAvatarUrl;
  final String status;
  final String kind;
  final Map<String, dynamic>? attachment;
  final bool edited;
  final bool starred;
  final bool pinned;
  final bool forwarded;
  final bool mentioned;
  final List<String> mentionUserIds;
  final List<MessageReaction> reactions;
  final ReplyPreview? reply;
  final StatusReplyPreview? statusReply;
  ChatMessage copyWith({String? status,Map<String,dynamic>? attachment})=>ChatMessage(id:id,text:text,time:time,mine:mine,senderId:senderId,senderName:senderName,senderAvatarUrl:senderAvatarUrl,createdAt:createdAt,status:status??this.status,kind:kind,attachment:attachment??this.attachment,edited:edited,starred:starred,pinned:pinned,forwarded:forwarded,mentioned:mentioned,mentionUserIds:mentionUserIds,reactions:reactions,reply:reply,statusReply:statusReply);
  Map<String,dynamic> toJson()=>{'id':id,'text':text,'mine':mine,'sender_id':senderId,'sender_name':senderName,'sender_avatar_url':senderAvatarUrl,'created_at':createdAt?.toUtc().toIso8601String(),'status':status,'kind':kind,'attachment':attachment,'edited':edited,'starred':starred,'pinned':pinned,'forwarded':forwarded,'mentioned':mentioned,'mention_user_ids':mentionUserIds,'reactions':reactions.map((item)=>item.toJson()).toList(),'reply':reply?.toJson(),'status_reply':statusReply?.toJson()};
  bool get isAttachment => kind != 'text' && kind != 'system' && attachment != null;
  bool get system => kind == 'system';
  bool get viewOnce => attachment?['view_once'] == true;
  bool get viewOnceOpened => attachment?['opened'] == true;
  bool get read => status == 'read';
  bool get delivered => status == 'delivered' || status == 'read';
}

class LiveLocationSession {
  const LiveLocationSession({required this.id,required this.messageId,required this.conversationId,required this.expiresAt,required this.updatedAt});
  factory LiveLocationSession.fromJson(Map<String,dynamic> json)=>LiveLocationSession(
    id:json['id'] as String,
    messageId:json['message_id'] as String,
    conversationId:json['conversation_id'] as String,
    expiresAt:DateTime.parse(json['expires_at'] as String).toLocal(),
    updatedAt:DateTime.parse(json['updated_at'] as String).toLocal(),
  );
  final String id,messageId,conversationId;
  final DateTime expiresAt,updatedAt;
  bool get active=>expiresAt.isAfter(DateTime.now());
}

class LiveLocationStartResult {
  const LiveLocationStartResult({required this.session,required this.message});
  final LiveLocationSession session;
  final ChatMessage message;
}

class SharedMediaItem {
  const SharedMediaItem({required this.id,required this.kind,required this.attachment,required this.createdAt});
  factory SharedMediaItem.fromJson(Map<String,dynamic> json)=>SharedMediaItem(id:json['id'] as String,kind:json['kind'] as String? ?? 'file',attachment:json['attachment'] as Map<String,dynamic>? ?? const {},createdAt:DateTime.parse(json['created_at'] as String).toLocal());
  final String id,kind;
  final Map<String,dynamic> attachment;
  final DateTime createdAt;
  String get url=>attachment['url']?.toString() ?? attachment['map_url']?.toString() ?? '';
  String get name=>attachment['name']?.toString() ?? attachment['file_name']?.toString() ?? attachment['label']?.toString() ?? 'Shared ${kind.toLowerCase()}';
}

String _displayTime(DateTime value) {
  final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
  final minute = value.minute.toString().padLeft(2, '0');
  return '${hour}:${minute} ${value.hour >= 12 ? 'PM' : 'AM'}';
}
