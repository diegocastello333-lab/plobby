import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Material de barra fija (pestañas, filtros, acción inferior). Con [AppMaterials.blur] desenfoca lo que pasa por
/// debajo; sin él es un color casi opaco. El desenfoque obliga a recalcular la zona en cada fotograma de scroll,
/// así que solo se aplica cuando [active] (hay contenido debajo) y [AppMaterials.blur] lo permiten.
class FrostedBar extends StatelessWidget {
  const FrostedBar({super.key, required this.child, this.active = true, this.sigma = AppMaterials.barBlur, this.oval = false});
  final Widget child;
  final bool active;
  final double sigma;
  /// Recorte circular (botones de cristal) en lugar de rectangular.
  final bool oval;
  @override
  Widget build(BuildContext context) {
    if (!AppMaterials.blur || !active) return oval ? ClipOval(child: child) : child;
    final f = BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child);
    return oval ? ClipOval(child: f) : ClipRect(child: f);
  }
}
