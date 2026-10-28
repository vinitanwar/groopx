import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/call_api.dart';
import '../../chat/data/presence_socket.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.callId, required this.video, this.joinExisting = false, this.reminderId = '', this.meetingTitle = ''});
  final String callId;
  final String reminderId;
  final String meetingTitle;
  final bool video;
  final bool joinExisting;
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Room? room;
  String? activeCallId;
  String status = 'Connecting…';
  String? error;
  bool muted = false, speaker = false, camera = true, ending = false;
  bool connected = false, switchingCamera = false;
  int callSeconds = 0;
  CameraPosition cameraPosition = CameraPosition.front;
  Timer? statusTimer, durationTimer;
  StreamSubscription<Map<String,dynamic>>? callSubscription;

  @override
  void initState() { super.initState();callSubscription=PresenceSocket.instance.events.listen(_handleCallEvent);_connect(); }

  Future<void> _handleCallEvent(Map<String,dynamic> event)async{final id=activeCallId;if(event['type']!='call_update'||id==null||event['call_id']?.toString()!=id||ending)return;final value=event['status']?.toString();if(value=='answered'){_markConnected();}else if(value=='declined'||value=='missed'||value=='ended'){await _finishRemote(value=='declined'?'Call declined':value=='missed'?'No answer':'Call ended');}}
  Future<void> _finishRemote(String message)async{if(ending)return;ending=true;statusTimer?.cancel();durationTimer?.cancel();if(mounted)setState(()=>error=message);await Future<void>.delayed(const Duration(seconds:2));try{await AudioManager.instance.setSpeakerOutputPreferred(false);}catch(_){}await room?.disconnect();if(mounted)context.pop();}

  void _markConnected(){
    if(ending||!mounted)return;
    if(!connected){
      connected=true;
      durationTimer?.cancel();
      durationTimer=Timer.periodic(const Duration(seconds:1),(_){if(mounted&&!ending)setState(()=>callSeconds++);});
    }
    setState(()=>status='Connected');
  }

  String get _durationLabel {
    final hours=callSeconds~/3600;
    final minutes=(callSeconds%3600)~/60;
    final seconds=callSeconds%60;
    final short='${minutes.toString().padLeft(2,'0')}:${seconds.toString().padLeft(2,'0')}';
    return hours==0?short:'${hours.toString().padLeft(2,'0')}:$short';
  }

  Future<void> _connect() async {
    try {
      final permissions=await <Permission>[Permission.microphone,if(widget.video)Permission.camera].request();
      if(permissions.values.any((value)=>!value.isGranted))throw StateError('Microphone${widget.video?' and camera':''} permission required');
      final session = widget.joinExisting
          ? await CallApi.instance.join(widget.callId)
          : await CallApi.instance.start(conversationId: widget.callId, video: widget.video, reminderId: widget.reminderId);
      final connectedRoom = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      connectedRoom.addListener(_roomChanged);
      await connectedRoom.connect(session.url, session.token);
      final localParticipant = connectedRoom.localParticipant;
      if (localParticipant == null) {
        throw StateError('Local participant is unavailable');
      }
      await localParticipant.setMicrophoneEnabled(true);
      if (widget.video) await localParticipant.setCameraEnabled(true,cameraCaptureOptions:const CameraCaptureOptions(cameraPosition:CameraPosition.front));
      var speakerEnabled=false;
      try{await AudioManager.instance.setSpeakerOutputPreferred(widget.video);speakerEnabled=widget.video;}catch(_){}
      if (mounted) setState(() { activeCallId = session.id; room = connectedRoom; speaker=speakerEnabled; status = widget.joinExisting?'Connected':'Ringing…'; });
      if(widget.joinExisting)_markConnected();
      statusTimer?.cancel();statusTimer=Timer.periodic(const Duration(seconds:2),(_)=>_checkStatus());
    } catch (failure) { if (mounted) setState(() { error = _callError(failure); status = 'Connection failed'; }); }
  }

  Future<void> _checkStatus()async{final id=activeCallId;if(id==null||ending)return;try{final value=await CallApi.instance.status(id);if(!mounted)return;if(value.status=='answered'){_markConnected();}else if(value.status=='declined'||value.status=='missed'||value.status=='ended'){await _finishRemote(value.status=='declined'?'Call declined':value.status=='missed'?'No answer':'Call ended');}}catch(_){}}

  String _callError(Object failure){
    if(failure is DioException){final data=failure.response?.data;if(data is Map&&data['error']!=null)return data['error'].toString();}
    return 'Unable to connect call. Internet aur permissions check karein.';
  }

  void _roomChanged() {
    final connectedRoom = room;
    if (connectedRoom == null || !mounted) return;
    if(connectedRoom.remoteParticipants.isNotEmpty){_markConnected();}else if(!connected){setState(()=>status='Waiting for others…');}else{setState((){});}
  }

  Future<void> _toggleMute() async {
    final value = !muted;
    try{await room?.localParticipant?.setMicrophoneEnabled(!value);if (mounted) setState(() => muted = value);}catch(_){_showControlError('Microphone update nahi ho saka.');}
  }

  Future<void> _toggleCamera() async {
    final value = !camera;
    try{
      final participant=room?.localParticipant;
      if(participant==null)return;
      if(value){await participant.setCameraEnabled(true,cameraCaptureOptions:CameraCaptureOptions(cameraPosition:cameraPosition));}
      else{await participant.setCameraEnabled(false);}
      if (mounted) setState(() => camera = value);
    }catch(_){_showControlError('Camera update nahi ho saka.');}
  }

  Future<void> _toggleSpeaker() async {
    final value = !speaker;
    try{await AudioManager.instance.setSpeakerOutputPreferred(value);if (mounted) setState(() => speaker = value);}catch(_){_showControlError('Speaker update nahi ho saka.');}
  }

  Future<void> _switchCamera()async{
    if(switchingCamera||!camera)return;
    LocalVideoTrack? track;
    final publications=room?.localParticipant?.videoTrackPublications;
    if(publications==null)return;
    for(final publication in publications){
      final candidate=publication.track;
      if(candidate is LocalVideoTrack){track=candidate;break;}
    }
    if(track==null)return;
    final next=cameraPosition.switched();
    setState(()=>switchingCamera=true);
    try{await track.setCameraPosition(next);if(mounted)setState(()=>cameraPosition=next);}
    catch(_){_showControlError('Camera switch nahi ho saka.');}
    finally{if(mounted)setState(()=>switchingCamera=false);}
  }

  void _showControlError(String message){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}

  Future<void> _end({bool notifyServer=true}) async {
    if (ending) return;
    setState(() => ending = true);
    statusTimer?.cancel();
    durationTimer?.cancel();
    try { if (notifyServer&&activeCallId != null) await CallApi.instance.end(activeCallId!); } catch (_) {}
    try{await AudioManager.instance.setSpeakerOutputPreferred(false);}catch(_){}
    await room?.disconnect();
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    durationTimer?.cancel();
    callSubscription?.cancel();
    unawaited(AudioManager.instance.setSpeakerOutputPreferred(false).catchError((_){ }));
    room?.removeListener(_roomChanged);
    room?.disconnect();
    room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {final controlsReady=room!=null&&error==null&&!ending;return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { if (!didPop) _end(); }, child: Scaffold(
    backgroundColor: const Color(0xFF060A19),
    body: SafeArea(child: Stack(children: [
      Positioned.fill(child: widget.video ? _videoStage() : _audioStage()),
      Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(widget.meetingTitle.isNotEmpty?widget.meetingTitle:'GroopX Call',maxLines:1,overflow:TextOverflow.ellipsis,style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)), const SizedBox(height: 6), Text(error ?? '${widget.reminderId.isNotEmpty?'Scheduled ':''}${widget.video ? 'video' : 'voice'} call • ${connected?_durationLabel:status}', textAlign: TextAlign.center, style: TextStyle(color: error == null ? const Color(0xFFB9BED0) : const Color(0xFFFF7B82))) ]))),
      if (error != null) Center(child: FilledButton(onPressed: () { setState(() { error = null; status = 'Connecting…'; }); _connect(); }, child: const Text('Retry'))),
      Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 35), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _Control(icon: muted ? Icons.mic_off : Icons.mic, active: muted, onTap: controlsReady?_toggleMute:null),
        _Control(icon: speaker ? Icons.volume_up : Icons.volume_down, active: speaker, onTap: controlsReady?_toggleSpeaker:null),
        if (widget.video) _Control(icon: camera ? Icons.videocam : Icons.videocam_off, active: !camera, onTap: controlsReady?_toggleCamera:null),
        if(widget.video)_Control(icon:Icons.cameraswitch,active:cameraPosition==CameraPosition.back,onTap:controlsReady&&camera&&!switchingCamera?_switchCamera:null),
        _Control(icon: Icons.call_end, danger: true, onTap: ending?null:_end),
      ]))),
    ])),
  ));}

  Widget _audioStage() => Center(child: Padding(padding: const EdgeInsets.only(bottom: 65), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const CircleAvatar(radius: 68, backgroundColor: Color(0xFF6335FF), child: Icon(Icons.person, size: 76, color: Colors.white)),
    const SizedBox(height: 20),
    Text(room?.remoteParticipants.isEmpty == false ? '${room!.remoteParticipants.length + 1} people connected' : (widget.reminderId.isNotEmpty ? 'Waiting for invited participants' : 'Waiting for others to join'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
  ])));

  Widget _videoStage() {
    final connectedRoom = room;
    if (connectedRoom == null) return const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF242B43), Color(0xFF080C1D)])), child: Center(child: CircularProgressIndicator(color: Color(0xFF6335FF))));
    final localParticipant = connectedRoom.localParticipant;
    final participants = <Participant>[
      if (localParticipant != null) localParticipant,
      ...connectedRoom.remoteParticipants.values,
    ];
    return Padding(padding: const EdgeInsets.fromLTRB(8, 88, 8, 105), child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: participants.length <= 1 ? 1 : 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: participants.length <= 2 ? .72 : .82),
      itemCount: participants.length,
      itemBuilder: (_, index) => _ParticipantVideo(participant: participants[index], local: index == 0),
    ));
  }
}

class _ParticipantVideo extends StatelessWidget {
  const _ParticipantVideo({required this.participant, required this.local});
  final Participant participant;
  final bool local;

  @override
  Widget build(BuildContext context) {
    VideoTrack? activeTrack;
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track is VideoTrack && !publication.muted) { activeTrack = track; break; }
    }
    final label = local ? 'You' : participant.name.isNotEmpty ? participant.name : participant.identity;
    return ClipRRect(borderRadius: BorderRadius.circular(18), child: Stack(fit: StackFit.expand, children: [
      if (activeTrack != null) VideoTrackRenderer(activeTrack, fit: VideoViewFit.cover) else Container(color: const Color(0xFF20263A), child: const Icon(Icons.person, size: 70, color: Color(0xFF7C8398))),
      Align(alignment: Alignment.bottomCenter, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)])), child: Row(children: [Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))), if (!participant.isMicrophoneEnabled()) const Icon(Icons.mic_off, size: 17, color: Colors.white)]))),
    ]));
  }
}

class _Control extends StatelessWidget {
  const _Control({required this.icon, required this.onTap, this.active = false, this.danger = false});
  final IconData icon; final VoidCallback? onTap; final bool active, danger;
  @override
  Widget build(BuildContext context) => Opacity(opacity:onTap==null ? .4 : 1,child:InkWell(onTap: onTap, borderRadius: BorderRadius.circular(30), child: CircleAvatar(radius: 28, backgroundColor: danger ? const Color(0xFFFF3B43) : active ? const Color(0xFF6335FF) : const Color(0xFF252B3B), child: Icon(icon, color: Colors.white, size: 25))));
}
