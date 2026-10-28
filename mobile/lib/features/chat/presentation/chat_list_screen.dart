import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/chat_api.dart';
import '../data/live_location_service.dart';
import '../data/presence_socket.dart';
import '../domain/chat_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../profile/data/backup_api.dart';
import '../../notifications/data/notification_api.dart';

const _purple = Color(0xFF6335FF);
const _ink = Color(0xFF080C25);
const _muted = Color(0xFF626A80);

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with WidgetsBindingObserver {
  final searchFocus = FocusNode();
  final searchController=TextEditingController();
  String filter = 'All';
  String query = '';
  List<ChatSummary> chats = const [];
  List<GlobalMessageSearchResult> messageResults=const[];
  Map<String,String> drafts = const {};
  final Set<String> selectedChatIds=<String>{};
  StreamSubscription<Map<String,dynamic>>? liveSubscription;
  Timer? liveRefreshTimer;
  Timer? searchDebounce;
  bool loading = true;
  bool searchingMessages=false;
  bool bulkBusy=false;
  String? error;
  String? messageSearchError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PresenceSocket.instance.start();
    unawaited(LiveLocationService.instance.initialize());
    liveSubscription=PresenceSocket.instance.events.listen(_handleLiveEvent);
    unawaited(BackupScheduler.maybeRun());
    unawaited(NotificationCenter.instance.refresh());
    _start();
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this);liveRefreshTimer?.cancel();searchDebounce?.cancel();liveSubscription?.cancel();searchController.dispose();searchFocus.dispose(); super.dispose(); }

  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed){unawaited(NotificationCenter.instance.refresh());unawaited(_load(showLoading:false));}}

  String get _cacheKey=>filter=='Archived'?'chat_list_archived_cache':'chat_list_cache';
  bool get selectionMode=>selectedChatIds.isNotEmpty;
  List<ChatSummary> get selectedChats=>chats.where((chat)=>selectedChatIds.contains(chat.id)).toList();
  void _handleLiveEvent(Map<String,dynamic> event){
    if(event['type']=='presence'){
      final conversationID=event['conversation_id']?.toString()??'';
      final index=chats.indexWhere((chat)=>chat.id==conversationID&&!chat.group);
      if(index<0||!mounted)return;
      final updated=[...chats];updated[index]=updated[index].copyWith(online:event['online']==true);setState(()=>chats=updated);return;
    }
    if(event['type']!='conversation_update')return;liveRefreshTimer?.cancel();liveRefreshTimer=Timer(const Duration(milliseconds:300),()=>_load(showLoading:false));
  }
  Future<void> _start()async{await _restoreCache();await _load(showLoading:chats.isEmpty);}
  Future<Map<String,String>> _draftsFor(List<ChatSummary> items,SharedPreferences preferences)async{final saved=<String,String>{};for(final chat in items){final value=preferences.getString('chat_draft_${chat.id}')?.trim()??'';if(value.isNotEmpty)saved[chat.id]=value;}return saved;}
  Future<void> _restoreCache()async{final preferences=await SharedPreferences.getInstance();final raw=preferences.getString(_cacheKey);if(raw==null||raw.isEmpty)return;try{final items=(jsonDecode(raw) as List).whereType<Map>().map((item)=>ChatSummary.fromJson(Map<String,dynamic>.from(item))).toList();final saved=await _draftsFor(items,preferences);if(mounted&&items.isNotEmpty)setState((){chats=items;drafts=saved;loading=false;error=null;});}catch(_){await preferences.remove(_cacheKey);}}
  Future<void> _saveCache(List<ChatSummary> items,SharedPreferences preferences)async{await preferences.setString(_cacheKey,jsonEncode(items.map((item)=>{...item.toJson(),'online':false}).toList()));}

  Future<void> _load({bool showLoading=true}) async {
    if(showLoading&&mounted)setState(() { loading = true; error = null; });
    try {
      final items = await ChatApi.instance.conversations(archived: filter == 'Archived');
      final preferences=await SharedPreferences.getInstance();
      final saved=await _draftsFor(items,preferences);await _saveCache(items,preferences);
      if (mounted) setState(() {chats=items;drafts=saved;error=null;selectedChatIds.removeWhere((id)=>!items.any((chat)=>chat.id==id));});
    } catch (_) {
      if (mounted&&chats.isEmpty) setState(() => error = 'Unable to load conversations');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<ChatSummary> get visibleChats => chats.where((chat) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isNotEmpty && !chat.name.toLowerCase().contains(normalized) && !chat.displayPreview.toLowerCase().contains(normalized) && !(drafts[chat.id]?.toLowerCase().contains(normalized)??false)) return false;
    if (filter == 'Groups') return chat.group;
    if (filter == 'Direct') return !chat.group;
    if (filter == 'Unread') return chat.unread > 0;
    if (filter == 'Drafts') return drafts.containsKey(chat.id);
    if (filter == 'Favorites') return chat.favorite;
    return true;
  }).toList();

  void _searchChanged(String value){
    searchDebounce?.cancel();final normalized=value.trim();final previous=query.trim();
    setState((){query=value;messageSearchError=null;if(normalized.length<2){messageResults=const[];searchingMessages=false;}else{if(normalized!=previous)messageResults=const[];searchingMessages=true;}});
    if(normalized.length<2)return;
    searchDebounce=Timer(const Duration(milliseconds:350),()async{
      try{final items=await ChatApi.instance.searchAllMessages(normalized);if(mounted&&query.trim()==normalized)setState((){messageResults=items;searchingMessages=false;});}
      catch(_){if(mounted&&query.trim()==normalized)setState((){searchingMessages=false;messageSearchError='Messages search nahi ho saki. Retry karein.';});}
    });
  }

  Future<void> _setFilter(String value) async {
    final changedArchiveMode = (filter == 'Archived') != (value == 'Archived');
    setState(() {filter = value;selectedChatIds.clear();});
    if (changedArchiveMode){setState((){chats=const[];drafts=const{};loading=true;error=null;});await _restoreCache();await _load(showLoading:chats.isEmpty);}
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop:!selectionMode,
        onPopInvokedWithResult:(didPop,_){if(!didPop&&selectionMode)_clearSelection();},
        child:Scaffold(
        backgroundColor: AppColors.background,
        body: GroopXBackground(child: SafeArea(child: Column(children: [
          if(selectionMode)_selectionHeader()else Padding(padding: const EdgeInsets.fromLTRB(19, 18, 19, 12), child: Row(children: [
            const Text('Chats', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            IconButton(onPressed: () => context.push('/statuses'), tooltip: 'Status updates', icon: const Icon(Icons.auto_awesome_outlined, color: _purple)),
            const _NotificationBell(),
            IconButton(onPressed: () => searchFocus.requestFocus(), tooltip: 'Search chats', icon: const Icon(Icons.search, color: _purple)),
            IconButton(onPressed: () => context.go('/contacts/new'), icon: const Icon(Icons.edit_outlined, color: _purple)),
          ])),
          if(bulkBusy)const LinearProgressIndicator(color:_purple,minHeight:2),
          if(!selectionMode)...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 19), child: TextField(controller:searchController,focusNode:searchFocus,onChanged:_searchChanged,decoration:InputDecoration(prefixIcon:const Icon(Icons.search,size:20),suffixIcon:query.isEmpty?null:IconButton(onPressed:(){searchController.clear();_searchChanged('');},icon:const Icon(Icons.close)),hintText:'Search chats and messages...',filled:true,fillColor:const Color(0xFFF7F7FA),border:OutlineInputBorder(borderSide:BorderSide.none,borderRadius:BorderRadius.circular(13))))),
            const SizedBox(height: 20),
            SizedBox(height: 35, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 19), children: ['All', 'Groups', 'Direct', 'Unread', 'Drafts', 'Favorites', 'Archived'].map((item) => Padding(padding: const EdgeInsets.only(right: 12), child: ChoiceChip(label: Text(item), selected: filter == item, onSelected: (_) => _setFilter(item), selectedColor: const Color(0xFFF0EBFF), labelStyle: TextStyle(color: filter == item ? _purple : _muted), side: const BorderSide(color: Color(0xFFE8E8F0))))).toList())),
            const SizedBox(height: 8),
          ],
          Expanded(child:_content()),
        ]))),
        bottomNavigationBar:selectionMode?null:const _BottomNav(),
      ));

  Widget _selectionHeader(){
    final selected=selectedChats;
    final makeUnread=selected.isNotEmpty&&selected.every((chat)=>chat.unread==0);
    final pin=selected.isNotEmpty&&!selected.every((chat)=>chat.pinned);
    final archive=selected.isNotEmpty&&!selected.every((chat)=>chat.archived);
    return Padding(
      padding:const EdgeInsets.fromLTRB(8,10,8,10),
      child:Row(children:[
        IconButton(onPressed:bulkBusy?null:_clearSelection,tooltip:'Cancel selection',icon:const Icon(Icons.close,color:_ink)),
        Text('${selectedChatIds.length}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:_ink)),
        const Spacer(),
        IconButton(onPressed:bulkBusy?null:()=>unawaited(_runBulk((chat)=>ChatApi.instance.setUnread(chat.id,makeUnread),makeUnread?'marked as unread':'marked as read')),tooltip:makeUnread?'Mark unread':'Mark read',icon:Icon(makeUnread?Icons.mark_email_unread_outlined:Icons.mark_email_read_outlined,color:_purple)),
        IconButton(onPressed:bulkBusy?null:()=>unawaited(_runBulk((chat)=>ChatApi.instance.updatePreferences(chat.id,pinned:pin),pin?'pinned':'unpinned')),tooltip:pin?'Pin chats':'Unpin chats',icon:Icon(pin?Icons.push_pin_outlined:Icons.push_pin,color:_purple)),
        IconButton(onPressed:bulkBusy?null:()=>unawaited(_runBulk((chat)=>ChatApi.instance.archive(chat.id,archive),archive?'archived':'restored')),tooltip:archive?'Archive chats':'Restore chats',icon:Icon(archive?Icons.archive_outlined:Icons.unarchive_outlined,color:_purple)),
        PopupMenuButton<String>(
          enabled:!bulkBusy,
          tooltip:'More bulk actions',
          onSelected:(value)=>unawaited(_selectionMenuAction(value)),
          itemBuilder:(_)=>[
            if(selectedChatIds.length<visibleChats.length)const PopupMenuItem(value:'select_all',child:ListTile(leading:Icon(Icons.select_all),title:Text('Select all'),contentPadding:EdgeInsets.zero)),
            PopupMenuItem(value:'favorite',child:ListTile(leading:Icon(selected.every((chat)=>chat.favorite)?Icons.star:Icons.star_border),title:Text(selected.every((chat)=>chat.favorite)?'Remove favorites':'Add to favorites'),contentPadding:EdgeInsets.zero)),
            PopupMenuItem(value:'mute',child:ListTile(leading:Icon(selected.every((chat)=>chat.muted)?Icons.notifications_active_outlined:Icons.notifications_off_outlined),title:Text(selected.every((chat)=>chat.muted)?'Unmute notifications':'Mute notifications'),contentPadding:EdgeInsets.zero)),
            if(selected.length==1)const PopupMenuItem(value:'more',child:ListTile(leading:Icon(Icons.tune),title:Text('More chat options'),contentPadding:EdgeInsets.zero)),
            const PopupMenuDivider(),
            const PopupMenuItem(value:'delete',child:ListTile(leading:Icon(Icons.delete_outline,color:Colors.red),title:Text('Remove from my chats',style:TextStyle(color:Colors.red)),contentPadding:EdgeInsets.zero)),
          ],
          icon:const Icon(Icons.more_vert,color:_purple),
        ),
      ]),
    );
  }

  void _toggleSelection(String id){
    if(bulkBusy)return;
    setState((){if(!selectedChatIds.add(id))selectedChatIds.remove(id);});
  }

  void _clearSelection(){if(!bulkBusy)setState(selectedChatIds.clear);}

  Future<void> _selectionMenuAction(String action)async{
    final selected=selectedChats;
    if(selected.isEmpty)return;
    if(action=='select_all'){setState(()=>selectedChatIds.addAll(visibleChats.map((chat)=>chat.id)));return;}
    if(action=='favorite'){
      final favorite=!selected.every((chat)=>chat.favorite);
      await _runBulk((chat)=>ChatApi.instance.updatePreferences(chat.id,favorite:favorite),favorite?'added to favorites':'removed from favorites');return;
    }
    if(action=='mute'){await _bulkMute();return;}
    if(action=='more'){
      final chat=selected.first;_clearSelection();await _manage(chat);return;
    }
    if(action=='delete'){
      final count=selected.length;
      final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(title:Text('Remove $count chat${count==1?'':'s'}?'),content:const Text('Chats sirf aapke account se remove honge. New message aane par conversation dobara dikh sakti hai.'),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('Remove'))]))??false;
      if(confirmed)await _runBulk((chat)=>ChatApi.instance.deleteConversation(chat.id),'removed');
    }
  }

  Future<void> _bulkMute()async{
    final selected=selectedChats;if(selected.isEmpty)return;
    final unmute=selected.every((chat)=>chat.muted);
    final seconds=unmute?0:await _chooseMuteDuration();
    if(seconds==null)return;
    await _runBulk((chat)=>ChatApi.instance.updatePreferences(chat.id,muteSeconds:seconds),unmute?'unmuted':'muted');
  }

  Future<int?> _chooseMuteDuration()=>showModalBottomSheet<int>(context:context,builder:(context)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[const ListTile(title:Text('Mute notifications',style:TextStyle(fontWeight:FontWeight.w800))),ListTile(leading:const Icon(Icons.schedule),title:const Text('8 hours'),onTap:()=>Navigator.pop(context,28800)),ListTile(leading:const Icon(Icons.date_range_outlined),title:const Text('1 week'),onTap:()=>Navigator.pop(context,604800)),ListTile(leading:const Icon(Icons.notifications_off_outlined),title:const Text('Always'),onTap:()=>Navigator.pop(context,-1))])));

  Future<void> _runBulk(Future<void> Function(ChatSummary chat) action,String successLabel)async{
    final targets=selectedChats;if(targets.isEmpty||bulkBusy)return;
    setState(()=>bulkBusy=true);
    final failed=<String>{};
    for(final chat in targets){try{await action(chat);}catch(_){failed.add(chat.id);}}
    await _load(showLoading:false);
    if(!mounted)return;
    setState((){bulkBusy=false;selectedChatIds..clear()..addAll(failed);});
    final completed=targets.length-failed.length;
    final message=failed.isEmpty?'${targets.length} chat${targets.length==1?'':'s'} $successLabel':'$completed completed, ${failed.length} failed. Failed chats selected hain.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  }

  Widget _content(){
    if(selectionMode)return ListView.builder(itemCount:visibleChats.length,itemBuilder:(_,index)=>_chatRow(visibleChats[index]));
    if(query.trim().length>=2)return _globalSearchResults();
    if(loading)return const Center(child:CircularProgressIndicator(color:_purple));
    if(error!=null)return GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Chats unavailable',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:()=>_load());
    if(visibleChats.isEmpty)return GroopXEmptyState(icon:Icons.chat_bubble_outline,title:query.trim().isEmpty?'No conversations yet':'No matching chats',message:query.trim().isEmpty?'New message button se kisi user ko search karke conversation start karein.':'Search text ya selected filter change karke dekhein.',actionLabel:query.trim().isEmpty?'New message':null,onAction:query.trim().isEmpty?()=>context.go('/contacts/new'):null);
    return RefreshIndicator(onRefresh:()=>_load(showLoading:false),child:ListView.builder(itemCount:visibleChats.length,itemBuilder:(_,index)=>_chatRow(visibleChats[index])));
  }

  Widget _globalSearchResults(){
    final chatMatches=visibleChats;
    if(chatMatches.isEmpty&&messageResults.isEmpty&&searchingMessages)return const Center(child:CircularProgressIndicator(color:_purple));
    if(chatMatches.isEmpty&&messageResults.isEmpty&&messageSearchError!=null)return GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Search unavailable',message:messageSearchError!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:()=>_searchChanged(query));
    if(chatMatches.isEmpty&&messageResults.isEmpty&&!searchingMessages)return const GroopXEmptyState(icon:Icons.search_off,title:'No results found',message:'Kisi dusre name ya message text se search karein.');
    return ListView(padding:const EdgeInsets.only(bottom:24),children:[
      if(chatMatches.isNotEmpty)_SearchSectionTitle(label:'Chats',count:chatMatches.length),
      ...chatMatches.map(_chatRow),
      if(searchingMessages)const Padding(padding:EdgeInsets.symmetric(horizontal:18,vertical:10),child:LinearProgressIndicator(color:_purple)),
      if(messageSearchError!=null)Padding(padding:const EdgeInsets.fromLTRB(18,10,18,4),child:Row(children:[const Expanded(child:Text('Message results load nahi hue.',style:TextStyle(color:_muted))),TextButton(onPressed:()=>_searchChanged(query),child:const Text('Retry'))])),
      if(messageResults.isNotEmpty)_SearchSectionTitle(label:'Messages',count:messageResults.length),
      ...messageResults.map(_messageResultTile),
    ]);
  }

  Widget _chatRow(ChatSummary chat){
    final selected=selectedChatIds.contains(chat.id);
    return Dismissible(
    key:ValueKey('$filter-${chat.id}'),
    direction:selectionMode?DismissDirection.none:DismissDirection.horizontal,
    confirmDismiss:(direction)=>_swipeAction(chat,direction),
    background:_SwipeActionBackground(alignment:Alignment.centerLeft,color:const Color(0xFFE8F7EC),icon:chat.unread>0?Icons.mark_email_read_outlined:Icons.mark_email_unread_outlined,label:chat.unread>0?'Mark read':'Mark unread'),
    secondaryBackground:_SwipeActionBackground(alignment:Alignment.centerRight,color:const Color(0xFFF0EBFF),icon:chat.archived?Icons.unarchive_outlined:Icons.archive_outlined,label:chat.archived?'Restore':'Archive'),
    child:_ChatTile(chat:chat,draft:drafts[chat.id],selected:selected,onTap:(){if(selectionMode){_toggleSelection(chat.id);return;}unawaited(_openChat(chat.id));},onManage:()=>_toggleSelection(chat.id)),
  );
  }

  Future<void> _openChat(String conversationId)async{await context.push('/chat/$conversationId');await _load(showLoading:false);}

  Widget _messageResultTile(GlobalMessageSearchResult result)=>Card(
    margin:const EdgeInsets.symmetric(horizontal:18,vertical:4),
    child:ListTile(
      onTap:()=>context.push('/chat/${result.conversationId}?message=${result.messageId}'),
      contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:6),
      leading:GroopXAvatar(label:result.conversationTitle,imageUrl:result.avatarUrl,radius:22),
      title:Text(result.text,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:_ink,fontWeight:FontWeight.w600)),
      subtitle:Padding(padding:const EdgeInsets.only(top:5),child:Text(_messageResultSubtitle(result),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:_muted))),
      trailing:const Icon(Icons.arrow_forward_ios_rounded,size:15,color:_muted),
    ),
  );

  String _messageResultSubtitle(GlobalMessageSearchResult result){
    final sender=result.mine?'You':result.senderName;
    final time=result.displayTime;
    return '$sender · ${result.conversationTitle}${time.isEmpty?'':' · $time'}';
  }

  Future<bool> _swipeAction(ChatSummary chat,DismissDirection direction)async{
    try{
      if(direction==DismissDirection.startToEnd){
        final markUnread=chat.unread==0;
        await ChatApi.instance.setUnread(chat.id,markUnread);
        await _load(showLoading:false);
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(markUnread?'Chat marked as unread':'Chat marked as read')));
      }else{
        final archive=!chat.archived;
        await ChatApi.instance.archive(chat.id,archive);
        await _load(showLoading:false);
        if(mounted){
          final messenger=ScaffoldMessenger.of(context);messenger.hideCurrentSnackBar();
          messenger.showSnackBar(SnackBar(content:Text(archive?'Chat archived':'Chat restored'),action:SnackBarAction(label:'Undo',onPressed:()=>unawaited(_undoArchive(chat.id,archive)))));
        }
      }
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Chat action complete nahi hua. Retry karein.')));
    }
    return false;
  }

  Future<void> _undoArchive(String conversationId,bool wasArchived)async{
    try{await ChatApi.instance.archive(conversationId,!wasArchived);await _load(showLoading:false);}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Undo complete nahi hua.')));}
  }

  Future<void> _manage(ChatSummary chat) async {
    final action = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading:Icon(chat.unread>0?Icons.mark_email_read_outlined:Icons.mark_email_unread_outlined),title:Text(chat.unread>0?'Mark as read':'Mark as unread'),onTap:()=>Navigator.pop(context,'read')),
      ListTile(leading:Icon(chat.pinned?Icons.push_pin:Icons.push_pin_outlined),title:Text(chat.pinned?'Unpin chat':'Pin chat'),onTap:()=>Navigator.pop(context,'pin')),
      ListTile(leading: Icon(chat.favorite ? Icons.star : Icons.star_border), title: Text(chat.favorite ? 'Remove from favorites' : 'Add to favorites'), onTap: () => Navigator.pop(context, 'favorite')),
      ListTile(leading: Icon(chat.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined), title: Text(chat.muted ? 'Unmute notifications' : 'Mute notifications'), onTap: () => Navigator.pop(context, 'mute')),
      ListTile(leading: Icon(chat.archived ? Icons.unarchive_outlined : Icons.archive_outlined), title: Text(chat.archived ? 'Restore conversation' : 'Archive conversation'), onTap: () => Navigator.pop(context, 'archive')),
      ListTile(leading:const Icon(Icons.cleaning_services_outlined),title:const Text('Clear chat'),onTap:()=>Navigator.pop(context,'clear')),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Remove from my chats', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'delete')),
    ])));
    if (action == null) return;
    if(action=='read'){await ChatApi.instance.setUnread(chat.id,chat.unread==0);}
    if(action=='pin'){await ChatApi.instance.updatePreferences(chat.id,pinned:!chat.pinned);}
    if (action == 'favorite') { await ChatApi.instance.updatePreferences(chat.id, favorite: !chat.favorite); }
    if(action=='mute'){
      if(chat.muted){await ChatApi.instance.updatePreferences(chat.id,muteSeconds:0);}else{if(!mounted)return;final seconds=await _chooseMuteDuration();if(seconds==null)return;await ChatApi.instance.updatePreferences(chat.id,muteSeconds:seconds);}
    }
    if (action == 'archive') { await ChatApi.instance.archive(chat.id, !chat.archived); }
    if(action=='clear'){
      if(!mounted)return;final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(title:const Text('Clear this chat?'),content:const Text('Messages sirf aapke account se clear honge. Dusre participants ke messages delete nahi honge.'),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Clear chat'))]))??false;
      if(!confirmed)return;await ChatApi.instance.clearConversation(chat.id);final preferences=await SharedPreferences.getInstance();await Future.wait([preferences.remove('chat_draft_${chat.id}'),preferences.remove('chat_history_${chat.id}')]);
    }
    if (action == 'delete') { await ChatApi.instance.deleteConversation(chat.id); }
    await _load();
  }
}

class _SearchSectionTitle extends StatelessWidget{
  const _SearchSectionTitle({required this.label,required this.count});
  final String label;final int count;
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.fromLTRB(19,14,19,7),child:Text('$label ($count)',style:const TextStyle(color:_ink,fontSize:13,fontWeight:FontWeight.w800)));
}

class _SwipeActionBackground extends StatelessWidget{
  const _SwipeActionBackground({required this.alignment,required this.color,required this.icon,required this.label});
  final Alignment alignment;final Color color;final IconData icon;final String label;
  @override
  Widget build(BuildContext context)=>Container(
    color:color,
    alignment:alignment,
    padding:const EdgeInsets.symmetric(horizontal:24),
    child:Row(mainAxisSize:MainAxisSize.min,children:[if(alignment==Alignment.centerRight)Text(label,style:const TextStyle(color:_ink,fontWeight:FontWeight.w700)),if(alignment==Alignment.centerRight)const SizedBox(width:8),Icon(icon,color:_purple),if(alignment==Alignment.centerLeft)const SizedBox(width:8),if(alignment==Alignment.centerLeft)Text(label,style:const TextStyle(color:_ink,fontWeight:FontWeight.w700))]),
  );
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.onTap, required this.onManage,this.draft,this.selected=false});
  final ChatSummary chat;
  final String? draft;
  final bool selected;
  final VoidCallback onTap, onManage;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        onLongPress: onManage,
        child: AnimatedContainer(duration:const Duration(milliseconds:160),color:selected?const Color(0xFFF0EBFF):Colors.transparent,child:Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: SizedBox(height: 73, child: Row(children: [
          Stack(clipBehavior:Clip.none,children: [
            CircleAvatar(radius: 25, backgroundColor: Color(chat.color), foregroundImage: (chat.avatarUrl?.isNotEmpty ?? false) ? NetworkImage(chat.avatarUrl!) : null, child: Icon(chat.group ? Icons.groups_rounded : Icons.person, color: Colors.white, size: 29)),
            if(selected)const Positioned(right:-2,bottom:-2,child:CircleAvatar(radius:10,backgroundColor:_purple,child:Icon(Icons.check,size:13,color:Colors.white)))else if (chat.online) const Positioned(right: 0, bottom: 1, child: CircleAvatar(radius: 5, backgroundColor: Color(0xFF16C653))),
          ]),
          const SizedBox(width: 13),
          Expanded(child: Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F4)))), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [Flexible(child: Text(chat.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink))), if(chat.pinned)const Padding(padding:EdgeInsets.only(left:5),child:Icon(Icons.push_pin,size:13,color:_purple)),if (chat.favorite) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.star, size: 14, color: Color(0xFFFFB300))), if (chat.muted) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.notifications_off, size: 13, color: _muted))]), const SizedBox(height: 5),draft==null?Text(chat.displayPreview,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,height:1.35,color:_muted)):Text.rich(TextSpan(children:[const TextSpan(text:'Draft: ',style:TextStyle(color:_purple,fontWeight:FontWeight.w700)),TextSpan(text:draft)]),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,height:1.35,color:_muted))])),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(chat.time, style: TextStyle(fontSize: 11, color: chat.unread > 0 ? _purple : _muted)), if (chat.unread > 0) ...[const SizedBox(height: 8), CircleAvatar(radius: 10, backgroundColor: _purple, child: Text('${chat.unread}', style: const TextStyle(fontSize: 10, color: Colors.white)))]])
          ]))),
        ])))),
      );
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();
  @override
  Widget build(BuildContext context)=>ValueListenableBuilder<int>(
    valueListenable:NotificationCenter.instance.unread,
    builder:(_,count,__)=>Stack(clipBehavior:Clip.none,children:[
      IconButton(onPressed:()async{await context.push('/notifications');unawaited(NotificationCenter.instance.refresh());},tooltip:'Notifications',icon:const Icon(Icons.notifications_none,color:_purple)),
      if(count>0)Positioned(right:5,top:4,child:Container(
        padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),
        constraints:const BoxConstraints(minWidth:18),
        decoration:BoxDecoration(color:Colors.red,borderRadius:BorderRadius.circular(10),border:Border.all(color:Colors.white,width:1.5)),
        child:Text(count>99?'99+':'$count',textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.w700)),
      )),
    ]),
  );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      height: 72,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 9),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18)],
      ),
      child: Row(children: [
        const Expanded(child: _NavItem(Icons.chat_bubble, 'Chat', true)),
        Expanded(child: _NavItem(Icons.groups_outlined, 'Group', false, onTap: () => context.go('/communities'))),
        Expanded(child: _NavItem(Icons.add_circle_outline, 'New Chat', false, emphasized: true, onTap: () => context.push('/contacts/new'))),
        Expanded(child: _NavItem(Icons.calendar_month_outlined, 'Schedule', false, onTap: () => context.go('/reminders'))),
        Expanded(child: _NavItem(Icons.person_outline, 'Profile', false, onTap: () => context.go('/profile'))),
      ]),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.icon, this.label, this.selected, {this.onTap, this.emphasized = false});
  final IconData icon; final String label; final bool selected;
  final VoidCallback? onTap;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: selected ? _purple : _muted, size: emphasized ? 28 : 22),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: TextStyle(fontSize: 10, color: selected ? _purple : _muted)),
            ),
          ),
        ]),
      ),
    ),
  );
}
