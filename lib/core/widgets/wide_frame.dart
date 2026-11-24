import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Envuelve TODA la app (MaterialApp.builder). Por debajo de [WideLayout.breakpoint] no hace nada. Por encima, la app se
/// dibuja en una columna centrada de [WideLayout.frameWidth] px sobre un fondo neutro (antes, a 1440 px, todo —incluida la
/// barra inferior— se estiraba a lo ancho). Dentro, `MediaQuery.size` es el de la columna: las pantallas, hojas y
/// diálogos se maquetan para ese ancho sin cambiar nada en ellas.
class WideFrame extends StatelessWidget {
  const WideFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width < WideLayout.breakpoint) return WideLayout(wide: false, child: child);
    return ColoredBox(color: AppColors.surfaceSunken, child: Center(child: ClipRect(child: SizedBox(
      width: WideLayout.frameWidth, height: mq.size.height,
      child: MediaQuery(data: mq.copyWith(size: Size(WideLayout.frameWidth, mq.size.height)),
          child: WideLayout(wide: true, child: DecoratedBox(
            decoration: const BoxDecoration(color: AppColors.bg, border: Border.symmetric(vertical: BorderSide(color: AppColors.border))),
            child: child))),
    ))));
  }
}
