import 'package:flutter/material.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../../../core/widgets/flame_paths.dart';

/// Llama animada. La intensidad (velocidad y brillo) crece con la racha.
/// Cuando `streak` aumenta tras una victoria CONFIRMADA se dispara una celebración corta.
class WinStreakBadge extends StatefulWidget {
  const WinStreakBadge({super.key, required this.streak, this.size = 30, this.showNumber = true});
  final int streak;
  final double size;
  final bool showNumber;
  @override
  State<WinStreakBadge> createState() => _WinStreakBadgeState();
}

class _WinStreakBadgeState extends State<WinStreakBadge> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this);
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  int get _level => widget.streak >= 10 ? 4 : widget.streak >= 5 ? 3 : widget.streak >= 3 ? 2 : widget.streak >= 1 ? 1 : 0;
  Duration get _period => Duration(milliseconds: const [0, 1800, 1400, 1100, 850][_level]);

  void _syncLoop() {
    if (_level == 0) { _loop.stop(); return; }
    _loop.duration = _period;
    if (!_loop.isAnimating) _loop.repeat(reverse: true);
  }

  @override
  void initState() { super.initState(); _syncLoop(); }

  @override
  void didUpdateWidget(covariant WinStreakBadge old) {
    super.didUpdateWidget(old);
    if (widget.streak > old.streak) _pop.forward(from: 0); // celebración
    _syncLoop();
  }

  @override
  void dispose() { _loop.dispose(); _pop.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'Racha de ${widget.streak} victorias',
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _pop]),
        builder: (_, __) {
          final t = reduce ? 0.0 : Curves.easeInOut.transform(_loop.value);
          final pop = reduce ? 1.0 : (_pop.isAnimating ? 1 + 0.4 * Curves.elasticOut.transform(_pop.value) - 0.4 * _pop.value : 1.0);
          final glow = _level == 0 ? 0.0 : 6.0 + _level * 4;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..scale(pop * (1 - 0.03 * t), pop * (1 + 0.04 * t))
                ..rotateZ(0.025 * (t - .5)),
              child: CustomPaint(
                size: Size(widget.size * .78, widget.size),
                painter: _FlamePainter(active: _level > 0, glow: glow),
              ),
            ),
            if (widget.showNumber) ...[
              const SizedBox(width: 6),
              Transform.scale(scale: pop, child: Text('${widget.streak}',
                  style: TextStyle(fontSize: widget.size, fontWeight: FontWeight.w800, color: PlobbyColors.lime, height: 1))),
            ],
          ]);
        },
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({required this.active, required this.glow});
  final bool active;
  final double glow;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 130);
    final outer = flameOuter();
    if (active && glow > 0) {
      canvas.drawPath(outer, Paint()..color = PlobbyColors.lime.withOpacity(.55)..maskFilter = MaskFilter.blur(BlurStyle.normal, glow));
    }
    canvas.drawPath(outer, Paint()..color = active ? PlobbyColors.lime : PlobbyColors.sage);
    canvas.drawPath(flameInner(), Paint()..color = (active ? PlobbyColors.forest : PlobbyColors.ivory).withOpacity(.85));
  }
  @override
  bool shouldRepaint(_FlamePainter o) => o.active != active || o.glow != glow;
}
