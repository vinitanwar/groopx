import 'package:flutter/material.dart';
import 'package:groopx/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / 375;
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF050918), Color(0xFF06091A), Color(0xFF020713)],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    SizedBox(height: 51 * scale),
                    _Brand(scale: scale),
                    const Spacer(),
                    _WelcomePanel(scale: scale),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Groop'),
              TextSpan(text: 'X', style: TextStyle(color: AppColors.purple)),
            ]),
            style: TextStyle(fontSize: 47 * scale, fontWeight: FontWeight.w800, height: 1),
          ),
          SizedBox(height: 8 * scale),
          Text('GROUP CHATS. PRIVACY FIRST.', style: TextStyle(fontSize: 9 * scale, letterSpacing: 1.1)),
          SizedBox(height: 7 * scale),
          Text('NEXT LEVEL. CONNECT.', style: TextStyle(fontSize: 9 * scale, color: AppColors.purple, letterSpacing: 1.1)),
        ],
      );
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(44 * scale, 44 * scale, 44 * scale, 51 * scale),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: .96),
          border: Border.all(color: AppColors.purple, width: 1.2),
          borderRadius: BorderRadius.vertical(top: Radius.circular(44 * scale)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Welcome to '),
                TextSpan(text: 'GroopX', style: TextStyle(color: AppColors.purple)),
              ]),
              style: TextStyle(fontSize: 24 * scale, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 17 * scale),
            Text(
              'Connect instantly with private, secure messaging. Upgrade anytime to unlock premium groups, communities, voice calls, and advanced collaboration.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13 * scale, height: 1.28, color: AppColors.muted),
            ),
            SizedBox(height: 24 * scale),
            SizedBox(
              width: double.infinity,
              height: 45 * scale,
              child: FilledButton(
                onPressed: () => context.go('/sign-up'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale)),
                  backgroundColor: AppColors.violet,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('SIGN UP', style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w700)),
                  Icon(Icons.north_east, size: 26 * scale),
                ]),
              ),
            ),
            SizedBox(height: 19 * scale),
            Row(children: [
              const Expanded(child: Divider(color: AppColors.divider)),
              Padding(padding: EdgeInsets.symmetric(horizontal: 17 * scale), child: Text('OR', style: TextStyle(color: AppColors.muted, fontSize: 13 * scale))),
              const Expanded(child: Divider(color: AppColors.divider)),
            ]),
            SizedBox(height: 18 * scale),
            SizedBox(
              width: double.infinity,
              height: 47 * scale,
              child: OutlinedButton.icon(
                onPressed: () => context.go('/sign-up'),
                iconAlignment: IconAlignment.end,
                icon: Icon(Icons.group_add_outlined, color: AppColors.purple, size: 22 * scale),
                label: const Expanded(child: Text('JOIN WITH INVITE CODE')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.purple,
                  side: const BorderSide(color: AppColors.purple),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale)),
                ),
              ),
            ),
            SizedBox(height: 31 * scale),
            GestureDetector(
              onTap: () => context.go('/sign-in'),
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'already have an account? '),
                  TextSpan(text: 'Sign In', style: TextStyle(color: AppColors.purple)),
                ]),
                style: TextStyle(fontSize: 13 * scale, color: AppColors.muted),
              ),
            ),
          ],
        ),
      );
}
