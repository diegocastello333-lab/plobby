import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/gamification_providers.dart';
import '../domain/gamification_models.dart';
import 'gamification_widgets.dart';
import 'share_image_sheet.dart';

/// FRIENDS RANKING: tú y tus amigos, por victorias, % de victorias o actividad, en la semana, el mes, el año o el
/// histórico. Solo cuentan partidos confirmados; las temporadas semanales y mensuales cerradas se ven congeladas.
class FriendsRankingScreen extends ConsumerStatefulWidget {
  const FriendsRankingScreen({super.key});
  @override
  ConsumerState<FriendsRankingScreen> createState() => _FriendsRankingScreenState();
}

class _FriendsRankingScreenState extends ConsumerState<FriendsRankingScreen> {
  var _period = RankPeriod.week, _metric = RankMetric.wins, _offset = 0;
  final _scroll = ScrollController();
  final _meKey = GlobalKey();
  bool _meHidden = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkMe);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// ¿Está mi fila fuera de la vista? Entonces se fija abajo (tarjeta «Tú»), sin tapar nada cuando sí se ve.
  void _checkMe() {
    final box = _meKey.currentContext?.findRenderObject() as RenderBox?, list = context.findRenderObject() as RenderBox?;
    bool hidden = false;
    if (box != null && box.attached && list != null) {
      final y = box.localToGlobal(Offset.zero).dy, h = MediaQuery.sizeOf(context).height;
      hidden = y > h - 40 - MediaQuery.paddingOf(context).bottom || y + box.size.height < 140;
    }
    if (hidden != _meHidden && mounted) setState(() => _meHidden = hidden);
  }

  String _periodTitle(RankingData r) => switch (r.period) {
        RankPeriod.week => r.offset == 0 ? 'Esta semana' : 'Semana del ${r.start.day} ${monthName(r.start.month).substring(0, 3)}',
        RankPeriod.month => r.offset == 0 ? 'Este mes' : '${capitalize(monthName(r.start.month))} ${r.start.year}',
        RankPeriod.year => '${r.start.year}',
        RankPeriod.all => 'Desde siempre',
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rankingProvider((_period, _offset)));
    final r = async.valueOrNull;
    return Scaffold(body: SafeArea(bottom: false, child: Column(children: [
      PlobbyHeaderBar(title: 'Ranking de amigos', onBack: () => context.pop(), trailing: r == null || r.me == null || !r.anyActivity ? null
          : IconSquareButton(icon: PlobbyIcons.share, tooltip: 'Compartir mi posición', onPressed: () => showShareImageSheet(context, ShareTarget.ranking(r, _metric)))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 0), child: SlidingTabs(
          labels: [for (final p in RankPeriod.values) p.label], index: _period.index, onChanged: (i) => setState(() { _period = RankPeriod.values[i]; _offset = 0; }))),
      SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(20, 10, 20, 6), children: [
        for (final m in RankMetric.values) Padding(padding: const EdgeInsets.only(right: 8),
            child: PlobbyFilterChip(label: m.label, selected: _metric == m, onTap: () => setState(() => _metric = m))),
      ])),
      Expanded(child: RefreshIndicator(
        color: AppColors.text,
        onRefresh: () async { ref.invalidate(rankingProvider((_period, _offset))); await ref.read(rankingProvider((_period, _offset)).future); },
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => ListView(padding: const EdgeInsets.all(20), children: const [LoadingBlock(height: 210), SizedBox(height: 14), LoadingBlock(height: 280)]),
          error: (e, __) => ListView(padding: const EdgeInsets.all(20), children: [ErrorStateCard(error: e, onRetry: () => ref.invalidate(rankingProvider((_period, _offset))))]),
          data: (r) {
            WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _checkMe(); });
            final mine = r.ranked(_metric).where((x) => x.player.id == r.meId).firstOrNull;
            return Stack(children: [
              _content(r),
              // fila propia fija abajo cuando no se ve (aparece y se va con un deslizamiento corto)
              if (mine != null) Positioned(left: 20, right: 20, bottom: 12 + MediaQuery.paddingOf(context).bottom, child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.normal), switchInCurve: Motion.enter, switchOutCurve: Motion.exit,
                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(a), child: c)),
                // solo existe mientras mi fila no se ve (así el lector de pantalla no la lee dos veces)
                child: !_meHidden ? const SizedBox.shrink(key: ValueKey('none')) : DecoratedBox(key: const ValueKey('me'),
                    decoration: BoxDecoration(borderRadius: AppRadius.rMd, boxShadow: AppShadows.pop),
                    child: _RankTile(row: mine, metric: _metric, me: true, move: r.movement(mine.player.id, _metric), margin: false)),
              )),
            ]);
          },
        ),
      )),
    ])));
  }

  Widget _content(RankingData r) {
    final list = r.ranked(_metric), below = r.belowMinimum(_metric);
    final canGoBack = _period == RankPeriod.week || _period == RankPeriod.month;
    return ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(20, 6, 20, 96), children: [
      // navegación entre temporadas (semanales y mensuales)
      Row(children: [
        if (canGoBack) IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Temporada anterior', size: 36, onPressed: () => setState(() => _offset--)),
        Expanded(child: Column(children: [
          Text(_periodTitle(r), textAlign: TextAlign.center, style: PlobbyText.cardTitle),
          if (r.closed) Text('Temporada cerrada', textAlign: TextAlign.center, style: PlobbyText.help)
          else if (_metric == RankMetric.rate) Text('Mínimo ${r.minMatches} partidos para entrar', textAlign: TextAlign.center, style: PlobbyText.help),
        ])),
        if (canGoBack) Opacity(opacity: _offset < 0 ? 1 : .3, child: IconSquareButton(icon: PlobbyIcons.chev, tooltip: 'Temporada siguiente', size: 36,
            onPressed: _offset < 0 ? () => setState(() => _offset++) : () {})),
      ]),
      const SizedBox(height: 14),
      if (r.rows.length <= 1)
        EmptyStateCard(icon: Icons.groups_2_outlined, title: 'Aún no tienes amigos con los que competir.', text: 'Añade amigos para comparar vuestros resultados.',
            primary: 'Buscar amigos', onPrimary: () => context.push('/friends/add'))
      else if (!r.anyActivity)
        EmptyStateCard(icon: Icons.sports_tennis, title: 'Nadie ha jugado en este periodo.', text: 'Los partidos confirmados suman aquí automáticamente.')
      else ...[
        if (r.closed && list.isNotEmpty && list.first.pos(_metric) == 1) _ChampionBanner(row: list.first, metric: _metric),
        if (list.length >= 2) AnimatedSwitcher(duration: Motion.normal, child: _Podium(key: ValueKey('$_period$_offset$_metric'), rows: list.take(3).toList(), metric: _metric, meId: r.meId)),
        const SizedBox(height: 14),
        for (final (i, row) in list.indexed) AppearOnce(key: ValueKey('${row.player.id}$_period$_offset$_metric'), index: i,
            // cada fila sale de su puesto anterior (temporada previa) y se desliza al actual
            child: _FromPrevious(key: ValueKey('mv${row.player.id}$_period$_offset$_metric'), move: r.movement(row.player.id, _metric) ?? 0,
                child: KeyedSubtree(key: row.player.id == r.meId ? _meKey : null,
                    child: _RankTile(row: row, metric: _metric, me: row.player.id == r.meId, move: r.movement(row.player.id, _metric))))),
        if (below.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('POR DEBAJO DEL MÍNIMO (${r.minMatches} PARTIDOS)', style: PlobbyText.eb),
          const SizedBox(height: 8),
          for (final row in below) _RankTile(row: row, metric: _metric, me: row.player.id == r.meId, move: null, unranked: true),
        ],
        const SizedBox(height: 16),
        Text(switch (_metric) {
          RankMetric.wins => 'Más victorias primero. Empate: mejor % de victorias.',
          RankMetric.rate => 'Mejor % de victorias primero. Empate: más victorias.',
          RankMetric.activity => 'Más partidos primero. Empate: más victorias.',
        }, textAlign: TextAlign.center, style: PlobbyText.help),
      ],
    ]);
  }
}

String _main(RankRow r, RankMetric m) => switch (m) { RankMetric.wins => '${r.wins}', RankMetric.rate => '${r.winRate}%', RankMetric.activity => '${r.played}' };
String _unit(RankRow r, RankMetric m) => switch (m) {
      RankMetric.wins => r.wins == 1 ? 'victoria' : 'victorias', RankMetric.rate => 'victorias', RankMetric.activity => r.played == 1 ? 'partido' : 'partidos' };

class _ChampionBanner extends StatelessWidget {
  const _ChampionBanner({required this.row, required this.metric});
  final RankRow row;
  final RankMetric metric;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Container(
        padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.brand, borderRadius: AppRadius.rMd),
        child: Row(children: [
          const PlobbyIcon(PlobbyIcons.trophy, size: 22, color: AppColors.brandInk), const SizedBox(width: 10),
          Expanded(child: Text('Ganador de la temporada: ${row.player.name}', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.brandInk))),
        ]),
      ));
}

/// Podio: 2.º — 1.º — 3.º, el primero más alto y con aro lima.
class _Podium extends StatelessWidget {
  const _Podium({super.key, required this.rows, required this.metric, required this.meId});
  final List<RankRow> rows;
  final RankMetric metric;
  final String meId;
  @override
  Widget build(BuildContext context) {
    Widget step(RankRow r, double h) {
      final first = r.pos(metric) == 1;
      return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (first) const PlobbyIcon(PlobbyIcons.trophy, size: 20),
        const SizedBox(height: 6),
        GAvatar(r.player, size: first ? 72 : 58, ring: first ? AppColors.brand : (r.player.id == meId ? AppColors.text : null), ringWidth: 3),
        const SizedBox(height: 8),
        Text(r.player.id == meId ? 'Tú' : r.player.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.cardTitle.copyWith(fontSize: 13.5)),
        Text('${_main(r, metric)} ${metric == RankMetric.rate ? '' : _unit(r, metric)}'.trim(), maxLines: 1, style: PlobbyText.help),
        const SizedBox(height: 8),
        _Rise(order: first ? 2 : (r.pos(metric) == 2 ? 1 : 0), child: Container(height: h, decoration: BoxDecoration(color: first ? AppColors.inverse : AppColors.surfaceSunken,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
            alignment: Alignment.center, child: Text('${r.pos(metric)}', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 22,
                fontWeight: FontWeight.w700, letterSpacing: 0, color: first ? AppColors.brand : AppColors.text)))),
      ]));
    }
    final order = [if (rows.length > 1) (rows[1], 64.0), (rows[0], 92.0), if (rows.length > 2) (rows[2], 48.0)];
    return Semantics(container: true, label: 'Podio: ${rows.map((r) => '${r.pos(metric)}º ${r.player.name}').join(', ')}', excludeSemantics: true,
        // 252 con texto normal; crece con Dynamic Type (nombres y victorias bajo cada avatar).
        child: SizedBox(height: 252 + 44 * (MediaQuery.textScalerOf(context).scale(12) / 12 - 1).clamp(0.0, 2.0), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (r, h) in order) ...[step(r, h), if (r != order.last.$1) const SizedBox(width: 10)],
        ])));
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.row, required this.metric, required this.me, required this.move, this.unranked = false, this.margin = true});
  final RankRow row;
  final RankMetric metric;
  final bool me, unranked, margin;
  final int? move;
  @override
  Widget build(BuildContext context) {
    final pos = row.pos(metric);
    return Semantics(container: true, label: '${unranked ? 'Sin clasificar' : 'Puesto $pos'}: ${row.player.name}, ${_main(row, metric)} ${_unit(row, metric)}'
        '${move == null || move == 0 ? '' : move! > 0 ? ', sube $move' : ', baja ${-move!}'}', excludeSemantics: true,
      child: Container(
        margin: EdgeInsets.only(bottom: margin ? 8 : 0), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: me ? (margin ? const Color(0x33D2F548) : AppColors.lime100) : AppColors.surface, borderRadius: AppRadius.rMd,
            border: Border.all(color: me ? AppColors.text : AppColors.border, width: me ? 1.5 : 1)),
        child: Row(children: [
          SizedBox(width: 30, child: Text(unranked ? '–' : '$pos', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTypography.displayFamily,
              fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0, color: unranked ? AppColors.textMuted : AppColors.text))),
          const SizedBox(width: 8),
          GestureDetector(onTap: me ? null : () => context.push('/player/${row.player.id}'), child: GAvatar(row.player, size: 40)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(me ? '${row.player.name} (tú)' : row.player.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.cardTitle.copyWith(fontSize: 14)),
            Text('${row.wins} V · ${row.losses} D · ${row.played == 0 ? '—' : '${row.winRate}%'} · Nv. ${row.level}', maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.help),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_main(row, metric), style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            _Move(move),
          ]),
        ]),
      ));
  }
}

class _Move extends StatelessWidget {
  const _Move(this.move);
  final int? move;
  @override
  Widget build(BuildContext context) {
    if (move == null || move == 0) return Text(move == 0 ? '=' : '', style: PlobbyText.help.copyWith(fontSize: 11));
    final up = move! > 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      PlobbyIcon(up ? PlobbyIcons.arrup : PlobbyIcons.arrdn, size: 12, color: up ? AppColors.success : AppColors.danger),
      Text('${move!.abs()}', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0,
          color: up ? AppColors.success : AppColors.danger)),
    ]);
  }
}

/// Desliza la fila desde su puesto en la temporada anterior ([move] > 0 = ha subido: viene de más abajo).
/// Una vez al abrir cada clasificación; con «reducir movimiento» ya está en su sitio.
class _FromPrevious extends StatelessWidget {
  const _FromPrevious({super.key, required this.move, required this.child});
  final int move;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (move == 0 || Motion.reduced(context)) return TweenAnimationBuilder<double>(tween: Tween(begin: 1, end: 1), duration: Motion.fast, builder: (_, __, c) => c!, child: child);
    final rowH = 62 * MediaQuery.textScalerOf(context).scale(14) / 14 + 8;   // alto aproximado de una fila
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: Motion.celebration, curve: Motion.springSoft,
      builder: (_, v, c) => Transform.translate(offset: Offset(0, move.clamp(-6, 6) * rowH * (1 - v)), child: c),
      child: child,
    );
  }
}

/// Escalón del podio que crece desde abajo; 3.º, luego 2.º y por último 1.º.
class _Rise extends StatelessWidget {
  const _Rise({required this.order, required this.child});
  final int order;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return TweenAnimationBuilder<double>(tween: Tween(begin: 1, end: 1), duration: Motion.fast, builder: (_, __, c) => c!, child: child);
    final total = Motion.emphasis + Motion.fast * order, start = (Motion.fast * order).inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: total,
      builder: (_, v, c) {
        final t = Motion.springBounce.transform(((v - start) / (1 - start)).clamp(0.0, 1.0));
        // escala desde la base: el escalón crece sin mover los avatares ni lo de abajo
        return Transform.scale(scaleX: 1, scaleY: t.clamp(0.0, 1.1), alignment: Alignment.bottomCenter, child: c);
      },
      child: child,
    );
  }
}
