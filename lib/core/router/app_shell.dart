import 'dart:ui' as ui;
import '../widgets/frosted_bar.dart';
import '../../features/gamification/presentation/achievements_screen.dart';
import 'package:flutter/material.dart';
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
        onTap: () { AppHaptics.light(); _go(i); }, radius: 34, highlightShape: BoxShape.circle,
        child: SizedBox(height: 56, child: Padding(padding: const EdgeInsets.only(top: 2), child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color), duration: AppAnimations.scaled(context, AppAnimations.tab), curve: AppAnimations.standard,
          builder: (_, col, __) => Column(children: [
            // Al activarse, el icono hace un «pop» corto (85 % → 100 % con rebote). Al desactivarse no se mueve.
            TweenAnimationBuilder<double>(
              key: ValueKey(on), tween: Tween(begin: on && !AppAnimations.reduceMotion(context) ? .82 : 1, end: 1),
              duration: Motion.emphasis, curve: AppAnimations.settle,
              builder: (_, sc, child) => Transform.scale(scale: sc, child: child),
              child: PlobbyIcon(icon, size: 24, color: col ?? color, filled: on, holeColor: AppMaterials.tabBar)),
            const SizedBox(height: 4),
            // «Competiciones» es más largo que el resto: se reduce lo justo para caber en su columna (sin cortarse).
            FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 15 / 12, letterSpacing: 0,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400, color: col ?? color))),
          ]),
        ))),
      )));
    }
    final body = AmbientBackground(
        palettes: _palettes, position: _palettePos[shell.currentIndex],
        offset: shell.currentIndex == 2 ? CompetitionsScreen.page : null,
        child: AchievementCelebration(child: _BranchFade(index: shell.currentIndex, child: shell)),
      );
    // Escritorio/tablet: barra lateral (logo, «+» y las cuatro pestañas) en vez de la barra inferior.
    if (WideLayout.isWide(context)) {
      return Scaffold(body: Row(children: [
        _SideRail(tabs: _tabs, current: shell.currentIndex, onTap: (i) { AppHaptics.light(); _go(i); }),
        // Las pestañas se maquetan para el ancho real de su columna (640 px), no el del marco con la barra lateral.
        Expanded(child: Builder(builder: (c) {
          final mq = MediaQuery.of(c);
          return MediaQuery(data: mq.copyWith(size: Size(mq.size.width - WideLayout.railWidth, mq.size.height)), child: body);
        })),
      ]));
    }
    return Scaffold(
      body: body,
      extendBody: true,
      // Como en iOS, las etiquetas de la barra de pestañas no crecen con el tamaño de texto del sistema (cada pestaña ya
      // tiene su etiqueta para VoiceOver/TalkBack); el resto de la app sí escala.
      bottomNavigationBar: MediaQuery.withNoTextScaling(child: FrostedBar(child: Container(
        height: AppInsets.tabBarHeight(context),
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
        // Material translúcido: el contenido pasa por debajo (extendBody) y se intuye desenfocado, como en iOS.
        decoration: BoxDecoration(color: AppMaterials.tabBar, border: Border(top: BorderSide(width: .5, color: AppMaterials.hairline))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          tab(0), tab(1),
          // «+» (nuevo partido) como pestaña central, dentro de la barra: ya no flota ni tapa contenido.
          const Expanded(child: _PlusTab()),
          tab(2), tab(3),
        ]),
      ))),
    );
  }
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
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Motion.enter);
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

/// Barra lateral para pantallas anchas: logotipo, botón «+» (nuevo partido) y las pestañas con icono y etiqueta.
class _SideRail extends StatelessWidget {
  const _SideRail({required this.tabs, required this.current, required this.onTap});
  final List<(PlobbyIcons, String)> tabs;
  final int current;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => Container(
        width: WideLayout.railWidth,
        decoration: BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))),
        child: SafeArea(right: false, child: Column(children: [
          const SizedBox(height: 20),
          Semantics(label: 'Plobby', image: true, child: Text('plobby', style: TextStyle(fontFamily: AppTypography.displayFamily,
              fontWeight: FontWeight.w700, fontSize: 18, height: 1, letterSpacing: -0.54, color: AppColors.text))),
          const SizedBox(height: 24),
          const PlusSquare(),
          const SizedBox(height: 20),
          for (var i = 0; i < tabs.length; i++) Semantics(button: true, selected: i == current, label: tabs[i].$2, excludeSemantics: true, child: InkWell(
            onTap: () => onTap(i),
            child: SizedBox(height: 72, width: double.infinity, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedContainer(duration: AppAnimations.scaled(context, AppAnimations.tab), curve: AppAnimations.standard,
                  width: 56, height: 32, decoration: BoxDecoration(color: i == current ? AppColors.brandSoft : const Color(0x00000000), borderRadius: AppRadius.rPill),
                  child: Center(child: PlobbyIcon(tabs[i].$1, size: 22, color: i == current ? AppColors.text : AppColors.textMuted))),
              const SizedBox(height: 4),
              Text(tabs[i].$2, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5,
                  height: 1.2, letterSpacing: 0, fontWeight: i == current ? FontWeight.w700 : FontWeight.w500, color: i == current ? AppColors.text : AppColors.textMuted)),
            ])),
          )),
        ])),
      );
}

/// «+» de la barra: pestaña central sin etiqueta, con el botón cuadrado lima centrado a la altura de los iconos.
class _PlusTab extends StatelessWidget {
  const _PlusTab();
  @override
  // Centrado con el bloque icono + etiqueta de las otras pestañas (2 + 24 + 4 + 15 px ≈ 45 px desde arriba), no con los
  // 56 px de la pestaña: así queda a la misma altura visual que el resto y no baja por debajo de las etiquetas.
  Widget build(BuildContext context) => const SizedBox(height: 56, child: Align(alignment: Alignment.topCenter,
      child: Padding(padding: EdgeInsets.only(top: 1.5), child: PlusSquare(size: PlusSquare.tabSize))));
}

/// Botón «Nuevo partido»: cuadrado lima de 44 px, esquinas continuas de 12 (radio pequeño del sistema), «+» en tinta.
/// Mismo botón en la barra inferior y en la barra lateral de escritorio.
class PlusSquare extends StatelessWidget {
  const PlusSquare({super.key, this.size = 44});
  /// En la barra inferior: alto del bloque icono + etiqueta de las otras pestañas.
  static const tabSize = 42.0;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: 'Nuevo partido', excludeSemantics: true, child: Pressable(scale: .92, child: Material(
        color: AppColors.brand,
        shape: const ContinuousRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.squircleSm))),
        child: InkWell(
          customBorder: const ContinuousRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.squircleSm))),
          onTap: () { AppHaptics.light(); HomeNav.newMatch(context); },
          child: SizedBox.square(dimension: size, child: Center(child: PlobbyIcon(PlobbyIcons.plus, size: size * .5, strokeWidth: 2.4, color: AppColors.brandInk)))),
      )));
}
