import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/plobby_theme.dart';
import '../application/rating_providers.dart';
import '../domain/rating_models.dart';
import 'elo_bar.dart';

class EloDetailScreen extends ConsumerWidget {
  const EloDetailScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(myRatingProvider);
    return Scaffold(
      backgroundColor: PlobbyColors.ivory,
      body: r.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: TextButton(onPressed: () => ref.invalidate(myRatingProvider), child: const Text('No se pudo cargar tu rating. Reintentar'))),
        data: (d) => _Body(d),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.d);
  final RatingDetail d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = d.scale.tierOf(d.elo), next = d.scale.nextTier(d.elo);
    final range = ref.watch(historyRangeProvider);
    final pts = d.inRange(range, DateTime.now());
    return ListView(padding: EdgeInsets.zero, children: [
      Container(
        color: PlobbyColors.forest,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 8, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const BackButton(color: PlobbyColors.ivory),
          Row(children: [
            CircleAvatar(radius: 30, backgroundColor: PlobbyColors.lime, foregroundImage: d.avatarUrl == null ? null : NetworkImage(d.avatarUrl!)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: const TextStyle(color: PlobbyColors.ivory, fontSize: 20, fontWeight: FontWeight.w800)),
              Text('@${d.username}', style: TextStyle(color: PlobbyColors.ivory.withOpacity(.65))),
              Chip(label: Text(tier.name), backgroundColor: PlobbyColors.lime, visualDensity: VisualDensity.compact),
            ]),
          ]),
          const SizedBox(height: 16),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: d.elo),
            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text('$v', style: const TextStyle(color: PlobbyColors.lime, fontSize: 64, fontWeight: FontWeight.w800, height: 1)),
          ),
          const SizedBox(height: 14),
          EloBar(elo: d.elo, scale: d.scale),
        ]),
      ),
      _Card('Qué significa tu rating', Text(
          'Tu ELO actual es ${d.elo}, lo que te sitúa en la categoría ${tier.name}. '
          '${next == null ? 'Estás en la categoría más alta.' : 'Te faltan ${next.from - d.elo} puntos para llegar a ${next.name}.'}')),
      const _Card('Cómo se calcula', Text(
          '• Solo cambia tras un partido confirmado.\n'
          '• Se compara la fuerza de tu equipo con la de los rivales.\n'
          '• Se calcula un resultado esperado: cuanto menos se esperaba tu victoria, más puntos ganas.\n'
          '• Ganar a rivales más fuertes suma más; perder contra rivales más débiles resta más.\n\n'
          'El cálculo lo realiza el servidor: la app nunca recalcula tu ELO.')),
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Wrap(spacing: 10, runSpacing: 10, children: [
        _Kpi('${d.confirmedMatches}', 'Partidos confirmados'),
        _Kpi('${d.winRate}%', '% de victorias'),
        _Kpi('${d.delta30 >= 0 ? '+' : ''}${d.delta30}', 'ELO en 30 días'),
        _Kpi('${d.wins} / ${d.losses}', 'Victorias / derrotas'),
        _Kpi('${d.bestElo}', 'ELO máximo histórico'),
      ])),
      _Card('Historial de rating', Column(children: [
        SegmentedButton<HistoryRange>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: HistoryRange.d30, label: Text('30 d')), ButtonSegment(value: HistoryRange.m3, label: Text('3 m')),
            ButtonSegment(value: HistoryRange.m12, label: Text('12 m')), ButtonSegment(value: HistoryRange.all, label: Text('Todo')),
          ],
          selected: {range},
          onSelectionChanged: (s) => ref.read(historyRangeProvider.notifier).state = s.first,
        ),
        const SizedBox(height: 12),
        SizedBox(height: 150, width: double.infinity, child: pts.length < 2
            ? const Center(child: Text('Aún no hay suficientes partidos en este periodo'))
            : CustomPaint(painter: _LinePainter([for (final c in pts) c.after.toDouble()]))),
      ])),
      _Card('Últimos cambios de rating', d.history.isEmpty
          ? const Text('Tu ELO cambiará cuando se confirme tu primer partido.')
          : Column(children: [for (final c in d.history.take(8)) _ChangeRow(c)])),
      const SizedBox(height: 40),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card(this.title, this.child);
  final String title; final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 10), child,
        ]),
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.v, this.l);
  final String v, l;
  @override
  Widget build(BuildContext context) => Container(
        width: (MediaQuery.of(context).size.width - 50) / 2, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: PlobbyColors.forest)),
          Text(l, style: const TextStyle(fontSize: 12, color: PlobbyColors.mute)),
        ]),
      );
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow(this.c);
  final RatingChange c;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        SizedBox(width: 58, child: Text('${c.at.day}/${c.at.month}', style: const TextStyle(color: PlobbyColors.mute, fontSize: 12, fontWeight: FontWeight.w700))),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c.won ? 'Victoria' : 'Derrota'} ${c.score}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('vs ${c.opponents}', style: const TextStyle(fontSize: 12, color: PlobbyColors.mute)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${c.delta > 0 ? '+' : ''}${c.delta}', style: TextStyle(fontWeight: FontWeight.w800, color: c.delta >= 0 ? PlobbyColors.forest : PlobbyColors.loss)),
          Text('${c.before} → ${c.after}', style: const TextStyle(fontSize: 11, color: PlobbyColors.mute)),
        ]),
      ]));
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.v);
  final List<double> v;
  @override
  void paint(Canvas canvas, Size s) {
    final lo = v.reduce((a, b) => a < b ? a : b) - 10, hi = v.reduce((a, b) => a > b ? a : b) + 10;
    Offset p(int i) => Offset(s.width * i / (v.length - 1), s.height - (v[i] - lo) / (hi - lo) * s.height);
    final path = Path()..moveTo(p(0).dx, p(0).dy);
    for (var i = 1; i < v.length; i++) { path.lineTo(p(i).dx, p(i).dy); }
    canvas.drawPath(path, Paint()..color = PlobbyColors.forest..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(p(v.length - 1), 5, Paint()..color = PlobbyColors.lime);
  }
  @override
  bool shouldRepaint(_LinePainter o) => o.v != v;
}
