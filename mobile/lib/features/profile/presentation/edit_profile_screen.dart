import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../auth/data/auth_api.dart';
import '../data/avatar_api.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final name = TextEditingController();
  final username = TextEditingController();
  final bio = TextEditingController();
  final dob = TextEditingController();
  String gender = '';
  String avatarUrl = '';
  bool loading = true;
  bool saving = false;
  bool photoLoading = false;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { name.dispose(); username.dispose(); bio.dispose(); dob.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final profile = await AuthApi.instance.currentUser();
      name.text = profile['full_name']?.toString() ?? '';
      username.text = profile['username']?.toString() ?? '';
      bio.text = profile['bio']?.toString() ?? '';
      dob.text = profile['date_of_birth']?.toString() ?? '';
      gender = profile['gender']?.toString() ?? '';
      avatarUrl = profile['avatar_url']?.toString() ?? '';
    } catch (_) {
      error = 'Profile details load nahi hui.';
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(dob.text) ?? DateTime(2000);
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: DateTime.now());
    if (picked != null) setState(() => dob.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
  }

  Future<void> _photoAction() async {
    final action = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Wrap(children: [
      const ListTile(title: Text('Profile photo', style: TextStyle(fontWeight: FontWeight.w800))),
      ListTile(leading: const Icon(Icons.photo_library_outlined, color: AppColors.purple), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, 'gallery')),
      ListTile(leading: const Icon(Icons.camera_alt_outlined, color: AppColors.purple), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, 'camera')),
      if (avatarUrl.isNotEmpty) ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Remove photo', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'remove')),
    ])));
    if (action == null) return;
    setState(() => photoLoading = true);
    try {
      if (action == 'remove') {
        await AvatarApi.instance.remove();
        avatarUrl = '';
      } else {
        avatarUrl = await AvatarApi.instance.pickAndUpload(action == 'camera' ? ImageSource.camera : ImageSource.gallery) ?? avatarUrl;
      }
      if (mounted) setState(() {});
    } catch (exception) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_photoError(exception))));
    } finally { if (mounted) setState(() => photoLoading = false); }
  }

  Future<void> _save() async {
    final cleanName = name.text.trim();
    final cleanUsername = username.text.trim().replaceAll(' ', '').toLowerCase();
    if (cleanName.isEmpty || cleanUsername.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name aur minimum 3-character username enter karein.')));
      return;
    }
    setState(() => saving = true);
    try {
      await AuthApi.instance.updateProfile(fullName: cleanName, username: cleanUsername, dateOfBirth: dob.text, gender: gender, bio: bio.text.trim());
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated'))); Navigator.pop(context, true); }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile save nahi hua. Username already used ho sakta hai.')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Edit Profile')),
    body: GroopXBackground(child: loading
      ? const Center(child: CircularProgressIndicator())
      : error != null
        ? GroopXEmptyState(icon: Icons.cloud_off_outlined, title: 'Unable to load', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: _load)
        : ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 32), children: [
            Center(child: GestureDetector(onTap: photoLoading ? null : _photoAction, child: Stack(clipBehavior: Clip.none, children: [
              GroopXAvatar(label: name.text.isEmpty ? 'GroopX' : name.text, imageUrl: avatarUrl, radius: 48),
              Positioned(right: -2, bottom: -2, child: CircleAvatar(radius: 16, backgroundColor: Colors.white, child: CircleAvatar(radius: 14, backgroundColor: AppColors.purple, child: photoLoading ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.camera_alt, size: 15, color: Colors.white)))),
            ]))),
            const SizedBox(height: 11),
            const Center(child: Text('Tap to change profile photo', style: TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600, fontSize: 12))),
            const SizedBox(height: 22),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline))),
              const SizedBox(height: 13),
              TextField(controller: username, autocorrect: false, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email), helperText: 'Unique public GroopX ID')),
              const SizedBox(height: 13),
              TextField(controller: dob, readOnly: true, onTap: _pickDate, decoration: const InputDecoration(labelText: 'Date of birth', hintText: 'YYYY-MM-DD', prefixIcon: Icon(Icons.calendar_today_outlined))),
              const SizedBox(height: 13),
              DropdownButtonFormField<String>(value: ['', 'Male', 'Female', 'Non-binary', 'Prefer not to say'].contains(gender) ? gender : '', decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.people_outline)), items: const [
                DropdownMenuItem(value: '', child: Text('Select gender')),
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Non-binary', child: Text('Non-binary')),
                DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
              ], onChanged: (value) => setState(() => gender = value ?? '')),
              const SizedBox(height: 13),
              TextField(controller: bio, maxLength: 160, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio', hintText: 'Tell people a little about yourself', prefixIcon: Icon(Icons.notes_outlined), alignLabelWithHint: true)),
            ]))),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: saving ? null : _save, icon: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check), label: Text(saving ? 'Saving…' : 'Save Changes')),
          ])),
  );

  String _photoError(Object exception) {
    final value = exception.toString().toLowerCase();
    if (value.contains('503') || value.contains('not configured')) return 'Photo storage abhi configure nahi hai.';
    if (value.contains('permission')) return 'Camera ya gallery permission allow karein.';
    if (value.contains('10 mb')) return 'Photo 10 MB se chhoti honi chahiye.';
    return 'Profile photo upload nahi hui. Retry karein.';
  }
}
