import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../data/call_api.dart';
import '../../chat/data/presence_socket.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key, required this.callId, required this.video, this.caller = 'GroopX user', this.meetingTitle = '', this.reminderId = '', this.keepJoinable = false});
  final String callId;
  final String caller;
  final String meetingTitle;
  final String reminderId;
  final bool video;
  final bool keepJoinable;
  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool busy = false;
  bool callLive = false;
  Timer? timer;
  Timer? ringTimer;
  StreamSubscription<Map<String,dynamic>>? callSubscription;

  @override void initState(){super.initState();callSubscription=PresenceSocket.instance.events.listen(_handleCallEvent);_ring();ringTimer=Timer.periodic(const Duration(seconds:2),(_)=>_ring());timer=Timer.periodic(const Duration(seconds:2),(_)=>_check());}
  void _ring(){SystemSound.play(SystemSoundType.alert);HapticFeedback.vibrate();}
  void _stopRinging(){ringTimer?.cancel();ringTimer=null;}
  void _handleCallEvent(Map<String,dynamic> event){if(event['type']!='call_update'||event['call_id']?.toString()!=widget.callId)return;final value=event['status']?.toString()??'ended';if(value=='answered'&&widget.keepJoinable){_markCallLive();}else if(value!='ringing'){_closeForStatus(value);}}
  void _markCallLive(){if(!mounted||callLive||busy)return;_stopRinging();setState(()=>callLive=true);}
  void _closeForStatus(String value){if(!mounted||busy)return;busy=true;timer?.cancel();_stopRinging();final message=value=='missed'?'Missed call':value=='answered'?'Call answered on another device':'Call is no longer available';ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));context.go('/chats');}
  Future<void> _check()async{try{final value=await CallApi.instance.status(widget.callId);if(!mounted)return;if(value.status=='answered'&&widget.keepJoinable){_markCallLive();}else if(value.status!='ringing'){_closeForStatus(value.status);}}catch(_){}}

  Future<void> _decline() async {
    if (busy) return;
    setState(() => busy = true);
    timer?.cancel();
    _stopRinging();
    try { await CallApi.instance.decline(widget.callId); } catch (_) {}
    if (mounted) context.go('/chats');
  }

  void _accept() {
    if (!busy){timer?.cancel();_stopRinging();final meeting=Uri.encodeComponent(widget.reminderId);final title=Uri.encodeComponent(widget.meetingTitle);context.go('/calls/${widget.video ? 'video' : 'audio'}/${widget.callId}/join?meeting=$meeting&title=$title');}
  }

  @override void dispose(){timer?.cancel();_stopRinging();callSubscription?.cancel();super.dispose();}

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: const Color(0xFF080D28),
      body: SafeArea(child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF25204B), Color(0xFF080D28)])),
        padding: const EdgeInsets.fromLTRB(24, 70, 24, 46),
        child: Column(children: [
          Text(callLive?(widget.reminderId.isEmpty?'Group call is live':'Scheduled meeting is live'):(widget.video ? 'Incoming video call' : 'Incoming voice call'), style: const TextStyle(color: Color(0xFFC9C5DC), fontSize: 15)),
          const SizedBox(height: 38),
          const CircleAvatar(radius: 64, backgroundColor: Color(0xFF6D31FF), child: Icon(Icons.person, size: 70, color: Colors.white)),
          const SizedBox(height: 22),
          Text(widget.caller, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
          Text(widget.meetingTitle.isEmpty?'GroopX private call':widget.meetingTitle, maxLines:2, overflow:TextOverflow.ellipsis, textAlign:TextAlign.center, style: const TextStyle(color: Color(0xFFA9A5B9))),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _button(Icons.call_end, callLive?'Not now':'Decline', const Color(0xFFE54555), _decline),
            _button(widget.video ? Icons.videocam : Icons.call, callLive?'Join':'Accept', const Color(0xFF1EBB68), _accept),
          ]),
        ]),
      )),
    ),
  );

  Widget _button(IconData icon, String label, Color color, VoidCallback action) => Column(children: [
    InkWell(
      onTap: busy ? null : action,
      borderRadius: BorderRadius.circular(38),
      child: CircleAvatar(radius: 36, backgroundColor: color, child: busy && (label == 'Decline' || label == 'Not now') ? const CircularProgressIndicator(color: Colors.white) : Icon(icon, size: 32, color: Colors.white)),
    ),
    const SizedBox(height: 10),
    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
  ]);
}
