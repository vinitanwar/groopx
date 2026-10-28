import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../../calls/data/call_api.dart';
import '../data/notification_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> items = const [];
  int unread = 0;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      if (mounted) setState(() { loading = true; error = null; });
      final result = await NotificationApi.instance.list();
      if (mounted) setState(() { items = result.items; unread = result.unread; loading = false; });
    } catch (_) { if (mounted) setState(() { loading = false; error = 'Unable to load notifications'; }); }
  }

  Future<void> _open(NotificationItem item) async {
    if (!item.read) {
      setState(() { items=items.map((value)=>value.id==item.id?NotificationItem(id:value.id,type:value.type,title:value.title,body:value.body,createdAt:value.createdAt,read:true,data:value.data):value).toList(); unread=unread>0?unread-1:0; });
      try{await NotificationApi.instance.markRead(item.id);}catch(_){await _load();return;}
    }
    final conversationID = item.data['conversation_id'] as String?;
    final groupID = item.data['group_id']?.toString();
    final messageID = item.data['message_id']?.toString();
    final callID = item.data['call_id'] as String?;
    final kind = item.data['kind']?.toString() == 'video' ? 'video' : 'audio';
    if (item.type == 'call' && callID != null && mounted) {
      try{
        final call=await CallApi.instance.status(callID);
        if(!mounted)return;
        if(call.status=='ringing'){await context.push('/calls/$kind/$callID/incoming?caller=${Uri.encodeComponent(item.data['caller']?.toString()??item.title)}');}
        else if(call.status=='answered'){await context.push('/calls/${call.kind}/$callID/join');}
        else{await context.push('/calls');}
      }catch(_){if(mounted)await context.push('/calls');}
    } else if ((item.type == 'meeting_invite' || item.type == 'meeting_response' || item.type == 'meeting_update' || item.type == 'meeting_cancelled') && mounted) {
      await context.push('/reminders');
    } else if (item.type == 'reminder' && mounted) {
      if (item.data['item_type']?.toString() == 'meeting' && conversationID?.isNotEmpty == true) {
        final callKind = item.data['call_kind']?.toString() == 'audio' ? 'audio' : 'video';
        await context.push('/call/$callKind/$conversationID');
      } else {
        await context.push('/reminders');
      }
    } else if (item.type == 'group_join_request' && groupID?.isNotEmpty == true && mounted) {
      await context.push('/groups/$groupID/join-requests');
    } else if (item.type == 'group_join_approved' && groupID?.isNotEmpty == true && mounted) {
      await context.push('/groups/$groupID');
    } else if (conversationID != null && mounted) {
      final target = messageID?.isNotEmpty == true ? '?message=${Uri.encodeQueryComponent(messageID!)}' : '';
      await context.push('/chat/$conversationID$target');
    } else if (mounted) {
      await context.push('/notifications/detail',extra:item);
    }
    await _load();
  }

  Future<void> _readAll() async { await NotificationApi.instance.markAllRead(); await _load(); }

  Future<void> _delete(NotificationItem item)async{
    final index=items.indexWhere((value)=>value.id==item.id);
    if(index<0)return;
    setState((){items=List.of(items)..removeAt(index);if(!item.read)unread=unread>0?unread-1:0;});
    NotificationCenter.instance.setUnread(unread);
    try{await NotificationApi.instance.delete(item.id);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Notification deleted')));}catch(_){await _load();}
  }

  Future<void> _clearRead()async{try{await NotificationApi.instance.clearRead();await _load();}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Read notifications clear nahi hui.')));}}

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(backgroundColor: Colors.white, title: Text(unread > 0 ? 'Notifications ($unread)' : 'Notifications', style: const TextStyle(fontWeight: FontWeight.w700, color: authInk)), actions: [if(unread>0)TextButton(onPressed: _readAll, child: const Text('Read all')),PopupMenuButton<String>(onSelected:(value){if(value=='clear')_clearRead();},itemBuilder:(_)=>const [PopupMenuItem(value:'clear',child:ListTile(contentPadding:EdgeInsets.zero,leading:Icon(Icons.cleaning_services_outlined),title:Text('Clear read')))])]),
    body: GroopXBackground(child: RefreshIndicator(
      onRefresh: _load,
      color: authPurple,
      child: loading
          ? const Center(child: CircularProgressIndicator(color: authPurple))
          : error != null
              ? ListView(children: [SizedBox(height: MediaQuery.sizeOf(context).height*.16), GroopXEmptyState(icon:Icons.cloud_off_outlined,title:'Unable to load',message:error!,actionLabel:'Retry',actionIcon:Icons.refresh,onAction:_load)])
              : items.isEmpty
                  ? ListView(children: const [SizedBox(height:120),GroopXEmptyState(icon:Icons.notifications_none,title:'No notifications yet',message:'New messages, calls aur reminders yahan dikhai denge.')])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16,12,16,28),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height:8),
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return Dismissible(key:ValueKey(item.id),direction:DismissDirection.endToStart,background:Container(alignment:Alignment.centerRight,padding:const EdgeInsets.only(right:24),decoration:BoxDecoration(color:Colors.red.shade400,borderRadius:BorderRadius.circular(18)),child:const Icon(Icons.delete_outline,color:Colors.white)),onDismissed:(_)=>_delete(item),child:Card(color:item.read?Colors.white:const Color(0xFFF5F1FF),child:ListTile(
                          onTap: () => _open(item),
                          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
                          leading: CircleAvatar(backgroundColor: const Color(0xFFEEE9FF), child: Icon(_icon(item.type), color: authPurple)),
                          title: Text(item.title, style: TextStyle(fontWeight: item.read ? FontWeight.w500 : FontWeight.w700, color: authInk)),
                          subtitle: Text('${item.body}\n${_time(item.createdAt)}', maxLines: 3, overflow: TextOverflow.ellipsis),
                          isThreeLine: true,
                          trailing: !item.read ? const CircleAvatar(radius: 4, backgroundColor: authPurple) : null,
                        )));
                      },
                    ),
    )),
  );

  IconData _icon(String type) => type == 'call' ? Icons.call : type == 'media' ? Icons.attach_file : type == 'mention' ? Icons.alternate_email : type == 'announcement' ? Icons.campaign_outlined : type == 'group_join_request' ? Icons.how_to_reg_outlined : type == 'group_join_approved' ? Icons.group_add_outlined : type == 'group_join_rejected' ? Icons.group_off_outlined : type == 'reminder' ? Icons.alarm_outlined : type == 'meeting_invite' ? Icons.event_available_outlined : type == 'meeting_response' ? Icons.how_to_reg_outlined : type == 'meeting_update' ? Icons.edit_calendar_outlined : type == 'meeting_cancelled' ? Icons.event_busy_outlined : type == 'scheduled_message_failed' ? Icons.schedule_send_outlined : Icons.chat_bubble_outline;
  String _time(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} • ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
