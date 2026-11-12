import 'package:flutter/material.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/profile_providers.dart';
import '../../domain/stats_calculator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/motion_widgets.dart';

/// Un decimal con coma, como en el HTML (4,2).
String _dec(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

String formatInt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

class EloCard extends ConsumerWidget {
  const EloCard({super.key, required this.view});
  final ProfileView view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elo = view.data.currentElo, c = view.calc, up = view.eloMonth >= 0;
    final range = ref.watch(eloRangeProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(color: PlobbyColors.forest, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RATING ELO', style: TextStyle(color: Color(0x99F6F8F1), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
            Text(formatInt(elo), style: const TextStyle(color: PlobbyColors.lime, fontSize: 54, fontWeight: FontWeight.w800, height: 1.1)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(children: [
              Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: up ? PlobbyColors.lime : const Color(0xFFFF6B6F)),
              Text('${up ? '+' : ''}${view.eloMonth}', style: TextStyle(color: up ? PlobbyColors.lime : const Color(0xFFFF6B6F), fontWeight: FontWeight.w800)),
            ]),
            const Text('este mes', style: TextStyle(color: Color(0x99F6F8F1), fontSize: 11.5)),
          ]),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          _chip(c.category(elo), true),
          _chip('Nivel calculado ${_dec(c.estimatedLevel(elo))}', false),
        ]),
        const SizedBox(height: 14),
        // `.eloc .seg`: variante oscura (marfil .08), activa en lima.
        SlidingTabs(dark: true, labels: const ['30 días', '3 meses', '12 meses'], index: const [EloRange.d30, EloRange.d90, EloRange.d365].indexOf(range),
            onChanged: (i) => ref.read(eloRangeProvider.notifier).state = const [EloRange.d30, EloRange.d90, EloRange.d365][i]),
        const SizedBox(height: 12),
        SizedBox(height: 110, width: double.infinity, child: CustomPaint(painter: _EloChart(view.series))),
        const Divider(color: Color(0x24F6F8F1)),
        // Pie del prototipo: dos líneas, etiqueta en marfil .7 y valor en negrita, espaciado .1em, decimales con coma.
        Text.rich(TextSpan(style: const TextStyle(fontFamily: AppTypography.sansFamily, color: Color(0xB3F6F8F1), fontSize: 11.5, height: 1.5, letterSpacing: 1.15, fontWeight: FontWeight.w600), children: [
          const TextSpan(text: 'Calculado (ELO): '),
          TextSpan(text: '${c.category(elo)} · ${_dec(c.estimatedLevel(elo))}', style: const TextStyle(color: AppColors.ink50, fontWeight: FontWeight.w800)),
          const TextSpan(text: '\nDeclarado por ti: '),
          TextSpan(text: '${view.data.profile.declaredLevel} · ${_dec(view.data.profile.declaredLevelValue)}', style: const TextStyle(color: AppColors.ink50, fontWeight: FontWeight.w800)),
        ])),
      ]),
    );
  }

  Widget _chip(String t, bool hi) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: hi ? PlobbyColors.lime : const Color(0x1FF6F8F1), borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: hi ? PlobbyColors.forest : PlobbyColors.ivory)));
}

class _EloChart extends CustomPainter {
  _EloChart(this.pts);
  final List<EloPoint> pts;
  @override
  void paint(Canvas canvas, Size s) {
    if (pts.length < 2) return;
    final lo = pts.map((p) => p.elo).reduce((a, b) => a < b ? a : b) - 4.0;
    final hi = pts.map((p) => p.elo).reduce((a, b) => a > b ? a : b) + 4.0;
    final t0 = pts.first.date.millisecondsSinceEpoch, t1 = pts.last.date.millisecondsSinceEpoch;
    Offset o(EloPoint p) => Offset(8 + (p.date.millisecondsSinceEpoch - t0) / (t1 - t0) * (s.width - 16),
        s.height - 8 - (p.elo - lo) / (hi - lo) * (s.height - 16));
    final line = Path()..moveTo(o(pts.first).dx, o(pts.first).dy);
    for (final p in pts.skip(1)) { line.lineTo(o(p).dx, o(p).dy); }
    final area = Path.from(line)..lineTo(s.width - 8, s.height)..lineTo(8, s.height)..close();
    canvas.drawPath(area, Paint()..color = PlobbyColors.lime.withOpacity(.10));
    canvas.drawPath(line, Paint()..color = PlobbyColors.lime..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
    final e = o(pts.last);
    canvas.drawCircle(e, 5, Paint()..color = PlobbyColors.lime);
    canvas.drawCircle(e, 5, Paint()..color = PlobbyColors.forest..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }
  @override
  bool shouldRepaint(_EloChart o) => o.pts != pts;
}
