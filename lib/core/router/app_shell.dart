import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/home/presentation/home_wiring.dart';
import '../theme/design_tokens.dart';
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
        child: SizedBox(height: 56, child: Padding(padding: const EdgeInsets.only(top: 2), child: Column(children: [
          PlobbyIcon(icon, size: 24, color: color),
          const SizedBox(height: 4),
          // «Competiciones» es más largo que el resto: se reduce lo justo para caber en su columna (sin cortarse).
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 15 / 12, letterSpacing: 0,
              fontWeight: on ? FontWeight.w700 : FontWeight.w400, color: color))),
        ]))),
      )));
    }
    return Scaffold(
      body: shell,
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
        child: Container(
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
        ),
      );
}
