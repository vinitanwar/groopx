import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/auth_components.dart';
import '../data/chat_socket.dart';
import '../domain/chat_models.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final input = TextEditingController();
  late final ChatSocket socket;
  StreamSubscription<ChatMessage>? subscription;
  final messages = <ChatMessage>[
    const ChatMessage(id: '1', text: 'Hey! Are we still on for the meeting today at 4 PM?', time: '9:30 AM', mine: false),
    const ChatMessage(id: '2', text: "Yes, absolutely! I’ll share the deck before the meeting.", time: '9:31 AM', mine: true),
    const ChatMessage(id: '3', text: 'Great! Here’s the latest design update.', time: '9:32 AM', mine: false),
    const ChatMessage(id: '4', text: 'Looks awesome! 🔥', time: '9:33 AM', mine: true),
    const ChatMessage(id: '5', text: 'Thanks for the voice note! 👍', time: '9:35 AM', mine: true),
  ];

  @override
  void initState() { super.initState(); socket = ChatSocket(widget.conversationId); subscription = socket.messages.listen((message) { if (mounted) setState(() => messages.add(message)); }); }
  @override
  void dispose() { subscription?.cancel(); socket.close(); input.dispose(); super.dispose(); }

  void send() {
    final text = input.text.trim(); if (text.isEmpty) return;
    socket.send(text);
    input.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFBFAFD),
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0, titleSpacing: 0, title: const Row(children: [CircleAvatar(radius: 21, backgroundColor: Color(0xFF37474F), child: Icon(Icons.person, color: Colors.white)), SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Vikram Mehta', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: authInk)), Text('●  Online', style: TextStyle(fontSize: 10, color: Color(0xFF697187)))])]), actions: [IconButton(onPressed: () => context.go('/call/audio/${widget.conversationId}'), icon: const Icon(Icons.call, color: authPurple)), IconButton(onPressed: () => context.go('/call/video/${widget.conversationId}'), icon: const Icon(Icons.videocam, color: authPurple)), const Icon(Icons.more_vert, color: authInk), const SizedBox(width: 8)]),
        body: Column(children: [
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Chip(label: Text('Today', style: TextStyle(fontSize: 10, color: authMuted)), backgroundColor: Color(0xFFF0F0F4), side: BorderSide.none)),
          Expanded(child: ListView.builder(reverse: true, padding: const EdgeInsets.symmetric(horizontal: 15), itemCount: messages.length, itemBuilder: (_, i) { final message = messages[messages.length - 1 - i]; return _Bubble(message: message); })),
          SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(15, 8, 15, 10), decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x10000000), blurRadius: 15)]), child: Row(children: [
            const CircleAvatar(backgroundColor: authPurple, child: Icon(Icons.add, color: Colors.white)),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: input, onSubmitted: (_) => send(), decoration: InputDecoration(hintText: 'Type a message...', filled: true, fillColor: const Color(0xFFF4F2F8), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(23))))),
            IconButton(onPressed: send, icon: const Icon(Icons.send_rounded, color: authPurple)),
            const Icon(Icons.mic, color: authPurple),
          ]))),
        ]),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) => Align(alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.fromLTRB(13, 10, 10, 7), constraints: const BoxConstraints(maxWidth: 265), decoration: BoxDecoration(color: message.mine ? const Color(0xFFEEE9FF) : Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: message.mine ? null : const [BoxShadow(color: Color(0x10000000), blurRadius: 9)]), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(message.text, style: const TextStyle(fontSize: 13, height: 1.35, color: authInk)), const SizedBox(height: 4), Row(mainAxisSize: MainAxisSize.min, children: [Text(message.time, style: const TextStyle(fontSize: 9, color: authMuted)), if (message.mine) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.done_all, size: 13, color: authPurple))])])));
}
