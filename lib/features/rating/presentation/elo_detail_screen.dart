import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/silhouette_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../application/rating_providers.dart';
import '../domain/rating_models.dart';
import 'elo_bar.dart';

/// Número con separador de miles español (1.482).
String _n(int v) => v.abs() >= 1000 ? '${v < 0 ? '-' : ''}${v.abs() ~/ 1000}.${(v.abs() % 1000).toString().padLeft(3, '0')}' : '$v';
const _months = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];

/// «Mi rating» — `scElo` del prototipo HTML: cabecera tinta con ELO grande y escala, explicación, factores,
/// historial (gráfico sobre tinta con selector de periodo) y últimos cambios. Los datos vienen del servidor.
class EloDetailScreen extends ConsumerWidget {
  const EloDetailScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(myRatingProvider);
    return Scaffold(
      body: r.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
        error: (e, _) => SafeArea(child: Column(children: [
          PlobbyHeaderBar(title: 'Mi rating', onBack: () => context.pop()),
          Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(title: 'No se pudo cargar tu rating', onRetry: () => ref.invalidate(myRatingProvider))),
        ])),
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
    final pct = ((d.elo - d.scale.min) * 100 / (d.scale.max - d.scale.min)).round().clamp(0, 100);
    const body = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.5, letterSpacing: 0, color: AppColors.ink700);
    const b = TextStyle(fontWeight: FontWeight.w700, color: AppColors.text);
    final soft = AppColors.ink50.withValues(alpha: .7);
    return ListView(padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom), children: [
      // Cabecera tinta
      Container(
        color: AppColors.inverse,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 26),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', glass: true, onPressed: () => context.pop()),
            Expanded(child: Center(child: Text('MI RATING', style: PlobbyText.eb.copyWith(color: AppColors.ink50.withValues(alpha: .6))))),
            const SizedBox(width: 40),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.brand, width: 2)),
                child: ClipOval(child: SizedBox(width: 62, height: 62, child: d.avatarUrl != null && d.avatarUrl!.isNotEmpty
                    ? Image.network(d.avatarUrl!, fit: BoxFit.cover, cacheWidth: 186, errorBuilder: (_, __, ___) => SilhouetteAvatar(seed: d.username, size: 62))
                    : SilhouetteAvatar(seed: d.username, size: 62)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.44, color: AppColors.ink50)),
              Text('@${d.username}', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, letterSpacing: 0, color: soft)),
              const SizedBox(height: 6),
              Pill(tier.name, tone: PillTone.lime),
            ])),
          ]),
          const SizedBox(height: 18),
          Semantics(label: 'ELO ${d.elo}', excludeSemantics: true, child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: d.elo),
              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text(_n(v), style: const TextStyle(fontFamily: AppTypography.displayFamily, color: AppColors.brand, fontSize: 64, height: 1, fontWeight: FontWeight.w700, letterSpacing: -2.56)),
            ),
            const SizedBox(width: 8),
            Text('ELO', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.08, color: soft)),
          ])),
          const SizedBox(height: 16),
          EloBar(elo: d.elo, scale: d.scale),
        ]),
      ),
      _Card('Qué significa tu rating', Text.rich(TextSpan(style: body, children: [
        const TextSpan(text: 'Tu ELO actual es '), TextSpan(text: _n(d.elo), style: b), const TextSpan(text: ', lo que te sitúa en la categoría '),
        TextSpan(text: tier.name, style: b), const TextSpan(text: '. '),
        if (next == null) const TextSpan(text: 'Estás en la categoría más alta. ')
        else ...[const TextSpan(text: 'Te faltan '), TextSpan(text: '${next.from - d.elo} puntos', style: b), TextSpan(text: ' para llegar a ${next.name}. ')],
        TextSpan(text: 'Tu escala va de ${d.scale.min} a ${d.scale.max} y estás al $pct % de ella.'),
      ]))),
      _Card('Cómo se calcula', Column(children: [
        for (final (i, parts) in const [
          (1, ['Solo cambia tras un ', 'partido confirmado', '.']),
          (2, ['Cuenta la ', 'fuerza relativa', ': se compara el ELO de tu equipo con el de los rivales.']),
          (3, ['Se calcula un ', 'resultado esperado', '. Cuanto menos se esperaba tu victoria, más puntos ganas.']),
          (4, ['Ganar a rivales más fuertes suma ', 'más', '; perder contra rivales más débiles resta más.']),
        ]) Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0x0F171C19), borderRadius: BorderRadius.circular(7)),
              child: Text('$i', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text))),
          const SizedBox(width: 10),
          Expanded(child: Text.rich(TextSpan(style: body.copyWith(fontSize: 13.5), children: [TextSpan(text: parts[0]), TextSpan(text: parts[1], style: b), TextSpan(text: parts[2])]))),
        ])),
        Text('El cálculo lo realiza el servidor: la app nunca recalcula tu ELO.', style: PlobbyText.help.copyWith(fontSize: 12.5)),
      ])),
      const _Title('Factores de tu rendimiento'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _Kpi('${d.confirmedMatches}', 'Partidos confirmados')),
          const SizedBox(width: 10),
          Expanded(child: _Kpi('${d.winRate}%', '% de victorias', tone: _Tone.lime)),
          const SizedBox(width: 10),
          Expanded(child: _Kpi('${d.delta30 >= 0 ? '+' : ''}${d.delta30}', 'ELO en 30 días', tone: _Tone.dark)),
        ])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _KpiRow('Victorias / Derrotas', '${d.wins} / ${d.losses}')),
          const SizedBox(width: 10),
          Expanded(child: _KpiRow('ELO histórico máximo', _n(d.bestElo))),
        ]),
      ])),
      const _Title('Historial de rating'),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rMd),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SlidingTabs(dark: true, labels: const ['30 días', '3 meses', '12 meses', 'Todo'], index: HistoryRange.values.indexOf(range),
              onChanged: (i) => ref.read(historyRangeProvider.notifier).state = HistoryRange.values[i]),
          const SizedBox(height: 16),
          SizedBox(height: 150, child: pts.length < 2
              ? Center(child: Text('Aún no hay suficientes partidos en este periodo', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, letterSpacing: 0, color: soft)))
              : Semantics(label: 'Evolución del ELO: de ${pts.first.after} a ${pts.last.after}', excludeSemantics: true, child: CustomPaint(painter: _LinePainter([for (final c in pts) c.after.toDouble()])))),
          if (pts.length >= 2) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: const Color(0x1FF6F8F1)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('${pts.last.after - pts.first.before >= 0 ? '+' : ''}${pts.last.after - pts.first.before} puntos en el periodo',
                  style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: soft))),
              Text.rich(TextSpan(style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: soft), children: [
                const TextSpan(text: 'Máximo '),
                TextSpan(text: _n(pts.map((c) => c.after).reduce((a, x) => a > x ? a : x)), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink50)),
              ])),
            ]),
          ],
        ]),
      ),
      const _Title('Últimos cambios de rating'),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: d.history.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Tu ELO cambiará cuando se confirme tu primer partido.', style: PlobbyText.sub))
            : Column(children: [for (var i = 0; i < d.history.length && i < 8; i++) _ChangeRow(d.history[i], first: i == 0)]),
      ),
    ]);
  }
}

class _Title extends StatelessWidget {
  const _Title(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(20, 28, 20, 12), child: Semantics(header: true,
      child: Text(t, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 18, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.18, color: AppColors.text))));
}

class _Card extends StatelessWidget {
  const _Card(this.title, this.child);
  final String title; final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 24, 20, 0), padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, style: PlobbyText.cardTitle)), const SizedBox(height: 10), child,
        ]),
      );
}

enum _Tone { light, lime, dark }

/// Factor grande (número Inter 30/800 y etiqueta 11/600): blanco, lima o tinta, como en el HTML.
class _Kpi extends StatelessWidget {
  const _Kpi(this.v, this.l, {this.tone = _Tone.light});
  final String v, l; final _Tone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, sub) = switch (tone) {
      _Tone.light => (AppColors.surface, AppColors.text, AppColors.textMuted),
      _Tone.lime => (AppColors.brand, AppColors.brandInk, const Color(0xB3171C19)),
      _Tone.dark => (AppColors.inverse, AppColors.brand, const Color(0xA6F6F8F1)),
    };
    return Semantics(label: '$l: $v', excludeSemantics: true, child: Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.rMd, boxShadow: tone == _Tone.light ? AppShadows.card : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 30, height: 1, fontWeight: FontWeight.w800, letterSpacing: -0.75, color: fg))),
        const SizedBox(height: 12),
        Text(l, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0, color: sub)),
      ]),
    ));
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow(this.l, this.v);
  final String l, v;
  @override
  Widget build(BuildContext context) => Semantics(label: '$l: $v', excludeSemantics: true, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.textMuted))),
          const SizedBox(width: 6),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.text)))),
        ]),
      ));
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow(this.c, {this.first = false});
  final RatingChange c; final bool first;
  @override
  Widget build(BuildContext context) => Semantics(label: '${c.won ? 'Victoria' : 'Derrota'} ${c.score} contra ${c.opponents}, ${c.delta > 0 ? '+' : ''}${c.delta} ELO', excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: Color(0x1A171C19)))),
        child: Row(children: [
          SizedBox(width: 58, child: Text('${c.at.day} ${_months[c.at.month - 1]}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.textMuted))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.won ? 'Victoria' : 'Derrota'} ${c.score}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            Text('vs ${c.opponents}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0, color: AppColors.textMuted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${c.delta > 0 ? '+' : ''}${c.delta}', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0, color: c.delta >= 0 ? AppColors.success : AppColors.danger)),
            Text('${_n(c.before)} – ${_n(c.after)}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, letterSpacing: 0, color: AppColors.textMuted)),
          ]),
        ]),
      ));
}

/// Línea lima con área degradada y punto final, sobre tinta (como el gráfico del HTML).
class _LinePainter extends CustomPainter {
  _LinePainter(this.v);
  final List<double> v;
  @override
  void paint(Canvas canvas, Size s) {
    final lo = v.reduce((a, b) => a < b ? a : b) - 10, hi = v.reduce((a, b) => a > b ? a : b) + 10;
    Offset p(int i) => Offset(s.width * i / (v.length - 1), s.height - (v[i] - lo) / (hi - lo) * s.height);
    final path = Path()..moveTo(p(0).dx, p(0).dy);
    for (var i = 1; i < v.length; i++) { path.lineTo(p(i).dx, p(i).dy); }
    final area = Path.from(path)..lineTo(s.width, s.height)..lineTo(0, s.height)..close();
    canvas.drawPath(area, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x40D2F548), Color(0x05D2F548)]).createShader(Offset.zero & s));
    canvas.drawPath(path, Paint()..color = AppColors.brand..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(p(v.length - 1), 4.5, Paint()..color = AppColors.brand);
  }
  @override
  bool shouldRepaint(_LinePainter o) => o.v != v;
}
