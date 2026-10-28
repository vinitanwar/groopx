import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/groopx_ui.dart';
import '../../contacts/data/social_api.dart';

class EditGroupScreen extends StatefulWidget {
  const EditGroupScreen({super.key, required this.groupId});
  final String groupId;

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  final name = TextEditingController();
  final description = TextEditingController();
  String privacy = 'private', avatarUrl = '';
  bool loading = true, saving = false, photoLoading = false, admin = false;
  bool announcementOnly = false, joinApprovalRequired = false;
  bool membersCanEditInfo = false, membersCanAddMembers = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final group = await SocialApi.instance.group(widget.groupId);
      final isAdmin = group.admin || group.members.any((member) => member.mine && member.role == 'admin');
      if (!group.canEditInfo && !isAdmin) {
        if (mounted) setState(() { error = 'Only permitted members can edit group info.'; loading = false; });
        return;
      }
      name.text = group.name;
      description.text = group.description;
      if (mounted) {
        setState(() {
          privacy = group.privacy;
          avatarUrl = group.avatarUrl;
          announcementOnly = group.announcementOnly;
          joinApprovalRequired = group.joinApprovalRequired;
          membersCanEditInfo = group.membersCanEditInfo;
          membersCanAddMembers = group.membersCanAddMembers;
          admin = isAdmin;
          error = null;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { error = 'Group details load nahi hui.'; loading = false; });
    }
  }

  Future<void> _photoAction() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(child: Wrap(children: [
        const ListTile(title: Text('Group photo', style: TextStyle(fontWeight: FontWeight.w800))),
        ListTile(leading: const Icon(Icons.photo_library_outlined, color: AppColors.purple), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, 'gallery')),
        ListTile(leading: const Icon(Icons.camera_alt_outlined, color: AppColors.purple), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, 'camera')),
        if (avatarUrl.isNotEmpty) ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Remove photo', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'remove')),
      ])),
    );
    if (action == null) return;
    setState(() => photoLoading = true);
    try {
      if (action == 'remove') {
        await SocialApi.instance.removeGroupAvatar(widget.groupId);
        avatarUrl = '';
      } else {
        avatarUrl = await SocialApi.instance.pickAndUploadGroupAvatar(widget.groupId, action == 'camera' ? ImageSource.camera : ImageSource.gallery) ?? avatarUrl;
      }
      if (mounted) setState(() {});
    } catch (uploadError) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uploadError.toString().contains('5 MB') ? 'Photo 5 MB se chhoti honi chahiye.' : 'Group photo update nahi hui. Retry karein.')));
    } finally {
      if (mounted) setState(() => photoLoading = false);
    }
  }

  Future<void> _save() async {
    if (name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group name minimum 2 characters ka hona chahiye.')));
      return;
    }
    setState(() => saving = true);
    try {
      await SocialApi.instance.updateGroup(
        widget.groupId,
        name: name.text.trim(),
        description: description.text.trim(),
        privacy: privacy,
        announcementOnly: announcementOnly,
        joinApprovalRequired: joinApprovalRequired,
        membersCanEditInfo: membersCanEditInfo,
        membersCanAddMembers: membersCanAddMembers,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group update nahi hua.')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Edit Group')),
    body: GroopXBackground(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? GroopXEmptyState(icon: Icons.lock_outline, title: 'Unable to edit', message: error!, actionLabel: 'Retry', actionIcon: Icons.refresh, onAction: () { setState(() { loading = true; error = null; }); _load(); })
              : ListView(padding: const EdgeInsets.all(18), children: [
                  Center(child: GestureDetector(
                    onTap: photoLoading ? null : _photoAction,
                    child: Stack(clipBehavior: Clip.none, children: [
                      CircleAvatar(radius: 46, backgroundColor: const Color(0xFFEEE9FF), foregroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl), child: avatarUrl.isEmpty ? const Icon(Icons.groups_rounded, size: 48, color: AppColors.purple) : null),
                      Positioned(right: -2, bottom: -2, child: CircleAvatar(radius: 16, backgroundColor: Colors.white, child: CircleAvatar(radius: 14, backgroundColor: AppColors.purple, child: photoLoading ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.camera_alt, size: 15, color: Colors.white)))),
                    ]),
                  )),
                  const SizedBox(height: 9),
                  const Center(child: Text('Tap to change group photo', style: TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600, fontSize: 12))),
                  const SizedBox(height: 24),
                  TextField(controller: name, maxLength: 50, decoration: const InputDecoration(labelText: 'Group name', prefixIcon: Icon(Icons.group_outlined))),
                  const SizedBox(height: 12),
                  TextField(controller: description, maxLength: 200, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.notes_outlined), alignLabelWithHint: true)),
                  if (admin) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(value: privacy, decoration: const InputDecoration(labelText: 'Privacy', prefixIcon: Icon(Icons.lock_outline)), items: const [DropdownMenuItem(value: 'private', child: Text('Private group')), DropdownMenuItem(value: 'public', child: Text('Public group'))], onChanged: (value) => setState(() => privacy = value ?? 'private')),
                    const SizedBox(height: 12),
                    _permissionSwitch(icon: Icons.campaign_outlined, title: 'Announcement mode', subtitle: 'Only admins can send. Members can read, react and vote.', value: announcementOnly, onChanged: (value) => setState(() => announcementOnly = value)),
                    const SizedBox(height: 12),
                    _permissionSwitch(icon: Icons.how_to_reg_outlined, title: 'Approve new members', subtitle: 'Invite link requests need admin approval before joining.', value: joinApprovalRequired, onChanged: (value) => setState(() => joinApprovalRequired = value)),
                    const SizedBox(height: 12),
                    _permissionSwitch(icon: Icons.edit_outlined, title: 'Members can edit group info', subtitle: 'Allow members to change the group name, description and photo.', value: membersCanEditInfo, onChanged: (value) => setState(() => membersCanEditInfo = value)),
                    const SizedBox(height: 12),
                    _permissionSwitch(icon: Icons.person_add_alt_1_outlined, title: 'Members can add participants', subtitle: 'Allow members to add GroopX users directly.', value: membersCanAddMembers, onChanged: (value) => setState(() => membersCanAddMembers = value)),
                    if (privacy == 'private') const Padding(padding: EdgeInsets.only(top: 12), child: Card(child: ListTile(leading: Icon(Icons.privacy_tip_outlined, color: AppColors.purple), title: Text('Private group protection', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('Phone numbers hidden rahenge. Privacy aur admin controls protected hain.')))),
                  ] else ...[
                    const SizedBox(height: 12),
                    const Card(child: ListTile(leading: Icon(Icons.verified_user_outlined, color: AppColors.purple), title: Text('Group info permission', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('Admins allow you to edit the group name, description and photo. Other admin settings stay protected.'))),
                  ],
                  const SizedBox(height: 26),
                  FilledButton.icon(onPressed: saving ? null : _save, icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check), label: Text(saving ? 'Saving…' : 'Save Changes')),
                ]),
    ),
  );

  Widget _permissionSwitch({required IconData icon, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) => Card(
    child: SwitchListTile(value: value, activeColor: AppColors.purple, secondary: Icon(icon, color: AppColors.purple), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(subtitle), onChanged: onChanged),
  );
}
