import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../data/chat_api.dart';
import '../data/chat_socket.dart';
import '../data/media_api.dart';
import '../domain/chat_models.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final input = TextEditingController();
  final scrollController = ScrollController();
  ChatSocket? socket;
  StreamSubscription<Map<String, dynamic>>? subscription;
  final messages = <ChatMessage>[];
  ConversationDetails? details;
  ChatMessage? replyingTo;
  Timer? typingTimer;
  bool otherTyping = false;
  bool loadingOlder = false;
  String? nextCursor;
  bool loading = true;
  bool uploading = false;
  double uploadProgress = 0;
  String? error;

  @override
  void initState() { super.initState(); scrollController.addListener(_onScroll); _connect(); }

  Future<void> _connect() async {
    try {
	  final results = await Future.wait([ChatApi.instance.messagePage(widget.conversationId), ChatApi.instance.conversation(widget.conversationId)]);
	  final page = results[0] as MessagePage;
	  final history = page.items;
      final info = results[1] as ConversationDetails;
      final connected = await ChatSocket.connect(widget.conversationId);
      subscription = connected.events.listen((event) {
        if (event['type'] == 'message') {
          if (mounted) setState(() => messages.add(ChatMessage.fromJson(event)));
          ChatApi.instance.markRead(widget.conversationId);
        } else if (event['type'] == 'message_update' || event['type'] == 'message_delete' || event['type'] == 'reaction') {
          _refreshMessages();
        } else if (event['type'] == 'read_receipt') {
          _refreshMessages();
        } else if (event['type'] == 'presence' && event['mine'] != true && mounted) {
          setState(() => details = ConversationDetails(title: details?.title ?? 'Conversation', group: details?.group ?? false, online: event['online'] == true, memberCount: details?.memberCount ?? 0, lastSeen: event['online'] == true ? details?.lastSeen : DateTime.now(), otherUserId: details?.otherUserId, blockedByMe: details?.blockedByMe ?? false, communicationBlocked: details?.communicationBlocked ?? false));
        } else if (event['type'] == 'typing' && event['mine'] != true && mounted) {
          setState(() => otherTyping = event['typing'] == true);
        }
      }, onError: (_) { if (mounted) setState(() => error = 'Live connection interrupted'); });
      await ChatApi.instance.markRead(widget.conversationId);
      if (mounted) setState(() { messages..clear()..addAll(history); nextCursor = page.nextCursor; details = info; socket = connected; loading = false; });
    } catch (_) { if (mounted) setState(() { loading = false; error = 'Unable to open this conversation'; }); }
  }

  @override
  void dispose() { typingTimer?.cancel(); subscription?.cancel(); socket?.close(); scrollController.dispose(); input.dispose(); super.dispose(); }

  void _onScroll() { if (scrollController.hasClients && scrollController.position.pixels >= scrollController.position.maxScrollExtent - 140) _loadOlder(); }
  Future<void> _loadOlder() async {
	if (loadingOlder || nextCursor == null) return; setState(() => loadingOlder = true);
	try { final page = await ChatApi.instance.messagePage(widget.conversationId, before: nextCursor); if (mounted) setState(() { messages.insertAll(0,page.items); nextCursor=page.nextCursor; }); }
	finally { if (mounted) setState(() => loadingOlder = false); }
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (details?.communicationBlocked == true) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Communication is blocked'))); return; }
    if (socket == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat is reconnecting'))); return; }
    socket!.send(text, replyToId: replyingTo?.id); socket!.sendTyping(false); input.clear();
    setState(() => replyingTo = null);
  }

  void _typing(String value) {
    if (socket == null || details?.communicationBlocked == true) return;
    typingTimer?.cancel(); socket!.sendTyping(value.trim().isNotEmpty);
    typingTimer = Timer(const Duration(milliseconds: 1200), () => socket?.sendTyping(false));
  }

  Future<void> _upload(FileType type) async {
    Navigator.of(context).pop();
    try {
      setState(() { uploading = true; uploadProgress = 0; });
      await MediaApi.instance.pickAndUpload(conversationId: widget.conversationId, type: type, onProgress: (value) { if (mounted) setState(() => uploadProgress = value); });
    } catch (failure) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $failure')));
    } finally { if (mounted) setState(() => uploading = false); }
  }

  void _showAttachments() => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
    _AttachmentAction(icon: Icons.image, label: 'Image', onTap: () => _upload(FileType.image)),
    _AttachmentAction(icon: Icons.description, label: 'Document', onTap: () => _upload(FileType.any)),
    _AttachmentAction(icon: Icons.audio_file, label: 'Audio', onTap: () => _upload(FileType.audio)),
  ]))));

  Future<void> _refreshMessages() async {
    final page = await ChatApi.instance.messagePage(widget.conversationId);
    if (mounted) setState(() { messages..clear()..addAll(page.items); nextCursor = page.nextCursor; });
  }

  Future<void> _messageActions(ChatMessage message) async {
    final action = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.all(14), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: ['👍','❤️','😂','😮','🙏'].map((emoji) => InkWell(onTap: () => Navigator.pop(context, 'reaction:$emoji'), child: Text(emoji, style: const TextStyle(fontSize: 28)))).toList())),
      ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () => Navigator.pop(context, 'reply')),
      if (message.mine && message.kind == 'text') ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit message'), onTap: () => Navigator.pop(context, 'edit')),
      if (message.mine) ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Delete message', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'delete')),
    ])));
    if (action == null) return;
    if (action == 'reply') { setState(() => replyingTo = message); return; }
    if (action.startsWith('reaction:')) {
      final emoji = action.substring(9); final existing = message.reactions.where((item) => item.emoji == emoji && item.mine).isNotEmpty;
      await ChatApi.instance.react(message.id, emoji, add: !existing);
    } else if (action == 'delete') {
      await ChatApi.instance.deleteMessage(message.id);
    } else if (action == 'edit') {
      final controller = TextEditingController(text: message.text);
      final text = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Edit message'), content: TextField(controller: controller, autofocus: true, maxLines: 4), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save'))]));
      controller.dispose(); if (text != null && text.isNotEmpty) await ChatApi.instance.editMessage(message.id, text);
    }
    await _refreshMessages();
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop:context.canPop(),onPopInvokedWithResult:(didPop,_){if(!didPop)context.go('/chats');},child:Scaffold(
    backgroundColor: const Color(0xFFFBFAFD),
    appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading:IconButton(onPressed:()=>context.go('/chats'),icon:const Icon(Icons.arrow_back)), titleSpacing: 0, title: InkWell(onTap:()=>context.push(details?.group==true?'/groups/${widget.conversationId}':'/contact/${widget.conversationId}'),child:Row(children: [CircleAvatar(radius: 21, backgroundColor: const Color(0xFF37474F), foregroundImage: (details?.avatarUrl?.isNotEmpty ?? false) ? NetworkImage(details!.avatarUrl!) : null, child: Icon(details?.group == true ? Icons.groups : Icons.person, color: Colors.white)), const SizedBox(width: 10), Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(details?.title ?? 'Conversation', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: authInk)), Text(_presenceText(), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: details?.online == true ? Colors.green : const Color(0xFF697187)))]) )])), actions: [IconButton(onPressed: details?.communicationBlocked == true ? null : () => context.push('/call/audio/${widget.conversationId}'), icon: const Icon(Icons.call, color: authPurple)), IconButton(onPressed: details?.communicationBlocked == true ? null : () => context.push('/call/video/${widget.conversationId}'), icon: const Icon(Icons.videocam, color: authPurple)), PopupMenuButton<String>(onSelected: _headerAction, itemBuilder: (_) => [const PopupMenuItem(value: 'search', child: ListTile(leading: Icon(Icons.search), title: Text('Search messages'))),const PopupMenuItem(value:'media',child:ListTile(leading:Icon(Icons.perm_media_outlined),title:Text('Media, links & docs'))),if(details?.group==true)const PopupMenuItem(value:'group',child:ListTile(leading:Icon(Icons.group_outlined),title:Text('Group info'))), if (details?.group != true) const PopupMenuItem(value: 'safety', child: ListTile(leading: Icon(Icons.shield_outlined), title: Text('Safety options')))])]),
    body: Column(children: [
      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Chip(label: Text('Today', style: TextStyle(fontSize: 10, color: authMuted)), backgroundColor: Color(0xFFF0F0F4), side: BorderSide.none)),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator(color: authPurple)) : error != null && messages.isEmpty ? Center(child: TextButton(onPressed: () { setState(() { loading = true; error = null; }); _connect(); }, child: Text('$error — Retry'))) : messages.isEmpty ? const Center(child: Text('Start the conversation', style: TextStyle(color: authMuted))) : ListView.builder(controller: scrollController, reverse: true, padding: const EdgeInsets.symmetric(horizontal: 15), itemCount: messages.length + (loadingOlder ? 1 : 0), itemBuilder: (_, i) { if (i == messages.length) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))); final message = messages[messages.length - 1 - i]; return _Bubble(message: message, onLongPress: () => _messageActions(message)); })),
      if (otherTyping) const Padding(padding: EdgeInsets.fromLTRB(18, 4, 18, 2), child: Align(alignment: Alignment.centerLeft, child: Text('Typing...', style: TextStyle(fontSize: 11, color: authPurple, fontStyle: FontStyle.italic)))),
      if (uploading) LinearProgressIndicator(value: uploadProgress == 0 ? null : uploadProgress, color: authPurple, backgroundColor: const Color(0xFFEEE9FF)),
      if (replyingTo != null) Container(color: const Color(0xFFF2EEFF), padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: Row(children: [const Icon(Icons.reply, size: 18, color: authPurple), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(replyingTo!.mine ? 'Replying to yourself' : 'Replying to message', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: authPurple)), Text(replyingTo!.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: authMuted))])), IconButton(onPressed: () => setState(() => replyingTo = null), icon: const Icon(Icons.close, size: 18))])),
      SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(15, 8, 15, 10), decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x10000000), blurRadius: 15)]), child: Row(children: [
        IconButton(onPressed: uploading || details?.communicationBlocked == true ? null : _showAttachments, style: IconButton.styleFrom(backgroundColor: authPurple), icon: const Icon(Icons.add, color: Colors.white)), const SizedBox(width: 8),
        Expanded(child: TextField(controller: input, onChanged: _typing, onSubmitted: (_) => send(), decoration: InputDecoration(hintText: 'Type a message...', filled: true, fillColor: const Color(0xFFF4F2F8), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(23))))),
        IconButton(onPressed: send, icon: const Icon(Icons.send_rounded, color: authPurple)), IconButton(onPressed: uploading || details?.communicationBlocked == true ? null : _showAttachments, icon: const Icon(Icons.mic, color: authPurple)),
      ]))),
    ]),
  ));

  String _presenceText() {
    if (details?.communicationBlocked == true) return details?.blockedByMe == true ? 'Blocked' : 'Unavailable';
    if (details?.group == true) return '${details?.memberCount ?? 0} members';
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

  void _headerAction(String action) {
    if (action == 'search') context.push('/chat/${widget.conversationId}/search');
    if (action == 'media') context.push('/chat/${widget.conversationId}/media');
    if (action == 'group') context.push('/groups/${widget.conversationId}');
    if (action == 'safety') _safetyActions();
  }

  Future<void> _report(String target) async {
    String reason = 'spam'; final note = TextEditingController();
    final submit = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (_, setDialogState) => AlertDialog(title: const Text('Report user'), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(value: reason, items: const [DropdownMenuItem(value: 'spam', child: Text('Spam')), DropdownMenuItem(value: 'harassment', child: Text('Harassment')), DropdownMenuItem(value: 'impersonation', child: Text('Impersonation')), DropdownMenuItem(value: 'inappropriate', child: Text('Inappropriate content')), DropdownMenuItem(value: 'other', child: Text('Other'))], onChanged: (value) => setDialogState(() => reason = value ?? reason)), TextField(controller: note, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'Details (optional)'))]), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit'))])));
    if (submit == true) { await SocialApi.instance.reportUser(target, conversationId: widget.conversationId, reason: reason, details: note.text.trim()); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted for review'))); }
    note.dispose();
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onLongPress});
  final ChatMessage message;
  final VoidCallback onLongPress;
  @override
  Widget build(BuildContext context) => Align(alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft, child: GestureDetector(onLongPress: onLongPress, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.fromLTRB(13, 10, 10, 7), constraints: const BoxConstraints(maxWidth: 265), decoration: BoxDecoration(color: message.mine ? const Color(0xFFEEE9FF) : Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: message.mine ? null : const [BoxShadow(color: Color(0x10000000), blurRadius: 9)]), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
    if (message.reply != null) Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0x12000000), border: Border(left: BorderSide(color: authPurple, width: 3))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message.reply!.mine ? 'You' : 'Reply', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: authPurple)), Text(message.reply!.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: authMuted))])),
    if (message.isAttachment) _AttachmentBody(message: message) else Text(message.text, style: const TextStyle(fontSize: 13, height: 1.35, color: authInk)),
    if (message.reactions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 4, children: message.reactions.map((item) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: item.mine ? const Color(0xFFDCD1FF) : const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(10)), child: Text('${item.emoji} ${item.count}', style: const TextStyle(fontSize: 11)))).toList())),
    const SizedBox(height: 4), Row(mainAxisSize: MainAxisSize.min, children: [if (message.edited) const Text('edited  ', style: TextStyle(fontSize: 8, color: authMuted)), Text(message.time, style: const TextStyle(fontSize: 9, color: authMuted)), if (message.mine) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(message.delivered ? Icons.done_all : Icons.done, size: 13, color: message.read ? authPurple : authMuted))]),
  ]))));
}

class _AttachmentBody extends StatelessWidget {
  const _AttachmentBody({required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final url = message.attachment?['url'] as String?;
    if (message.kind == 'image' && url != null) return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 220, height: 160, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fileRow(Icons.broken_image)));
    return _fileRow(message.kind == 'audio' ? Icons.play_circle : message.kind == 'video' ? Icons.video_file : Icons.description);
  }
  Widget _fileRow(IconData icon) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: authPurple), const SizedBox(width: 8), Flexible(child: Text(message.attachment?['file_name'] as String? ?? message.text, overflow: TextOverflow.ellipsis, style: const TextStyle(color: authInk)))]);
}

class _AttachmentAction extends StatelessWidget {
  const _AttachmentAction({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(backgroundColor: const Color(0xFFEEE9FF), child: Icon(icon, color: authPurple)), const SizedBox(height: 7), Text(label)])));
}
