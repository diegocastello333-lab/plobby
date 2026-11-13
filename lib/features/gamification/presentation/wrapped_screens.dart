import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/gamification_providers.dart';
import '../domain/gamification_models.dart';
import 'gamification_widgets.dart';
import 'share_image_sheet.dart';

/// Lista de Wrapped disponibles (años y meses con partidos). El mes recién cerrado aparece como «Nuevo».
class WrappedListScreen extends ConsumerWidget {
  const WrappedListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wrappedPeriodsProvider);
    return Scaffold(body: SafeArea(bottom: false, child: Column(children: [
      PlobbyHeaderBar(title: 'Plobby Wrapped', onBack: () => context.pop()),
      Expanded(child: async.when(
        loading: () => ListView(padding: const EdgeInsets.all(20), children: const [LoadingBlock(height: 160), SizedBox(height: 12), LoadingBlock(height: 72)]),
        error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(wrappedPeriodsProvider))),
        data: (ps) {
          if (ps.isEmpty) {
            return Padding(padding: const EdgeInsets.all(20), child: EmptyStateCard(icon: Icons.auto_awesome, title: 'Tu primer Wrapped te espera.',
                text: 'Juega y confirma partidos: al terminar el mes tendrás tu resumen.'));
          }
          final years = ps.where((p) => p.kind == WrappedKind.year).toList(), months = ps.where((p) => p.kind == WrappedKind.month).toList();
          final now = DateTime.now();
          return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 48), children: [
            if (years.isNotEmpty) ...[
              AppearOnce(child: _YearCard(p: years.first)),
              for (final y in years.skip(1)) Padding(padding: const EdgeInsets.only(top: 10), child: _PeriodTile(p: y, now: now)),
              const SizedBox(height: 24),
            ],
            const SectionHeader(title: 'Meses'),
            for (final (i, m) in months.indexed) AppearOnce(index: i, child: _PeriodTile(p: m, now: now)),
          ]);
        },
      )),
    ])));
  }
}

void _open(BuildContext context, WrappedPeriod p) => context.push('/wrapped/${p.kind.name}/${p.start.year}-${p.start.month.toString().padLeft(2, '0')}');

class _YearCard extends StatelessWidget {
  const _YearCard({required this.p});
  final WrappedPeriod p;
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: 'Tu ${p.start.year} en Plobby, ${p.played} partidos', excludeSemantics: true,
      child: Pressable(child: GestureDetector(onTap: () => _open(context, p), child: Container(
        height: 168, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('PLOBBY WRAPPED', style: PlobbyText.eb.copyWith(color: AppColors.brand)),
            const Spacer(),
            if (p.inProgress) const Pill('En curso', tone: PillTone.lime),
          ]),
          const Spacer(),
          Text('Tu ${p.start.year}', style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 40, height: 1, fontWeight: FontWeight.w700, letterSpacing: -1.2, color: AppColors.ink50)),
          const SizedBox(height: 8),
          Row(children: [
            Text('${p.played} partidos', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, letterSpacing: 0, color: Color(0xB3F6F8F1))),
            const Spacer(),
            const PlobbyIcon(PlobbyIcons.play, size: 18, color: AppColors.brand),
          ]),
        ]),
      ))));
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({required this.p, required this.now});
  final WrappedPeriod p;
  final DateTime now;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: SurfaceCard(
      onTap: () => _open(context, p),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: p.isNew(now) ? AppColors.brand : AppColors.surfaceSunken, borderRadius: AppRadius.rSm),
            alignment: Alignment.center, child: PlobbyIcon(PlobbyIcons.star, size: 18, color: p.isNew(now) ? AppColors.brandInk : AppColors.text)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(capitalize(p.label), style: PlobbyText.cardTitle),
          Text('${p.played} ${p.played == 1 ? 'partido' : 'partidos'}', style: PlobbyText.help),
        ])),
        if (p.isNew(now)) const Pill('Nuevo', tone: PillTone.lime) else if (p.inProgress) const Pill('En curso'),
        const SizedBox(width: 6),
        const PlobbyIcon(PlobbyIcons.chev, size: 16, color: AppColors.textMuted),
      ])));
}

/// Experiencia tipo Stories: diapositivas a pantalla completa, toque derecho/izquierdo o deslizar; barras de
/// progreso arriba; avance automático cada 6 s (se pausa manteniendo el dedo). Solo diapositivas con datos reales.
class WrappedStoryScreen extends ConsumerStatefulWidget {
  const WrappedStoryScreen({super.key, required this.kind, required this.start});
  final WrappedKind kind;
  final DateTime start;
  @override
  ConsumerState<WrappedStoryScreen> createState() => _WrappedStoryScreenState();
}

class _WrappedStoryScreenState extends ConsumerState<WrappedStoryScreen> with SingleTickerProviderStateMixin {
  final _page = PageController();
  late final _timer = AnimationController(vsync: this, duration: const Duration(seconds: 6))..addStatusListener((s) { if (s == AnimationStatus.completed) _next(); });
  var _index = 0, _count = 1;

  @override
  void dispose() { _timer.dispose(); _page.dispose(); super.dispose(); }

  void _go(int i) {
    if (i < 0 || i >= _count) return;
    _page.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }
  void _next() => _index < _count - 1 ? _go(_index + 1) : _timer.stop();

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(wrappedProvider((widget.kind, widget.start)));
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: Scaffold(
      backgroundColor: AppColors.ink900,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brand)),
        error: (_, __) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Align(alignment: Alignment.centerLeft, child: IconSquareButton(icon: PlobbyIcons.close, tooltip: 'Cerrar', onPressed: () => context.pop())),
          const SizedBox(height: 20),
          ErrorStateCard(onRetry: () => ref.invalidate(wrappedProvider((widget.kind, widget.start)))),
        ]))),
        data: (w) {
          final slides = wrappedSlides(w);
          _count = slides.length;
          if (!reduce && !_timer.isAnimating && _index < _count - 1 && _timer.value == 0) _timer.forward();
          return GestureDetector(
            onLongPressStart: (_) => _timer.stop(), onLongPressEnd: (_) { if (!reduce) _timer.forward(); },
            onTapUp: (d) => d.localPosition.dx < MediaQuery.sizeOf(context).width * .3 ? _go(_index - 1) : _next(),
            child: Stack(children: [
              PageView.builder(
                controller: _page, itemCount: slides.length,
                onPageChanged: (i) { setState(() => _index = i); _timer.reset(); if (!reduce && i < _count - 1) _timer.forward(); },
                itemBuilder: (_, i) => _Slide(w: w, slide: slides[i], index: i),
              ),
              SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Column(children: [
                Row(children: [
                  for (var i = 0; i < slides.length; i++) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: AnimatedBuilder(animation: _timer, builder: (_, __) => LinearProgressIndicator(minHeight: 3,
                        value: i < _index ? 1 : i == _index ? (_index == _count - 1 ? 1 : _timer.value) : 0,
                        color: AppColors.brand, backgroundColor: const Color(0x33F6F8F1))),
                  ))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text('WRAPPED · ${w.periodLabel.toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: PlobbyText.eb.copyWith(color: const Color(0xB3F6F8F1)))),
                  const SizedBox(width: 8),
                  IconSquareButton(icon: PlobbyIcons.share, tooltip: 'Compartir', glass: true, size: 36, onPressed: () => showShareImageSheet(context, ShareTarget.wrapped(w))),
                  const SizedBox(width: 8),
                  IconSquareButton(icon: PlobbyIcons.close, tooltip: 'Cerrar', glass: true, size: 36, onPressed: () => context.pop()),
                ]),
              ]))),
            ]),
          );
        },
      ),
    ));
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.w, required this.slide, required this.index});
  final WrappedData w;
  final WrappedSlide slide;
  final int index;

  static const _big = TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w700, letterSpacing: -2, color: AppColors.ink50, height: 1);
  static const _lead = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 19, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: 0, color: Color(0xCCF6F8F1));
  static const _hl = TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 30, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: AppColors.ink50);

  String get _when => w.kind == WrappedKind.year ? 'este año' : 'en ${monthName(w.start.month)}';

  @override
  Widget build(BuildContext context) {
    final bg = switch (index % 3) { 0 => AppColors.ink900, 1 => const Color(0xFF1B2620), _ => const Color(0xFF12201A) };
    final content = switch (slide) {
      WrappedSlide.cover => _col([
          Text('TU PLOBBY\nWRAPPED', style: _big.copyWith(fontSize: 52, color: AppColors.brand)),
          const SizedBox(height: 18),
          Text(w.periodLabel, style: _hl),
          const SizedBox(height: 10),
          Text(w.played == 0 ? 'No hay partidos confirmados en este periodo.' : 'Así ha sido ${w.kind == WrappedKind.year ? 'tu año' : 'tu mes'} en la pista, ${w.name.split(' ').first}.', style: _lead),
        ]),
      WrappedSlide.played => _col([
          Text('${capitalize(_when)} has jugado', style: _lead),
          _BigNumber(w.played),
          Text(w.played == 1 ? 'partido' : 'partidos', style: _hl),
          const SizedBox(height: 16),
          Text('${w.setsPlayed} sets disputados.', style: _lead),
        ]),
      WrappedSlide.wins => _col([
          Text('Has ganado', style: _lead),
          _BigNumber(w.wins),
          Text('de ${w.played} partidos', style: _hl),
          const SizedBox(height: 18),
          _Meter(value: (w.winRate ?? 0) / 100, label: '${w.winRate}% de victorias'),
        ]),
      WrappedSlide.partner => _col([
          Text('Tu compañero más habitual', style: _lead),
          const SizedBox(height: 18),
          GAvatar(w.topPartner!.player, size: 108, ring: AppColors.brand, ringWidth: 4),
          const SizedBox(height: 18),
          Text(w.topPartner!.player.name, style: _hl),
          const SizedBox(height: 8),
          Text('${w.topPartner!.played} partidos juntos · ${w.topPartner!.winRate}% de victorias', style: _lead),
        ]),
      WrappedSlide.rival => _col([
          Text('El rival al que más te has enfrentado', style: _lead),
          const SizedBox(height: 18),
          GAvatar(w.topRival!.player, size: 96, ring: const Color(0x80F6F8F1), ringWidth: 3),
          const SizedBox(height: 16),
          Text(w.topRival!.player.name, style: _hl),
          Text('${w.topRival!.played} veces · le ganaste ${w.topRival!.wins}', style: _lead),
          if (w.bestRival != null && w.bestRival!.player.id != w.topRival!.player.id) ...[
            const SizedBox(height: 22),
            Text('Tu mejor balance: contra ${w.bestRival!.player.first}, ${w.bestRival!.wins} de ${w.bestRival!.played}.', style: _lead),
          ],
        ]),
      WrappedSlide.streak => _col([
          const PlobbyIcon(PlobbyIcons.flame, size: 64, color: AppColors.brand),
          const SizedBox(height: 10),
          Text('Tu mayor racha', style: _lead),
          _BigNumber(w.bestStreak),
          Text('victorias seguidas', style: _hl),
        ]),
      WrappedSlide.busiest => _col([
          if (w.kind == WrappedKind.year && w.busiestBucket != null) ...[
            Text('Tu mes más activo', style: _lead),
            const SizedBox(height: 8),
            Text(capitalize(monthName(w.busiestBucket!.start.month)), style: _big.copyWith(fontSize: 56, color: AppColors.brand)),
            Text('${w.busiestBucket!.played} partidos', style: _hl),
            const SizedBox(height: 22),
            _Bars(w: w),
          ] else ...[
            Text('Tus días de pádel', style: _lead),
            const SizedBox(height: 8),
            Text('Los ${w.topWeekday}', style: _big.copyWith(fontSize: 48, color: AppColors.brand)),
            Text('es cuando más juegas', style: _hl),
            if (w.buckets.length >= 2) ...[const SizedBox(height: 22), _Bars(w: w)],
          ],
        ]),
      WrappedSlide.evolution => _col([
          Text('Respecto al ${w.kind == WrappedKind.year ? 'año' : 'mes'} anterior', style: _lead),
          const SizedBox(height: 18),
          _Compare(label: 'Partidos', before: '${w.prevPlayed}', now: '${w.played}', up: w.played >= w.prevPlayed),
          if (w.prevWinRate != null && w.winRate != null) _Compare(label: '% de victorias', before: '${w.prevWinRate}%', now: '${w.winRate}%', up: w.winRate! >= w.prevWinRate!),
          if (w.bestBucket != null) ...[
            const SizedBox(height: 18),
            Text('Tu mejor ${w.kind == WrappedKind.year ? 'mes' : 'semana'}: ${w.kind == WrappedKind.year ? capitalize(monthName(w.bestBucket!.start.month)) : 'la del ${w.bestBucket!.start.day}'}, '
                'con un ${w.bestBucket!.winRate}% de victorias.', style: _lead),
          ],
        ]),
      WrappedSlide.memorable => _col([
          Text('Tu partido más memorable', style: _lead),
          const SizedBox(height: 14),
          Text(w.memorable!.score, style: _big.copyWith(fontSize: 48, letterSpacing: -1)),
          const SizedBox(height: 12),
          Text('${shortDate(w.memorable!.playedAt)}${w.memorable!.myPartner != null ? ' · con ${w.memorable!.myPartner}' : ''}', style: _lead),
          if ((w.memorable!.theirPartner ?? '').isNotEmpty) Text('contra ${w.memorable!.theirPartner}', style: _lead),
          const SizedBox(height: 8),
          Text(w.memorable!.sets.length >= 3 ? 'Una victoria a tres sets.' : 'Tu victoria más disputada.', style: _lead.copyWith(color: AppColors.brand)),
        ]),
      WrappedSlide.record => _col([
          Text(w.isRecord ? 'Nuevo récord personal' : 'Tu ELO más alto del periodo', style: _lead),
          _BigNumber(w.recordElo!),
          Text('puntos de ELO', style: _hl),
        ]),
      WrappedSlide.achievements => _col([
          Text('Logros desbloqueados', style: _lead),
          _BigNumber(w.achievements.length),
          const SizedBox(height: 10),
          for (final a in w.achievements.take(4)) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
            const PlobbyIcon(PlobbyIcons.star, size: 18, color: AppColors.brand), const SizedBox(width: 10),
            Expanded(child: Text(a.$2, style: _lead.copyWith(color: AppColors.ink50))),
          ])),
        ]),
      WrappedSlide.summary => _col([
          Text('Tu ${w.kind == WrappedKind.year ? 'año' : 'mes'} en Plobby', style: _lead),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Tile('PARTIDOS', '${w.played}'), _Tile('VICTORIAS', '${w.wins}'),
            _Tile('% VICTORIAS', w.winRate == null ? '—' : '${w.winRate}%'), _Tile('MEJOR RACHA', '${w.bestStreak}'),
          ]),
          const SizedBox(height: 22),
          Builder(builder: (context) => PlobbyButton(label: 'Compartir mi Wrapped', icon: PlobbyIcons.share, onPressed: () => showShareImageSheet(context, ShareTarget.wrapped(w)))),
        ]),
    };
    return ColoredBox(color: bg, child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(28, 92, 28, 40), child: content)));
  }

  Widget _col(List<Widget> c) => Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, w) in c.indexed) AppearOnce(animationKey: '$slide', index: i, child: w),
      ]);
}

class _BigNumber extends StatelessWidget {
  const _BigNumber(this.value);
  final int value;
  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()), duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('${v.round()}', style: _Slide._big.copyWith(fontSize: 120, color: AppColors.brand))));
}

class _Meter extends StatelessWidget {
  const _Meter({required this.value, required this.label});
  final double value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(6), child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value), duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 12, color: AppColors.brand, backgroundColor: const Color(0x24F6F8F1)))),
        const SizedBox(height: 10),
        Text(label, style: _Slide._lead.copyWith(color: AppColors.ink50)),
      ]);
}

class _Bars extends StatelessWidget {
  const _Bars({required this.w});
  final WrappedData w;
  @override
  Widget build(BuildContext context) {
    final max = w.buckets.fold<int>(1, (a, b) => b.played > a ? b.played : a);
    final busiest = w.busiestBucket;
    return SizedBox(height: 120, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final b in w.buckets) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(height: 90 * b.played / max, decoration: BoxDecoration(color: b == busiest ? AppColors.brand : const Color(0x40F6F8F1), borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 6),
        Text(w.kind == WrappedKind.year ? monthName(b.start.month)[0].toUpperCase() : '${b.start.day}',
            style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10.5, letterSpacing: 0, color: Color(0x99F6F8F1))),
      ]))),
    ]));
  }
}

class _Compare extends StatelessWidget {
  const _Compare({required this.label, required this.before, required this.now, required this.up});
  final String label, before, now;
  final bool up;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [
        Expanded(child: Text(label, style: _Slide._lead)),
        Text(before, style: _Slide._lead),
        const SizedBox(width: 10),
        PlobbyIcon(up ? PlobbyIcons.arrup : PlobbyIcons.arrdn, size: 18, color: up ? AppColors.brand : const Color(0xFFFF8A8A)),
        const SizedBox(width: 10),
        Text(now, style: _Slide._hl.copyWith(fontSize: 26)),
      ]));
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) => Container(
        width: (MediaQuery.sizeOf(context).width - 56 - 12) / 2, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0x14F6F8F1), borderRadius: AppRadius.rMd),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: PlobbyText.eb.copyWith(color: const Color(0x99F6F8F1))),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: _Slide._hl.copyWith(fontSize: 32, color: AppColors.brand))),
        ]),
      ));
}
