import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'auth_components.dart';
import 'phone_screen.dart';
import '../data/auth_api.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.mode, required this.phone});
  final AuthMode mode;
  final String phone;
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final fields = List.generate(6, (_) => TextEditingController());
  bool loading = false;
  @override
  void dispose() { for (final field in fields) { field.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => AuthPage(
        child: Column(children: [
          const SizedBox(height: 7),
          const GroopXBrand(compact: true),
          const SizedBox(height: 52),
          const Text('Verify Your Number', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: authInk)),
          const SizedBox(height: 10),
          const Text('We’ve sent a 6-digit OTP to', style: TextStyle(color: authMuted)),
          const SizedBox(height: 5),
          Text(widget.phone, style: const TextStyle(color: authPurple, fontWeight: FontWeight.w600)),
          const SizedBox(height: 35),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(6, (index) => SizedBox(
            width: 39,
            height: 49,
            child: TextField(
              controller: fields[index],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
              onChanged: (value) { if (value.isNotEmpty && index < 5) FocusScope.of(context).nextFocus(); },
              decoration: InputDecoration(contentPadding: EdgeInsets.zero, enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFD4D8E2)), borderRadius: BorderRadius.circular(8)), focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: authPurple), borderRadius: BorderRadius.circular(8))),
            ),
          ))),
          const SizedBox(height: 44),
          const Text("Didn’t receive the code?", style: TextStyle(color: authMuted)),
          const SizedBox(height: 7),
          const Text.rich(TextSpan(children: [TextSpan(text: 'Resend OTP in '), TextSpan(text: '00:28', style: TextStyle(color: authPurple))]), style: TextStyle(color: authMuted)),
          const SizedBox(height: 28),
          PurpleButton(label: loading ? 'Verifying…' : 'Verify & Continue', onPressed: loading ? () {} : _verify),
          const SizedBox(height: 28),
          const SecurityNote('Your verification code is secure and\nwill expire in 10 minutes.'),
        ]),
      );

  Future<void> _verify() async {
    final code = fields.map((field) => field.text).join();
    if (code.length != 6) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the complete 6-digit OTP'))); return; }
    setState(() => loading = true);
    try {
      await AuthApi.instance.verifyOtp(widget.phone, code);
      if (mounted) context.go(widget.mode == AuthMode.signUp ? '/profile-setup' : '/chats');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid or expired OTP')));
    } finally { if (mounted) setState(() => loading = false); }
  }
}
