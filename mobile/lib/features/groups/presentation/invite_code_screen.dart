import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../auth/data/auth_api.dart';

class InviteCodeScreen extends StatefulWidget {
  const InviteCodeScreen({super.key});

  @override
  State<InviteCodeScreen> createState() => _InviteCodeScreenState();
}

class _InviteCodeScreenState extends State<InviteCodeScreen> {
  final controller = TextEditingController();
  String? error;
  bool loading = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String? _token() {
    var value = controller.text.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      value = uri.pathSegments.last;
    }
    value = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return value.length < 4 ? null : value;
  }

  Future<void> _continue() async {
    final token = _token();
    if (token == null) {
      setState(() => error = 'Valid invite code ya invite link enter karein.');
      return;
    }
    setState(() { loading = true; error = null; });
    final hasSession = await AuthSession.instance.hasSession;
    if (!mounted) return;
    if (hasSession) {
      context.go('/join/$token');
    } else {
      await AuthSession.instance.savePendingInvite(token);
      if (mounted) context.go('/sign-in');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Join a private group'),
      leading: IconButton(
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: GroopXBackground(
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 36, 22, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                  child: Column(
                    children: [
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEE9FF),
                          borderRadius: BorderRadius.circular(27),
                        ),
                        child: const Icon(Icons.group_add_outlined,
                            size: 42, color: AppColors.purple),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Enter your invite code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Private group ke admin se mila code ya complete invite link paste karein.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, height: 1.45),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: controller,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => loading ? null : _continue(),
                        onChanged: (_) {
                          if (error != null) setState(() => error = null);
                        },
                        decoration: InputDecoration(
                          labelText: 'Invite code or link',
                          hintText: 'Example: GX-A7K92 or groopx.app/join/...',
                          prefixIcon: const Icon(Icons.link_rounded),
                          errorText: error,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: loading ? null : _continue,
                          icon: loading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                          label: Text(loading ? 'Checking…' : 'Continue'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 17, color: AppColors.purple),
                          SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'Phone number group members ko visible nahi hoga.',
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
