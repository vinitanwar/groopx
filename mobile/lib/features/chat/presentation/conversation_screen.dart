import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/groopx_ui.dart';
import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/device_contacts.dart';
import '../../contacts/data/social_api.dart';
import '../../reminders/data/reminder_api.dart';
import '../data/chat_api.dart';
import '../data/chat_socket.dart';
import '../data/live_location_service.dart';
import '../data/media_api.dart';
import '../data/voice_playback.dart';
import '../domain/chat_models.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId,this.initialMessageId});
  final String conversationId;
  final String? initialMessageId;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> with WidgetsBindingObserver {
  static const voiceRecorder=MethodChannel('com.futureittouch.groopx/voice_recorder');
  final input = TextEditingController();
  final inputFocus=FocusNode();
  final scrollController = ScrollController();
  ChatSocket? socket;
  StreamSubscription<Map<String, dynamic>>? subscription;
  final messages = <ChatMessage>[];
  final messageKeys=<String,GlobalKey>{};
  final selectedMessageIds=<String>{};
  ConversationDetails? details;
  ChatMessage? pinnedBanner;
  ChatMessage? replyingTo;
  Timer? typingTimer;
  Timer? draftTimer;
  Timer? reconnectTimer;
  final typingUsers=<String,String>{};
  final typingExpiryTimers=<String,Timer>{};
  final selectedMentions=<String,String>{};
  List<GroupMember> mentionMembers=const[];
  bool mentionMembersLoading=false;
  bool mentionMembersLoaded=false;
  String? mentionMembersError;
  bool loadingOlder = false;
  bool showJumpToLatest=false;
  int newMessageCount=0;
  String? highlightedMessageId;
  String? nextCursor;
  bool loading = true;
  bool uploading = false;
  bool schedulingMessage=false;
  bool recording = false;
  int recordingSeconds = 0;
  Timer? recordingTimer;
  double uploadProgress = 0;
  String? error;
  String chatTheme='default';
  bool pinBannerDismissed=false;
  bool realtimeOffline=false;
  bool reconnecting=false;
  int reconnectAttempts=0;
  bool appPaused=false;
  bool initialJumpDone=false;
  bool selectionBusy=false;
  Future<void> pendingWrite=Future.value();

  bool get _selectionMode=>selectedMessageIds.isNotEmpty;
  bool get _sendingDisabled=>details?.communicationBlocked==true||details?.canSend==false;
  List<ChatMessage> get _selectedMessages=>messages.where((item)=>selectedMessageIds.contains(item.id)).toList();
  ChatMessage? get _singleSelectedMessage{final selected=_selectedMessages;return selected.length==1?selected.first:null;}

  @override
  void initState() { super.initState();WidgetsBinding.instance.addObserver(this); scrollController.addListener(_onScroll); unawaited(LiveLocationService.instance.initialize()); _restoreDraft(); _restoreTheme(); _loadPinnedBanner(); _startConversation(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.paused||state==AppLifecycleState.detached){appPaused=true;reconnectTimer?.cancel();_clearTypingUsers();subscription?.cancel();subscription=null;socket?.close();socket=null;}else if(state==AppLifecycleState.resumed){final wasPaused=appPaused;appPaused=false;if(wasPaused)_reconnectLive();}}

  String get _draftKey=>'chat_draft_${widget.conversationId}';
  String get _draftMentionsKey=>'chat_draft_mentions_${widget.conversationId}';
  String get _pendingKey=>'chat_pending_${widget.conversationId}';
  String get _historyKey=>'chat_history_${widget.conversationId}';
  Future<void> _startConversation()async{await _restoreMessageCache();await _connect();}
  Future<void> _saveMessageCache()async{final cached=messages.where((item)=>!item.id.startsWith('local-')).toList();final limited=cached.length>200?cached.sublist(cached.length-200):cached;final preferences=await SharedPreferences.getInstance();if(limited.isNotEmpty)await preferences.setString(_historyKey,jsonEncode(limited.map((item)=>item.toJson()).toList()));}
  Future<void> _restoreMessageCache()async{final preferences=await SharedPreferences.getInstance();final raw=preferences.getString(_historyKey);if(raw==null||raw.isEmpty)return;try{final cached=(jsonDecode(raw) as List).whereType<Map>().map((item)=>ChatMessage.fromJson(Map<String,dynamic>.from(item))).toList();if(mounted&&cached.isNotEmpty)setState((){messages..clear()..addAll(cached);loading=false;realtimeOffline=true;});}catch(_){await preferences.remove(_historyKey);}}
  Future<void> _savePendingMessages()async{
    final snapshot=messages.where((item)=>item.id.startsWith('local-')).map((item)=>{
      'id':item.id,'text':item.text,'created_at':item.createdAt?.toIso8601String(),
      if(item.mentionUserIds.isNotEmpty)'mention_user_ids':item.mentionUserIds,
      if(item.reply!=null)'reply':{'id':item.reply!.id,'text':item.reply!.text,'mine':item.reply!.mine,'sender_name':item.reply!.senderName},
    }).toList();
    pendingWrite=pendingWrite.then((_ )async{final preferences=await SharedPreferences.getInstance();if(snapshot.isEmpty){await preferences.remove(_pendingKey);}else{await preferences.setString(_pendingKey,jsonEncode(snapshot));}});
    await pendingWrite;
  }
  Future<void> _restorePendingMessages()async{
    final preferences=await SharedPreferences.getInstance();final raw=preferences.getString(_pendingKey);if(raw==null||raw.isEmpty)return;
    try{
      final restored=(jsonDecode(raw) as List).whereType<Map>().map((value){final item=Map<String,dynamic>.from(value);final replyValue=item['reply'];final reply=replyValue is Map?ReplyPreview.fromJson(Map<String,dynamic>.from(replyValue)):null;final created=DateTime.tryParse(item['created_at']?.toString()??'')?.toLocal()??DateTime.now();final mentionUserIds=(item['mention_user_ids'] as List<dynamic>? ?? const[]).map((value)=>value.toString()).toList();return ChatMessage(id:item['id'].toString(),text:item['text']?.toString()??'',time:TimeOfDay.fromDateTime(created).format(context),mine:true,createdAt:created,status:'failed',mentionUserIds:mentionUserIds,reply:reply);}).toList();
      if(mounted)setState((){for(final message in restored){if(!messages.any((item)=>item.id==message.id))messages.add(message);}});
    }catch(_){await preferences.remove(_pendingKey);}
  }
  Future<void> _restoreDraft()async{final preferences=await SharedPreferences.getInstance();final draft=preferences.getString(_draftKey)??'';final rawMentions=preferences.getString(_draftMentionsKey);final restored=<String,String>{};if(rawMentions!=null){try{final value=jsonDecode(rawMentions);if(value is Map){for(final entry in value.entries){final id=entry.key.toString(),handle=entry.value.toString();if(id.isNotEmpty&&_containsMentionToken(draft,handle))restored[id]=handle;}}}catch(_){await preferences.remove(_draftMentionsKey);}}if(mounted&&input.text.isEmpty){input.text=draft;input.selection=TextSelection.collapsed(offset:draft.length);setState((){selectedMentions..clear()..addAll(restored);});}}
  void _scheduleDraftSave(String value){draftTimer?.cancel();final mentionSnapshot=Map<String,String>.from(selectedMentions);draftTimer=Timer(const Duration(milliseconds:350),()async{final preferences=await SharedPreferences.getInstance();final draft=value.trimRight();if(draft.isEmpty){await preferences.remove(_draftKey);await preferences.remove(_draftMentionsKey);}else{await preferences.setString(_draftKey,draft);if(mentionSnapshot.isEmpty){await preferences.remove(_draftMentionsKey);}else{await preferences.setString(_draftMentionsKey,jsonEncode(mentionSnapshot));}}});}
  Future<void> _clearDraft()async{draftTimer?.cancel();final preferences=await SharedPreferences.getInstance();await Future.wait([preferences.remove(_draftKey),preferences.remove(_draftMentionsKey)]);}
  Future<void> _restoreTheme()async{final preferences=await SharedPreferences.getInstance();if(mounted)setState(()=>chatTheme=preferences.getString('chat_theme_${widget.conversationId}')??'default');}
  Color get _chatBackground=>switch(chatTheme){'lavender'=>const Color(0xFFF0EAFF),'blue'=>const Color(0xFFEAF5FF),'green'=>const Color(0xFFEAF8F0),'dark'=>const Color(0xFF202333),_=>const Color(0xFFFBFAFD)};
  bool _sameDay(DateTime? first,DateTime? second)=>first!=null&&second!=null&&first.year==second.year&&first.month==second.month&&first.day==second.day;
  String _dateLabel(DateTime date){final now=DateTime.now();final today=DateTime(now.year,now.month,now.day);final value=DateTime(date.year,date.month,date.day);final days=today.difference(value).inDays;if(days==0)return'Today';if(days==1)return'Yesterday';const weekdays=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];if(days>1&&days<7)return weekdays[value.weekday-1];const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];return value.year==today.year?'${value.day} ${months[value.month-1]}':'${value.day} ${months[value.month-1]} ${value.year}';}
  Widget _dateSeparator(DateTime date)=>Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Center(child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:5),decoration:BoxDecoration(color:const Color(0xFFECEAF1),borderRadius:BorderRadius.circular(12)),child:Text(_dateLabel(date),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w600,color:authMuted)))));

  void _handleSocketEvent(Map<String,dynamic> event){
    if (event['type'] == 'message') {final incoming=ChatMessage.fromJson(event);if(!incoming.mine&&incoming.senderId.isNotEmpty)_removeTypingUser(incoming.senderId);final awayFromLatest=scrollController.hasClients&&scrollController.position.pixels>80;if(mounted&&!messages.any((item)=>item.id==incoming.id)){setState((){messages.add(incoming);if(awayFromLatest&&!incoming.mine)newMessageCount++;});_saveMessageCache();}if(!awayFromLatest)ChatApi.instance.markRead(widget.conversationId);
    }else if(event['type']=='live_location_update'){
      LiveLocationService.instance.handleRealtimeEvent(event);
      final messageID=event['message_id']?.toString()??'';final value=event['attachment'];final index=messages.indexWhere((item)=>item.id==messageID);
      if(index>=0&&value is Map&&mounted){setState(()=>messages[index]=messages[index].copyWith(attachment:Map<String,dynamic>.from(value)));_saveMessageCache();}
    }else if(event['type']=='poll_update'){
      final messageID=event['message_id']?.toString()??'';final value=event['attachment'];final index=messages.indexWhere((item)=>item.id==messageID);
      if(index>=0&&value is Map&&mounted){final incoming=Map<String,dynamic>.from(value);_updatePollMessage(messageID,event['mine']==true?incoming:_mergePollAttachment(messages[index].attachment,incoming));}
    }else if(event['type']=='view_once_opened'){
      final messageID=event['message_id']?.toString()??'';final index=messages.indexWhere((item)=>item.id==messageID);
      if(index>=0&&mounted){final attachment=Map<String,dynamic>.from(messages[index].attachment??const{});attachment['opened_count']=(event['opened_count'] as num?)?.toInt()??(attachment['opened_count'] as num?)?.toInt()??0;if(event['mine']==true){attachment['opened']=true;attachment['available']=false;}_updateViewOnceMessage(messageID,attachment);}
    }else if(event['type']=='message_update'||event['type']=='message_delete'||event['type']=='reaction'||event['type']=='message_pin'){_refreshMessages();if(event['type']=='message_pin')_loadPinnedBanner(show:true);
    }else if(event['type']=='group_member_update'){
      if(mounted)setState((){mentionMembers=const[];mentionMembersLoaded=false;mentionMembersError=null;});
      unawaited(_refreshGroupMemberData());
    }else if(event['type']=='disappearing_update'||event['type']=='group_settings_update'){_refreshDetails();
    }else if(event['type']=='read_receipt'||event['type']=='delivery_receipt'){_refreshMessages();
    }else if(event['type']=='presence'&&event['mine']!=true&&mounted&&details!=null){setState(()=>details=details!.copyWith(online:event['online']==true,lastSeen:event['online']==true?details!.lastSeen:DateTime.now()));
    }else if(event['type']=='typing'&&event['mine']!=true){_handleTypingEvent(event);}
  }

  Map<String,dynamic> _mergePollAttachment(Map<String,dynamic>? current,Map<String,dynamic> incoming){
    final selected=<String,bool>{};
    for(final value in current?['options'] as List<dynamic>? ?? const[]){if(value is Map){final option=Map<String,dynamic>.from(value);selected[option['id']?.toString()??'']=option['selected']==true;}}
    final merged=Map<String,dynamic>.from(incoming);
    merged['options']=(incoming['options'] as List<dynamic>? ?? const[]).map((value){final option=Map<String,dynamic>.from(value as Map);final id=option['id']?.toString()??'';if(selected.containsKey(id))option['selected']=selected[id];return option;}).toList();
    return merged;
  }

  void _updatePollMessage(String messageID,Map<String,dynamic> attachment){
    final index=messages.indexWhere((item)=>item.id==messageID);if(index<0||!mounted)return;
    setState(()=>messages[index]=messages[index].copyWith(attachment:attachment));
    unawaited(_saveMessageCache());
  }
  void _updateViewOnceMessage(String messageID,Map<String,dynamic> attachment){
    final index=messages.indexWhere((item)=>item.id==messageID);if(index<0||!mounted)return;
    setState(()=>messages[index]=messages[index].copyWith(attachment:attachment));
    unawaited(_saveMessageCache());
  }
  void _handleTypingEvent(Map<String,dynamic> event){
    final userID=event['user_id']?.toString()??'';
    if(userID.isEmpty)return;
    typingExpiryTimers.remove(userID)?.cancel();
    if(event['typing']!=true){_removeTypingUser(userID);return;}
    final name=(event['sender_name']?.toString().trim().isNotEmpty??false)?event['sender_name'].toString().trim():'GroopX member';
    if(mounted)setState(()=>typingUsers[userID]=name);else typingUsers[userID]=name;
    typingExpiryTimers[userID]=Timer(const Duration(seconds:4),()=>_removeTypingUser(userID));
  }
  void _removeTypingUser(String userID){typingExpiryTimers.remove(userID)?.cancel();if(!typingUsers.containsKey(userID))return;if(mounted)setState(()=>typingUsers.remove(userID));else typingUsers.remove(userID);}
  void _clearTypingUsers({bool notify=true}){for(final timer in typingExpiryTimers.values){timer.cancel();}typingExpiryTimers.clear();if(typingUsers.isEmpty)return;if(notify&&mounted){setState(typingUsers.clear);}else{typingUsers.clear();}}
  String get _typingLabel{final names=typingUsers.values.toList();if(names.isEmpty)return'';if(details?.group!=true)return'Typing...';if(names.length==1)return'${names.first} is typing...';if(names.length==2)return'${names.first} and ${names.last} are typing...';return'${names.first} and ${names.length-1} others are typing...';}
  Future<void> _attachSocket(ChatSocket connected)async{await subscription?.cancel();socket?.close();_clearTypingUsers();socket=connected;subscription=connected.events.listen(_handleSocketEvent,onError:(_)=>_scheduleReconnect(),onDone:_scheduleReconnect);}
  void _scheduleReconnect(){if(!mounted||appPaused||reconnectTimer?.isActive==true||reconnecting)return;_clearTypingUsers();setState(()=>realtimeOffline=true);const delays=[2,4,8,15,30];final delay=delays[reconnectAttempts.clamp(0,delays.length-1).toInt()];reconnectTimer=Timer(Duration(seconds:delay),_reconnectLive);}
  Future<void> _reconnectLive()async{if(reconnecting||appPaused)return;reconnectTimer?.cancel();reconnecting=true;if(mounted)setState(()=>realtimeOffline=true);try{final connected=await ChatSocket.connect(widget.conversationId);if(appPaused){connected.close();return;}await _attachSocket(connected);await Future.wait([_refreshMessages(),_refreshDetails()]);await _retryFailedMessages();reconnectAttempts=0;if(mounted)setState((){realtimeOffline=false;error=null;});}catch(_){reconnectAttempts++;}finally{reconnecting=false;if(realtimeOffline)_scheduleReconnect();}}

  Future<void> _connect() async {
    try {
	  final results = await Future.wait([ChatApi.instance.messagePage(widget.conversationId), ChatApi.instance.conversation(widget.conversationId)]);
	  final page = results[0] as MessagePage;
	  final history = page.items;
      final info = results[1] as ConversationDetails;
      final connected = await ChatSocket.connect(widget.conversationId);
      if(appPaused){connected.close();if(mounted)setState((){loading=false;realtimeOffline=true;});return;}
      await _attachSocket(connected);
      await ChatApi.instance.markRead(widget.conversationId);
      if (mounted) setState(() { messages..clear()..addAll(history); nextCursor = page.nextCursor; details = info; socket = connected; loading = false; });
      if(mounted&&_mentionDraftRange!=null)unawaited(_loadMentionMembers());
      if(widget.initialMessageId?.isNotEmpty==true&&!initialJumpDone){initialJumpDone=true;WidgetsBinding.instance.addPostFrameCallback((_)=>unawaited(_openInitialMessage()));}
      await _saveMessageCache();await _restorePendingMessages();await _retryFailedMessages();
    } catch (_) {await _restorePendingMessages();if (mounted) setState(() { loading = false; error = 'Unable to open this conversation'; }); }
  }

  @override
  void dispose() {WidgetsBinding.instance.removeObserver(this); typingTimer?.cancel();_clearTypingUsers(notify:false); draftTimer?.cancel();reconnectTimer?.cancel(); final draft=input.text.trimRight(),mentionSnapshot=Map<String,String>.from(selectedMentions);SharedPreferences.getInstance().then((preferences)async{if(draft.isEmpty){await preferences.remove(_draftKey);await preferences.remove(_draftMentionsKey);}else{await preferences.setString(_draftKey,draft);if(mentionSnapshot.isEmpty){await preferences.remove(_draftMentionsKey);}else{await preferences.setString(_draftMentionsKey,jsonEncode(mentionSnapshot));}}});_savePendingMessages(); recordingTimer?.cancel(); if(recording)voiceRecorder.invokeMethod<void>('cancel'); subscription?.cancel(); socket?.close(); scrollController.dispose(); inputFocus.dispose(); input.dispose(); super.dispose(); }

  void _onScroll(){if(!scrollController.hasClients)return;final pixels=scrollController.position.pixels;final show=pixels>280;if(mounted&&(show!=showJumpToLatest||(pixels<40&&newMessageCount>0)))setState((){showJumpToLatest=show;if(pixels<40)newMessageCount=0;});if(pixels<40)ChatApi.instance.markRead(widget.conversationId);if(pixels>=scrollController.position.maxScrollExtent-140)_loadOlder();}
  void _jumpToLatest(){if(!scrollController.hasClients)return;setState(()=>newMessageCount=0);ChatApi.instance.markRead(widget.conversationId);scrollController.animateTo(0,duration:const Duration(milliseconds:280),curve:Curves.easeOut);}
  Future<void> _openInitialMessage()async{await Future<void>.delayed(const Duration(milliseconds:120));final target=widget.initialMessageId;if(mounted&&target!=null&&target.isNotEmpty)await _jumpToMessage(target);}
  Future<void> _jumpToMessage(String messageId)async{
    while(!messages.any((item)=>item.id==messageId)&&nextCursor!=null){await _loadOlder();}
    final originalIndex=messages.indexWhere((item)=>item.id==messageId);
    if(originalIndex<0){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Original message available nahi hai.')));return;}
    if(!mounted)return;
    setState(()=>highlightedMessageId=messageId);
    final reverseIndex=messages.length-1-originalIndex;
    if(scrollController.hasClients){final estimate=(reverseIndex*78.0).clamp(0.0,scrollController.position.maxScrollExtent).toDouble();await scrollController.animateTo(estimate,duration:const Duration(milliseconds:320),curve:Curves.easeOut);}
    await Future<void>.delayed(const Duration(milliseconds:40));
    final targetContext=messageKeys[messageId]?.currentContext;
    if(targetContext!=null)await Scrollable.ensureVisible(targetContext,duration:const Duration(milliseconds:220),curve:Curves.easeOut,alignment:.5);
    await Future<void>.delayed(const Duration(milliseconds:900));
    if(mounted&&highlightedMessageId==messageId)setState(()=>highlightedMessageId=null);
  }
  Future<void> _loadOlder() async {
	if (loadingOlder || nextCursor == null) return; setState(() => loadingOlder = true);
	try { final page = await ChatApi.instance.messagePage(widget.conversationId, before: nextCursor); if (mounted) setState(() { messages.insertAll(0,page.items); nextCursor=page.nextCursor; }); }
	finally { if (mounted) setState(() => loadingOlder = false); }
  }

  _MentionDraftRange? get _mentionDraftRange {
    if(details?.group!=true)return null;
    final selection=input.selection;
    if(!selection.isValid||!selection.isCollapsed)return null;
    final cursor=selection.extentOffset.clamp(0,input.text.length).toInt();
    final prefix=input.text.substring(0,cursor);
    final at=prefix.lastIndexOf('@');
    if(at<0)return null;
    if(at>0&&!RegExp(r'[\s(\[{]').hasMatch(prefix[at-1]))return null;
    final query=prefix.substring(at+1);
    if(!RegExp(r'^[^\s@.,!?;:()\[\]{}]*$').hasMatch(query))return null;
    return _MentionDraftRange(start:at,end:cursor,query:query);
  }

  bool _containsMentionToken(String text,String handle){if(handle.isEmpty)return false;return RegExp('(^|[\\s\\(\\[\\{])@${RegExp.escape(handle)}(\$|[\\s\\.,!\\?;:\\)\\]\\}])',caseSensitive:false).hasMatch(text);}
  List<String> _activeMentionUserIDs(String text)=>selectedMentions.entries.where((entry)=>_containsMentionToken(text,entry.value)).take(20).map((entry)=>entry.key).toList();
  void _syncSelectedMentions(String text){selectedMentions.removeWhere((_,handle)=>!_containsMentionToken(text,handle));}

  Future<void> _loadMentionMembers()async{
    if(details?.group!=true||mentionMembersLoading||mentionMembersLoaded)return;
    if(mounted)setState((){mentionMembersLoading=true;mentionMembersError=null;});
    try{
      final group=await SocialApi.instance.group(widget.conversationId);
      final members=group.members.where((member)=>!member.mine&&member.mention.isNotEmpty).toList()..sort((first,second)=>first.name.toLowerCase().compareTo(second.name.toLowerCase()));
      if(mounted)setState((){mentionMembers=members;mentionMembersLoaded=true;mentionMembersError=null;});
    }catch(_){if(mounted)setState(()=>mentionMembersError='Group members load nahi hue.');}
    finally{if(mounted)setState(()=>mentionMembersLoading=false);}
  }

  void _selectMention(GroupMember member){
    final range=_mentionDraftRange;if(range==null)return;
    final before=input.text.substring(0,range.start),after=input.text.substring(range.end);
    final spacer=after.isNotEmpty&&RegExp(r'^\s').hasMatch(after)?'':' ';
    final replacement='@${member.mention}$spacer';
    final value='$before$replacement$after';
    final cursor=before.length+replacement.length;
    selectedMentions[member.id]=member.mention;
    input.value=TextEditingValue(text:value,selection:TextSelection.collapsed(offset:cursor));
    _typing(value);
    inputFocus.requestFocus();
  }

  Widget _mentionSuggestions(){
    final range=_mentionDraftRange;if(range==null)return const SizedBox.shrink();
    final query=range.query.toLowerCase();
    final visible=mentionMembers.where((member)=>query.isEmpty||member.mention.toLowerCase().contains(query)||member.name.toLowerCase().contains(query)||member.username.toLowerCase().contains(query)).take(6).toList();
    Widget child;
    if(mentionMembersLoading){child=const SizedBox(height:58,child:Center(child:SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:authPurple))));}
    else if(mentionMembersError!=null){child=ListTile(dense:true,leading:const Icon(Icons.refresh,color:authPurple),title:Text(mentionMembersError!,style:const TextStyle(fontSize:12)),onTap:(){setState(()=>mentionMembersLoaded=false);_loadMentionMembers();});}
    else if(visible.isEmpty){child=const SizedBox(height:52,child:Center(child:Text('No matching group member',style:TextStyle(fontSize:12,color:authMuted))));}
    else{child=ListView(shrinkWrap:true,padding:EdgeInsets.zero,children:visible.map((member)=>ListTile(dense:true,leading:CircleAvatar(radius:17,backgroundColor:const Color(0xFFE8E0FF),child:Text(_contactInitials(member.name),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:authPurple))),title:Text(member.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700)),subtitle:Text('@${member.mention}',style:const TextStyle(fontSize:11,color:authPurple)),onTap:()=>_selectMention(member))).toList());}
    return Container(constraints:const BoxConstraints(maxHeight:238),margin:const EdgeInsets.fromLTRB(15,4,15,0),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFFD9CEFA)),boxShadow:const[BoxShadow(color:Color(0x16000000),blurRadius:12)]),clipBehavior:Clip.antiAlias,child:child);
  }

  Future<void> send() async {
    if(schedulingMessage)return;
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (_sendingDisabled) { _showSendingUnavailable(); return; }
    final mentionUserIDs=_activeMentionUserIDs(text);
    final reply=replyingTo;final replyID=reply?.id;final pending=ChatMessage(id:'local-${DateTime.now().microsecondsSinceEpoch}',text:text,time:TimeOfDay.now().format(context),mine:true,createdAt:DateTime.now(),status:'sending',mentionUserIds:mentionUserIDs,reply:reply==null?null:ReplyPreview(id:reply.id,text:reply.text,mine:reply.mine,senderName:reply.senderName));input.clear();setState((){replyingTo=null;selectedMentions.clear();messages.add(pending);});_savePendingMessages();_jumpToLatest();
    try{
      final saved=await ChatApi.instance.sendMessage(widget.conversationId,text,replyToId:replyID,clientMessageId:pending.id,mentionUserIds:mentionUserIDs);
      if(mounted)setState((){messages.removeWhere((item)=>item.id==pending.id);if(!messages.any((item)=>item.id==saved.id))messages.add(saved);});await Future.wait([_savePendingMessages(),_saveMessageCache()]);
      await _clearDraft();
      socket?.sendTyping(false);
    }catch(_){if(mounted)setState((){final index=messages.indexWhere((item)=>item.id==pending.id);if(index>=0)messages[index]=pending.copyWith(status:'failed');});await _savePendingMessages();}
  }

  Future<void> _scheduleCurrentMessage()async{
    if(schedulingMessage)return;
    final text=input.text.trim();
    if(text.isEmpty)return;
    if(_sendingDisabled){_showSendingUnavailable();return;}
    final now=DateTime.now();
    final oneHour=now.add(const Duration(hours:1));
    var evening=DateTime(now.year,now.month,now.day,20);
    if(!evening.isAfter(now))evening=evening.add(const Duration(days:1));
    final tomorrow=DateTime(now.year,now.month,now.day+1,9);
    final choice=await showModalBottomSheet<String>(context:context,backgroundColor:Colors.white,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),builder:(sheetContext)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const ListTile(title:Text('Send message later',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('GroopX closed ho tab bhi backend send karega. Free server wake-up par thoda delay ho sakta hai.')),
      ListTile(leading:const Icon(Icons.timer_outlined,color:authPurple),title:const Text('In 1 hour'),subtitle:Text(_reminderDateTimeLabel(oneHour)),onTap:()=>Navigator.pop(sheetContext,'hour')),
      ListTile(leading:const Icon(Icons.nights_stay_outlined,color:authPurple),title:Text(_sameDay(evening,now)?'Tonight':'Tomorrow evening'),subtitle:Text(_reminderDateTimeLabel(evening)),onTap:()=>Navigator.pop(sheetContext,'evening')),
      ListTile(leading:const Icon(Icons.wb_sunny_outlined,color:authPurple),title:const Text('Tomorrow morning'),subtitle:Text(_reminderDateTimeLabel(tomorrow)),onTap:()=>Navigator.pop(sheetContext,'tomorrow')),
      ListTile(leading:const Icon(Icons.edit_calendar_outlined,color:authPurple),title:const Text('Pick date & time'),onTap:()=>Navigator.pop(sheetContext,'custom')),
      const SizedBox(height:8),
    ])));
    if(choice==null||!mounted)return;
    DateTime? scheduledAt;
    if(choice=='hour')scheduledAt=oneHour;
    if(choice=='evening')scheduledAt=evening;
    if(choice=='tomorrow')scheduledAt=tomorrow;
    if(choice=='custom')scheduledAt=await _pickReminderDateTime(maximumDays:365);
    if(scheduledAt==null||!mounted)return;
    if(!scheduledAt.isAfter(DateTime.now().add(const Duration(seconds:30)))){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Future date and time select karein.')));return;}
    final reply=replyingTo;
    setState(()=>schedulingMessage=true);
    try{
      await ChatApi.instance.scheduleMessage(widget.conversationId,text,scheduledAt,replyToId:reply?.id);
      if(!mounted)return;
      input.clear();
      setState((){replyingTo=null;selectedMentions.clear();});
      await _clearDraft();
      socket?.sendTyping(false);
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Message ${_reminderDateTimeLabel(scheduledAt)} send hoga.'),action:SnackBarAction(label:'View',onPressed:()=>context.push('/chat/${widget.conversationId}/scheduled'))));
    }catch(failure){
      if(mounted){var message='Message schedule nahi hua. Retry karein.';if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}
    }finally{if(mounted)setState(()=>schedulingMessage=false);}
  }

  Future<bool> _retryMessage(ChatMessage message,{bool silent=false})async{if(_sendingDisabled){if(!silent)_showSendingUnavailable();return false;}final index=messages.indexWhere((item)=>item.id==message.id);if(index<0||!mounted)return false;setState(()=>messages[index]=message.copyWith(status:'sending'));try{final saved=await ChatApi.instance.sendMessage(widget.conversationId,message.text,replyToId:message.reply?.id,clientMessageId:message.id,mentionUserIds:message.mentionUserIds);if(mounted)setState((){messages.removeWhere((item)=>item.id==message.id);if(!messages.any((item)=>item.id==saved.id))messages.add(saved);});await Future.wait([_savePendingMessages(),_saveMessageCache()]);await _clearDraft();return true;}catch(_){if(mounted){final failedIndex=messages.indexWhere((item)=>item.id==message.id);if(failedIndex>=0)setState(()=>messages[failedIndex]=message.copyWith(status:'failed'));await _savePendingMessages();if(!silent)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Message abhi bhi send nahi hua. Internet check karein.')));}return false;}}
  Future<void> _retryFailedMessages()async{if(_sendingDisabled)return;final failed=messages.where((item)=>item.id.startsWith('local-')&&item.status=='failed').toList();var sent=0;for(final message in failed){if(await _retryMessage(message,silent:true))sent++;}if(sent>0&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$sent pending message${sent==1?'':'s'} sent')));}

  void _startReply(ChatMessage message){if(_sendingDisabled){_showSendingUnavailable();return;}setState(()=>replyingTo=message);HapticFeedback.selectionClick();WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)inputFocus.requestFocus();});}
  Future<void> _quickReact(ChatMessage message)async{final hasHeart=message.reactions.any((item)=>item.emoji=='❤️'&&item.mine);HapticFeedback.lightImpact();try{await ChatApi.instance.react(message.id,'❤️',add:!hasHeart);await _refreshMessages();}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Reaction update nahi hua. Retry karein.')));}}
  void _showReactionDetails(ChatMessage message,String emoji){showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(_)=>_ReactionDetailsSheet(messageId:message.id,initialEmoji:emoji,onChanged:(){_refreshMessages();}));}

  void _typing(String value) {
    _syncSelectedMentions(value);
    if(_mentionDraftRange!=null)unawaited(_loadMentionMembers());
    if(mounted)setState((){});
    _scheduleDraftSave(value);
    if (socket == null || _sendingDisabled) return;
    typingTimer?.cancel(); socket!.sendTyping(value.trim().isNotEmpty);
    typingTimer = Timer(const Duration(milliseconds: 1200), () => socket?.sendTyping(false));
  }

  void _showSendingUnavailable(){
    final message=details?.canSend==false?'Only group admins can send messages in announcement mode':'Communication is blocked';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  }

  Future<void> _upload(FileType type,{bool multiple=false}) async {
    Navigator.of(context).pop();
    await _pickAndUpload(type,multiple:multiple);
  }

  Future<void> _pickAndUpload(FileType type,{bool multiple=false,bool viewOnce=false}) async {
    if(_sendingDisabled){_showSendingUnavailable();return;}
    try {
      setState(() { uploading = true; uploadProgress = 0; });
      await MediaApi.instance.pickAndUpload(conversationId: widget.conversationId, type: type,allowMultiple:multiple,viewOnce:viewOnce, onProgress: (value) { if (mounted) setState(() => uploadProgress = value); });
    } catch (failure) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_uploadError(failure))));
    } finally { if (mounted) setState(() => uploading = false); }
  }

  Future<void> _capturePhoto({bool viewOnce=false,bool closeSheet=true})async{
    if(_sendingDisabled){if(closeSheet)Navigator.of(context).pop();_showSendingUnavailable();return;}
    if(closeSheet)Navigator.of(context).pop();
    final permission=await Permission.camera.request();
    if(!permission.isGranted){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Camera use karne ke liye permission allow karein.')));return;}
    try{
      final photo=await ImagePicker().pickImage(source:ImageSource.camera,imageQuality:88,maxWidth:2048);
      if(photo==null)return;
      final file=File(photo.path);
      if(!mounted)return;
      setState((){uploading=true;uploadProgress=0;});
      await MediaApi.instance.uploadFile(conversationId:widget.conversationId,path:photo.path,fileName:photo.name,size:await file.length(),viewOnce:viewOnce,onProgress:(value){if(mounted)setState(()=>uploadProgress=value);});
    }catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_uploadError(failure))));}
    finally{if(mounted)setState(()=>uploading=false);}
  }

  Future<void> _captureVideo({bool viewOnce=false,bool closeSheet=true})async{
    if(_sendingDisabled){if(closeSheet)Navigator.of(context).pop();_showSendingUnavailable();return;}
    if(closeSheet)Navigator.of(context).pop();
    final permissions=await [Permission.camera,Permission.microphone].request();
    if(permissions.values.any((status)=>!status.isGranted)){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Video record karne ke liye camera aur microphone permission allow karein.')));return;}
    try{
      final video=await ImagePicker().pickVideo(source:ImageSource.camera,maxDuration:const Duration(minutes:3));
      if(video==null)return;
      final file=File(video.path);
      if(!mounted)return;
      setState((){uploading=true;uploadProgress=0;});
      await MediaApi.instance.uploadFile(conversationId:widget.conversationId,path:video.path,fileName:video.name,size:await file.length(),viewOnce:viewOnce,onProgress:(value){if(mounted)setState(()=>uploadProgress=value);});
    }catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_uploadError(failure))));}
    finally{if(mounted)setState(()=>uploading=false);}
  }

  String _uploadError(Object failure){
    if(failure is DioException){final data=failure.response?.data;if(data is Map&&data['error']!=null)return data['error'].toString();}
    if(failure is StateError)return failure.message.toString();
    return 'Upload failed. Internet check karke retry karein.';
  }

  Future<void> _startVoiceNote()async{
    if(uploading||recording)return;
    if(_sendingDisabled){_showSendingUnavailable();return;}
    final permission=await Permission.microphone.request();
    if(!permission.isGranted){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Voice note ke liye microphone permission allow karein.')));return;}
    try{
      await voiceRecorder.invokeMethod<String>('start');
      if(!mounted)return;
      setState((){recording=true;recordingSeconds=0;});
      recordingTimer=Timer.periodic(const Duration(seconds:1),(_){if(!mounted)return;setState(()=>recordingSeconds++);if(recordingSeconds>=300)_finishVoiceNote(send:true);});
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Voice recording start nahi hui.')));}
  }

  Future<void> _finishVoiceNote({required bool send})async{
    if(!recording)return;
    recordingTimer?.cancel();recordingTimer=null;
    final duration=recordingSeconds;
    setState(()=>recording=false);
    String? recordedPath;
    try{
      final path=await voiceRecorder.invokeMethod<String>(send?'stop':'cancel');
      recordedPath=path;
      if(!send||path==null)return;
      final file=File(path);
      if(duration<1||!await file.exists()){throw StateError('Voice note bahut short hai');}
      setState((){uploading=true;uploadProgress=0;});
      await MediaApi.instance.uploadFile(conversationId:widget.conversationId,path:path,fileName:'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',size:await file.length(),durationMs:duration*1000,onProgress:(value){if(mounted)setState(()=>uploadProgress=value);});
    }catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_uploadError(failure))));}
    finally{if(recordedPath!=null){final temporary=File(recordedPath);if(await temporary.exists())await temporary.delete();}if(mounted)setState(()=>uploading=false);}
  }

  String get _recordingTime=>'${(recordingSeconds~/60).toString().padLeft(2,'0')}:${(recordingSeconds%60).toString().padLeft(2,'0')}';

  Future<void> _showViewOnceOptions()async{
    if(_sendingDisabled){Navigator.of(context).pop();_showSendingUnavailable();return;}
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds:180));
    if(!mounted)return;
    final choice=await showModalBottomSheet<String>(context:context,backgroundColor:Colors.white,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),builder:(sheetContext)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const ListTile(leading:CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Text('1',style:TextStyle(color:authPurple,fontWeight:FontWeight.w900))),title:Text('Send view once',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Recipient photo ya video sirf ek baar open kar sakega. Maximum size 25 MB.')),
      ListTile(leading:const Icon(Icons.photo_outlined,color:authPurple),title:const Text('Photo from gallery'),onTap:()=>Navigator.pop(sheetContext,'photo')),
      ListTile(leading:const Icon(Icons.video_library_outlined,color:authPurple),title:const Text('Video from gallery'),onTap:()=>Navigator.pop(sheetContext,'video')),
      ListTile(leading:const Icon(Icons.camera_alt_outlined,color:authPurple),title:const Text('Take photo'),onTap:()=>Navigator.pop(sheetContext,'camera')),
      ListTile(leading:const Icon(Icons.videocam_outlined,color:authPurple),title:const Text('Record video'),onTap:()=>Navigator.pop(sheetContext,'record')),
      const SizedBox(height:8),
    ])));
    if(choice==null||!mounted)return;
    if(choice=='photo')await _pickAndUpload(FileType.image,viewOnce:true);
    if(choice=='video')await _pickAndUpload(FileType.video,viewOnce:true);
    if(choice=='camera')await _capturePhoto(viewOnce:true,closeSheet:false);
    if(choice=='record')await _captureVideo(viewOnce:true,closeSheet:false);
  }

  void _showAttachments() => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Wrap(alignment:WrapAlignment.spaceAround,runSpacing:12,children: [
    _AttachmentAction(icon: Icons.camera_alt, label: 'Camera', onTap: ()=>_capturePhoto()),
    _AttachmentAction(icon: Icons.videocam, label: 'Record video', onTap: ()=>_captureVideo()),
    _AttachmentAction(icon: Icons.image, label: 'Gallery', onTap: () => _upload(FileType.image,multiple:true)),
    _AttachmentAction(icon: Icons.video_file, label: 'Video', onTap: () => _upload(FileType.video)),
    _AttachmentAction(icon: Icons.filter_1_outlined, label: 'View once', onTap: _showViewOnceOptions),
    _AttachmentAction(icon: Icons.description, label: 'Document', onTap: () => _upload(FileType.any)),
    _AttachmentAction(icon: Icons.audio_file, label: 'Audio', onTap: () => _upload(FileType.audio)),
    _AttachmentAction(icon: Icons.location_on, label: 'Location', onTap: _showLocationOptions),
    _AttachmentAction(icon: Icons.contact_page_outlined, label: 'Contact', onTap: _shareContact),
    _AttachmentAction(icon: Icons.poll_outlined, label: 'Poll', onTap: _createPoll),
  ]))));

  Future<void> _createPoll()async{
    if(_sendingDisabled){Navigator.of(context).pop();_showSendingUnavailable();return;}
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds:180));
    if(!mounted)return;
    final draft=await showModalBottomSheet<_PollDraft>(context:context,isScrollControlled:true,useSafeArea:true,backgroundColor:Colors.white,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),builder:(_)=>const _PollComposerSheet());
    if(draft==null||!mounted||uploading)return;
    setState((){uploading=true;uploadProgress=0;});
    try{
      final saved=await ChatApi.instance.createPoll(widget.conversationId,question:draft.question,options:draft.options,allowMultiple:draft.allowMultiple);
      if(mounted&&!messages.any((item)=>item.id==saved.id)){setState(()=>messages.add(saved));await _saveMessageCache();_jumpToLatest();}
    }catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_uploadError(failure))));}
    finally{if(mounted)setState(()=>uploading=false);}
  }

  Future<void> _shareContact()async{
    if(_sendingDisabled){Navigator.of(context).pop();_showSendingUnavailable();return;}
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds:180));
    if(!mounted)return;
    final contact=await showModalBottomSheet<DeviceContactCard>(context:context,isScrollControlled:true,useSafeArea:true,backgroundColor:Colors.white,shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),builder:(_)=>const _ContactPickerSheet());
    if(contact==null||!mounted)return;
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(title:const Text('Share contact?'),content:ListTile(contentPadding:EdgeInsets.zero,leading:CircleAvatar(backgroundColor:const Color(0xFFEEE9FF),child:Text(_contactInitials(contact.name),style:const TextStyle(color:authPurple,fontWeight:FontWeight.w800))),title:Text(contact.name,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(contact.phone)),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Send'))]));
    if(confirmed!=true||!mounted||uploading)return;
    setState((){uploading=true;uploadProgress=0;});
    try{
      final saved=await ChatApi.instance.sendContact(widget.conversationId,name:contact.name,phone:contact.phone);
      if(mounted&&!messages.any((item)=>item.id==saved.id)){setState(()=>messages.add(saved));await _saveMessageCache();}
    }catch(failure){
      if(mounted){final message=failure is DioException&&failure.response?.data is Map?(failure.response!.data as Map)['error']?.toString():null;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message?.isNotEmpty==true?message!:'Contact share nahi hua. Internet check karke retry karein.')));}
    }finally{if(mounted)setState(()=>uploading=false);}
  }

  Future<void> _showLocationOptions()async{
    if(_sendingDisabled){Navigator.of(context).pop();_showSendingUnavailable();return;}
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds:180));
    if(!mounted)return;
    final action=await showModalBottomSheet<String>(context:context,builder:(context)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const ListTile(title:Text('Share location',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Choose current point or continuously updated live location.')),
      ListTile(leading:const CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.my_location,color:authPurple)),title:const Text('Send current location'),subtitle:const Text('Share one fixed map point'),onTap:()=>Navigator.pop(context,'current')),
      ListTile(leading:const CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.location_searching,color:authPurple)),title:const Text('Share live location'),subtitle:const Text('Updates securely for a limited time'),onTap:()=>Navigator.pop(context,'live')),
      const SizedBox(height:8),
    ])));
    if(action=='current')await _sendCurrentLocation();
    if(action=='live')await _shareLiveLocation();
  }

  Future<Position> _currentPosition()async{
    if(!await Geolocator.isLocationServiceEnabled())throw StateError('Phone location service off hai.');
    var permission=await Geolocator.checkPermission();
    if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();
    if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever)throw StateError('Location permission denied');
    return Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:20)));
  }

  Future<void> _sendCurrentLocation() async{
    if(uploading)return;
    if(_sendingDisabled){_showSendingUnavailable();return;}
    setState((){uploading=true;uploadProgress=0;});
    try{
      final position=await _currentPosition();
      final saved=await ChatApi.instance.sendLocation(widget.conversationId,latitude:position.latitude,longitude:position.longitude);
      if(mounted&&!messages.any((item)=>item.id==saved.id)){setState(()=>messages.add(saved));await _saveMessageCache();}
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Location share nahi ho saki. Permission aur GPS check karein.')));}
    finally{if(mounted)setState(()=>uploading=false);}
  }

  Future<void> _shareLiveLocation()async{
    if(_sendingDisabled){_showSendingUnavailable();return;}
    final duration=await showModalBottomSheet<int>(context:context,builder:(context)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const ListTile(title:Text('Share live location for',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('You can stop sharing at any time.')),
      ListTile(leading:const Icon(Icons.timer_outlined,color:authPurple),title:const Text('15 minutes'),onTap:()=>Navigator.pop(context,900)),
      ListTile(leading:const Icon(Icons.schedule,color:authPurple),title:const Text('1 hour'),onTap:()=>Navigator.pop(context,3600)),
      ListTile(leading:const Icon(Icons.more_time,color:authPurple),title:const Text('8 hours'),onTap:()=>Navigator.pop(context,28800)),
      const SizedBox(height:8),
    ])));
    if(duration==null||uploading)return;
    setState((){uploading=true;uploadProgress=0;});
    try{
      final result=await LiveLocationService.instance.start(widget.conversationId,duration);
      if(mounted&&!messages.any((item)=>item.id==result.message.id)){setState(()=>messages.add(result.message));await _saveMessageCache();}
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Live location sharing started.')));
    }catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_liveLocationError(failure))));}
    finally{if(mounted)setState(()=>uploading=false);}
  }

  String _liveLocationError(Object failure){
    if(failure is StateError)return failure.toString().replaceFirst('Bad state: ','');
    if(failure is DioException&&failure.response?.data is Map){final message=(failure.response!.data as Map)['error']?.toString();if(message?.isNotEmpty==true)return message!;}
    return'Live location start nahi hui. Internet, GPS aur permission check karein.';
  }

  bool _liveLocationActive(ChatMessage message){
    final attachment=message.attachment;if(attachment?['live']!=true||attachment?['active']!=true)return false;
    final expiresAt=DateTime.tryParse(attachment?['expires_at']?.toString()??'')?.toLocal();
    return expiresAt!=null&&expiresAt.isAfter(DateTime.now());
  }

  Future<void> _stopLiveLocation(ChatMessage message)async{
    final id=message.attachment?['live_location_id']?.toString()??'';if(id.isEmpty)return;
    try{
      await LiveLocationService.instance.stop(id);
      if(mounted){final index=messages.indexWhere((item)=>item.id==message.id);if(index>=0){final attachment=Map<String,dynamic>.from(messages[index].attachment??const{});attachment['active']=false;attachment['stopped_at']=DateTime.now().toUtc().toIso8601String();setState(()=>messages[index]=messages[index].copyWith(attachment:attachment));await _saveMessageCache();}ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Live location sharing stopped.')));}
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Live location stop nahi hui. Retry karein.')));}
  }

  Future<void> _refreshMessages() async {
    final page = await ChatApi.instance.messagePage(widget.conversationId);
    if (mounted) setState(() {final local=messages.where((item)=>item.id.startsWith('local-')).toList();messages..clear()..addAll(page.items)..addAll(local);nextCursor=page.nextCursor;final validIDs=messages.map((item)=>item.id).toSet();selectedMessageIds.removeWhere((id)=>!validIDs.contains(id));});
    await _saveMessageCache();
  }

  Future<void> _refreshDetails()async{
    final value=await ChatApi.instance.conversation(widget.conversationId);
    if(!mounted)return;
    if(!value.canSend){
      typingTimer?.cancel();socket?.sendTyping(false);
      if(recording)unawaited(_finishVoiceNote(send:false));
      _clearTypingUsers();
    }
    setState((){details=value;if(!value.canSend){replyingTo=null;selectedMentions.clear();}});
  }

  Future<void> _refreshGroupMemberData()async{
    try{await Future.wait([_refreshMessages(),_refreshDetails()]);}catch(_){}
  }

  Future<void> _loadPinnedBanner({bool show=false})async{try{final items=await ChatApi.instance.pinnedMessages(widget.conversationId);if(mounted)setState((){pinnedBanner=items.isEmpty?null:items.first;if(show)pinBannerDismissed=false;});}catch(_){}}

  Future<void> _messageActions(ChatMessage message) async {
    final action = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (sheetContext) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(sheetContext).height * .72, child: ListView(children: [
      Padding(padding: const EdgeInsets.all(14), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: ['👍','❤️','😂','😮','🙏'].map((emoji) => InkWell(onTap: () => Navigator.pop(sheetContext, 'reaction:$emoji'), child: Text(emoji, style: const TextStyle(fontSize: 28)))).toList())),
      if(details?.canSend!=false)ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () => Navigator.pop(sheetContext, 'reply')),
      if(!message.viewOnce)ListTile(leading:const Icon(Icons.copy_outlined),title:const Text('Copy'),onTap:()=>Navigator.pop(sheetContext,'copy')),
      if(message.kind!='poll'&&!message.viewOnce)ListTile(leading: const Icon(Icons.forward), title: const Text('Forward'), onTap: () => Navigator.pop(sheetContext, 'forward')),
      ListTile(leading: const Icon(Icons.alarm_add_outlined, color: authPurple), title: const Text('Remind me'), subtitle: const Text('Create a follow-up reminder'), onTap: () => Navigator.pop(sheetContext, 'reminder')),
      ListTile(leading:Icon(message.starred?Icons.star:Icons.star_border,color:message.starred?Colors.amber:null),title:Text(message.starred?'Unstar message':'Star message'),onTap:()=>Navigator.pop(sheetContext,'star')),
      ListTile(leading:Icon(message.pinned?Icons.push_pin:Icons.push_pin_outlined,color:message.pinned?authPurple:null),title:Text(message.pinned?'Unpin message':'Pin message'),onTap:()=>Navigator.pop(sheetContext,'pin')),
      if(message.mine)ListTile(leading:const Icon(Icons.info_outline),title:const Text('Message info'),onTap:()=>Navigator.pop(sheetContext,'info')),
      if (message.mine && message.kind == 'text' && details?.canSend!=false) ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit message'), onTap: () => Navigator.pop(sheetContext, 'edit')),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Delete message', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(sheetContext, 'delete')),
    ]))));
    if (action == null) return;
    if (action == 'reply') { _startReply(message); return; }
    if(action=='copy'){final attachment=message.attachment;final value=message.text.trim().isNotEmpty?message.text:(attachment?['map_url']?.toString()??attachment?['url']?.toString()??'');if(value.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Is message mein copyable text nahi hai.')));return;}await Clipboard.setData(ClipboardData(text:value));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Message copied')));return;}
    if (action == 'forward') { await _forwardMessage(message); return; }
    if (action == 'reminder') { await _createMessageReminder(message); return; }
    if(action=='star'){
      await ChatApi.instance.setStarred(message.id,!message.starred);
    }else if(action=='info'){
      await context.push('/message/${message.id}/info');return;
    }else if(action=='pin'){
      try{await ChatApi.instance.setPinned(message.id,!message.pinned);await _loadPinnedBanner(show:true);}catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_uploadError(failure))));}
    }else if (action.startsWith('reaction:')) {
      final emoji = action.substring(9); final existing = message.reactions.where((item) => item.emoji == emoji && item.mine).isNotEmpty;
      await ChatApi.instance.react(message.id, emoji, add: !existing);
    } else if (action == 'delete') {
      final scope=await showModalBottomSheet<bool>(context:context,builder:(sheetContext)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[const ListTile(title:Text('Delete message?',style:TextStyle(fontWeight:FontWeight.w800))),ListTile(leading:const Icon(Icons.delete_outline),title:const Text('Delete for me'),onTap:()=>Navigator.pop(sheetContext,false)),if(message.mine)ListTile(leading:const Icon(Icons.delete_forever_outlined,color:Colors.red),title:const Text('Delete for everyone',style:TextStyle(color:Colors.red)),onTap:()=>Navigator.pop(sheetContext,true)),ListTile(leading:const Icon(Icons.close),title:const Text('Cancel'),onTap:()=>Navigator.pop(sheetContext))])));
      if(scope==null)return;
      try{await ChatApi.instance.deleteMessage(message.id,forEveryone:scope);}catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_uploadError(failure))));return;}
    } else if (action == 'edit') {
      final controller = TextEditingController(text: message.text);
      final text = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Edit message'), content: TextField(controller: controller, autofocus: true, maxLines: 4), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save'))]));
      controller.dispose(); if (text != null && text.isNotEmpty) await ChatApi.instance.editMessage(message.id, text);
    }
    await _refreshMessages();
  }

  Future<void> _createMessageReminder(ChatMessage message) async {
    final now = DateTime.now();
    final oneHour = now.add(const Duration(hours: 1));
    var evening = DateTime(now.year, now.month, now.day, 20);
    if (!evening.isAfter(now)) evening = evening.add(const Duration(days: 1));
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final choice = await showModalBottomSheet<String>(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Remind me about this message', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('The reminder will open this chat')),
      ListTile(leading: const Icon(Icons.timer_outlined, color: authPurple), title: const Text('In 1 hour'), subtitle: Text(_reminderDateTimeLabel(oneHour)), onTap: () => Navigator.pop(sheetContext, 'hour')),
      ListTile(leading: const Icon(Icons.nights_stay_outlined, color: authPurple), title: Text(_sameDay(evening, now) ? 'Tonight' : 'Tomorrow evening'), subtitle: Text(_reminderDateTimeLabel(evening)), onTap: () => Navigator.pop(sheetContext, 'evening')),
      ListTile(leading: const Icon(Icons.wb_sunny_outlined, color: authPurple), title: const Text('Tomorrow morning'), subtitle: Text(_reminderDateTimeLabel(tomorrow)), onTap: () => Navigator.pop(sheetContext, 'tomorrow')),
      ListTile(leading: const Icon(Icons.edit_calendar_outlined, color: authPurple), title: const Text('Pick date & time'), onTap: () => Navigator.pop(sheetContext, 'custom')),
      const SizedBox(height: 8),
    ])));
    if (choice == null || !mounted) return;
    DateTime? scheduledAt;
    if (choice == 'hour') {
      scheduledAt = oneHour;
    } else if (choice == 'evening') {
      scheduledAt = evening;
    } else if (choice == 'tomorrow') {
      scheduledAt = tomorrow;
    } else {
      scheduledAt = await _pickReminderDateTime();
    }
    if (scheduledAt == null || !mounted) return;
    if (!scheduledAt.isAfter(DateTime.now())) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Future date and time select karein.'))); return; }
    final chatTitle = (details?.title.trim().isNotEmpty ?? false) ? details!.title.trim() : 'GroopX chat';
    var reminderTitle = 'Follow up: $chatTitle';
    if (reminderTitle.length > 160) reminderTitle = reminderTitle.substring(0, 160);
    final sender = message.mine ? 'You' : (message.senderName.trim().isEmpty ? chatTitle : message.senderName.trim());
    var notes = '$sender: ${_messageReminderSummary(message)}';
    if (notes.length > 1000) notes = notes.substring(0, 1000);
    try {
      await ReminderApi.instance.create(title: reminderTitle, scheduledAt: scheduledAt, notes: notes, conversationId: widget.conversationId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reminder set for ${_reminderDateTimeLabel(scheduledAt)}'), action: SnackBarAction(label: 'View', onPressed: () => context.push('/reminders'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder create nahi hua. Retry karein.')));
    }
  }

  Future<DateTime?> _pickReminderDateTime({int maximumDays=730}) async {
    final now = DateTime.now();
    final initial = now.add(const Duration(hours: 1));
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(Duration(days:maximumDays)));
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _messageReminderSummary(ChatMessage message) {
    if (message.text.trim().isNotEmpty) return message.text.trim();
    final attachment = message.attachment;
    final name = (attachment?['file_name']?.toString() ?? attachment?['name']?.toString() ?? attachment?['label']?.toString() ?? '').trim();
    if (name.isNotEmpty) return name;
    return switch (message.kind) { 'image' => 'Photo message', 'video' => 'Video message', 'audio' => 'Audio message', 'location' => 'Shared location', 'contact' => 'Shared contact', 'poll' => 'Poll message', 'file' => 'Document message', _ => 'Chat message' };
  }

  String _reminderDateTimeLabel(DateTime value) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final day = _sameDay(value, now) ? 'Today' : _sameDay(value, tomorrow) ? 'Tomorrow' : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    final hour = value.hour == 0 ? 12 : value.hour > 12 ? value.hour - 12 : value.hour;
    return '$day • $hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  void _toggleMessageSelection(ChatMessage message){
    if(message.id.startsWith('local-')||selectionBusy||recording||uploading)return;
    final selecting=!selectedMessageIds.contains(message.id);
    final starting=selecting&&selectedMessageIds.isEmpty;
    setState((){if(selecting){selectedMessageIds.add(message.id);}else{selectedMessageIds.remove(message.id);}});
    if(selecting)HapticFeedback.selectionClick();
    if(starting){inputFocus.unfocus();socket?.sendTyping(false);}
  }

  void _clearMessageSelection(){if(selectionBusy||selectedMessageIds.isEmpty)return;setState(selectedMessageIds.clear);}

  String _copyableMessageText(ChatMessage message){
    if(message.viewOnce)return'';
    if(message.text.trim().isNotEmpty)return message.text.trim();
    final attachment=message.attachment;
    return attachment?['map_url']?.toString()??attachment?['url']?.toString()??attachment?['file_name']?.toString()??'';
  }

  Future<void> _copySelectedMessages()async{
    final selected=List<ChatMessage>.of(_selectedMessages);
    final values=<String>[];
    for(final message in selected){
      final value=_copyableMessageText(message);
      if(value.isEmpty)continue;
      if(selected.length==1){values.add(value);}else{final sender=message.mine?'You':(message.senderName.trim().isEmpty?'GroopX member':message.senderName.trim());values.add('$sender: $value');}
    }
    if(values.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Selected messages mein copyable text nahi hai.')));return;}
    await Clipboard.setData(ClipboardData(text:values.join('\n')));
    if(!mounted)return;
    _clearMessageSelection();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${values.length} message${values.length==1?'':'s'} copied')));
  }

  Future<void> _setSelectedStarred()async{
    final selected=List<ChatMessage>.of(_selectedMessages);
    if(selected.isEmpty)return;
    final starred=!selected.every((message)=>message.starred);
    setState(()=>selectionBusy=true);
    final failed=<String>{};
    var changed=0;
    for(final message in selected){try{await ChatApi.instance.setStarred(message.id,starred);changed++;}catch(_){failed.add(message.id);}}
    try{await _refreshMessages();}catch(_){}
    if(!mounted)return;
    setState((){selectedMessageIds..clear()..addAll(failed);selectionBusy=false;});
    final text=failed.isEmpty?'$changed message${changed==1?'':'s'} ${starred?'starred':'unstarred'}':'$changed updated, ${failed.length} failed. Selected messages retry karein.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
  }

  Future<void> _deleteSelectedMessages()async{
    final selected=List<ChatMessage>.of(_selectedMessages);
    if(selected.isEmpty)return;
    final allMine=selected.every((message)=>message.mine);
    final scope=await showModalBottomSheet<bool>(context:context,builder:(sheetContext)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[ListTile(title:Text('Delete ${selected.length} message${selected.length==1?'':'s'}?',style:const TextStyle(fontWeight:FontWeight.w800))),ListTile(leading:const Icon(Icons.delete_outline),title:const Text('Delete for me'),onTap:()=>Navigator.pop(sheetContext,false)),if(allMine)ListTile(leading:const Icon(Icons.delete_forever_outlined,color:Colors.red),title:const Text('Delete for everyone',style:TextStyle(color:Colors.red)),onTap:()=>Navigator.pop(sheetContext,true)),ListTile(leading:const Icon(Icons.close),title:const Text('Cancel'),onTap:()=>Navigator.pop(sheetContext))])));
    if(scope==null||!mounted)return;
    setState(()=>selectionBusy=true);
    final deleted=<String>{};
    final failed=<String>{};
    for(final message in selected){try{await ChatApi.instance.deleteMessage(message.id,forEveryone:scope);deleted.add(message.id);}catch(_){failed.add(message.id);}}
    if(!mounted)return;
    setState((){messages.removeWhere((message)=>deleted.contains(message.id));for(final id in deleted){messageKeys.remove(id);}if(replyingTo!=null&&deleted.contains(replyingTo!.id))replyingTo=null;if(pinnedBanner!=null&&deleted.contains(pinnedBanner!.id))pinnedBanner=null;selectedMessageIds..clear()..addAll(failed);selectionBusy=false;});
    await _saveMessageCache();
    unawaited(_loadPinnedBanner());
    if(!mounted)return;
    final text=failed.isEmpty?'${deleted.length} message${deleted.length==1?'':'s'} deleted':'${deleted.length} deleted, ${failed.length} failed. Selected messages retry karein.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
  }

  Future<List<String>?> _pickForwardTargets(String title)async{
    List<ChatSummary> chats;
    try { chats=(await ChatApi.instance.conversations()).where((item)=>item.id!=widget.conversationId).toList(); }
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Chats load nahi hue. Retry karein.')));return null;}
    if(!mounted)return null;
    if(chats.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Forward karne ke liye koi aur chat nahi hai.')));return null;}
    final selected=<String>{};
    final targets=await showDialog<List<String>>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(_,setDialogState)=>AlertDialog(
      title:Text(title),
      content:SizedBox(width:double.maxFinite,height:360,child:ListView.builder(itemCount:chats.length,itemBuilder:(_,index){final chat=chats[index];final checked=selected.contains(chat.id);return CheckboxListTile(value:checked,secondary:CircleAvatar(child:Icon(chat.group?Icons.groups:Icons.person)),title:Text(chat.name,maxLines:1,overflow:TextOverflow.ellipsis),subtitle:chat.preview.isEmpty?null:Text(chat.preview,maxLines:1,overflow:TextOverflow.ellipsis),onChanged:(value){setDialogState((){if(value==true&&selected.length<5){selected.add(chat.id);}else if(value!=true){selected.remove(chat.id);}});});})),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel')),FilledButton(onPressed:selected.isEmpty?null:()=>Navigator.pop(dialogContext,selected.toList()),child:Text('Forward (${selected.length})'))],
    )));
    return targets;
  }

  Future<void> _forwardMessage(ChatMessage message) async {
    if(message.kind=='poll'){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Poll forward nahi kiya ja sakta.')));return;}
    if(message.viewOnce){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('View once media forward nahi ki ja sakti.')));return;}
    final targets=await _pickForwardTargets('Forward message');
    if(targets==null||targets.isEmpty)return;
    try{final count=await ChatApi.instance.forwardMessage(message.id,targets);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Message $count chat${count==1?'':'s'} me forward ho gaya.')));}
    catch(failure){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_uploadError(failure))));}
  }

  Future<void> _forwardSelectedMessages()async{
    final selected=List<ChatMessage>.of(_selectedMessages);
    if(selected.isEmpty)return;
    if(selected.any((message)=>message.kind=='poll'||message.viewOnce)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Poll aur view once media forward nahi ki ja sakti. Selection change karke retry karein.')));return;}
    final targets=await _pickForwardTargets(selected.length==1?'Forward message':'Forward ${selected.length} messages');
    if(targets==null||targets.isEmpty||!mounted)return;
    setState(()=>selectionBusy=true);
    final failed=<String>{};
    var copies=0;
    for(final message in selected){try{copies+=await ChatApi.instance.forwardMessage(message.id,targets);}catch(_){failed.add(message.id);}}
    if(!mounted)return;
    setState((){selectedMessageIds..clear()..addAll(failed);selectionBusy=false;});
    final text=failed.isEmpty?'$copies forwarded message cop${copies==1?'y':'ies'} sent':'$copies copies sent, ${failed.length} messages failed. Retry selected messages.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
  }

  void _replyToSelected(){final message=_singleSelectedMessage;if(message==null)return;setState(selectedMessageIds.clear);_startReply(message);}

  Future<void> _openSelectedMessageActions()async{final message=_singleSelectedMessage;if(message==null)return;setState(selectedMessageIds.clear);await _messageActions(message);}

  PreferredSizeWidget _selectionAppBar(){
    final selected=_selectedMessages;
    final allStarred=selected.isNotEmpty&&selected.every((message)=>message.starred);
    return AppBar(
      backgroundColor:const Color(0xFFF1ECFF),
      elevation:0,
      leading:IconButton(onPressed:selectionBusy?null:_clearMessageSelection,tooltip:'Cancel selection',icon:const Icon(Icons.close,color:authInk)),
      title:Text('${selected.length} selected',style:const TextStyle(color:authInk,fontWeight:FontWeight.w700)),
      actions:selectionBusy?[const Padding(padding:EdgeInsets.symmetric(horizontal:20),child:Center(child:SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:authPurple))))]:[
        IconButton(onPressed:_setSelectedStarred,tooltip:allStarred?'Unstar':'Star',icon:Icon(allStarred?Icons.star:Icons.star_border,color:allStarred?Colors.amber:authPurple)),
        IconButton(onPressed:_copySelectedMessages,tooltip:'Copy',icon:const Icon(Icons.copy_outlined,color:authPurple)),
        if(!selected.any((message)=>message.kind=='poll'||message.viewOnce))IconButton(onPressed:_forwardSelectedMessages,tooltip:'Forward',icon:const Icon(Icons.forward,color:authPurple)),
        PopupMenuButton<String>(tooltip:'More actions',onSelected:(action){if(action=='reply')_replyToSelected();if(action=='delete')_deleteSelectedMessages();if(action=='more')_openSelectedMessageActions();},itemBuilder:(_)=>[if(selected.length==1&&details?.canSend!=false)const PopupMenuItem(value:'reply',child:ListTile(leading:Icon(Icons.reply),title:Text('Reply'))),const PopupMenuItem(value:'delete',child:ListTile(leading:Icon(Icons.delete_outline,color:Colors.red),title:Text('Delete',style:TextStyle(color:Colors.red)))),if(selected.length==1)const PopupMenuItem(value:'more',child:ListTile(leading:Icon(Icons.more_horiz),title:Text('More options')))]),
      ],
    );
  }

  Widget _bottomComposer()=>SafeArea(
    top:false,
    child:Container(
      padding:const EdgeInsets.fromLTRB(15,8,15,10),
      decoration:const BoxDecoration(color:Colors.white,boxShadow:[BoxShadow(color:Color(0x10000000),blurRadius:15)]),
      child:details?.canSend==false
          ? const Row(children:[
              CircleAvatar(backgroundColor:Color(0xFFEEE9FF),child:Icon(Icons.campaign_outlined,color:authPurple)),
              SizedBox(width:12),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
                Text('Only admins can send messages',style:TextStyle(fontWeight:FontWeight.w700,color:authInk)),
                Text('Announcement mode is on',style:TextStyle(fontSize:11,color:authMuted)),
              ])),
            ])
          : recording
              ? Row(children:[
                  IconButton(onPressed:()=>_finishVoiceNote(send:false),icon:const Icon(Icons.delete_outline,color:Colors.red)),
                  const SizedBox(width:8),const Icon(Icons.fiber_manual_record,color:Colors.red,size:14),const SizedBox(width:8),
                  Expanded(child:Text('Recording  $_recordingTime',style:const TextStyle(fontWeight:FontWeight.w600,color:authInk))),
                  IconButton.filled(onPressed:()=>_finishVoiceNote(send:true),style:IconButton.styleFrom(backgroundColor:authPurple),icon:const Icon(Icons.send,color:Colors.white)),
                ])
              : Row(children:[
                  IconButton(onPressed:uploading||schedulingMessage||details?.communicationBlocked==true?null:_showAttachments,style:IconButton.styleFrom(backgroundColor:authPurple),icon:const Icon(Icons.add,color:Colors.white)),
                  const SizedBox(width:8),
                  Expanded(child:TextField(controller:input,focusNode:inputFocus,onChanged:_typing,onSubmitted:(_)=>send(),decoration:InputDecoration(hintText:details?.group==true?'Message · @ to mention':'Type a message...',filled:true,fillColor:const Color(0xFFF4F2F8),border:OutlineInputBorder(borderSide:BorderSide.none,borderRadius:BorderRadius.circular(23))))),
                  ValueListenableBuilder<TextEditingValue>(valueListenable:input,builder:(_,value,__)=>(value.text.trim().isEmpty)?const SizedBox.shrink():IconButton(tooltip:'Send later',onPressed:uploading||schedulingMessage||details?.communicationBlocked==true?null:_scheduleCurrentMessage,icon:const Icon(Icons.schedule_send_outlined,color:authPurple))),
                  IconButton(onPressed:schedulingMessage?null:send,icon:const Icon(Icons.send_rounded,color:authPurple)),
                  IconButton(onPressed:uploading||schedulingMessage||details?.communicationBlocked==true?null:_startVoiceNote,icon:const Icon(Icons.mic,color:authPurple)),
                ]),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(canPop:!_selectionMode&&context.canPop(),onPopInvokedWithResult:(didPop,_){if(didPop)return;if(_selectionMode){_clearMessageSelection();return;}context.go('/chats');},child:Scaffold(
    backgroundColor:_chatBackground,
    appBar:_selectionMode?_selectionAppBar():AppBar(backgroundColor: Colors.white, elevation: 0, leading:IconButton(onPressed:()=>context.go('/chats'),icon:const Icon(Icons.arrow_back)), titleSpacing: 0, title: InkWell(onTap:()=>context.push(details?.group==true?'/groups/${widget.conversationId}':'/contact/${widget.conversationId}'),child:Row(children: [CircleAvatar(radius: 21, backgroundColor: const Color(0xFF37474F), foregroundImage: (details?.avatarUrl?.isNotEmpty ?? false) ? NetworkImage(details!.avatarUrl!) : null, child: Icon(details?.group == true ? Icons.groups : Icons.person, color: Colors.white)), const SizedBox(width: 10), Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(details?.title ?? 'Conversation', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: authInk)), Text(_presenceText(), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: details?.online == true ? Colors.green : const Color(0xFF697187)))]) )])), actions: [IconButton(onPressed: details?.communicationBlocked == true ? null : () => context.push('/call/audio/${widget.conversationId}'), icon: const Icon(Icons.call, color: authPurple)), IconButton(onPressed: details?.communicationBlocked == true ? null : () => context.push('/call/video/${widget.conversationId}'), icon: const Icon(Icons.videocam, color: authPurple)), PopupMenuButton<String>(onSelected: _headerAction, itemBuilder: (_) => [const PopupMenuItem(value: 'search', child: ListTile(leading: Icon(Icons.search), title: Text('Search messages'))),const PopupMenuItem(value:'scheduled',child:ListTile(leading:Icon(Icons.schedule_send_outlined),title:Text('Scheduled messages'))),const PopupMenuItem(value:'pinned',child:ListTile(leading:Icon(Icons.push_pin_outlined),title:Text('Pinned messages'))),const PopupMenuItem(value:'starred',child:ListTile(leading:Icon(Icons.star_border),title:Text('Starred messages'))),const PopupMenuItem(value:'disappearing',child:ListTile(leading:Icon(Icons.timer_outlined),title:Text('Disappearing messages'))),const PopupMenuItem(value:'media',child:ListTile(leading:Icon(Icons.perm_media_outlined),title:Text('Media, links & docs'))),const PopupMenuItem(value:'theme',child:ListTile(leading:Icon(Icons.palette_outlined),title:Text('Chat theme'))),const PopupMenuItem(value:'export',child:ListTile(leading:Icon(Icons.download_outlined),title:Text('Export chat'))),if(details?.group==true)const PopupMenuItem(value:'group',child:ListTile(leading:Icon(Icons.group_outlined),title:Text('Group info'))), if (details?.group != true) const PopupMenuItem(value: 'safety', child: ListTile(leading: Icon(Icons.shield_outlined), title: Text('Safety options')))])]),
    body: Column(children: [
      if(realtimeOffline)Material(color:const Color(0xFFFFF3CD),child:InkWell(onTap:_reconnectLive,child:Padding(padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),child:Row(children:[reconnecting?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Color(0xFF8A6400))):const Icon(Icons.cloud_off,size:18,color:Color(0xFF8A6400)),const SizedBox(width:9),Expanded(child:Text(reconnecting?'Reconnecting live chat...':'Live connection offline · Tap to retry',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:Color(0xFF6B5100))))])))),
      if(pinnedBanner!=null&&!pinBannerDismissed)Material(color:const Color(0xFFF4F0FF),child:InkWell(onTap:()=>_jumpToMessage(pinnedBanner!.id),child:Padding(padding:const EdgeInsets.fromLTRB(14,8,6,8),child:Row(children:[const Icon(Icons.push_pin,color:authPurple,size:18),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Pinned message',style:TextStyle(fontSize:10,fontWeight:FontWeight.w700,color:authPurple)),Text(pinnedBanner!.viewOnce?pinnedBanner!.text:pinnedBanner!.kind=='text'?pinnedBanner!.text:(pinnedBanner!.attachment?['file_name']?.toString()??pinnedBanner!.text),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,color:authInk))])),IconButton(tooltip:'Hide pinned message',onPressed:()=>setState(()=>pinBannerDismissed=true),icon:const Icon(Icons.close,size:18,color:authMuted))])))),
      Expanded(child:Stack(children:[Positioned.fill(child:loading?const Center(child:CircularProgressIndicator(color:authPurple)):error!=null&&messages.isEmpty?Center(child:TextButton(onPressed:(){setState((){loading=true;error=null;});_connect();},child:Text('$error — Retry'))):messages.isEmpty?const Center(child:Text('Start the conversation',style:TextStyle(color:authMuted))):ListView.builder(controller:scrollController,reverse:true,padding:const EdgeInsets.symmetric(horizontal:15),itemCount:messages.length+(loadingOlder?1:0),itemBuilder:(_,i){if(i==messages.length)return const Padding(padding:EdgeInsets.all(12),child:Center(child:CircularProgressIndicator(strokeWidth:2)));final originalIndex=messages.length-1-i;final message=messages[originalIndex];final local=message.id.startsWith('local-');final selected=selectedMessageIds.contains(message.id);final showDate=message.createdAt!=null&&(originalIndex==0||!_sameDay(message.createdAt,messages[originalIndex-1].createdAt));return Column(mainAxisSize:MainAxisSize.min,children:[if(showDate)_dateSeparator(message.createdAt!),_Bubble(key:messageKeys.putIfAbsent(message.id,GlobalKey.new),message:message,showSender:details?.group==true&&!message.mine,highlighted:highlightedMessageId==message.id,selected:selected,selectionMode:_selectionMode,onTap:_selectionMode&&!local?()=>_toggleMessageSelection(message):null,onRetry:message.status=='failed'&&details?.canSend!=false?()=>_retryMessage(message):null,onQuickReact:local?(){}:()=>_quickReact(message),onReactionTap:(emoji)=>_showReactionDetails(message,emoji),onSwipeReply:()=>_startReply(message),onReplyTap:message.reply==null?null:()=>_jumpToMessage(message.reply!.id),onStopLiveLocation:message.mine&&_liveLocationActive(message)?()=>_stopLiveLocation(message):null,onPollChanged:(attachment)=>_updatePollMessage(message.id,attachment),onViewOnceOpened:(attachment)=>_updateViewOnceMessage(message.id,attachment),onLongPress:local?(){}:()=>_toggleMessageSelection(message))]);})),if(showJumpToLatest&&!_selectionMode)Positioned(right:16,bottom:12,child:Badge(isLabelVisible:newMessageCount>0,label:Text(newMessageCount>99?'99+':'$newMessageCount'),child:FloatingActionButton.small(heroTag:'jump-latest-${widget.conversationId}',onPressed:_jumpToLatest,backgroundColor:Colors.white,foregroundColor:authPurple,tooltip:newMessageCount>0?'$newMessageCount new messages':'Latest message',child:const Icon(Icons.keyboard_arrow_down_rounded))))])),
      if(!_selectionMode&&details?.canSend!=false&&_mentionDraftRange!=null)_mentionSuggestions(),
      if(!_selectionMode&&typingUsers.isNotEmpty)Padding(padding:const EdgeInsets.fromLTRB(18,4,18,4),child:Align(alignment:Alignment.centerLeft,child:Container(key:ValueKey(_typingLabel),padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:const Color(0xFFF0EAFF),borderRadius:BorderRadius.circular(14)),child:Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.more_horiz,size:16,color:authPurple),const SizedBox(width:6),Flexible(child:Text(_typingLabel,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:authPurple,fontStyle:FontStyle.italic,fontWeight:FontWeight.w600)))])))),
      if(!_selectionMode&&uploading)LinearProgressIndicator(value: uploadProgress == 0 ? null : uploadProgress, color: authPurple, backgroundColor: const Color(0xFFEEE9FF)),
      if(!_selectionMode&&details?.canSend!=false&&replyingTo!=null)Container(color: const Color(0xFFF2EEFF), padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: Row(children: [const Icon(Icons.reply, size: 18, color: authPurple), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(replyingTo!.mine ? 'Replying to yourself' : 'Replying to ${replyingTo!.senderName.isEmpty?'message':replyingTo!.senderName}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: authPurple)), Text(replyingTo!.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: authMuted))])), IconButton(onPressed: () => setState(() => replyingTo = null), icon: const Icon(Icons.close, size: 18))])),
      if(!_selectionMode)_bottomComposer(),
    ]),
  ));

  String _presenceText() {
    if (details?.communicationBlocked == true) return details?.blockedByMe == true ? 'Blocked' : 'Unavailable';
    if (details?.group == true) return details?.announcementOnly==true?'${details?.memberCount ?? 0} members · Admin messages only':'${details?.memberCount ?? 0} members';
    if (details?.online == true) return 'Online';
    final seen = details?.lastSeen;
    if (seen == null) return 'Secure chat';
    final hour = seen.hour == 0 ? 12 : (seen.hour > 12 ? seen.hour - 12 : seen.hour);
    return 'Last seen ${hour}:${seen.minute.toString().padLeft(2, '0')} ${seen.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _safetyActions() async {
    final target = details?.otherUserId; if (target == null) return;
    final action = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: Icon(details?.blockedByMe == true ? Icons.person_add_alt : Icons.block, color: Colors.red), title: Text(details?.blockedByMe == true ? 'Unblock user' : 'Block user'), onTap: () => Navigator.pop(context, 'block')),
      ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.orange), title: const Text('Report user'), onTap: () => Navigator.pop(context, 'report')),
    ])));
    if (action == 'block') { await SocialApi.instance.setBlocked(target, details?.blockedByMe != true); final info = await ChatApi.instance.conversation(widget.conversationId); if (mounted) setState(() => details = info); }
    if (action == 'report') { await _report(target); }
  }

  Future<void> _headerAction(String action) async {
    if (action == 'search'){final messageId=await context.push<String>('/chat/${widget.conversationId}/search');if(messageId!=null&&mounted)await _jumpToMessage(messageId);}
    if(action=='scheduled')context.push('/chat/${widget.conversationId}/scheduled');
    if (action == 'starred') context.push('/chat/${widget.conversationId}/starred');
    if (action == 'pinned') context.push('/chat/${widget.conversationId}/pinned');
    if(action=='disappearing')context.push('/chat/${widget.conversationId}/disappearing');
    if (action == 'media') context.push('/chat/${widget.conversationId}/media');
    if(action=='theme')_selectTheme();
    if(action=='export')_exportChat();
    if (action == 'group') context.push('/groups/${widget.conversationId}');
    if (action == 'safety') _safetyActions();
  }

  Future<void> _selectTheme()async{final options=<String,Color>{'default':const Color(0xFFFBFAFD),'lavender':const Color(0xFFF0EAFF),'blue':const Color(0xFFEAF5FF),'green':const Color(0xFFEAF8F0),'dark':const Color(0xFF202333)};final selected=await showModalBottomSheet<String>(context:context,builder:(context)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[const ListTile(title:Text('Chat theme',style:TextStyle(fontWeight:FontWeight.w800))),...options.entries.map((entry)=>RadioListTile<String>(value:entry.key,groupValue:chatTheme,onChanged:(value)=>Navigator.pop(context,value),secondary:CircleAvatar(backgroundColor:entry.value),title:Text(entry.key[0].toUpperCase()+entry.key.substring(1))))])));if(selected==null)return;final preferences=await SharedPreferences.getInstance();await preferences.setString('chat_theme_${widget.conversationId}',selected);if(mounted)setState(()=>chatTheme=selected);}

  Future<void> _exportChat()async{try{final items=await ChatApi.instance.exportMessages(widget.conversationId);if(items.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Export karne ke liye messages nahi hain.')));return;}final title=details?.title??'GroopX Chat';final buffer=StringBuffer('GroopX chat export: $title\nExported: ${DateTime.now().toLocal()}\n\n');for(final message in items){final stamp=message.createdAt?.toLocal().toString()??message.time;if(message.system){buffer.writeln('[$stamp] • ${message.text}');continue;}final sender=message.mine?'You':(message.senderName.isEmpty?title:message.senderName);final content=message.viewOnce?'[VIEW ONCE ${message.kind.toUpperCase()}]':message.kind=='text'?message.text:'[${message.kind.toUpperCase()}] ${message.text}';buffer.writeln('[$stamp] $sender: $content');}final safeName=title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'),'_');final path=await FilePicker.platform.saveFile(dialogTitle:'Export GroopX chat',fileName:'GroopX_${safeName}_chat.txt',type:FileType.custom,allowedExtensions:const['txt'],bytes:Uint8List.fromList(utf8.encode(buffer.toString())));if(path!=null&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Chat export save ho gaya.')));}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Chat export nahi hua. Retry karein.')));}}

  Future<void> _report(String target) async {
    String reason = 'spam'; final note = TextEditingController();
    final submit = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (_, setDialogState) => AlertDialog(title: const Text('Report user'), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(value: reason, items: const [DropdownMenuItem(value: 'spam', child: Text('Spam')), DropdownMenuItem(value: 'harassment', child: Text('Harassment')), DropdownMenuItem(value: 'impersonation', child: Text('Impersonation')), DropdownMenuItem(value: 'inappropriate', child: Text('Inappropriate content')), DropdownMenuItem(value: 'other', child: Text('Other'))], onChanged: (value) => setDialogState(() => reason = value ?? reason)), TextField(controller: note, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'Details (optional)'))]), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit'))])));
    if (submit == true) { await SocialApi.instance.reportUser(target, conversationId: widget.conversationId, reason: reason, details: note.text.trim()); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted for review'))); }
    note.dispose();
  }
}

class _MentionDraftRange {
  const _MentionDraftRange({required this.start,required this.end,required this.query});
  final int start,end;
  final String query;
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key,required this.message,required this.showSender,required this.onLongPress,required this.onSwipeReply,required this.onQuickReact,required this.onReactionTap,required this.selected,required this.selectionMode,this.onTap,this.onReplyTap,this.onRetry,this.onStopLiveLocation,this.onPollChanged,this.onViewOnceOpened,this.highlighted=false});
  final ChatMessage message;
  final bool showSender;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeReply;
  final VoidCallback onQuickReact;
  final ValueChanged<String> onReactionTap;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final VoidCallback? onReplyTap;
  final VoidCallback? onStopLiveLocation;
  final ValueChanged<Map<String,dynamic>>? onPollChanged;
  final ValueChanged<Map<String,dynamic>>? onViewOnceOpened;
  final bool highlighted,selected,selectionMode;
  @override
  Widget build(BuildContext context) {
    if(message.system)return _SystemMessageNotice(message:message,highlighted:highlighted);
    final senderLabel=message.senderName.isEmpty?'GroopX member':message.senderName;
    const selectedMark=Padding(padding:EdgeInsets.only(left:7,right:7,bottom:12),child:Icon(Icons.check_circle,color:authPurple,size:22));
    final bubble=GestureDetector(
      behavior:HitTestBehavior.opaque,
      onTap:onTap,
      onLongPress:onLongPress,
      onDoubleTap:selectionMode?null:onQuickReact,
      onHorizontalDragEnd:selectionMode?null:(details){if((details.primaryVelocity??0)>320)onSwipeReply();},
      child:AnimatedContainer(
        duration:const Duration(milliseconds:220),
        margin:const EdgeInsets.only(bottom:12),
        padding:const EdgeInsets.fromLTRB(13,10,10,7),
        constraints:const BoxConstraints(maxWidth:265),
        decoration:BoxDecoration(color:selected?const Color(0xFFDCD1FF):highlighted?const Color(0xFFD8CBFF):message.mine?const Color(0xFFEEE9FF):Colors.white,border:selected||highlighted?Border.all(color:authPurple,width:2):null,borderRadius:BorderRadius.circular(12),boxShadow:message.mine?null:const[BoxShadow(color:Color(0x10000000),blurRadius:9)]),
        child:IgnorePointer(ignoring:selectionMode,child:Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
          if(showSender)Align(alignment:Alignment.centerLeft,child:Padding(padding:const EdgeInsets.only(bottom:6),child:Text(senderLabel,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:authPurple)))),
          if(message.reply!=null)InkWell(onTap:onReplyTap,child:Container(width:double.infinity,margin:const EdgeInsets.only(bottom:7),padding:const EdgeInsets.all(8),decoration:const BoxDecoration(color:Color(0x12000000),border:Border(left:BorderSide(color:authPurple,width:3))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(message.reply!.mine?'You':(message.reply!.senderName.isEmpty?'Reply':message.reply!.senderName),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w700,color:authPurple)),Text(message.reply!.text,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:authMuted))]))),
          if(message.forwarded)const Align(alignment:Alignment.centerLeft,child:Padding(padding:EdgeInsets.only(bottom:5),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.forward,size:12,color:authMuted),SizedBox(width:3),Text('Forwarded',style:TextStyle(fontSize:10,fontStyle:FontStyle.italic,color:authMuted))]))),
          if(message.mentioned)Align(alignment:Alignment.centerLeft,child:Container(margin:const EdgeInsets.only(bottom:6),padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:const Color(0xFFE6DDFF),borderRadius:BorderRadius.circular(9)),child:const Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.alternate_email,size:12,color:authPurple),SizedBox(width:3),Text('You were mentioned',style:TextStyle(fontSize:9,fontWeight:FontWeight.w800,color:authPurple))]))),
          if(message.statusReply!=null)_StatusReplyReference(item:message.statusReply!),
          if(message.isAttachment)_AttachmentBody(message:message,onStopLiveLocation:onStopLiveLocation,onPollChanged:onPollChanged,onViewOnceOpened:onViewOnceOpened)else _LinkedMessageText(text:message.text),
          if(message.reactions.isNotEmpty)Padding(padding:const EdgeInsets.only(top:6),child:Wrap(spacing:4,children:message.reactions.map((item)=>InkWell(onTap:()=>onReactionTap(item.emoji),borderRadius:BorderRadius.circular(10),child:Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),decoration:BoxDecoration(color:item.mine?const Color(0xFFDCD1FF):const Color(0xFFF1F1F4),borderRadius:BorderRadius.circular(10)),child:Text('${item.emoji} ${item.count}',style:const TextStyle(fontSize:11))))).toList())),
          const SizedBox(height:4),Row(mainAxisSize:MainAxisSize.min,children:[if(message.pinned)const Padding(padding:EdgeInsets.only(right:4),child:Icon(Icons.push_pin,size:11,color:authPurple)),if(message.starred)const Padding(padding:EdgeInsets.only(right:4),child:Icon(Icons.star,size:11,color:Color(0xFFFFB300))),if(message.edited)const Text('edited  ',style:TextStyle(fontSize:8,color:authMuted)),Text(message.time,style:const TextStyle(fontSize:9,color:authMuted)),if(message.status=='sending')const Padding(padding:EdgeInsets.only(left:4),child:SizedBox(width:11,height:11,child:CircularProgressIndicator(strokeWidth:1.5,color:authMuted))),if(message.status=='failed')InkWell(onTap:onRetry,child:const Padding(padding:EdgeInsets.only(left:5),child:Icon(Icons.error,size:16,color:Colors.red))),if(message.mine&&message.status!='sending'&&message.status!='failed')Padding(padding:const EdgeInsets.only(left:4),child:Icon(message.delivered?Icons.done_all:Icons.done,size:13,color:message.read?authPurple:authMuted))]),
        ])),
      ),
    );
    return Row(mainAxisAlignment:message.mine?MainAxisAlignment.end:MainAxisAlignment.start,crossAxisAlignment:CrossAxisAlignment.end,children:[if(!message.mine&&selected)selectedMark,if(showSender)...[Padding(padding:const EdgeInsets.only(bottom:12),child:GroopXAvatar(label:senderLabel,imageUrl:message.senderAvatarUrl,radius:14)),const SizedBox(width:7)],Flexible(child:Align(alignment:message.mine?Alignment.centerRight:Alignment.centerLeft,child:bubble)),if(message.mine&&selected)selectedMark]);
  }
}

class _StatusReplyReference extends StatelessWidget {
  const _StatusReplyReference({required this.item});
  final StatusReplyPreview item;
  @override
  Widget build(BuildContext context){
    final title=item.reaction.isNotEmpty
      ?item.userName.isEmpty?'Reacted ${item.reaction} to status':"Reacted ${item.reaction} to ${item.userName}'s status"
      :item.userName.isEmpty?'Replied to status':"Replied to ${item.userName}'s status";
    final description=item.mediaType=='text'
      ?(item.textContent.isEmpty?'Text status':item.textContent)
      :item.caption.isEmpty?(item.mediaType=='video'?'Video status':'Photo status'):item.caption;
    final preview=item.mediaType=='text'
      ?ColoredBox(color:_statusReplyColor(item.backgroundColor),child:const Center(child:Text('Aa',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w800))))
      :item.mediaType=='image'&&item.mediaUrl.isNotEmpty
        ?Image.network(item.mediaUrl,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const ColoredBox(color:Color(0xFFE5DFFF),child:Icon(Icons.auto_awesome_outlined,color:authPurple)))
        :const ColoredBox(color:Color(0xFFE5DFFF),child:Icon(Icons.play_circle_outline,color:authPurple));
    return Container(
      width:double.infinity,
      margin:const EdgeInsets.only(bottom:8),
      padding:const EdgeInsets.all(7),
      decoration:BoxDecoration(color:const Color(0x12000000),borderRadius:BorderRadius.circular(9),border:const Border(left:BorderSide(color:authPurple,width:3))),
      child:Row(children:[
        ClipRRect(borderRadius:BorderRadius.circular(7),child:SizedBox(width:48,height:48,child:preview)),
        const SizedBox(width:8),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:authPurple)),const SizedBox(height:3),Text(description,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10.5,color:authMuted,height:1.25))]))
      ]),
    );
  }
}

Color _statusReplyColor(String value){
  final normalized=value.replaceFirst('#','');
  final rgb=int.tryParse(normalized,radix:16);
  return rgb==null||normalized.length!=6?authPurple:Color(0xFF000000|rgb);
}

class _SystemMessageNotice extends StatelessWidget {
  const _SystemMessageNotice({required this.message,required this.highlighted});
  final ChatMessage message;
  final bool highlighted;
  @override
  Widget build(BuildContext context)=>Center(child:AnimatedContainer(
    duration:const Duration(milliseconds:220),
    margin:const EdgeInsets.only(bottom:12),
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),
    constraints:const BoxConstraints(maxWidth:300),
    decoration:BoxDecoration(color:highlighted?const Color(0xFFD8CBFF):const Color(0xFFECEAF1),borderRadius:BorderRadius.circular(14),border:highlighted?Border.all(color:authPurple):null),
    child:Row(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.info_outline_rounded,size:14,color:authMuted),
      const SizedBox(width:6),
      Flexible(child:Text(message.text,textAlign:TextAlign.center,style:const TextStyle(fontSize:10.5,height:1.3,fontWeight:FontWeight.w600,color:authMuted))),
      if(message.time.isNotEmpty)...[const SizedBox(width:6),Text(message.time,style:const TextStyle(fontSize:8.5,color:authMuted))],
    ]),
  ));
}

class _LinkedMessageText extends StatefulWidget {
  const _LinkedMessageText({required this.text});
  final String text;
  @override State<_LinkedMessageText> createState()=>_LinkedMessageTextState();
}

class _LinkedMessageTextState extends State<_LinkedMessageText> {
  static final tokenPattern=RegExp(r'''https?://[^\s<>"']+|@[^\s@.,!?;:()\[\]{}]{1,50}''',caseSensitive:false);
  final recognizers=<TapGestureRecognizer>[];
  List<InlineSpan> spans=const[];
  String? firstLink;

  @override void initState(){super.initState();_buildLinks();}
  @override void didUpdateWidget(covariant _LinkedMessageText oldWidget){super.didUpdateWidget(oldWidget);if(oldWidget.text!=widget.text)_buildLinks();}
  @override void dispose(){_clearRecognizers();super.dispose();}

  void _clearRecognizers(){for(final recognizer in recognizers){recognizer.dispose();}recognizers.clear();}
  void _buildLinks(){
    _clearRecognizers();
    final built=<InlineSpan>[];var cursor=0;String? preview;
    for(final match in tokenPattern.allMatches(widget.text)){
      if(match.start>cursor)built.add(TextSpan(text:widget.text.substring(cursor,match.start)));
      final raw=match.group(0)!;
      final isLink=raw.toLowerCase().startsWith('http://')||raw.toLowerCase().startsWith('https://');
      final validMention=!isLink&&(match.start==0||RegExp(r'[\s(\[{]').hasMatch(widget.text[match.start-1]));
      if(validMention){built.add(TextSpan(text:raw,style:const TextStyle(color:authPurple,fontWeight:FontWeight.w800,backgroundColor:Color(0xFFE9E1FF))));cursor=match.end;continue;}
      if(!isLink){built.add(TextSpan(text:raw));cursor=match.end;continue;}
      final link=raw.replaceFirst(RegExp(r'[.,;:!?\)\]\}]+$'),'');
      if(link.isEmpty){built.add(TextSpan(text:raw));}else{
        preview??=link;
        final recognizer=TapGestureRecognizer()..onTap=()=>_open(link);recognizers.add(recognizer);
        built.add(TextSpan(text:link,style:const TextStyle(color:Color(0xFF5530C8),fontWeight:FontWeight.w700,decoration:TextDecoration.underline),recognizer:recognizer));
        if(link.length<raw.length)built.add(TextSpan(text:raw.substring(link.length)));
      }
      cursor=match.end;
    }
    if(cursor<widget.text.length)built.add(TextSpan(text:widget.text.substring(cursor)));
    spans=built.isEmpty?[TextSpan(text:widget.text)]:built;firstLink=preview;
  }

  Future<void> _open(String value)async{var opened=false;try{final uri=Uri.tryParse(value);opened=uri!=null&&await launchUrl(uri,mode:LaunchMode.externalApplication);}catch(_){}if(!opened&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Link open nahi hua.')));}
  String _host(String value){final host=Uri.tryParse(value)?.host??'';return host.isEmpty?'External link':host.replaceFirst(RegExp(r'^www\.'),'');}

  @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text.rich(TextSpan(style:const TextStyle(fontSize:13,height:1.35,color:authInk),children:spans)),
    if(firstLink!=null)Padding(padding:const EdgeInsets.only(top:8),child:Material(color:const Color(0xFFF7F4FF),borderRadius:BorderRadius.circular(10),child:InkWell(onTap:()=>_open(firstLink!),borderRadius:BorderRadius.circular(10),child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:10,vertical:9),decoration:BoxDecoration(border:Border.all(color:const Color(0xFFD9CEFA)),borderRadius:BorderRadius.circular(10)),child:Row(children:[const CircleAvatar(radius:16,backgroundColor:Color(0xFFE7DEFF),child:Icon(Icons.link,size:17,color:authPurple)),const SizedBox(width:9),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(_host(firstLink!),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:authInk)),const Text('Open link',style:TextStyle(fontSize:10,color:authMuted))])),const Icon(Icons.open_in_new,size:15,color:authPurple)]))))),
  ]);
}

class _ReactionDetailsSheet extends StatefulWidget {
  const _ReactionDetailsSheet({required this.messageId,required this.initialEmoji,required this.onChanged});
  final String messageId,initialEmoji;
  final VoidCallback onChanged;
  @override State<_ReactionDetailsSheet> createState()=>_ReactionDetailsSheetState();
}

class _ReactionDetailsSheetState extends State<_ReactionDetailsSheet> {
  List<MessageReactionDetail>? items;
  String? error;
  late String selectedEmoji;
  bool removing=false;

  @override void initState(){super.initState();selectedEmoji=widget.initialEmoji;_load();}
  Future<void> _load()async{try{final loaded=await ChatApi.instance.reactionDetails(widget.messageId);if(mounted)setState((){items=loaded;error=null;if(selectedEmoji.isNotEmpty&&!loaded.any((item)=>item.emoji==selectedEmoji))selectedEmoji='';});}catch(_){if(mounted)setState(()=>error='Reactions load nahi hui.');}}
  Future<void> _remove(MessageReactionDetail item)async{if(removing)return;setState(()=>removing=true);try{await ChatApi.instance.react(widget.messageId,item.emoji,add:false);if(!mounted)return;setState((){items=[...?items]..removeWhere((value)=>value.userId==item.userId&&value.emoji==item.emoji);if(selectedEmoji.isNotEmpty&&!(items??const[]).any((value)=>value.emoji==selectedEmoji))selectedEmoji='';});widget.onChanged();}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Reaction remove nahi hui. Retry karein.')));}finally{if(mounted)setState(()=>removing=false);}}

  @override Widget build(BuildContext context){
    final loaded=items;
    final counts=<String,int>{};for(final item in loaded??const<MessageReactionDetail>[]){counts[item.emoji]=(counts[item.emoji]??0)+1;}
    final visible=selectedEmoji.isEmpty?loaded??const<MessageReactionDetail>[]:(loaded??const<MessageReactionDetail>[]).where((item)=>item.emoji==selectedEmoji).toList();
    return SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.58,child:Column(children:[
      Container(width:42,height:4,margin:const EdgeInsets.only(top:10),decoration:BoxDecoration(color:const Color(0xFFD5D4DC),borderRadius:BorderRadius.circular(4))),
      ListTile(title:const Text('Message reactions',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:loaded==null?null:Text('${loaded.length} reaction${loaded.length==1?'':'s'}'),trailing:IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close))),
      if(loaded!=null&&loaded.isNotEmpty)SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:14),children:[Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text('All ${loaded.length}'),selected:selectedEmoji.isEmpty,onSelected:(_)=>setState(()=>selectedEmoji=''))),...counts.entries.map((entry)=>Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text('${entry.key} ${entry.value}'),selected:selectedEmoji==entry.key,onSelected:(_)=>setState(()=>selectedEmoji=entry.key))))])),
      const Divider(height:1),
      Expanded(child:loaded==null&&error==null?const Center(child:CircularProgressIndicator(color:authPurple)):error!=null?Center(child:TextButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:Text('$error Retry'))):visible.isEmpty?const Center(child:Text('No reactions yet',style:TextStyle(color:authMuted))):ListView.builder(itemCount:visible.length,itemBuilder:(_,index){final item=visible[index];return ListTile(leading:GroopXAvatar(label:item.name,imageUrl:item.avatarUrl,radius:20),title:Text(item.mine?'You':item.name,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:item.mine?const Text('Your reaction'):null,trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text(item.emoji,style:const TextStyle(fontSize:24)),if(item.mine)IconButton(onPressed:removing?null:()=>_remove(item),tooltip:'Remove reaction',icon:const Icon(Icons.close_rounded,size:20))]));})),
    ])));
  }
}

String _contactInitials(String name){
  final parts=name.trim().split(RegExp(r'\s+')).where((part)=>part.isNotEmpty).toList();
  if(parts.isEmpty)return'?';
  String first(String value)=>String.fromCharCode(value.runes.first);
  return(parts.length==1?first(parts.first):'${first(parts.first)}${first(parts.last)}').toUpperCase();
}

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet();
  @override State<_ContactPickerSheet> createState()=>_ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final search=TextEditingController();
  List<DeviceContactCard>? contacts;
  String? error;

  @override void initState(){super.initState();_load();}
  @override void dispose(){search.dispose();super.dispose();}

  Future<void> _load()async{
    setState((){contacts=null;error=null;});
    try{
      final loaded=await DeviceContacts.instance.contacts();
      if(mounted)setState(()=>contacts=loaded);
    }on DeviceContactFailure catch(failure){if(mounted)setState(()=>error=failure.message);}
    catch(_){if(mounted)setState(()=>error='Phone contacts load nahi ho sake. Retry karein.');}
  }

  List<DeviceContactCard> get visible{
    final values=contacts??const<DeviceContactCard>[];
    final query=search.text.trim().toLowerCase();
    if(query.isEmpty)return values;
    final digits=query.replaceAll(RegExp(r'[^0-9]'),'');
    return values.where((contact)=>contact.name.toLowerCase().contains(query)||contact.phone.toLowerCase().contains(query)||(digits.isNotEmpty&&contact.phone.replaceAll(RegExp(r'[^0-9]'),'').contains(digits))).toList(growable:false);
  }

  @override Widget build(BuildContext context){
    final loaded=contacts;
    final results=visible;
    return SizedBox(height:MediaQuery.sizeOf(context).height*.78,child:Column(children:[
      Container(width:42,height:4,margin:const EdgeInsets.only(top:10),decoration:BoxDecoration(color:const Color(0xFFD5D4DC),borderRadius:BorderRadius.circular(4))),
      ListTile(title:const Text('Share contact',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:const Text('Only the contact you choose will be shared.'),trailing:IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close))),
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:TextField(controller:search,onChanged:(_)=>setState((){}),decoration:InputDecoration(hintText:'Search name or number',prefixIcon:const Icon(Icons.search,color:authPurple),filled:true,fillColor:const Color(0xFFF5F2FC),border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none)))),
      const Divider(height:1),
      Expanded(child:loaded==null&&error==null?const Center(child:CircularProgressIndicator(color:authPurple)):error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.contacts_outlined,size:48,color:authMuted),const SizedBox(height:12),Text(error!,textAlign:TextAlign.center,style:const TextStyle(color:authMuted)),const SizedBox(height:14),Wrap(spacing:8,alignment:WrapAlignment.center,children:[OutlinedButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:const Text('Retry')),TextButton(onPressed:openAppSettings,child:const Text('Open settings'))])]))):results.isEmpty?const Center(child:Text('Koi matching contact nahi mila.',style:TextStyle(color:authMuted))):ListView.separated(itemCount:results.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:74),itemBuilder:(_,index){final contact=results[index];return ListTile(onTap:()=>Navigator.pop(context,contact),leading:CircleAvatar(backgroundColor:const Color(0xFFEEE9FF),child:Text(_contactInitials(contact.name),style:const TextStyle(color:authPurple,fontWeight:FontWeight.w800))),title:Text(contact.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(contact.phone,maxLines:1,overflow:TextOverflow.ellipsis),trailing:const Icon(Icons.chevron_right,color:authMuted));})),
    ]));
  }
}

class _ContactCardBody extends StatelessWidget {
  const _ContactCardBody({required this.message});
  final ChatMessage message;

  String get name{
    final value=message.attachment?['display_name']?.toString().trim()??'';
    return value.isEmpty?message.text.replaceFirst(RegExp(r'^Contact:\s*'),'').trim():value;
  }
  String get phone=>message.attachment?['phone']?.toString().trim()??'';

  Future<void> _call(BuildContext context)async{
    var opened=false;
    try{opened=phone.isNotEmpty&&await launchUrl(Uri(scheme:'tel',path:phone),mode:LaunchMode.externalApplication);}catch(_){}
    if(!opened&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Phone dialer open nahi hua.')));
  }

  Future<void> _save(BuildContext context)async{
    final contact=DeviceContactCard(name:name,phone:phone);
    final opened=await DeviceContacts.instance.openContactEditor(contact);
    if(!opened){await Clipboard.setData(ClipboardData(text:phone));if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Contact editor available nahi hai. Number copy ho gaya.')));}
  }

  @override Widget build(BuildContext context)=>SizedBox(width:220,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[CircleAvatar(radius:24,backgroundColor:authPurple,child:Text(_contactInitials(name),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800))),const SizedBox(width:11),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(name.isEmpty?'Shared contact':name,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800,color:authInk)),const SizedBox(height:3),Text(phone,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,color:authMuted))]))]),
    const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Divider(height:1)),
    Row(children:[Expanded(child:TextButton.icon(onPressed:phone.isEmpty?null:()=>_call(context),icon:const Icon(Icons.call_outlined,size:18),label:const Text('Call'))),const SizedBox(width:4),Expanded(child:TextButton.icon(onPressed:phone.isEmpty?null:()=>_save(context),icon:const Icon(Icons.person_add_alt_1_outlined,size:18),label:const Text('Save')))]),
  ]));
}

class _PollDraft {
  const _PollDraft({required this.question,required this.options,required this.allowMultiple});
  final String question;
  final List<String> options;
  final bool allowMultiple;
}

class _PollComposerSheet extends StatefulWidget {
  const _PollComposerSheet();
  @override State<_PollComposerSheet> createState()=>_PollComposerSheetState();
}

class _PollComposerSheetState extends State<_PollComposerSheet> {
  final question=TextEditingController();
  final options=<TextEditingController>[TextEditingController(),TextEditingController()];
  bool allowMultiple=false;

  @override void dispose(){question.dispose();for(final option in options){option.dispose();}super.dispose();}

  String _clean(String value)=>value.trim().replaceAll(RegExp(r'\s+'),' ');

  bool get valid{
    final title=_clean(question.text);
    final values=options.map((option)=>_clean(option.text)).toList();
    return title.isNotEmpty&&title.runes.length<=300&&values.length>=2&&values.length<=12&&values.every((value)=>value.isNotEmpty&&value.runes.length<=120)&&values.map((value)=>value.toLowerCase()).toSet().length==values.length;
  }

  void _addOption(){if(options.length>=12)return;setState(()=>options.add(TextEditingController()));}
  void _removeOption(int index){if(options.length<=2)return;final removed=options.removeAt(index);removed.dispose();setState((){});}
  void _submit(){if(!valid)return;Navigator.pop(context,_PollDraft(question:_clean(question.text),options:options.map((option)=>_clean(option.text)).toList(growable:false),allowMultiple:allowMultiple));}

  @override Widget build(BuildContext context)=>FractionallySizedBox(heightFactor:.9,child:Padding(padding:EdgeInsets.fromLTRB(18,8,18,MediaQuery.viewInsetsOf(context).bottom+12),child:Column(children:[
    Container(width:42,height:4,margin:const EdgeInsets.only(bottom:8),decoration:BoxDecoration(color:const Color(0xFFD5D4DC),borderRadius:BorderRadius.circular(4))),
    Row(children:[const Expanded(child:ListTile(contentPadding:EdgeInsets.zero,title:Text('Create poll',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Ask a question in this chat'))),IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close))]),
    Expanded(child:ListView(children:[
      TextField(controller:question,autofocus:true,maxLength:300,maxLines:3,textCapitalization:TextCapitalization.sentences,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'Question',hintText:'What would you like to ask?',prefixIcon:Icon(Icons.poll_outlined,color:authPurple),border:OutlineInputBorder())),
      const SizedBox(height:8),
      const Text('Options',style:TextStyle(fontWeight:FontWeight.w800,color:authInk)),
      const SizedBox(height:8),
      ...List.generate(options.length,(index)=>Padding(key:ValueKey(options[index]),padding:const EdgeInsets.only(bottom:9),child:TextField(controller:options[index],maxLength:120,textCapitalization:TextCapitalization.sentences,onChanged:(_)=>setState((){}),decoration:InputDecoration(counterText:'',labelText:'Option ${index+1}',prefixIcon:const Icon(Icons.radio_button_unchecked,color:authPurple),suffixIcon:options.length>2?IconButton(onPressed:()=>_removeOption(index),tooltip:'Remove option',icon:const Icon(Icons.close)):null,border:const OutlineInputBorder())))),
      if(options.length<12)Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:_addOption,icon:const Icon(Icons.add),label:const Text('Add option'))),
      SwitchListTile(contentPadding:EdgeInsets.zero,value:allowMultiple,activeColor:authPurple,onChanged:(value)=>setState(()=>allowMultiple=value),title:const Text('Allow multiple answers',style:TextStyle(fontWeight:FontWeight.w700)),subtitle:const Text('People can select more than one option')),
    ])),
    SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:valid?_submit:null,icon:const Icon(Icons.send_rounded),label:const Text('Send poll'))),
  ])));
}

class _PollMessageBody extends StatefulWidget {
  const _PollMessageBody({required this.message,this.onChanged});
  final ChatMessage message;
  final ValueChanged<Map<String,dynamic>>? onChanged;
  @override State<_PollMessageBody> createState()=>_PollMessageBodyState();
}

class _PollMessageBodyState extends State<_PollMessageBody> {
  bool busy=false;
  Map<String,dynamic> get attachment=>widget.message.attachment??const <String,dynamic>{};
  String get pollID=>attachment['poll_id']?.toString()??'';
  bool get closed=>attachment['closed']==true;
  bool get allowMultiple=>attachment['allow_multiple']==true;
  List<Map<String,dynamic>> get options=>(attachment['options'] as List<dynamic>? ?? const[]).whereType<Map>().map((value)=>Map<String,dynamic>.from(value)).toList(growable:false);

  Future<void> _vote(String optionID)async{
    if(busy||closed||pollID.isEmpty||optionID.isEmpty)return;
    final selected=options.where((option)=>option['selected']==true).map((option)=>option['id']?.toString()??'').where((id)=>id.isNotEmpty).toSet();
    if(allowMultiple){if(!selected.add(optionID))selected.remove(optionID);}else{if(selected.length==1&&selected.contains(optionID)){selected.clear();}else{selected..clear()..add(optionID);}}
    setState(()=>busy=true);
    try{final value=await ChatApi.instance.setPollVotes(pollID,selected.toList(growable:false));if(mounted)widget.onChanged?.call(value);}
    catch(failure){if(mounted){final message=failure is DioException&&failure.response?.data is Map?(failure.response!.data as Map)['error']?.toString():null;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message?.isNotEmpty==true?message!:'Vote save nahi hua. Retry karein.')));}}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> _close()async{
    if(busy||closed||pollID.isEmpty)return;
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(title:const Text('Close poll?'),content:const Text('Poll close hone ke baad koi vote change nahi kar sakega.'),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Close poll'))]));
    if(confirmed!=true||!mounted)return;
    setState(()=>busy=true);
    try{final value=await ChatApi.instance.closePoll(pollID);if(mounted)widget.onChanged?.call(value);}
    catch(failure){if(mounted){final message=failure is DioException&&failure.response?.data is Map?(failure.response!.data as Map)['error']?.toString():null;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message?.isNotEmpty==true?message!:'Poll close nahi hua. Retry karein.')));}}
    finally{if(mounted)setState(()=>busy=false);}
  }

  @override Widget build(BuildContext context){
    final values=options;
    final totalVotes=(attachment['total_votes'] as num?)?.toInt()??values.fold<int>(0,(sum,option)=>sum+((option['votes'] as num?)?.toInt()??0));
    final totalVoters=(attachment['total_voters'] as num?)?.toInt()??0;
    final question=attachment['question']?.toString().trim()??widget.message.text.replaceFirst(RegExp(r'^Poll:\s*'),'').trim();
    return SizedBox(width:230,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Padding(padding:EdgeInsets.only(top:2),child:Icon(Icons.poll_outlined,size:19,color:authPurple)),const SizedBox(width:8),Expanded(child:Text(question.isEmpty?'Poll':question,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:14,color:authInk)))]),
      const SizedBox(height:9),
      ...values.map((option){final id=option['id']?.toString()??'';final label=option['text']?.toString()??'';final votes=(option['votes'] as num?)?.toInt()??0;final selected=option['selected']==true;final progress=totalVotes==0?0.0:votes/totalVotes;return Padding(padding:const EdgeInsets.only(bottom:8),child:Material(color:selected?const Color(0xFFE6DDFF):const Color(0xFFF7F5FC),borderRadius:BorderRadius.circular(9),child:InkWell(onTap:busy||closed?null:()=>_vote(id),borderRadius:BorderRadius.circular(9),child:Padding(padding:const EdgeInsets.fromLTRB(9,8,9,7),child:Column(children:[Row(children:[Icon(allowMultiple?(selected?Icons.check_box:Icons.check_box_outline_blank):(selected?Icons.radio_button_checked:Icons.radio_button_unchecked),size:18,color:selected?authPurple:authMuted),const SizedBox(width:7),Expanded(child:Text(label,style:TextStyle(fontSize:12,fontWeight:selected?FontWeight.w700:FontWeight.w500,color:authInk))),Text('$votes',style:const TextStyle(fontSize:10,fontWeight:FontWeight.w700,color:authMuted))]),const SizedBox(height:6),ClipRRect(borderRadius:BorderRadius.circular(3),child:LinearProgressIndicator(value:progress,minHeight:3,backgroundColor:const Color(0xFFE4E1EB),valueColor:const AlwaysStoppedAnimation<Color>(authPurple))) ])))));}),
      Row(children:[if(busy)const Padding(padding:EdgeInsets.only(right:7),child:SizedBox(width:13,height:13,child:CircularProgressIndicator(strokeWidth:1.6,color:authPurple))),Expanded(child:Text(closed?'Poll closed':allowMultiple?'Select one or more':'Select one',style:TextStyle(fontSize:10,color:closed?Colors.red:authMuted,fontWeight:FontWeight.w600))),Text('$totalVoters voter${totalVoters==1?'':'s'}',style:const TextStyle(fontSize:10,color:authMuted))]),
      if(widget.message.mine&&!closed)Padding(padding:const EdgeInsets.only(top:5),child:SizedBox(width:double.infinity,child:TextButton.icon(onPressed:busy?null:_close,icon:const Icon(Icons.lock_outline,size:16),label:const Text('Close poll'),style:TextButton.styleFrom(visualDensity:VisualDensity.compact)))),
    ]));
  }
}

class _AttachmentBody extends StatelessWidget {
  const _AttachmentBody({required this.message,this.onStopLiveLocation,this.onPollChanged,this.onViewOnceOpened});
  final ChatMessage message;
  final VoidCallback? onStopLiveLocation;
  final ValueChanged<Map<String,dynamic>>? onPollChanged;
  final ValueChanged<Map<String,dynamic>>? onViewOnceOpened;
  @override
  Widget build(BuildContext context) {
    final url = message.attachment?['url'] as String?;
    final name=message.attachment?['file_name']?.toString()??message.text;
    final caption=message.attachment?['caption']?.toString().trim()??'';
    if(message.kind=='poll')return _PollMessageBody(message:message,onChanged:onPollChanged);
    if(message.kind=='contact')return _ContactCardBody(message:message);
    if(message.viewOnce)return _ViewOnceBody(message:message,onOpened:onViewOnceOpened);
    if (message.kind == 'image' && url != null) return _captioned(InkWell(onTap:()=>_preview(context,url,name),child:ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 220, height: 160, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fileRow(Icons.broken_image)))),caption);
    if(message.kind=='location'){
      if(message.attachment?['live']==true)return _LiveLocationBody(message:message,onStop:onStopLiveLocation);
      final mapUrl=message.attachment?['map_url']?.toString();
      return InkWell(onTap:mapUrl==null?null:()=>launchUrl(Uri.parse(mapUrl),mode:LaunchMode.externalApplication),child:_fileRow(Icons.location_on));
    }
    if(message.kind=='audio'){
      final duration=(message.attachment?['duration_ms'] as num?)?.toInt()??0;
      if(url!=null)return _VoiceNotePlayer(url:url,durationMs:duration);
      return _fileRow(Icons.audio_file,label:name);
    }
    final file=InkWell(onTap:url==null?null:()=>_preview(context,url,name),child:_fileRow(message.kind == 'video' ? Icons.video_file : Icons.description));
    return message.kind=='video'?_captioned(file,caption):file;
  }
  void _preview(BuildContext context,String url,String name)=>context.push('/attachment',extra:<String,String>{'kind':message.kind,'name':name,'url':url});
  Widget _captioned(Widget child,String caption)=>caption.isEmpty?child:SizedBox(width:220,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[child,const SizedBox(height:7),Text(caption,style:const TextStyle(color:authInk,fontSize:12.5,height:1.3))]));
  Widget _fileRow(IconData icon,{String? label}) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: authPurple), const SizedBox(width: 8), Flexible(child: Text(label??message.attachment?['file_name']?.toString()??message.text, overflow: TextOverflow.ellipsis, style: const TextStyle(color: authInk)))]);
}

class _ViewOnceBody extends StatefulWidget {
  const _ViewOnceBody({required this.message,this.onOpened});
  final ChatMessage message;
  final ValueChanged<Map<String,dynamic>>? onOpened;
  @override State<_ViewOnceBody> createState()=>_ViewOnceBodyState();
}

class _ViewOnceBodyState extends State<_ViewOnceBody> {
  bool busy=false;
  bool get opened=>widget.message.viewOnceOpened;
  int get openedCount=>(widget.message.attachment?['opened_count'] as num?)?.toInt()??0;
  int get recipientCount=>(widget.message.attachment?['recipient_count'] as num?)?.toInt()??0;
  String get mediaLabel=>widget.message.kind=='video'?'video':'photo';

  Future<void> _open()async{
    if(busy||opened||widget.message.mine)return;
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(title:Text('Open view once $mediaLabel?'),content:const Text('Close karne ke baad yeh media dobara open nahi hogi.'),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Open'))]));
    if(confirmed!=true||!mounted)return;
    setState(()=>busy=true);
    try{
      final result=await ChatApi.instance.openViewOnce(widget.message.id);
      final url=result['url']?.toString()??'';
      if(url.isEmpty)throw StateError('View once media unavailable hai');
      final attachment=Map<String,dynamic>.from(widget.message.attachment??const{});attachment['opened']=true;attachment['available']=false;widget.onOpened?.call(attachment);
      if(!mounted)return;
      await context.push('/attachment',extra:<String,String>{'kind':result['kind']?.toString()??widget.message.kind,'name':'View once $mediaLabel','url':url,'one_time':'true'});
    }catch(failure){
      if(!mounted)return;
      var message='View once media open nahi hui. Retry karein.';
      if(failure is DioException&&failure.response?.data is Map&&(failure.response!.data as Map)['error']!=null)message=(failure.response!.data as Map)['error'].toString();
      if(failure is StateError)message=failure.message.toString();
      if(failure is DioException&&failure.response?.statusCode==409){final attachment=Map<String,dynamic>.from(widget.message.attachment??const{});attachment['opened']=true;attachment['available']=false;widget.onOpened?.call(attachment);}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
    }finally{if(mounted)setState(()=>busy=false);}
  }

  @override Widget build(BuildContext context){
    final sentStatus=recipientCount<=0?'Sent as view once':openedCount>=recipientCount?'Opened by everyone':openedCount==0?'Not opened yet':'Opened by $openedCount of $recipientCount';
    final unavailable=opened?'Opened':'View once $mediaLabel';
    return Material(color:const Color(0xFFF4F0FF),borderRadius:BorderRadius.circular(10),child:InkWell(onTap:widget.message.mine||opened||busy?null:_open,borderRadius:BorderRadius.circular(10),child:Container(width:220,padding:const EdgeInsets.all(11),decoration:BoxDecoration(border:Border.all(color:const Color(0xFFD9CEFA)),borderRadius:BorderRadius.circular(10)),child:Row(children:[
      CircleAvatar(radius:20,backgroundColor:widget.message.mine||opened?const Color(0xFFE1DDEB):authPurple,child:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):Text('1',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18,color:widget.message.mine||opened?authMuted:Colors.white))),
      const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(widget.message.mine?'View once $mediaLabel':unavailable,style:TextStyle(fontWeight:FontWeight.w800,color:opened?authMuted:authInk)),const SizedBox(height:2),Text(widget.message.mine?sentStatus:opened?'This media cannot be reopened':'Tap to open once',style:const TextStyle(fontSize:10,color:authMuted))])),
      Icon(widget.message.kind=='video'?Icons.play_circle_outline:Icons.photo_outlined,color:opened?authMuted:authPurple),
    ]))));
  }
}

class _LiveLocationBody extends StatefulWidget {
  const _LiveLocationBody({required this.message,this.onStop});
  final ChatMessage message;
  final VoidCallback? onStop;
  @override State<_LiveLocationBody> createState()=>_LiveLocationBodyState();
}

class _LiveLocationBodyState extends State<_LiveLocationBody> {
  Timer? timer;
  @override void initState(){super.initState();timer=Timer.periodic(const Duration(seconds:20),(_){if(mounted)setState((){});});}
  @override void dispose(){timer?.cancel();super.dispose();}
  bool get active{final attachment=widget.message.attachment;if(attachment?['active']!=true)return false;final expiry=DateTime.tryParse(attachment?['expires_at']?.toString()??'')?.toLocal();return expiry!=null&&expiry.isAfter(DateTime.now());}
  String get status{
    if(!active)return'Live location ended';
    final expiry=DateTime.tryParse(widget.message.attachment?['expires_at']?.toString()??'')!.toLocal();final remaining=expiry.difference(DateTime.now());
    if(remaining.inMinutes<1)return'Ends in less than a minute';
    if(remaining.inHours<1)return'Updates for ${remaining.inMinutes+1} min';
    final minutes=remaining.inMinutes%60;return minutes==0?'Updates for ${remaining.inHours} hr':'Updates for ${remaining.inHours} hr ${minutes} min';
  }
  Future<void> _open()async{final raw=widget.message.attachment?['map_url']?.toString();var opened=false;try{final uri=Uri.tryParse(raw??'');opened=uri!=null&&await launchUrl(uri,mode:LaunchMode.externalApplication);}catch(_){}if(!opened&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Map open nahi hua.')));}
  @override Widget build(BuildContext context)=>SizedBox(width:220,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Material(color:const Color(0xFFE5DDFF),borderRadius:BorderRadius.circular(10),child:InkWell(onTap:_open,borderRadius:BorderRadius.circular(10),child:SizedBox(height:105,width:double.infinity,child:Stack(alignment:Alignment.center,children:[
      Positioned.fill(child:CustomPaint(painter:_MapPatternPainter())),
      CircleAvatar(radius:25,backgroundColor:active?authPurple:authMuted,child:const Icon(Icons.location_on,color:Colors.white,size:29)),
      const Positioned(right:8,top:8,child:CircleAvatar(radius:14,backgroundColor:Colors.white,child:Icon(Icons.open_in_new,size:15,color:authPurple))),
    ])))),
    const SizedBox(height:8),Text(widget.message.text.isEmpty?'Live location':widget.message.text,style:const TextStyle(fontWeight:FontWeight.w800,color:authInk)),
    const SizedBox(height:2),Row(children:[Icon(active?Icons.wifi_tethering:Icons.location_off_outlined,size:14,color:active?Colors.green:authMuted),const SizedBox(width:5),Expanded(child:Text(status,style:TextStyle(fontSize:11,color:active?Colors.green:authMuted,fontWeight:FontWeight.w600)))]),
    if(active&&widget.message.mine&&widget.onStop!=null)Padding(padding:const EdgeInsets.only(top:7),child:SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:widget.onStop,icon:const Icon(Icons.stop_circle_outlined,size:17),label:const Text('Stop sharing'),style:OutlinedButton.styleFrom(foregroundColor:Colors.red,side:const BorderSide(color:Color(0xFFFFB8B8)),visualDensity:VisualDensity.compact)))),
  ]));
}

class _MapPatternPainter extends CustomPainter {
  @override void paint(Canvas canvas,Size size){final paint=Paint()..color=const Color(0xFFCBC0F4)..strokeWidth=1.2;for(double x=-size.height;x<size.width;x+=28){canvas.drawLine(Offset(x,0),Offset(x+size.height,size.height),paint);}paint.color=const Color(0xFFD7CEF6);for(double y=12;y<size.height;y+=25){canvas.drawLine(Offset(0,y),Offset(size.width,y),paint);}}
  @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}

class _VoiceNotePlayer extends StatelessWidget {
  const _VoiceNotePlayer({required this.url,required this.durationMs});
  final String url;
  final int durationMs;
  String _time(int value){final seconds=value~/1000;return '${(seconds~/60).toString().padLeft(2,'0')}:${(seconds%60).toString().padLeft(2,'0')}';}
  String _speed(double value)=>value==value.roundToDouble()?'${value.toInt()}x':'${value.toStringAsFixed(1)}x';
  @override
  Widget build(BuildContext context){
    final controller=VoicePlaybackController.instance;
    return AnimatedBuilder(animation:controller,builder:(_,__) {
      final active=controller.isCurrent(url);
      final total=active&&controller.durationMs>0?controller.durationMs:durationMs;
      final position=active?controller.positionMs:0;
      return SizedBox(width:230,child:Row(children:[
        Semantics(label:active&&controller.playing?'Pause voice message':'Play voice message',button:true,child:IconButton.filled(tooltip:active&&controller.playing?'Pause':'Play',style:IconButton.styleFrom(backgroundColor:authPurple),onPressed:()async{try{await controller.toggle(url,durationMs);}catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Voice note play nahi hua.')));}},icon:controller.loading&&active?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):Icon(active&&controller.playing?Icons.pause:Icons.play_arrow,color:Colors.white))),
        Expanded(child:Column(mainAxisSize:MainAxisSize.min,children:[
          SliderTheme(data:SliderTheme.of(context).copyWith(trackHeight:2,thumbShape:const RoundSliderThumbShape(enabledThumbRadius:5),overlayShape:SliderComponentShape.noOverlay),child:Slider(value:total>0?position.clamp(0,total).toDouble():0,max:total>0?total.toDouble():1,onChanged:active?(value){controller.seek(url,value.toInt());}:null)),
          Padding(padding:const EdgeInsets.only(left:10,right:2),child:Row(children:[
            Expanded(child:Text(active?'${_time(position)} / ${_time(total)}':_time(total),style:const TextStyle(fontSize:10,color:authMuted))),
            Tooltip(message:'Playback speed',child:InkWell(onTap:active&&!controller.loading?()async{try{await controller.cycleSpeed(url);}catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Playback speed change nahi hui.')));}}:null,borderRadius:BorderRadius.circular(12),child:Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:active?const Color(0xFFE8E0FF):const Color(0xFFF1EFF5),borderRadius:BorderRadius.circular(12)),child:Text(_speed(controller.speed),style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:active?authPurple:authMuted))))),
          ])),
        ])),
      ]));
    });
  }
}

class _AttachmentAction extends StatelessWidget {
  const _AttachmentAction({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(backgroundColor: const Color(0xFFEEE9FF), child: Icon(icon, color: authPurple)), const SizedBox(height: 7), Text(label)])));
}
