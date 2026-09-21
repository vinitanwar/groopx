import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../data/social_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final search = TextEditingController();
  Timer? debounce;
  List<UserOption> results = const [];
  bool searching = false;
  String? error;
  String? openingUserId;

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        results = const [];
        searching = false;
        error = null;
      });
      return;
    }
    debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final users = await SocialApi.instance.searchUsers(query);
      if (mounted && search.text.trim() == query) setState(() => results = users);
    } catch (_) {
      if (mounted) setState(() => error = 'Users load nahi ho sake. Retry karein.');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _startChat(UserOption user) async {
    setState(() => openingUserId = user.id);
    try {
      final conversationId = await SocialApi.instance.saveContact(
        displayName: user.name,
        phone: '',
        username: user.username,
        notes: '',
      );
      if (mounted) context.go('/chat/$conversationId');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat start nahi ho saki. Dobara try karein.')),
        );
      }
    } finally {
      if (mounted) setState(() => openingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go('/chats')),
          title: const Text('New Message', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: GroopXBackground(child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: TextField(
              controller: search,
              autofocus: true,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: authInk),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: authPurple),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          search.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.close),
                      ),
                labelText: 'Search GroopX users',
                hintText: 'Name, @username or mobile number',
                helperText: 'Kam se kam 2 characters type karein',
              ),
            ),
          ),
          if (searching) const LinearProgressIndicator(color: authPurple),
          Expanded(child: _body()),
        ])),
      );

  Widget _body() {
    final query = search.text.trim();
    if (error != null) {
      return GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Search unavailable', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: () => _search(query));
    }
    if (query.length < 2) {
      return const GroopXEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Find a GroopX user',
        message: 'User ka name, username ya registered mobile number search karein.',
      );
    }
    if (!searching && results.isEmpty) {
      return const GroopXEmptyState(
        icon: Icons.search_off,
        title: 'No user found',
        message: 'Spelling ya registered username/mobile number check karein.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
      itemBuilder: (_, index) {
        final user = results[index];
        final opening = openingUserId == user.id;
        return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          leading: GroopXAvatar(label: user.name),
          title: Text(user.name, style: const TextStyle(color: authInk, fontWeight: FontWeight.w700)),
          subtitle: Text(user.username.isEmpty ? 'GroopX user' : '@${user.username}', style: const TextStyle(color: authMuted)),
          trailing: opening
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chat_bubble_outline, color: authPurple),
          enabled: openingUserId == null,
          onTap: () => _startChat(user),
        ));
      },
    );
  }
}
