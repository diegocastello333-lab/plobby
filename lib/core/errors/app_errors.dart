import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Gestión centralizada de errores no controlados.
///
/// - Errores de Flutter (construcción, layout, pintado) y errores asíncronos sin capturar se registran aquí
///   (últimos 30, en memoria y en el log) en vez de perderse.
/// - En la APK (release), un widget que falla al construirse ya no deja un rectángulo gris/negro que tapa la
///   pantalla: se muestra un aviso discreto en su lugar y el resto de la app sigue funcionando.
/// - Los errores esperables (red, permisos, validación) siguen gestionándose en cada pantalla con su mensaje.
class AppErrors {
  AppErrors._();
  static final recent = <String>[];

  static void record(Object error, StackTrace? stack, {String origin = 'app'}) {
    final line = '[$origin] ${DateTime.now().toIso8601String()} $error';
    recent.add(line);
    if (recent.length > 30) recent.removeAt(0);
    debugPrint(line);
    if (stack != null) debugPrint(stack.toString().split('\n').take(8).join('\n'));
  }

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack, origin: 'flutter');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, origin: 'async');
      return true;   // registrado: no cerrar la app por un Future sin capturar
    };
    if (kReleaseMode) ErrorWidget.builder = (details) => const _SectionError();
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError();
  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.all(Radius.circular(12))),
            child: Padding(padding: EdgeInsets.all(12), child: Text('No se pudo mostrar esta sección. Vuelve atrás e inténtalo de nuevo.',
                style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, letterSpacing: 0, color: AppColors.textMuted))),
          ),
        ),
      );
}
