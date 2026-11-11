import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../motion/app_motion.dart';
import '../theme/design_tokens.dart';

/// Pulsación: escala ≈97 % + opacidad. Envuelve cualquier control interactivo SIN cambiar su acción.
/// Usa un Listener, así que no compite con el gesto del hijo (onTap sigue siendo del hijo).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});
  final Widget child; final bool enabled;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) { if (widget.enabled && _down != v) setState(() => _down = v); }
  @override
  Widget build(BuildContext context) {
    final reduce = AppAnimations.reduceMotion(context);
    return Listener(
      onPointerDown: (_) => _set(true), onPointerUp: (_) => _set(false), onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !reduce ? AppAnimations.pressScale : 1, duration: _down ? AppAnimations.press : AppAnimations.pressRelease, curve: AppAnimations.standard,
        child: AnimatedOpacity(opacity: _down ? .92 : 1, duration: AppAnimations.press, child: widget.child)),
    );
  }
}

/// Encabezado de sección: título y acción en la MISMA fila, centrados en el mismo eje, altura fija (44),
/// acción con zona táctil ≥44 dp y sin recortes (el título se elide, la acción no).
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction, this.style, this.padding = EdgeInsets.zero});
  final String title; final String? actionLabel; final VoidCallback? onAction; final TextStyle? style; final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
      padding: padding,
      child: SizedBox(height: AppLayout.headerHeight, child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        if (actionLabel != null) SectionLink(label: actionLabel!, onTap: onAction),
      ])));
}

/// «Ver todos»: mismo tamaño y estilo en toda la app. Texto centrado verticalmente; zona táctil 44 dp.
class SectionLink extends StatelessWidget {
  const SectionLink({super.key, required this.label, this.onTap});
  final String label; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Pressable(
      child: Semantics(button: true, label: label, child: InkWell(
        onTap: onTap, borderRadius: AppRadius.rSm,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppLayout.minTap, minWidth: AppLayout.minTap),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2), child: Align(alignment: Alignment.centerRight, widthFactor: 1,
              child: Text(label, maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.brandText))))))));
}

/// Aparición de tarjeta: opacidad 0→1 + 10 px, 260 ms, retraso por índice. Una sola vez por `animationKey`.
/// Sin clave → anima solo la primera vez que ese widget se monta (State), no en cada rebuild.
class AppearOnce extends StatefulWidget {
  const AppearOnce({super.key, required this.child, this.animationKey, this.index = 0});
  final Widget child; final String? animationKey; final int index;
  @override
  State<AppearOnce> createState() => _AppearOnceState();
}

class _AppearOnceState extends State<AppearOnce> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppAnimations.appear);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: AppAnimations.standard);
  Timer? _t; bool _skip = false;
  @override
  void initState() {
    super.initState();
    final k = widget.animationKey;
    _skip = k != null && AppearRegistry.hasSeen(k);
    if (k != null) AppearRegistry.markSeen(k);
    if (_skip) { _c.value = 1; return; }
    final d = AppAnimations.staggerDelay(widget.index);
    if (d == Duration.zero) { _c.forward(); } else { _t = Timer(d, () { if (mounted) _c.forward(); }); }
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppAnimations.reduceMotion(context)) { _t?.cancel(); _c.value = 1; }
  }
  @override
  void dispose() { _t?.cancel(); _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _a, child: widget.child,
      builder: (_, child) => Opacity(opacity: _a.value, child: Transform.translate(offset: Offset(0, (1 - _a.value) * AppAnimations.appearOffset), child: child)));
}

/// Skeleton con brillo discreto. Recibe las dimensiones FINALES del contenido para evitar saltos.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = AppRadius.rMd});
  final double? width; final double height; final BorderRadius radius;
  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppAnimations.shimmer);
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = AppAnimations.reduceMotion(context);
    if (reduce) { _c.stop(); _started = false; } else if (!_started) { _c.repeat(); _started = true; }
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: RepaintBoundary(child: AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(width: widget.width, height: widget.height, decoration: BoxDecoration(
          borderRadius: widget.radius,
          gradient: LinearGradient(begin: Alignment(-1.5 + 3 * _c.value, 0), end: Alignment(-0.5 + 3 * _c.value, 0),
              colors: const [AppColors.surfaceSunken, Color(0xFFF7F9F3), AppColors.surfaceSunken]))))));
}

/// Skeleton de «tarjeta de próximo partido» con la altura final (alineada con UpcomingMatchCard).
class MatchCardSkeleton extends StatelessWidget {
  const MatchCardSkeleton({super.key});
  static const height = 178.0;
  @override
  Widget build(BuildContext context) => const SkeletonBox(height: height, radius: AppRadius.rLg);
}

/// Cuenta numérica animada del valor anterior al nuevo. SOLO anima cuando `from != to` Y se pide
/// (`animate`): al abrir el perfil se muestra el valor real directamente. El valor final siempre es `to`.
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.from, required this.to, this.animate = false, this.style, this.format});
  final int from, to; final bool animate; final TextStyle? style; final String Function(int)? format;
  @override
  Widget build(BuildContext context) {
    String f(int v) => format?.call(v) ?? '$v';
    if (!animate || from == to || AppAnimations.reduceMotion(context)) return Text(f(to), style: style);
    return TweenAnimationBuilder<double>(
        tween: Tween(begin: from.toDouble(), end: to.toDouble()), duration: AppAnimations.countUp, curve: AppAnimations.standard,
        builder: (_, v, __) => Text(f(v.round()), style: style));
  }
}

/// Indicador de variación de ELO (positivo/negativo) con la delta real.
class DeltaChip extends StatelessWidget {
  const DeltaChip({super.key, required this.delta});
  final int delta;
  @override
  Widget build(BuildContext context) {
    final up = delta >= 0, c = up ? AppColors.success : AppColors.danger;
    return TweenAnimationBuilder<double>(
        tween: Tween(begin: .85, end: 1), duration: AppAnimations.badge, curve: AppAnimations.settle,
        builder: (_, s, child) => Transform.scale(scale: AppAnimations.reduceMotion(context) ? 1 : s, child: child),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: up ? AppColors.successSoft : AppColors.dangerSoft, borderRadius: AppRadius.rSm),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: c), const SizedBox(width: 2),
              Text('${up ? '+' : ''}$delta', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
            ])));
  }
}

/// «Pop» puntual (logro desbloqueado, número de racha): escala + brillo sutil. Se dispara cambiando `trigger`
/// (p. ej. un id de evento); con el mismo valor no se repite. Primer build: sin animación.
class PopOnEvent extends StatefulWidget {
  const PopOnEvent({super.key, required this.child, required this.trigger, this.glow = false});
  final Widget child; final Object? trigger; final bool glow;
  @override
  State<PopOnEvent> createState() => _PopOnEventState();
}

class _PopOnEventState extends State<PopOnEvent> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  @override
  void didUpdateWidget(PopOnEvent old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !AppAnimations.reduceMotion(context)) _c.forward(from: 0);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _c, child: widget.child,
      builder: (_, child) {
        final t = _c.value, s = 1 + .12 * Curves.easeOut.transform(t < .5 ? t * 2 : (1 - t) * 2), g = (t < .5 ? t * 2 : (1 - t) * 2);
        return Transform.scale(scale: s, child: DecoratedBox(
            decoration: widget.glow && _c.isAnimating ? BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.brand.withOpacity(.55 * g), blurRadius: 18 * g)]) : const BoxDecoration(),
            child: child));
      });
}

/// Campana: se agita UNA vez al aumentar `count`; el contador aparece con escala. Sin animación continua.
class BellBadge extends StatefulWidget {
  const BellBadge({super.key, required this.count, required this.icon, this.showCount = true});
  final int count; final Widget icon; final bool showCount; // showCount:false → solo la sacudida (el contador lo pinta otro widget)
  @override
  State<BellBadge> createState() => _BellBadgeState();
}

class _BellBadgeState extends State<BellBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  @override
  void didUpdateWidget(BellBadge old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count && !AppAnimations.reduceMotion(context)) _c.forward(from: 0);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        AnimatedBuilder(animation: _c, child: widget.icon, builder: (_, child) => Transform.rotate(angle: (1 - _c.value) * .35 * _wave(_c.value), child: child)),
        if (widget.showCount) Positioned(right: -4, top: -4, child: AnimatedScale(
            scale: widget.count > 0 ? 1 : 0, duration: AppAnimations.badge, curve: AppAnimations.settle,
            child: Container(constraints: const BoxConstraints(minWidth: 16, minHeight: 16), padding: const EdgeInsets.symmetric(horizontal: 4), alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.danger, borderRadius: AppRadius.rSm),
                child: Text(widget.count > 99 ? '99+' : '${widget.count}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))))),
      ]);
  static double _wave(double t) => math.sin(t * 6 * math.pi);
}

/// Selector de pestañas con indicador deslizante y color de texto progresivo. Misma API que un TabBar simple:
/// el estado (`index`) y `onChanged` siguen siendo del llamador; aquí solo se anima.
class SlidingTabs extends StatelessWidget {
  const SlidingTabs({super.key, required this.labels, required this.index, required this.onChanged, this.height = 40});
  final List<String> labels; final int index; final ValueChanged<int> onChanged; final double height;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth / labels.length;
        final d = AppAnimations.scaled(context, AppAnimations.tab);
        return SizedBox(height: height < AppLayout.minTap ? AppLayout.minTap : height, child: Stack(alignment: Alignment.centerLeft, children: [
          AnimatedPositioned(duration: d, curve: AppAnimations.standard, left: index * w, width: w, top: 2, bottom: 2,
              child: DecoratedBox(decoration: BoxDecoration(color: AppColors.brand, borderRadius: AppRadius.rMd))),
          Row(children: [for (var i = 0; i < labels.length; i++) Expanded(child: Semantics(selected: i == index, button: true, child: InkWell(
              borderRadius: AppRadius.rMd, onTap: () => onChanged(i),
              child: Center(child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: i == index ? AppColors.brandInk : AppColors.textMuted), duration: d,
                  builder: (_, col, __) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: FittedBox(fit: BoxFit.scaleDown, // etiquetas largas: se reducen en vez de cortarse
                      child: Text(labels[i], maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: col)))))))))]),
        ]));
      });
}
