import 'package:flutter/material.dart';
import '../motion/app_motion.dart';
import '../theme/plobby_text.dart';

/// Título grande de pantalla que se encoge al desplazar el contenido (como los «large titles» de iOS): con la lista
/// arriba es Unbounded 28 alineado a la izquierda; al bajar 48 px pasa a Inter 17 semibold centrado y la cabecera
/// ocupa menos. Escucha los desplazamientos VERTICALES de lo que haya debajo ([child]), aunque vayan dentro de un
/// PageView horizontal. Con «reducir movimiento» el cambio es directo (sin interpolar).
class CollapsingTitleScaffold extends StatefulWidget {
  const CollapsingTitleScaffold({super.key, required this.title, required this.child, this.below});
  final String title;
  /// Lo que va fijo bajo el título (p. ej. las pestañas Ligas | Torneos).
  final Widget? below;
  final Widget child;
  @override
  State<CollapsingTitleScaffold> createState() => _CollapsingTitleScaffoldState();
}

class _CollapsingTitleScaffoldState extends State<CollapsingTitleScaffold> {
  static const _range = 48.0;
  final _t = ValueNotifier<double>(0);

  @override
  void dispose() { _t.dispose(); super.dispose(); }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final v = (n.metrics.pixels / _range).clamp(0.0, 1.0);
    final reduce = AppAnimations.reduceMotion(context);
    final next = reduce ? (v > .5 ? 1.0 : 0.0) : v;
    if ((next - _t.value).abs() > .001) _t.value = next;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final big = PlobbyText.t1, small = PlobbyText.headline;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ValueListenableBuilder<double>(valueListenable: _t, builder: (_, t, __) {
        final style = TextStyle.lerp(big, small, t)!;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 26 - 16 * t, 20, 0),
          child: Align(alignment: Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!,
              child: Semantics(header: true, child: Text(widget.title, style: style, maxLines: 1))),
        );
      }),
      if (widget.below != null) widget.below!,
      Expanded(child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child)),
    ]);
  }
}
