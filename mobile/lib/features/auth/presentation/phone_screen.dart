import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_components.dart';
import '../data/auth_api.dart';

enum AuthMode { signIn, signUp }

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.mode});
  final AuthMode mode;
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final phone = TextEditingController();
  bool loading = false;
  @override
  void dispose() { phone.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final signUp = widget.mode == AuthMode.signUp;
    return AuthPage(
      child: Column(children: [
        if (signUp) const _Steps(),
        SizedBox(height: signUp ? 55 : 18),
        GroopXBrand(compact: !signUp),
        SizedBox(height: signUp ? 30 : 54),
        Text(signUp ? 'Sign Up' : 'Welcome Back', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: authInk)),
        const SizedBox(height: 9),
        Text(signUp ? 'Enter your mobile number to get started\nwith GroopX.' : 'Sign in to continue to GroopX', textAlign: TextAlign.center, style: const TextStyle(color: authMuted, height: 1.45)),
        const SizedBox(height: 29),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 25, offset: Offset(0, 8))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mobile Number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: authInk)),
            const SizedBox(height: 10),
            PhoneField(controller: phone),
            const SizedBox(height: 28),
            PurpleButton(label: loading ? 'Sending…' : (signUp ? 'Continue' : 'Sign In'), onPressed: loading ? () {} : () => _requestOtp(signUp)),
          ]),
        ),
        const SizedBox(height: 30),
        const SecurityNote('We will send you a One Time Password (OTP)\nto verify your number'),
        if (!signUp) ...[
          const SizedBox(height: 63),
          GestureDetector(onTap: () => context.go('/sign-up'), child: const Text.rich(TextSpan(children: [TextSpan(text: "Don’t have an account? "), TextSpan(text: 'Sign Up', style: TextStyle(color: authPurple))]), style: TextStyle(fontSize: 12, color: authMuted))),
        ],
      ]),
    );
  }

  Future<void> _requestOtp(bool signUp) async {
    final normalized = '+91${phone.text.replaceAll(RegExp(r'\D'), '')}';
    if (normalized.length < 13) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid mobile number'))); return; }
    setState(() => loading = true);
    try {
      await AuthApi.instance.requestOtp(normalized);
      if (mounted) context.go('/otp/${signUp ? 'sign-up' : 'sign-in'}?phone=${Uri.encodeQueryComponent(normalized)}');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to send OTP. Please try again.')));
    } finally { if (mounted) setState(() => loading = false); }
  }
}

class _Steps extends StatelessWidget {
  const _Steps();
  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: Column(children: [CircleAvatar(radius: 17, backgroundColor: authPurple, child: Text('1')), SizedBox(height: 7), Text('Mobile Number', style: TextStyle(fontSize: 10, color: authPurple))])),
        Container(height: 2, width: 110, color: const Color(0xFFB99BFF)),
        const Expanded(child: Column(children: [CircleAvatar(radius: 17, backgroundColor: Colors.white, child: Text('2', style: TextStyle(color: authInk))), SizedBox(height: 7), Text('Personal Info', style: TextStyle(fontSize: 10, color: authMuted))])),
      ]);
}
