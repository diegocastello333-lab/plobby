import 'package:flutter/material.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/profile_providers.dart';
import '../../domain/stats_calculator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          _chip('Nivel calculado ${c.estimatedLevel(elo).toStringAsFixed(1)}', false),
        ]),
        const SizedBox(height: 14),
        SegmentedButton<EloRange>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(foregroundColor: const Color(0xA6F6F8F1), selectedForegroundColor: PlobbyColors.forest, selectedBackgroundColor: PlobbyColors.ivory, visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: EloRange.d30, label: Text('30 días')),
            ButtonSegment(value: EloRange.d90, label: Text('3 meses')),
            ButtonSegment(value: EloRange.d365, label: Text('12 meses')),
          ],
          selected: {range},
          onSelectionChanged: (s) => ref.read(eloRangeProvider.notifier).state = s.first,
        ),
        const SizedBox(height: 12),
        SizedBox(height: 110, width: double.infinity, child: CustomPaint(painter: _EloChart(view.series))),
        const Divider(color: Color(0x24F6F8F1)),
        Text('Calculado (ELO): ${c.category(elo)} · ${c.estimatedLevel(elo).toStringAsFixed(1)}   |   '
            'Declarado por ti: ${view.data.profile.declaredLevel} · ${view.data.profile.declaredLevelValue.toStringAsFixed(1)}',
            style: const TextStyle(color: Color(0xB8F6F8F1), fontSize: 12)),
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
