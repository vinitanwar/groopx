import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_components.dart';
import '../data/device_contacts.dart';
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
  bool syncingContacts = false;
  bool showingPhoneContacts = false;
  int scannedContacts = 0;
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
    setState(() {
      showingPhoneContacts = false;
      if (query.length < 2) {
        results = const [];
        searching = false;
        error = null;
      }
    });
    if (query.length < 2) return;
    debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      searching = true;
      showingPhoneContacts = false;
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

  Future<void> _syncPhoneContacts() async {
    debounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    search.clear();
    setState(() {
      syncingContacts = true;
      showingPhoneContacts = true;
      results = const [];
      scannedContacts = 0;
      error = null;
    });
    try {
      final phones = await DeviceContacts.instance.phoneNumbers();
      final users = await SocialApi.instance.discoverContacts(phones);
      if (mounted) setState(() {
        results = users;
        scannedContacts = phones.length;
      });
    } on DeviceContactFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Phone contacts sync nahi ho sake. Retry karein.');
    } finally {
      if (mounted) setState(() => syncingContacts = false);
    }
  }

  Future<void> _startChat(UserOption user) async {
    setState(() => openingUserId = user.id);
    try {
      final conversationId = await SocialApi.instance.saveContact(
        contactUserId: user.id,
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
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Card(child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              leading: Container(width: 43, height: 43, decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.contacts_outlined, color: authPurple)),
              title: const Text('Find from phone contacts', style: TextStyle(fontWeight: FontWeight.w700, color: authInk)),
              subtitle: const Text('Registered GroopX contacts securely check karein', style: TextStyle(fontSize: 12, color: authMuted)),
              trailing: syncingContacts ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, color: authPurple),
              enabled: !syncingContacts,
              onTap: _syncPhoneContacts,
            )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            child: TextField(
              controller: search,
              enabled: !syncingContacts,
              autofocus: false,
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
      return GroopXEmptyState(icon: Icons.cloud_off_outlined, title: showingPhoneContacts ? 'Contact sync unavailable' : 'Search unavailable', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: showingPhoneContacts ? _syncPhoneContacts : () => _search(query));
    }
    if (syncingContacts && results.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: authPurple));
    }
    if (showingPhoneContacts && !syncingContacts && results.isEmpty) {
      return GroopXEmptyState(
        icon: Icons.person_search_outlined,
        title: 'No GroopX contacts found',
        message: scannedContacts == 0 ? 'Phone mein readable contacts nahi mile.' : '$scannedContacts phone contacts check hue, lekin koi registered GroopX user nahi mila.',
        actionLabel: 'Sync again',
        actionIcon: Icons.sync,
        onAction: _syncPhoneContacts,
      );
    }
    if (!showingPhoneContacts && query.length < 2) {
      return const GroopXEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Find a GroopX user',
        message: 'User ka name, username ya registered mobile number search karein.',
      );
    }
    if (!showingPhoneContacts && !searching && results.isEmpty) {
      return const GroopXEmptyState(
        icon: Icons.search_off,
        title: 'No user found',
        message: 'Spelling ya registered username/mobile number check karein.',
      );
    }
    return Column(children: [
      if (showingPhoneContacts) Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 6), child: Align(alignment: Alignment.centerLeft, child: Text('${results.length} GroopX contact${results.length == 1 ? '' : 's'} found', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: authMuted)))),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
        itemBuilder: (_, index) {
        final user = results[index];
        final opening = openingUserId == user.id;
        return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          leading: GroopXAvatar(label: user.name, imageUrl: user.avatarUrl),
          title: Text(user.name, style: const TextStyle(color: authInk, fontWeight: FontWeight.w700)),
          subtitle: Text(user.username.isEmpty ? (showingPhoneContacts ? 'From phone contacts' : 'GroopX user') : '@${user.username}', style: const TextStyle(color: authMuted)),
          trailing: opening
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chat_bubble_outline, color: authPurple),
          enabled: openingUserId == null,
          onTap: () => _startChat(user),
        ));
        },
      )),
    ]);
  }
}
