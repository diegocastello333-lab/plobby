import '../../features/gamification/presentation/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/home/presentation/home_wiring.dart';
import '../theme/design_tokens.dart';
import '../../features/tournaments/presentation/competitions_screen.dart';
import '../motion/app_motion.dart';
import '../widgets/ambient_background.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/plobby_icon.dart';

/// Barra inferior — `#nav` del prototipo HTML (medidas de getComputedStyle):
/// 92 px, blanca, borde superior 1 px tinta .08, padding 10 4 0, cinco columnas iguales.
/// Pestaña: 56 px, padding-top 2, separación 4, icono 24 (trazo 1.8), etiqueta Inter 12; activa tinta 700, inactiva
/// gris 400 (sin punto ni fondo). Centro: botón «+» lima de 60 px, subido 30 px, aro blanco de 6 px y sombra.
/// El «+» abre el menú de nuevo partido (misma acción que antes).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [(PlobbyIcons.home, 'Inicio'), (PlobbyIcons.feed, 'Feed'), (PlobbyIcons.trophy, 'Competiciones'), (PlobbyIcons.user, 'Perfil')];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  /// Fondo vivo por pestaña: Inicio, Feed, Ligas, Torneos, Perfil (Competiciones mezcla Ligas↔Torneos con el dedo).
  static const _palettes = [AmbientPalette.home, AmbientPalette.feed, AmbientPalette.leagues, AmbientPalette.tournaments, AmbientPalette.profile];
  static const _palettePos = [0.0, 1.0, 2.0, 4.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Las solicitudes/notificaciones en vivo se escuchan en LiveSync (raíz de la app), no aquí: así también funcionan
    // en pantallas fuera de las pestañas (Amigos, chat, perfil de otro jugador…).
    // 92 px en el HTML = 10 (padding) + 56 (pestaña) + 26 de aire inferior. En móviles con barra de gestos se usa el
    // inset del sistema si es mayor.
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget tab(int i) {
      final (icon, label) = _tabs[i];
      final on = shell.currentIndex == i;
      final color = on ? AppColors.text : AppColors.textMuted;
      return Expanded(child: Semantics(button: true, selected: on, label: label, excludeSemantics: true, child: InkResponse(
        onTap: () { HapticFeedback.selectionClick(); _go(i); }, radius: 34, highlightShape: BoxShape.circle,
        child: SizedBox(height: 56, child: Padding(padding: const EdgeInsets.only(top: 2), child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color), duration: AppAnimations.scaled(context, AppAnimations.tab), curve: AppAnimations.standard,
          builder: (_, col, __) => Column(children: [
            // Al activarse, el icono hace un «pop» corto (85 % → 100 % con rebote). Al desactivarse no se mueve.
            TweenAnimationBuilder<double>(
              key: ValueKey(on), tween: Tween(begin: on && !AppAnimations.reduceMotion(context) ? .82 : 1, end: 1),
              duration: const Duration(milliseconds: 420), curve: AppAnimations.settle,
              builder: (_, sc, child) => Transform.scale(scale: sc, child: child),
              child: PlobbyIcon(icon, size: 24, color: col ?? color)),
            const SizedBox(height: 4),
            // «Competiciones» es más largo que el resto: se reduce lo justo para caber en su columna (sin cortarse).
            FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 15 / 12, letterSpacing: 0,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400, color: col ?? color))),
          ]),
        ))),
      )));
    }
    return Scaffold(
      body: AmbientBackground(
        palettes: _palettes, position: _palettePos[shell.currentIndex],
        offset: shell.currentIndex == 2 ? CompetitionsScreen.page : null,
        child: AchievementCelebration(child: _BranchFade(index: shell.currentIndex, child: shell)),
      ),
      extendBody: true,
      bottomNavigationBar: Container(
        height: 66 + (bottom > 26 ? bottom : 26),
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
        decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: Color(0x14171C19)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          tab(0), tab(1),
          Expanded(child: SizedBox(height: 56, child: OverflowBox(alignment: Alignment.topCenter, maxHeight: 90, child: Transform.translate(offset: const Offset(0, -30), child: const _PlusButton())))),
          tab(2), tab(3),
        ]),
      ),
    );
  }
}

class _PlusButton extends StatelessWidget {
  const _PlusButton();
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'Nuevo partido', excludeSemantics: true,
        child: Pressable(scale: .9, child: Container(
          width: 60, height: 60,
          decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [
            BoxShadow(color: AppColors.surface, spreadRadius: 6),                                         // 0 0 0 6px #fff
            BoxShadow(color: Color(0x59171C19), blurRadius: 20, offset: Offset(0, 10), spreadRadius: -4),  // 0 10 20 −4 .35
          ]),
          child: Material(
            color: AppColors.brand, shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () { HapticFeedback.lightImpact(); HomeNav.newMatch(context); },
              // Icono «+» del HTML: 28 px, trazo 2.6, extremos redondeados.
              child: Center(child: SvgPicture.string('<svg viewBox="0 0 24 24" fill="none" stroke="#171C19" stroke-width="2.6" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
                  width: 28, height: 28)),
            ),
          ),
        )),
      );
}

/// Cambio de pestaña de la barra inferior: el contenido nuevo entra con un fundido rápido y sube 6 px (fade-through).
/// Las pestañas siguen vivas (StatefulShellRoute): solo se anima la presentación, nada se reconstruye.
class _BranchFade extends StatefulWidget {
  const _BranchFade({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<_BranchFade> createState() => _BranchFadeState();
}

class _BranchFadeState extends State<_BranchFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppAnimations.branch, value: 1);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  @override
  void didUpdateWidget(_BranchFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !AppAnimations.reduceMotion(context)) _c.forward(from: 0);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _a, child: widget.child, builder: (_, child) {
        // Misma estructura siempre (Opacity 1 no crea capa): cambiarla haría perder el estado de las pestañas.
        final t = _a.value;
        return Opacity(opacity: .15 + .85 * t, child: Transform.translate(offset: Offset(0, (1 - t) * 6), child: child));
      });
}
