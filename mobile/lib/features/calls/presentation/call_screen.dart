import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../data/call_api.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.callId, required this.video, this.joinExisting = false});
  final String callId;
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

  @override
  void initState() { super.initState(); _connect(); }

  Future<void> _connect() async {
    try {
      final session = widget.joinExisting
          ? await CallApi.instance.join(widget.callId)
          : await CallApi.instance.start(conversationId: widget.callId, video: widget.video);
      final connectedRoom = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      connectedRoom.addListener(_roomChanged);
      await connectedRoom.connect(session.url, session.token);
      await connectedRoom.localParticipant.setMicrophoneEnabled(true);
      if (widget.video) await connectedRoom.localParticipant.setCameraEnabled(true);
      if (mounted) setState(() { activeCallId = session.id; room = connectedRoom; status = 'Connected'; });
    } catch (failure) { if (mounted) setState(() { error = 'Unable to connect call'; status = 'Connection failed'; }); }
  }

  void _roomChanged() {
    final connectedRoom = room;
    if (connectedRoom != null && mounted) setState(() => status = connectedRoom.remoteParticipants.isEmpty ? 'Waiting for others…' : '${connectedRoom.remoteParticipants.length + 1} participants');
  }

  Future<void> _toggleMute() async {
    final value = !muted;
    await room?.localParticipant.setMicrophoneEnabled(!value);
    if (mounted) setState(() => muted = value);
  }

  Future<void> _toggleCamera() async {
    final value = !camera;
    await room?.localParticipant.setCameraEnabled(value);
    if (mounted) setState(() => camera = value);
  }

  Future<void> _toggleSpeaker() async {
    final value = !speaker;
    await room?.setSpeakerOn(value);
    if (mounted) setState(() => speaker = value);
  }

  Future<void> _end() async {
    if (ending) return;
    setState(() => ending = true);
    try { if (activeCallId != null) await CallApi.instance.end(activeCallId!); } catch (_) {}
    await room?.disconnect();
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    room?.removeListener(_roomChanged);
    room?.disconnect();
    room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { if (!didPop) _end(); }, child: Scaffold(
    backgroundColor: const Color(0xFF060A19),
    body: SafeArea(child: Stack(children: [
      Positioned.fill(child: widget.video ? _videoStage() : _audioStage()),
      Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('GroopX Call', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)), const SizedBox(height: 6), Text(error ?? '${widget.video ? 'Video' : 'Voice'} call • $status', textAlign: TextAlign.center, style: TextStyle(color: error == null ? const Color(0xFFB9BED0) : const Color(0xFFFF7B82))) ]))),
      if (error != null) Center(child: FilledButton(onPressed: () { setState(() { error = null; status = 'Connecting…'; }); _connect(); }, child: const Text('Retry'))),
      Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 35), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _Control(icon: muted ? Icons.mic_off : Icons.mic, active: muted, onTap: _toggleMute),
        _Control(icon: speaker ? Icons.volume_up : Icons.volume_down, active: speaker, onTap: _toggleSpeaker),
        if (widget.video) _Control(icon: camera ? Icons.videocam : Icons.videocam_off, active: !camera, onTap: _toggleCamera),
        _Control(icon: Icons.call_end, danger: true, onTap: _end),
      ]))),
    ])),
  ));

  Widget _audioStage() => Center(child: Padding(padding: const EdgeInsets.only(bottom: 65), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const CircleAvatar(radius: 68, backgroundColor: Color(0xFF6335FF), child: Icon(Icons.person, size: 76, color: Colors.white)),
    const SizedBox(height: 20),
    Text(room?.remoteParticipants.isEmpty == false ? '${room!.remoteParticipants.length + 1} people connected' : 'Waiting for others to join', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
  ])));

  Widget _videoStage() {
    final connectedRoom = room;
    if (connectedRoom == null) return const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF242B43), Color(0xFF080C1D)])), child: Center(child: CircularProgressIndicator(color: Color(0xFF6335FF))));
    final participants = <Participant>[connectedRoom.localParticipant, ...connectedRoom.remoteParticipants.values];
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
  final IconData icon; final VoidCallback onTap; final bool active, danger;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(30), child: CircleAvatar(radius: 28, backgroundColor: danger ? const Color(0xFFFF3B43) : active ? const Color(0xFF6335FF) : const Color(0xFF252B3B), child: Icon(icon, color: Colors.white, size: 25)));
}
