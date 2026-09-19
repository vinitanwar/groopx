import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../data/auth_api.dart';
import '../data/auth_session.dart';
import 'auth_components.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController username;
  late final TextEditingController dob;
  late final TextEditingController bio;
  String gender = 'Prefer not to say';
  String avatarPath = '';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final session = AuthSession.instance;
    name = TextEditingController(text: session.fullName);
    username = TextEditingController(text: session.username);
    dob = TextEditingController(text: session.dateOfBirth);
    bio = TextEditingController(text: session.bio);
    gender = session.gender.isEmpty ? 'Prefer not to say' : session.gender;
    avatarPath = session.avatarUrl;
  }

  @override
  void dispose() { name.dispose(); username.dispose(); dob.dispose(); bio.dispose(); super.dispose(); }

  Future<void> pickPhoto() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82, maxWidth: 1200);
    if (photo != null && mounted) setState(() => avatarPath = photo.path);
  }

  Future<void> selectDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(context: context, initialDate: DateTime(now.year - 18), firstDate: DateTime(1900), lastDate: now);
    if (selected != null) dob.text = '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
  }

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final token = AuthSession.instance.accessToken;
    if (token == null) return;
    setState(() => saving = true);
    try {
      await AuthApi.instance.updateProfile(accessToken: token, fullName: name.text.trim(), username: username.text.trim(), dateOfBirth: dob.text, gender: gender, bio: bio.text.trim(), avatarUrl: avatarPath);
      await AuthSession.instance.saveProfile(fullName: name.text.trim(), username: username.text.trim(), dateOfBirth: dob.text, gender: gender, bio: bio.text.trim(), avatarUrl: avatarPath);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to update profile')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(title: const Text('My Profile'), leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/chats'))),
    body: Form(key: formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
      Center(child: Stack(children: [
        CircleAvatar(radius: 52, backgroundColor: const Color(0xFFF0EBFF), backgroundImage: avatarPath.isNotEmpty && File(avatarPath).existsSync() ? FileImage(File(avatarPath)) : null, child: avatarPath.isEmpty ? const Icon(Icons.person, size: 55, color: authPurple) : null),
        Positioned(right: 0, bottom: 0, child: IconButton.filled(onPressed: pickPhoto, icon: const Icon(Icons.camera_alt_outlined), style: IconButton.styleFrom(backgroundColor: authPurple))),
      ])),
      if (avatarPath.isNotEmpty) Center(child: TextButton(onPressed: () => setState(() => avatarPath = ''), child: const Text('Remove photo'))),
      _field(name, 'Full name', Icons.person_outline, validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter your full name' : null),
      _field(username, 'Username', Icons.alternate_email, validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(v?.trim() ?? '') ? null : 'Use 3–20 letters, numbers or underscore'),
      _field(dob, 'Date of birth', Icons.calendar_today_outlined, readOnly: true, onTap: selectDate, validator: (v) => (v?.isEmpty ?? true) ? 'Select date of birth' : null),
      DropdownButtonFormField<String>(value: gender, decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.people_outline)), items: const ['Male', 'Female', 'Other', 'Prefer not to say'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => gender = v!)),
      const SizedBox(height: 14),
      _field(bio, 'Bio / About', Icons.info_outline, maxLines: 3),
      const SizedBox(height: 24),
      FilledButton(onPressed: saving ? null : save, style: FilledButton.styleFrom(backgroundColor: authPurple, minimumSize: const Size.fromHeight(52)), child: Text(saving ? 'Saving…' : 'Save Changes')),
      TextButton(onPressed: () async { await AuthSession.instance.signOut(); if (context.mounted) context.go('/'); }, child: const Text('Log out', style: TextStyle(color: Colors.red))),
    ])),
  );

  Widget _field(TextEditingController controller, String label, IconData icon, {String? Function(String?)? validator, bool readOnly = false, VoidCallback? onTap, int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(controller: controller, readOnly: readOnly, onTap: onTap, maxLines: maxLines, style: const TextStyle(color: authInk), decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: authPurple)), validator: validator),
  );
}
