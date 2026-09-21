import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_api.dart';
import 'auth_components.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final fullName = TextEditingController();
  final username = TextEditingController();
  final dateOfBirth = TextEditingController();
  String gender = '';
  bool loading = false;

  @override
  void dispose() {
    fullName.dispose();
    username.dispose();
    dateOfBirth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthPage(
    child: Column(children: [
      Row(children: [
        const Expanded(child: Column(children: [CircleAvatar(radius: 17, backgroundColor: authPurple, child: Text('1')), SizedBox(height: 7), Text('Mobile Number', style: TextStyle(fontSize: 10, color: authPurple))])),
        Container(height: 2, width: 110, color: authPurple),
        const Expanded(child: Column(children: [CircleAvatar(radius: 17, backgroundColor: authPurple, child: Text('2')), SizedBox(height: 7), Text('Personal Info', style: TextStyle(fontSize: 10, color: authPurple))])),
      ]),
      const SizedBox(height: 35),
      const GroopXBrand(compact: true),
      const SizedBox(height: 35),
      const Text('Tell us about you', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: authInk)),
      const SizedBox(height: 9),
      const Text('Add your details to personalize\nyour GroopX experience.', textAlign: TextAlign.center, style: TextStyle(color: authMuted, height: 1.5)),
      const SizedBox(height: 25),
      _ProfileField(controller: fullName, icon: Icons.person_outline, hint: 'Full Name'),
      const SizedBox(height: 14),
      _ProfileField(controller: dateOfBirth, icon: Icons.calendar_today_outlined, hint: 'Date of Birth (YYYY-MM-DD)'),
      const SizedBox(height: 14),
      _ProfileField(controller: username, icon: Icons.alternate_email, hint: 'Username', helper: 'This will be your unique ID'),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        value: gender.isEmpty ? null : gender,
        decoration: _decoration(Icons.people_outline, 'Gender'),
        items: const ['Female', 'Male', 'Non-binary', 'Prefer not to say'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
        onChanged: (value) => setState(() => gender = value ?? ''),
      ),
      const SizedBox(height: 24),
      PurpleButton(label: loading ? 'Saving…' : 'Continue', onPressed: loading ? () {} : _submit),
      const SizedBox(height: 25),
      const SecurityNote('Your information is secure and will\nnever be shared.'),
    ]),
  );

  Future<void> _submit() async {
    if (fullName.text.trim().isEmpty || username.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your name and a username of at least 3 characters')));
      return;
    }
    setState(() => loading = true);
    try {
      await AuthApi.instance.updateProfile(
        fullName: fullName.text.trim(),
        username: username.text.trim(),
        dateOfBirth: dateOfBirth.text.trim(),
        gender: gender,
      );
      final invite = await AuthSession.instance.takePendingInvite();
      if (mounted) context.go(invite == null ? '/chats' : '/join/$invite');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile could not be saved. Check the username and date.')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.controller, required this.icon, required this.hint, this.helper});
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final String? helper;
  @override
  Widget build(BuildContext context) => TextField(controller: controller, decoration: _decoration(icon, hint).copyWith(helperText: helper));
}

InputDecoration _decoration(IconData icon, String hint) => InputDecoration(
  prefixIcon: Icon(icon, color: authPurple, size: 20),
  hintText: hint,
  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFD7DAE3)), borderRadius: BorderRadius.circular(10)),
  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: authPurple), borderRadius: BorderRadius.circular(10)),
);
