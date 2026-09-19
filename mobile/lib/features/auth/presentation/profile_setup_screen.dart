import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_api.dart';
import '../data/auth_session.dart';
import 'auth_components.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _dateOfBirth = TextEditingController();
  final _username = TextEditingController();
  String? _gender;
  bool _loading = false;

  @override
  void dispose() {
    _fullName.dispose();
    _dateOfBirth.dispose();
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthPage(
        child: Form(
          key: _formKey,
          child: Column(children: [
            Row(children: [
              const Expanded(child: Column(children: [CircleAvatar(radius: 17, backgroundColor: authPurple, child: Text('1', style: TextStyle(color: Colors.white))), SizedBox(height: 7), Text('Mobile Number', style: TextStyle(fontSize: 10, color: authPurple))])),
              Container(height: 2, width: 110, color: authPurple),
              const Expanded(child: Column(children: [CircleAvatar(radius: 17, backgroundColor: authPurple, child: Text('2', style: TextStyle(color: Colors.white))), SizedBox(height: 7), Text('Personal Info', style: TextStyle(fontSize: 10, color: authPurple))])),
            ]),
            const SizedBox(height: 35),
            const GroopXBrand(compact: true),
            const SizedBox(height: 35),
            const Text('Tell us about you', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: authInk)),
            const SizedBox(height: 9),
            const Text('Add your details to personalize\nyour GroopX experience.', textAlign: TextAlign.center, style: TextStyle(color: authMuted, height: 1.5)),
            const SizedBox(height: 25),
            _field(controller: _fullName, icon: Icons.person_outline, label: 'Full name', hint: 'Example: Vinod Kumar', validator: (value) => value == null || value.trim().length < 2 ? 'Enter your full name' : null),
            const SizedBox(height: 14),
            _field(controller: _dateOfBirth, icon: Icons.calendar_today_outlined, label: 'Date of birth', hint: 'DD/MM/YYYY', readOnly: true, onTap: _selectDate, validator: (value) => value == null || value.isEmpty ? 'Select your date of birth' : null),
            const SizedBox(height: 14),
            _field(controller: _username, icon: Icons.alternate_email, label: 'Username', hint: 'Example: vinod28', helper: 'Your unique GroopX ID (letters, numbers and underscore)', validator: (value) {
              if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value?.trim() ?? '')) return 'Use 3–20 letters, numbers or underscore';
              return null;
            }),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _gender,
              style: const TextStyle(color: authInk, fontSize: 16),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.people_outline, color: authPurple, size: 20), labelText: 'Gender', hintText: 'Select gender'),
              items: const ['Male', 'Female', 'Other', 'Prefer not to say'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
              onChanged: (value) => setState(() => _gender = value),
              validator: (value) => value == null ? 'Select a gender option' : null,
            ),
            const SizedBox(height: 24),
            PurpleButton(label: _loading ? 'Saving…' : 'Continue', onPressed: _loading ? () {} : _submit),
            const SizedBox(height: 25),
            const SecurityNote('Your information is secure and will\nnever be shared.'),
          ]),
        ),
      );

  Widget _field({required TextEditingController controller, required IconData icon, required String label, required String hint, String? helper, bool readOnly = false, VoidCallback? onTap, String? Function(String?)? validator}) => TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        style: const TextStyle(color: authInk, fontSize: 16),
        cursorColor: authPurple,
        decoration: InputDecoration(prefixIcon: Icon(icon, color: authPurple, size: 20), labelText: label, hintText: hint, helperText: helper),
        validator: validator,
      );

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(context: context, initialDate: DateTime(now.year - 18), firstDate: DateTime(1900), lastDate: now);
    if (selected != null) _dateOfBirth.text = '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final token = AuthSession.instance.accessToken;
    if (token == null) {
      if (mounted) context.go('/sign-in');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthApi.instance.updateProfile(accessToken: token, fullName: _fullName.text.trim(), dateOfBirth: _dateOfBirth.text, username: _username.text.trim(), gender: _gender!);
      await AuthSession.instance.saveProfile(fullName: _fullName.text.trim(), username: _username.text.trim(), dateOfBirth: _dateOfBirth.text, gender: _gender!);
      if (mounted) context.go('/chats');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to save profile. Please try again.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
