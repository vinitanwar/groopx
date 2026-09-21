import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const authPurple = Color(0xFF6D31FF);
const authInk = Color(0xFF080D28);
const authMuted = Color(0xFF687086);

class AuthPage extends StatelessWidget {
  const AuthPage({super.key, required this.child, this.showBack = true});
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(children: [
            const Positioned(right: -46, top: 65, child: _Glow(size: 145)),
            const Positioned(left: -50, bottom: -42, child: _Glow(size: 150)),
            if (showBack)
              Positioned(left: 13, top: 8, child: IconButton(onPressed: context.pop, icon: const Icon(Icons.arrow_back, color: authInk))),
            Positioned.fill(child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(24, showBack ? 52 : 28, 24, 28),
              child: ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight - (showBack ? 80 : 56)), child: child),
            ))),
          ]),
        ),
      );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: authPurple.withValues(alpha: .045)),
      );
}

class GroopXBrand extends StatelessWidget {
  const GroopXBrand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(Icons.chat_bubble_outline_rounded, size: compact ? 43 : 57, color: authPurple),
        Text.rich(
          const TextSpan(children: [TextSpan(text: 'Groop'), TextSpan(text: 'X', style: TextStyle(color: authPurple))]),
          style: TextStyle(fontSize: compact ? 38 : 49, height: .9, fontWeight: FontWeight.w800, color: authInk),
        ),
        const SizedBox(height: 13),
        const Text('GROUP CHATS. PRIVACY FIRST.', style: TextStyle(fontSize: 10, letterSpacing: 1.1, color: authMuted)),
        const SizedBox(height: 6),
        const Text('NEXT LEVEL. CONNECT.', style: TextStyle(fontSize: 10, letterSpacing: 1.1, color: authPurple)),
      ]);
}

class PurpleButton extends StatelessWidget {
  const PurpleButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: authPurple,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          child: Row(children: [const Spacer(), Text(label, style: const TextStyle(fontSize: 16)), const Spacer(), const Icon(Icons.arrow_forward)]),
        ),
      );
}
class SecurityNote extends StatelessWidget {
  const SecurityNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock_outline, size: 17, color: authPurple),
        const SizedBox(width: 11),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 11, height: 1.45, color: authMuted))),
      ]);
}

class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.controller});
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.phone,
        style: const TextStyle(color: authInk, fontSize: 16, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Enter mobile number',
          prefixIcon: const Padding(padding: EdgeInsets.all(14), child: Text('🇮🇳  +91  ⌄', style: TextStyle(fontSize: 14))),
          prefixIconConstraints: const BoxConstraints(minWidth: 96),
          enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFD6C4FF)), borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: authPurple), borderRadius: BorderRadius.circular(10)),
        ),
      );
}
