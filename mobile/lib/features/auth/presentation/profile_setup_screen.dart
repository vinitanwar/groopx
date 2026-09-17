import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_components.dart';

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});
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
          const _ProfileField(icon: Icons.person_outline, hint: 'Full Name'),
          const SizedBox(height: 14),
          const _ProfileField(icon: Icons.calendar_today_outlined, hint: 'Date of Birth'),
          const SizedBox(height: 14),
          const _ProfileField(icon: Icons.person_outline, hint: 'Username', helper: 'This will be your unique ID'),
          const SizedBox(height: 14),
          const _ProfileField(icon: Icons.people_outline, hint: 'Gender', trailing: Icons.keyboard_arrow_down),
          const SizedBox(height: 24),
          PurpleButton(label: 'Continue', onPressed: () => context.go('/chats')),
          const SizedBox(height: 25),
          const SecurityNote('Your information is secure and will\nnever be shared.'),
        ]),
      );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.icon, required this.hint, this.helper, this.trailing});
  final IconData icon;
  final String hint;
  final String? helper;
  final IconData? trailing;
  @override
  Widget build(BuildContext context) => TextField(
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: authPurple, size: 20),
          suffixIcon: trailing == null ? null : Icon(trailing, color: authInk),
          hintText: hint,
          helperText: helper,
          enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFD7DAE3)), borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: authPurple), borderRadius: BorderRadius.circular(10)),
        ),
      );
}
