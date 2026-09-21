import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GroopXBackground extends StatelessWidget {
  const GroopXBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: AppColors.background),
    child: Stack(children: [
      Positioned(right: -75, top: -55, child: _Orb(size: 210, color: AppColors.purple)),
      Positioned(left: -90, bottom: -75, child: _Orb(size: 230, color: AppColors.violet)),
      Positioned.fill(child: child),
    ]),
  );
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .055)));
}

class GroopXEmptyState extends StatelessWidget {
  const GroopXEmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.actionIcon = Icons.add, this.onAction});
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 82, height: 82, decoration: BoxDecoration(color: const Color(0xFFEEE9FF), borderRadius: BorderRadius.circular(26)), child: Icon(icon, size: 40, color: AppColors.purple)),
    const SizedBox(height: 18),
    Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)),
    const SizedBox(height: 8),
    Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.45, color: AppColors.muted)),
    if(actionLabel!=null&&onAction!=null)...[const SizedBox(height: 20),FilledButton.icon(onPressed:onAction,icon:Icon(actionIcon),label:Text(actionLabel!))],
  ])));
}

class GroopXSectionTitle extends StatelessWidget {
  const GroopXSectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text))), if(trailing!=null)trailing!]);
}

class GroopXAvatar extends StatelessWidget {
  const GroopXAvatar({super.key, required this.label, this.imageUrl, this.icon, this.radius=24});
  final String label;
  final String? imageUrl;
  final IconData? icon;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(radius: radius, backgroundColor: const Color(0xFFEEE9FF), foregroundImage: imageUrl?.isNotEmpty==true?NetworkImage(imageUrl!):null, child: icon!=null?Icon(icon,color:AppColors.purple,size:radius):Text(label.trim().isEmpty?'G':label.trim()[0].toUpperCase(),style:TextStyle(color:AppColors.purple,fontWeight:FontWeight.w800,fontSize:radius*.72)));
}
