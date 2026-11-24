import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/motion/app_motion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../../../core/theme/plobby_text.dart';
import '../../../../core/widgets/plobby_components.dart';
import 'activity_cards.dart' show avatar;
import '../../application/feed_providers.dart';
import '../../domain/feed_models.dart';
import 'comments_sheet.dart';

/// Reacciones discretas: plegadas solo se ven las que ya tiene la publicación y un botón «reaccionar»; un toque en él
/// pone 🔥 (la reacción rápida, igual que el doble toque) y una pulsación larga despliega las cinco.
class ReactionBar extends ConsumerStatefulWidget {
  const ReactionBar({super.key, required this.post, this.onDark = false});
  final FeedPost post;
  final bool onDark;
  @override
  ConsumerState<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends ConsumerState<ReactionBar> {
  bool _open = false;
  FeedPost get post => widget.post;
  bool get onDark => widget.onDark;

  void _react(ReactionType t) {
    AppHaptics.medium();
    ref.read(feedControllerProvider.notifier).react(post.id, t);
    if (_open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = post.reactions;
    final shown = _open ? ReactionType.values : [for (final t in ReactionType.values) if ((r.counts[t] ?? 0) > 0 || r.mine == t) t];
    final fg = onDark ? AppColors.ink50.withValues(alpha: .7) : AppColors.textMuted;
    final names = r.recent.take(2).map((u) => u.name.split(' ').first).join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      AnimatedSize(duration: Motion.normal, curve: Motion.move, alignment: Alignment.centerLeft, child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in shown) _Pill(t: t, count: r.counts[t] ?? 0, selected: r.mine == t, onDark: onDark, onTap: () => _react(t)),
        if (!_open) _AddReaction(onDark: onDark, onTap: () => _react(ReactionType.fire), onLongPress: () { AppHaptics.light(); setState(() => _open = true); }),
      ])),
      const SizedBox(height: 10),
      Row(children: [
        if (r.total > 0) ...[
          Flexible(child: InkWell(onTap: () => _who(context), child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 22.0 + 15 * (r.recent.length.clamp(1, 3) - 1), height: 22, child: Stack(children: [for (var i = 0; i < r.recent.length.clamp(0, 3); i++) Positioned(left: i * 15.0, child: avatar(r.recent[i], 11, ring: onDark ? AppColors.inverse : AppColors.surface))])),
            const SizedBox(width: 8),
            Flexible(child: Text(names.isEmpty ? '${r.total} ${r.total == 1 ? 'reacción' : 'reacciones'}' : '$names${r.total > 2 ? ' y ${r.total - 2} más' : ''}', maxLines: 2, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: fg, fontWeight: FontWeight.w600))),
          ]))),
        ] else Flexible(child: Text('Sé el primero en reaccionar', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: fg))),
        const SizedBox(width: 8),
        // Zona táctil de 44 pt (antes 0: solo el texto era pulsable).
        TextButton(onPressed: () => showCommentsSheet(context, post), style: TextButton.styleFrom(foregroundColor: fg, minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 4)),
            child: Text(post.commentCount == 0 ? 'Comentar' : '${post.commentCount} ${post.commentCount == 1 ? 'comentario' : 'comentarios'}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0))),
      ]),
      if (post.previewComments.isNotEmpty) ...[
        Divider(height: 18, thickness: 1, color: onDark ? const Color(0x24F6F8F1) : AppColors.inkA(0x1A)),
        for (final c in post.previewComments) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text.rich(TextSpan(children: [TextSpan(text: '${c.author.name.split(' ').first} ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: c.content)]), style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, height: 1.4, letterSpacing: 0, color: onDark ? AppColors.ink50 : AppColors.text))),
        if (post.commentCount > 2) TextButton(onPressed: () => showCommentsSheet(context, post), style: TextButton.styleFrom(foregroundColor: fg, padding: EdgeInsets.zero, minimumSize: Size.zero), child: Text('Ver los ${post.commentCount} comentarios', style: const TextStyle(fontSize: 12.5))),
      ],
    ]);
  }

  Future<void> _who(BuildContext context) async {
    final list = await ref.read(feedRepositoryProvider).reactionsFor(post.id);
    if (!context.mounted) return;
    showPlobbySheet(context, (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const SheetHeader(title: 'Reacciones'),
      for (final e in list) ListTile(contentPadding: EdgeInsets.zero, leading: avatar(e.$1, 20),
          title: Text(e.$1.name, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w700)), subtitle: Text('@${e.$1.username}', style: PlobbyText.help), trailing: Text(e.$2.emoji, style: const TextStyle(fontSize: 22))),
    ]));
  }
}

class _Pill extends StatefulWidget {
  const _Pill({required this.t, required this.count, required this.selected, required this.onDark, required this.onTap});
  final ReactionType t; final int count; final bool selected, onDark; final VoidCallback onTap;
  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: Motion.emphasis);
  @override
  void didUpdateWidget(covariant _Pill o) { super.didUpdateWidget(o); if (widget.selected && !o.selected) c.forward(from: 0); }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return Semantics(button: true, selected: sel, label: 'Reaccionar con ${widget.t.emoji}', child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(animation: c, builder: (_, child) {
        final s = 1 + .3 * Motion.spring.transform(c.value) * (1 - c.value);
        return Transform.scale(scale: c.isAnimating ? s : 1, child: child);
      }, child: AnimatedContainer(
        duration: Motion.fast, height: 32, constraints: const BoxConstraints(minWidth: 40), padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: sel ? AppColors.brand : (widget.onDark ? const Color(0x1FF6F8F1) : AppColors.inkA(0x0F)), borderRadius: BorderRadius.circular(16), border: sel ? Border.all(color: AppColors.brandInk, width: 1.5) : null),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // partículas: el emoji «salta» al elegirlo (decoración; no cambia el tamaño de la píldora)
          Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Text(widget.t.emoji, style: const TextStyle(fontSize: 15)),
            if (!Motion.reduced(context)) Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: c,
                builder: (_, __) => c.isAnimating ? CustomPaint(painter: _Burst(c.value, widget.t.emoji)) : const SizedBox.shrink()))),
          ]),
          if (widget.count > 0) ...[const SizedBox(width: 5), RollingCount(value: widget.count, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0, color: sel ? AppColors.brandInk : (widget.onDark ? const Color(0xBFF6F8F1) : AppColors.textMuted)))],
        ]))),
    ));
  }
}

/// Seis emojis pequeños que salen en abanico hacia arriba y se desvanecen (una vez por reacción).
class _Burst extends CustomPainter {
  _Burst(this.t, this.emoji);
  final double t;
  final String emoji;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), e = Motion.enter.transform(t);
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + (i - 2.5) * .42, d = 10 + 26 * e;
      final tp = TextPainter(text: TextSpan(text: emoji, style: TextStyle(fontSize: 11 + 4 * (1 - t), color: Color.fromRGBO(0, 0, 0, (1 - t).clamp(0.0, 1.0)))),
          textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, c + Offset(math.cos(a) * d, math.sin(a) * d - 8 * e) - Offset(tp.width / 2, tp.height / 2));
    }
  }
  @override
  bool shouldRepaint(_Burst o) => o.t != t;
}

/// Contador que rueda: el número nuevo entra desde abajo (sube) o desde arriba (baja).
class RollingCount extends StatefulWidget {
  const RollingCount({super.key, required this.value, required this.style});
  final int value;
  final TextStyle style;
  @override
  State<RollingCount> createState() => _RollingCountState();
}

class _RollingCountState extends State<RollingCount> {
  bool _up = true;
  @override
  void didUpdateWidget(covariant RollingCount o) {
    super.didUpdateWidget(o);
    if (o.value != widget.value) _up = widget.value > o.value;
  }
  @override
  Widget build(BuildContext context) => Semantics(label: '${widget.value}', excludeSemantics: true, child: ClipRect(child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.normal), switchInCurve: Motion.enter, switchOutCurve: Motion.exit,
        transitionBuilder: (child, a) {
          final incoming = child.key == ValueKey(widget.value);
          final dir = (_up ? 1.0 : -1.0) * (incoming ? 1 : -1);
          return SlideTransition(position: Tween(begin: Offset(0, .9 * dir), end: Offset.zero).animate(a), child: FadeTransition(opacity: a, child: child));
        },
        child: Text('${widget.value}', key: ValueKey(widget.value), style: widget.style.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      )));
}

/// Doble toque en el contenido de una publicación = 🔥. Solo AÑADE la reacción (nunca la quita por accidente) y
/// enseña un 🔥 grande que crece y se desvanece en el centro. Los botones de reacción siguen siendo la vía accesible.
class DoubleTapFire extends ConsumerStatefulWidget {
  const DoubleTapFire({super.key, required this.post, required this.child});
  final FeedPost post;
  final Widget child;
  @override
  ConsumerState<DoubleTapFire> createState() => _DoubleTapFireState();
}

class _DoubleTapFireState extends ConsumerState<DoubleTapFire> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.celebration);
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  void _fire() {
    if (widget.post.reactions.mine != ReactionType.fire) {
      AppHaptics.medium();
      ref.read(feedControllerProvider.notifier).react(widget.post.id, ReactionType.fire);
    }
    if (!Motion.reduced(context)) _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onDoubleTap: _fire,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          widget.child,
          Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: _c, builder: (_, __) {
            if (!_c.isAnimating) return const SizedBox.shrink();
            final v = _c.value, pop = Motion.springBounce.transform((v * 2.2).clamp(0.0, 1.0));
            final fade = v < .65 ? 1.0 : (1 - (v - .65) / .35).clamp(0.0, 1.0);
            return Center(child: Opacity(opacity: fade, child: Transform.translate(offset: Offset(0, -18 * Motion.exit.transform(((v - .65) / .35).clamp(0.0, 1.0))),
                child: Transform.scale(scale: .4 + .8 * pop, child: const Text('🔥', style: TextStyle(fontSize: 64))))));
          }))),
        ]),
      );
}

/// Botón discreto para reaccionar: toque = 🔥; pulsación larga = elegir entre las cinco.
class _AddReaction extends StatelessWidget {
  const _AddReaction({required this.onDark, required this.onTap, required this.onLongPress});
  final bool onDark;
  final VoidCallback onTap, onLongPress;
  @override
  Widget build(BuildContext context) {
    final fg = onDark ? AppColors.ink50.withValues(alpha: .7) : AppColors.textMuted;
    final shape = AppShapes.of(AppRadius.pill, side: BorderSide(color: onDark ? const Color(0x33F6F8F1) : AppColors.border));
    return Semantics(button: true, label: 'Reaccionar. Mantén pulsado para elegir la reacción', excludeSemantics: true, child: Material(
      color: Colors.transparent, shape: shape,
      child: InkWell(customBorder: shape, onTap: onTap, onLongPress: onLongPress, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_reaction_outlined, size: 18, color: fg),
        ])))),
    ));
  }
}
