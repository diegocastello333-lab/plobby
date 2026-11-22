import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/celebration.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../gamification/application/gamification_providers.dart';
import '../../gamification/domain/gamification_models.dart';
import '../../gamification/presentation/gamification_widgets.dart';
import '../../gamification/presentation/share_image_sheet.dart';
import '../../rating/application/rating_providers.dart';
import '../application/lifecycle_providers.dart';
import '../domain/match_lifecycle.dart';
import '../domain/post_match_summary.dart';

/// Recuerda en el dispositivo qué partidos ya mostraron su resumen (se enseña solo, UNA vez por partido).
class PostMatchSeen {
  PostMatchSeen._();
  static const _key = 'plobby.post_match_seen';
  static Future<bool> isSeen(String id) async {
    try { return ((await SharedPreferences.getInstance()).getStringList(_key) ?? const []).contains(id); } catch (_) { return true; }
  }
  static Future<void> markSeen(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final l = [...(p.getStringList(_key) ?? const <String>[]).where((x) => x != id), id];
      await p.setStringList(_key, l.length > 60 ? l.sublist(l.length - 60) : l);
    } catch (_) {/* sin almacenamiento: como mucho se vuelve a enseñar */}
  }
}

/// Abre el resumen SOLO la primera vez que el jugador ve un partido confirmado reciente (≤ 7 días) en este dispositivo.
/// No hace nada fuera de un GoRouter (p. ej. en tests de una pantalla suelta).
class PostMatchAutoOpen extends StatefulWidget {
  const PostMatchAutoOpen({super.key, required this.matchId, required this.enabled});
  final String matchId;
  final bool enabled;
  @override
  State<PostMatchAutoOpen> createState() => _PostMatchAutoOpenState();
}

class _PostMatchAutoOpenState extends State<PostMatchAutoOpen> {
  bool _checked = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked || !widget.enabled || GoRouter.maybeOf(context) == null) return;
    _checked = true;
    unawaited(PostMatchSeen.isSeen(widget.matchId).then((seen) {
      if (!seen && mounted) context.push('/match/${widget.matchId}/summary');
    }));
  }
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Pantalla post-partido (`/match/:id/summary`). Secuencia: sets uno a uno con los juegos contando → Victoria o
/// «Buen partido» → ELO contando con el ±cambio y la barra de categoría → XP con su desglose → logros nuevos
/// volteándose. «Saltar» está visible desde el principio y un toque en cualquier parte lo termina. Con «reducir
/// movimiento» se muestra el estado final directamente. Los datos son los del servidor; la animación solo los decora.
class PostMatchScreen extends ConsumerWidget {
  const PostMatchScreen({super.key, required this.matchId});
  final String matchId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(matchProvider(matchId));
    final uid = ref.watch(currentUserIdProvider);
    final rating = ref.watch(myRatingProvider), ach = ref.watch(achievementsProvider);
    final match = m.valueOrNull;
    if (m.hasError && match == null) {
      return Scaffold(body: Column(children: [
        PlobbyHeaderBar(title: 'Resumen del partido', onBack: () => context.pop()),
        Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(20),
            child: ErrorStateCard(error: m.error, onRetry: () => ref.invalidate(matchProvider(matchId)))))),
      ]));
    }
    // espera a los tres (o a que fallen: entonces se enseña lo que haya)
    if (match == null || (!rating.hasValue && !rating.hasError) || (!ach.hasValue && !ach.hasError)) {   // una recarga NO reinicia la secuencia
      return const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.text)));
    }
    if (match.status != MatchStatus.confirmed) {
      return Scaffold(body: Column(children: [
        PlobbyHeaderBar(title: 'Resumen del partido', onBack: () => context.pop()),
        const Expanded(child: Center(child: Padding(padding: EdgeInsets.all(20),
            child: EmptyStateCard(icon: Icons.schedule, title: 'Aún no está confirmado', text: 'El resumen aparece cuando los dos capitanes aceptan el resultado.')))),
      ]));
    }
    final s = PostMatchSummary.build(m: match, uid: uid, ratings: rating.valueOrNull, ach: ach.valueOrNull);
    return _PostMatchView(summary: s);
  }
}

/// Tramos de la secuencia (en fracciones de una sola línea de tiempo). Solo existen los tramos con datos.
class _Timeline {
  _Timeline(PostMatchSummary s) {
    void add(String k, Duration d) { _spans[k] = (_total, d); _total += d; }
    add('sets', Motion.emphasis * math.max(1, s.sets.length));
    add('head', Motion.emphasis);
    if (s.hasElo) add('elo', Motion.celebrationLong);
    if (s.hasXp) add('xp', Motion.celebrationLong);
    if (s.achievements.isNotEmpty) add('ach', Motion.celebration + Motion.normal * (s.achievements.length - 1));
  }
  final _spans = <String, (Duration, Duration)>{};
  Duration _total = Duration.zero;
  Duration get total => _total;
  bool has(String k) => _spans.containsKey(k);
  double start(String k) => _spans[k] == null ? 1 : _spans[k]!.$1.inMicroseconds / _total.inMicroseconds;
  /// Progreso 0→1 del tramo [k] cuando la línea de tiempo va por [v].
  double of(String k, double v) {
    final sp = _spans[k];
    if (sp == null) return 1;
    final a = sp.$1.inMicroseconds / _total.inMicroseconds, b = (sp.$1 + sp.$2).inMicroseconds / _total.inMicroseconds;
    return ((v - a) / (b - a)).clamp(0.0, 1.0);
  }
}

class _PostMatchView extends ConsumerStatefulWidget {
  const _PostMatchView({required this.summary});
  final PostMatchSummary summary;
  @override
  ConsumerState<_PostMatchView> createState() => _PostMatchViewState();
}

class _PostMatchViewState extends ConsumerState<_PostMatchView> with SingleTickerProviderStateMixin {
  late final _tl = _Timeline(widget.summary);
  late final AnimationController _c = AnimationController(vsync: this, duration: _tl.total)
    ..addListener(_cues)
    ..addStatusListener((st) { if (st == AnimationStatus.completed) _finish(); });
  final _fired = <String>{};
  bool _started = false, _done = false;

  PostMatchSummary get s => widget.summary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(PostMatchSeen.markSeen(s.matchId));
    if (Motion.reduced(context)) {
      _cue('head');            // sin animación, pero la vibración del resultado sí (una vez)
      _c.value = 1;
      _finish();
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Vibración UNA vez por evento, al empezar su tramo. La derrota no vibra.
  void _cues() {
    for (final k in const ['head', 'ach']) {
      if (_tl.has(k) && _c.value >= _tl.start(k)) _cue(k);
    }
  }

  void _cue(String k) {
    if (!_fired.add(k)) return;
    if (k == 'head' && s.won) AppHaptics.success();
    if (k == 'ach' && s.achievements.isNotEmpty) AppHaptics.medium();
  }

  void _skip() {
    if (_done) return;
    _fired.addAll(const ['head', 'ach']);   // saltar no dispara vibraciones atrasadas
    _c.stop();
    _c.value = 1;
    _finish();
  }

  void _finish() {
    if (_done) return;
    setState(() => _done = true);
    // subida de nivel y/o de categoría: UNA celebración a pantalla completa al terminar (no interrumpe la secuencia)
    if (s.leveledUp || s.tierUp) {
      final title = s.leveledUp ? '¡Nivel ${s.levelAfter}!' : '¡${s.tierAfter}!';
      final text = [
        if (s.leveledUp) 'Has subido al nivel ${s.levelAfter}.',
        if (s.tierUp) 'Nueva categoría de ELO: ${s.tierAfter}.',
      ].join(' ');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showCelebration(context, Celebration(eventKey: 'pm:${s.matchId}', title: title, text: text,
            icon: s.leveledUp ? PlobbyIcons.star : PlobbyIcons.trophy));
      });
    }
    if (s.achievements.isNotEmpty) {
      // los logros ya se han visto aquí: se marcan en el servidor (seen_at) para no volver a celebrarlos
      unawaited(ref.read(gamificationRepositoryProvider).markAchievementsSeen().then((_) {
        if (mounted) ref.invalidate(achievementsProvider);
      }).catchError((Object _) {/* se marcarán la próxima vez que se abra Logros */}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent, onTap: _done ? null : _skip,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            return Column(children: [
              SizedBox(height: pad.top),
              SizedBox(height: 52, child: Row(children: [
                SizedBox(width: 84, child: Align(alignment: AlignmentDirectional.centerStart, child: IconButton(tooltip: 'Cerrar', onPressed: () => context.pop(),
                    icon: const PlobbyIcon(PlobbyIcons.close, size: 22, color: AppColors.text)))),
                Expanded(child: Text('Resumen del partido', textAlign: TextAlign.center, style: PlobbyText.t2, maxLines: 2)),
                SizedBox(width: 84, child: AnimatedOpacity(
                  opacity: _done ? 0 : 1, duration: Motion.of(context, Motion.fast),
                  child: IgnorePointer(ignoring: _done, child: TextButton(onPressed: _skip,
                      child: Text('Saltar', style: PlobbyText.link.copyWith(color: AppColors.text)))),
                )),
              ])),
              Expanded(child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                _Hero(s: s, sets: _tl.of('sets', v), head: _tl.of('head', v)),
                if (s.hasElo) ...[const SizedBox(height: 12), _Reveal(t: _tl.of('elo', v), child: _EloBlock(s: s, t: _tl.of('elo', v)))],
                if (s.hasXp) ...[const SizedBox(height: 12), _Reveal(t: _tl.of('xp', v), child: _XpBlock(s: s, t: _tl.of('xp', v)))],
                if (s.achievements.isNotEmpty) ...[const SizedBox(height: 12), _Reveal(t: _tl.of('ach', v), child: _AchBlock(s: s, t: _tl.of('ach', v)))],
              ])),
              AnimatedOpacity(
                opacity: _done ? 1 : 0, duration: Motion.of(context, Motion.normal), curve: Motion.enter,
                child: IgnorePointer(ignoring: !_done, child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + pad.bottom),
                  child: Row(children: [
                    Expanded(child: PlobbyButton(label: 'Ver detalles', kind: PlobbyButtonKind.outline,
                        onPressed: () => context.pushReplacement('/match/${s.matchId}/final'))),
                    const SizedBox(width: 10),
                    Expanded(child: PlobbyButton(label: 'Compartir', icon: PlobbyIcons.share,
                        onPressed: () => showShareImageSheet(context, ShareTarget.postMatch(s)))),
                  ]),
                )),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Aparece subiendo 12 px y con fundido al empezar su tramo (con un poco de margen para leer).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.t, required this.child});
  final double t;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final e = Motion.enter.transform((t * 4).clamp(0.0, 1.0));
    return Opacity(opacity: e, child: Transform.translate(offset: Offset(0, 12 * (1 - e)), child: child));
  }
}

// ─────────────── Resultado ───────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.s, required this.sets, required this.head});
  final PostMatchSummary s;
  final double sets, head;
  @override
  Widget build(BuildContext context) {
    final n = s.sets.length;
    final h = Motion.springBounce.transform(head);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
      decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg),
      child: Column(children: [
        Text('PARTIDO CONFIRMADO', textAlign: TextAlign.center, style: PlobbyText.eb.copyWith(color: AppColors.brand)),
        const SizedBox(height: 14),
        Semantics(
          label: 'Sets: ${s.score}', excludeSemantics: true,
          child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < n; i++) _SetChip(s: s, i: i, t: ((sets * n) - i).clamp(0.0, 1.0)),
          ]),
        ),
        const SizedBox(height: 16),
        // titular: el resultado se dice con palabras e icono (no solo con color)
        Opacity(opacity: head.clamp(0.0, 1.0), child: Transform.scale(scale: .85 + .15 * h, child: Column(children: [
          Semantics(header: true, liveRegion: true, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            PlobbyIcon(s.won ? PlobbyIcons.trophy : PlobbyIcons.thumb, size: 22, color: s.won ? AppColors.brand : const Color(0xFFF2F5EF)),
            const SizedBox(width: 10),
            Flexible(child: Text(s.headline, style: PlobbyText.t1.copyWith(color: s.won ? AppColors.brand : const Color(0xFFF2F5EF)))),
          ])),
          const SizedBox(height: 6),
          Text(s.subline, textAlign: TextAlign.center, style: PlobbyText.sub.copyWith(color: const Color(0xD9FFFFFF))),
        ]))),
      ]),
    );
  }
}

/// Un set: entra con escala y los juegos cuentan de 0 al resultado.
class _SetChip extends StatelessWidget {
  const _SetChip({required this.s, required this.i, required this.t});
  final PostMatchSummary s;
  final int i;
  final double t;
  @override
  Widget build(BuildContext context) {
    final (a, b) = s.mine(s.sets[i]);
    final e = Motion.enter.transform(t), pop = Motion.springBounce.transform(t);
    final won = a > b;
    return Opacity(opacity: e, child: Transform.scale(scale: .7 + .3 * pop, child: Container(
      constraints: const BoxConstraints(minWidth: 84), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: won ? AppColors.brand : AppColors.ink800, borderRadius: AppRadius.rMd),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('SET ${i + 1}', style: PlobbyText.key.copyWith(color: won ? AppColors.ink700 : const Color(0xFF9AA39D))),
        const SizedBox(height: 4),
        Text('${(a * e).round()}-${(b * e).round()}', style: TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600,
            fontSize: 30, letterSpacing: -0.6, height: 1.1, color: won ? AppColors.ink900 : Colors.white, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    )));
  }
}

// ─────────────── ELO ───────────────

class _EloBlock extends StatelessWidget {
  const _EloBlock({required this.s, required this.t});
  final PostMatchSummary s;
  final double t;
  @override
  Widget build(BuildContext context) {
    final e = Motion.move.transform((t * 1.25).clamp(0.0, 1.0));
    final before = s.eloBefore!, d = s.eloDelta!, now = (before + d * e).round();
    final up = d >= 0;
    final sign = up ? '+' : '−';
    final deltaIn = Motion.springBounce.transform(((t - .45) / .4).clamp(0.0, 1.0));
    return _Card(
      semantics: 'ELO: $before a ${s.eloAfter}, ${up ? 'sube' : 'baja'} ${d.abs()} puntos${s.tierUp ? '. Nueva categoría: ${s.tierAfter}' : ''}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ELO', style: PlobbyText.eb.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text('$now', style: PlobbyText.stat.copyWith(fontSize: 34, letterSpacing: -0.68, fontFeatures: const [FontFeature.tabularFigures()])),
          ])),
          // cambio flotante: sube desde abajo; flecha + signo + número (no solo color)
          Opacity(opacity: deltaIn.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 14 * (1 - deltaIn)), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: up ? AppColors.successSoft : AppColors.surfaceSunken, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              PlobbyIcon(up ? PlobbyIcons.arrup : PlobbyIcons.arrdn, size: 14, color: up ? AppColors.success : AppColors.textMuted),
              const SizedBox(width: 4),
              Text('$sign${d.abs()}', style: PlobbyText.value.copyWith(fontWeight: FontWeight.w800, color: up ? AppColors.success : AppColors.ink700)),
            ]),
          ))),
        ]),
        if (s.scale != null) ...[
          const SizedBox(height: 14),
          _TierBar(scale: s, value: now),
          if (s.tierUp) ...[
            const SizedBox(height: 10),
            Opacity(opacity: ((t - .8) / .2).clamp(0.0, 1.0), child: Row(children: [
              const PlobbyIcon(PlobbyIcons.star, size: 16, color: AppColors.text), const SizedBox(width: 6),
              Flexible(child: Text('Nueva categoría: ${s.tierAfter}', style: PlobbyText.value.copyWith(fontWeight: FontWeight.w700))),
            ])),
          ],
        ],
      ]),
    );
  }
}

/// Barra de categoría: posición del ELO entre el mínimo y el máximo, con marcas en cada umbral y el nombre actual.
class _TierBar extends StatelessWidget {
  const _TierBar({required this.scale, required this.value});
  final PostMatchSummary scale;
  final int value;
  @override
  Widget build(BuildContext context) {
    final sc = scale.scale!;
    final f = sc.fraction(value), tier = sc.tierOf(value), next = sc.nextTier(value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (_, c) => SizedBox(height: 10, child: Stack(children: [
        Container(decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(5))),
        Container(width: c.maxWidth * f, decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.lime500))),
        for (final t in sc.tiers.skip(1)) Positioned(left: c.maxWidth * sc.fraction(t.from) - 1, top: 0, bottom: 0,
            child: Container(width: 2, color: AppColors.bg)),
      ]))),
      const SizedBox(height: 6),
      Row(children: [
        Text(tier.name, style: PlobbyText.label),
        const Spacer(),
        if (next != null) Text('${next.name} en ${next.from}', style: PlobbyText.help),
      ]),
    ]);
  }
}

// ─────────────── XP ───────────────

class _XpBlock extends StatelessWidget {
  const _XpBlock({required this.s, required this.t});
  final PostMatchSummary s;
  final double t;
  @override
  Widget build(BuildContext context) {
    final e = Motion.move.transform((t * 1.25).clamp(0.0, 1.0));
    final xp = (s.xpBefore! + s.xpGained * e).round();
    final lvl = levelForXp(xp), floor = xpForLevel(lvl), ceil = xpForLevel(lvl + 1);
    final frac = ceil <= floor ? 1.0 : ((xp - floor) / (ceil - floor)).clamp(0.0, 1.0);
    return _Card(
      semantics: 'Experiencia: más ${s.xpGained} XP. Nivel ${s.levelAfter}${s.leveledUp ? ', has subido de nivel' : ''}. '
          '${s.xpLines.map((l) => '${l.label} más ${l.xp}').join(', ')}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('EXPERIENCIA', style: PlobbyText.eb.copyWith(color: AppColors.textMuted)),
          const Spacer(),
          Text('+${(s.xpGained * e).round()} XP', style: PlobbyText.value.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text('Nivel $lvl', style: PlobbyText.cardTitle),
          if (s.leveledUp && lvl > s.levelBefore) ...[
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                child: Text('¡SUBES DE NIVEL!', style: PlobbyText.key.copyWith(color: AppColors.brandInk))),
          ],
          const Spacer(),
          Text('${ceil - xp} XP para el ${lvl + 1}', style: PlobbyText.help),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(
          value: frac, minHeight: 10, color: AppColors.brand, backgroundColor: AppColors.surfaceSunken)),
        const SizedBox(height: 10),
        for (var i = 0; i < s.xpLines.length; i++)
          Opacity(opacity: ((t * (s.xpLines.length + 1)) - i).clamp(0.0, 1.0), child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Expanded(child: Text(s.xpLines[i].label, style: PlobbyText.desc, maxLines: 2)),
              Text('+${s.xpLines[i].xp}', style: PlobbyText.value),
            ]),
          )),
      ]),
    );
  }
}

// ─────────────── Logros ───────────────

class _AchBlock extends StatelessWidget {
  const _AchBlock({required this.s, required this.t});
  final PostMatchSummary s;
  final double t;
  @override
  Widget build(BuildContext context) {
    final n = s.achievements.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(n == 1 ? 'LOGRO DESBLOQUEADO' : 'LOGROS DESBLOQUEADOS', style: PlobbyText.eb.copyWith(color: AppColors.textMuted))),
      for (var i = 0; i < n; i++) Padding(padding: const EdgeInsets.only(bottom: 10),
          child: _FlipCard(item: s.achievements[i], t: ((t * (n + 1.5)) - i).clamp(0.0, 1.0))),
    ]);
  }
}

/// Carta que se voltea: primero el reverso (candado), luego el logro. El lector de pantalla siempre lee el logro.
class _FlipCard extends StatelessWidget {
  const _FlipCard({required this.item, required this.t});
  final AchievementItem item;
  final double t;
  @override
  Widget build(BuildContext context) {
    final a = math.pi * (1 - Motion.spring.transform(t));
    final front = a <= math.pi / 2;
    final face = front
        ? _Card(child: Row(children: [
            AchievementBadge(item, size: 48),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: PlobbyText.cardTitle),
              const SizedBox(height: 2),
              Text(item.description, style: PlobbyText.help),
            ])),
            if (item.xp > 0) Text('+${item.xp} XP', style: PlobbyText.value.copyWith(fontWeight: FontWeight.w800)),
          ]))
        : Container(
            height: 72, alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rMd),
            child: const PlobbyIcon(PlobbyIcons.lock, size: 22, color: AppColors.brand),
          );
    return Semantics(
      label: 'Logro desbloqueado: ${item.title}. ${item.description}', excludeSemantics: true,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..setEntry(3, 2, .0012)..rotateY(front ? a : a - math.pi),
        child: face,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.semantics});
  final Widget child;
  final String? semantics;
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, border: Border.all(color: AppColors.border)),
      child: child,
    );
    return semantics == null ? box : Semantics(container: true, label: semantics, excludeSemantics: true, child: box);
  }
}
