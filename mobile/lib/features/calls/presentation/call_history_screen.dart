import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../chat/data/presence_socket.dart';
import '../data/call_api.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});
  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> with WidgetsBindingObserver {
  List<CallHistoryItem> items = const [];
  bool loading = true;
  String? error;
  String filter = 'all';
  StreamSubscription<Map<String,dynamic>>? callSubscription;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    callSubscription=PresenceSocket.instance.events.listen((event){if(event['type']=='call_update'){refreshTimer?.cancel();refreshTimer=Timer(const Duration(milliseconds:350),_load);}});
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed)_load();}

  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);callSubscription?.cancel();refreshTimer?.cancel();super.dispose();}

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final value = await CallApi.instance.history();
      if (mounted) setState(() => items = value);
    } catch (_) {
      if (mounted) setState(() => error = 'Call history load nahi hui.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<CallHistoryItem> get visibleItems=>switch(filter){'missed'=>items.where((item)=>item.status=='missed'&&!item.outgoing).toList(),'video'=>items.where((item)=>item.kind=='video').toList(),'audio'=>items.where((item)=>item.kind=='audio').toList(),_=>items};

  Future<void> _call(CallHistoryItem item)async{
    if(item.conversationId.isEmpty)return;
    final active=item.status=='ringing'||item.status=='answered';
    await context.push(active?'/calls/${item.kind}/${item.id}/join':'/call/${item.kind}/${item.conversationId}');
    if(mounted)await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Calls'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
    body: GroopXBackground(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? GroopXEmptyState(icon: Icons.phone_disabled_outlined, title: 'Calls unavailable', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
              : Column(children:[
                  SizedBox(height:58,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.fromLTRB(16,10,16,6),children:[_filter('all','All',Icons.call_outlined),_filter('missed','Missed',Icons.call_missed_outgoing),_filter('video','Video',Icons.videocam_outlined),_filter('audio','Voice',Icons.phone_outlined)])),
                  Expanded(child:RefreshIndicator(
                  onRefresh: _load,
                  child: visibleItems.isEmpty
                      ? ListView(children: const [SizedBox(height: 130), GroopXEmptyState(icon: Icons.call_outlined, title: 'No calls yet', message: 'Audio aur video call history yahan dikhai degi.')])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16,8,16,28),
                          itemCount: visibleItems.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final item = visibleItems[index];
                            final failed = item.status == 'missed' || item.status == 'declined';
                            final showDate=index==0||!_sameDay(visibleItems[index-1].startedAt,item.startedAt);
                            return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[if(showDate)Padding(padding:const EdgeInsets.fromLTRB(4,10,4,7),child:Text(_day(item.startedAt),style:const TextStyle(color:AppColors.muted,fontSize:12,fontWeight:FontWeight.w700))),Card(child: ListTile(
                              onTap:item.conversationId.isEmpty?null:()=>context.push('/chat/${item.conversationId}'),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              leading: GroopXAvatar(label: item.title, imageUrl: item.avatarUrl),
                              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle:Padding(padding:const EdgeInsets.only(top:4),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Icon(item.outgoing?Icons.call_made:Icons.call_received,size:14,color:failed?Colors.red:Colors.green),const SizedBox(width:5),Expanded(child:Text('${_label(item)} · ${item.kind=='video'?'Video':'Voice'}',overflow:TextOverflow.ellipsis))]),const SizedBox(height:3),Text('${_time(item.startedAt)}${item.durationSeconds>0?' · ${_duration(item.durationSeconds)}':''}${item.participantCount>2?' · ${item.participantCount} participants':''}',style:const TextStyle(fontSize:12,color:AppColors.muted))])),
                              isThreeLine:true,
                              trailing: IconButton(
                                tooltip: item.status=='ringing'||item.status=='answered'?'Rejoin call':item.kind == 'video' ? 'Video call' : 'Audio call',
                                onPressed:item.conversationId.isEmpty?null:()=>_call(item),
                                icon: Icon(item.kind == 'video' ? Icons.videocam_outlined : Icons.call_outlined, color: AppColors.purple),
                              ),
                            ))]);
                          },
                        ),
                ))]),
    ),
  );

  Widget _filter(String value,String label,IconData icon)=>Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(selected:filter==value,onSelected:(_)=>setState(()=>filter=value),avatar:Icon(icon,size:17,color:filter==value?AppColors.purple:AppColors.muted),label:Text(label)));
  String _label(CallHistoryItem item) => switch (item.status) { 'missed' => item.outgoing?'No answer':'Missed', 'declined' => item.outgoing?'Declined':'Declined by you', 'answered' => 'Ongoing', 'ringing' => item.outgoing?'Calling':'Incoming', _ => item.outgoing?'Outgoing':'Incoming' };
  bool _sameDay(DateTime a,DateTime b)=>a.year==b.year&&a.month==b.month&&a.day==b.day;
  String _day(DateTime value){final now=DateTime.now(),yesterday=now.subtract(const Duration(days:1));if(_sameDay(value,now))return 'TODAY';if(_sameDay(value,yesterday))return 'YESTERDAY';const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];return '${value.day} ${months[value.month-1]} ${value.year}'.toUpperCase();}
  String _time(DateTime value){final hour=value.hour%12==0?12:value.hour%12;return '$hour:${value.minute.toString().padLeft(2,'0')} ${value.hour>=12?'PM':'AM'}';}
  String _duration(int seconds){final hours=seconds~/3600,minutes=(seconds%3600)~/60,remaining=seconds%60;if(hours>0)return '${hours}h ${minutes}m';if(minutes>0)return '${minutes}m ${remaining}s';return '${remaining}s';}
}
