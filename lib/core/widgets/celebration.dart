import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../motion/app_motion.dart';
import '../theme/design_tokens.dart';
import '../theme/plobby_text.dart';
import 'plobby_icon.dart';

/// Confeti dibujado en código (sin Lottie ni imágenes): rectángulos y círculos con la paleta de Plobby que salen de
/// arriba, caen con gravedad, giran y se desvanecen. Determinista ([seed]) para que los tests sean estables.
/// Una sola ráfaga: no se repite en bucle.
class ConfettiPainter extends CustomPainter {
  ConfettiPainter(this.t, {this.seed = 7, this.count = 70});
  final double t;
  final int seed, count;
  static const _colors = [AppColors.lime300, AppColors.ink900, AppColors.court300, AppColors.lime500, Color(0xFFFFFFFF)];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final r = math.Random(seed), p = Paint();
    for (var i = 0; i < count; i++) {
      final x0 = size.width * (.2 + .6 * r.nextDouble()), vx = (r.nextDouble() - .5) * size.width * .9;
      final vy = -size.height * (.35 + .35 * r.nextDouble()), g = size.height * 1.6;
      final spin = (r.nextDouble() - .5) * 18, w = 5 + r.nextDouble() * 6, h = 8 + r.nextDouble() * 8;
      final x = x0 + vx * t, y = size.height * .32 + vy * t + g * t * t / 2;
      final fade = t < .7 ? 1.0 : (1 - (t - .7) / .3);
      p.color = _colors[i % _colors.length].withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin * t);
      if (i % 4 == 0) {
        canvas.drawCircle(Offset.zero, w / 2, p);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), const Radius.circular(1.5)), p);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter o) => o.t != t;
}

/// Qué se celebra a pantalla completa.
class Celebration {
  const Celebration({required this.eventKey, required this.title, required this.text, this.icon = PlobbyIcons.star});
  /// Clave del evento («level:4», «tier:Avanzado»): cada evento se celebra UNA vez por dispositivo.
  final String eventKey;
  final String title, text;
  final PlobbyIcons icon;
}

/// Registro de celebraciones ya mostradas (en el dispositivo).
class CelebrationLog {
  CelebrationLog._();
  static const _key = 'plobby.celebrations_seen';
  static Future<bool> claim(String eventKey) async {
    try {
      final p = await SharedPreferences.getInstance();
      final l = p.getStringList(_key) ?? const <String>[];
      if (l.contains(eventKey)) return false;
      final n = [...l, eventKey];
      await p.setStringList(_key, n.length > 100 ? n.sublist(n.length - 100) : n);
      return true;
    } catch (_) {
      return false;   // sin almacenamiento no se arriesga a repetir celebraciones
    }
  }
}

/// Celebración a pantalla completa (subida de nivel o de categoría): confeti + tarjeta, ≈2,4 s y se cierra sola
/// (o con un toque). Con «reducir movimiento» no hay confeti ni escala: un fundido corto y la tarjeta.
/// Devuelve sin mostrar nada si este evento ya se celebró.
Future<void> showCelebration(BuildContext context, Celebration c) async {
  if (!await CelebrationLog.claim(c.eventKey)) return;
  if (!context.mounted) return;
  AppHaptics.success();
  await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false, barrierDismissible: true, barrierColor: AppColors.inkA(0x99), barrierLabel: 'Cerrar',
    transitionDuration: Motion.of(context, Motion.normal), reverseTransitionDuration: Motion.of(context, Motion.normal),
    pageBuilder: (_, __, ___) => _CelebrationView(c: c),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _CelebrationView extends StatefulWidget {
  const _CelebrationView({required this.c});
  final Celebration c;
  @override
  State<_CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends State<_CelebrationView> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: Motion.celebrationLong * 2);
  bool _closed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_a.isAnimating || _a.value > 0) return;
    if (Motion.reduced(context)) {
      _a.value = 1;
      Timer(Motion.celebrationLong * 2, _close);   // timing
    } else {
      _a.forward().whenComplete(_close);
    }
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = Motion.reduced(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque, onTap: _close,
      child: Material(type: MaterialType.transparency, child: Stack(children: [
        if (!reduce) Positioned.fill(child: RepaintBoundary(child: AnimatedBuilder(animation: _a,
            builder: (_, __) => CustomPaint(painter: ConfettiPainter(_a.value))))),
        Center(child: AnimatedBuilder(animation: _a, builder: (_, child) {
          final s = reduce ? 1.0 : Motion.springBounce.transform((_a.value * 3.5).clamp(0.0, 1.0));
          return Transform.scale(scale: .7 + .3 * s, child: Opacity(opacity: reduce ? 1 : (_a.value * 6).clamp(0.0, 1.0), child: child));
        }, child: Semantics(
          liveRegion: true, label: '${widget.c.title}. ${widget.c.text}', excludeSemantics: true,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40), padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg, boxShadow: AppShadows.pop),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 64, height: 64, alignment: Alignment.center, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                  child: PlobbyIcon(widget.c.icon, size: 30, color: AppColors.brandInk)),
              const SizedBox(height: 16),
              Text(widget.c.title, textAlign: TextAlign.center, style: PlobbyText.t1.copyWith(color: AppColors.brand)),
              const SizedBox(height: 6),
              Text(widget.c.text, textAlign: TextAlign.center, style: PlobbyText.sub.copyWith(color: const Color(0xD9FFFFFF))),
            ]),
          ),
        ))),
      ])),
    );
  }
}
