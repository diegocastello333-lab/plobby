import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/presentation/home_wiring.dart';
import '../theme/design_tokens.dart';

/// Barra inferior del prototipo: Inicio · Feed · (+) · Ligas · Perfil. El «+» abre el menú de nuevo partido.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Inicio'),
    (Icons.article_outlined, Icons.article_rounded, 'Feed'),
    (Icons.emoji_events_outlined, Icons.emoji_events_rounded, 'Ligas'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    Widget tab(int i) {
      final t = _tabs[i], on = shell.currentIndex == i;
      return Expanded(child: Semantics(button: true, selected: on, label: t.$3, child: InkResponse(
        onTap: () { HapticFeedback.selectionClick(); _go(i); }, radius: 36,
        child: SizedBox(height: 56, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(on ? t.$2 : t.$1, color: on ? AppColors.text : AppColors.textMuted),
          const SizedBox(height: 3),
          Text(t.$3, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? AppColors.text : AppColors.textMuted)),
          const SizedBox(height: 3),
          AnimatedContainer(duration: const Duration(milliseconds: 180), width: on ? 5 : 0, height: 5, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
        ])))));
    }
    return Scaffold(
      body: shell,
      extendBody: true,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: Color(0x14171C19)))),
        child: SafeArea(top: false, child: SizedBox(height: 64, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          tab(0), tab(1),
          SizedBox(width: 76, child: Center(child: Transform.translate(offset: const Offset(0, -18), child: const _PlusButton()))),
          tab(2), tab(3),
        ]))),
      ),
    );
  }
}

class _PlusButton extends StatelessWidget {
  const _PlusButton();
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'Nuevo partido',
        child: Container(
          decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [
            BoxShadow(color: AppColors.surface, spreadRadius: 6),
            BoxShadow(color: Color(0x59171C19), blurRadius: 20, offset: Offset(0, 10), spreadRadius: -4),
          ]),
          child: Material(
            color: AppColors.brand, shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () { HapticFeedback.lightImpact(); HomeNav.newMatch(context); },
              child: const SizedBox(width: 60, height: 60, child: Icon(Icons.add_rounded, size: 30, color: AppColors.brandInk)),
            ),
          ),
        ),
      );
}
