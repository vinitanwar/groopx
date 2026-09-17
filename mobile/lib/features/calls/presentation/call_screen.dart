import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.callId, required this.video});
  final String callId;
  final bool video;
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool muted = false; bool speaker = false; bool camera = true;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF060A19),
    body: SafeArea(child: Stack(children: [
      Positioned.fill(child: widget.video ? Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF242B43), Color(0xFF080C1D)])), child: const Center(child: Icon(Icons.person, size: 180, color: Color(0xFF6C7285)))) : const SizedBox()),
      Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 55), child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: widget.video ? 46 : 62, backgroundColor: const Color(0xFF6335FF), child: const Icon(Icons.person, size: 70, color: Colors.white)), const SizedBox(height: 22), const Text('Vikram Mehta', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: Colors.white)), const SizedBox(height: 8), Text(widget.video ? 'Video call • Connecting…' : 'Voice call • Connecting…', style: const TextStyle(color: Color(0xFFB9BED0))) ]))),
      Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 35), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _Control(icon: muted ? Icons.mic_off : Icons.mic, active: muted, onTap: () => setState(() => muted = !muted)),
        _Control(icon: speaker ? Icons.volume_up : Icons.volume_down, active: speaker, onTap: () => setState(() => speaker = !speaker)),
        if (widget.video) _Control(icon: camera ? Icons.videocam : Icons.videocam_off, active: !camera, onTap: () => setState(() => camera = !camera)),
        _Control(icon: Icons.call_end, danger: true, onTap: () => context.pop()),
      ]))),
    ])),
  );
}

class _Control extends StatelessWidget {
  const _Control({required this.icon, required this.onTap, this.active = false, this.danger = false});
  final IconData icon; final VoidCallback onTap; final bool active, danger;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(30), child: CircleAvatar(radius: 28, backgroundColor: danger ? const Color(0xFFFF3B43) : active ? const Color(0xFF6335FF) : const Color(0xFF252B3B), child: Icon(icon, color: Colors.white, size: 25)));
}
