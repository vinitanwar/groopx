import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../../contacts/data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key, required this.token});
  final String token;

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  bool joining = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    setState(() { joining = true; error = null; });
    try {
      final result = await SocialApi.instance.joinGroupInvite(widget.token);
      if (mounted) context.go(result.kind == 'community' ? '/communities/${result.id}' : '/groups/${result.id}');
    } catch (_) {
      if (mounted) setState(() { joining = false; error = 'Invite invalid, expired, ya pehle hi use ho chuka hai.'; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Join Group')),
    body: GroopXBackground(child:Center(child: Card(margin:const EdgeInsets.all(24),child:Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircleAvatar(radius: 42, backgroundColor: Color(0xFFEEE9FF), child: Icon(Icons.group_add_outlined, size: 42, color: authPurple)),
      const SizedBox(height: 20),
      Text(joining ? 'Joining group…' : 'Could not join group', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: authInk)),
      const SizedBox(height: 10),
      if (joining) const CircularProgressIndicator(color: authPurple) else ...[
        Text(error ?? 'Invite unavailable', textAlign: TextAlign.center, style: const TextStyle(color: authMuted)),
        const SizedBox(height: 20),
        PurpleButton(label: 'Try Again', onPressed: _join),
        TextButton(onPressed: () => context.go('/chats'), child: const Text('Back to Chats')),
      ],
    ]))))),
  );
}
