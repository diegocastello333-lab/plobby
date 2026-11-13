import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../social/presentation/friends_screen.dart';
import '../application/gamification_providers.dart';
import '../domain/gamification_models.dart';
import 'gamification_widgets.dart';
import 'share_image_sheet.dart';

/// Elige un amigo y abre la comparativa.
Future<void> pickHeadToHead(BuildContext context) async {
  final r = await pickFriends(context, const FriendPick(title: 'Comparar con…', confirmLabel: 'Comparar'));
  if (r != null && r.isNotEmpty && context.mounted) context.push('/h2h/${r.first.id}');
}

/// HEAD TO HEAD: estadísticas generales de cada uno (todas sus partidas) y, aparte, sus enfrentamientos directos
/// (partidos en equipos contrarios). Nunca se mezclan: ganar mucho en general no es ganar el cara a cara.
class HeadToHeadScreen extends ConsumerWidget {
  const HeadToHeadScreen({super.key, required this.otherId});
  final String otherId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(headToHeadProvider(otherId));
    return Scaffold(body: SafeArea(bottom: false, child: Column(children: [
      PlobbyHeaderBar(title: 'Head to Head', onBack: () => context.pop(), trailing: async.valueOrNull == null ? null
          : IconSquareButton(icon: PlobbyIcons.share, tooltip: 'Compartir comparativa', onPressed: () => showShareImageSheet(context, ShareTarget.h2h(async.value!)))),
      Expanded(child: async.when(
        loading: () => ListView(padding: const EdgeInsets.all(20), children: const [LoadingBlock(height: 220), SizedBox(height: 16), LoadingBlock(height: 300)]),
        error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(
            message: e.toString().contains('not_friends') ? 'Solo puedes compararte con tus amigos.' : 'Revisa tu conexión e inténtalo de nuevo.',
            onRetry: () => ref.invalidate(headToHeadProvider(otherId)))),
        data: (d) => _Body(d: d),
      )),
    ])));
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.d});
  final H2HData d;
  @override
  Widget build(BuildContext context) {
    final v = d.verdict;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 48), children: [
      AppearOnce(index: 0, child: _Hero(d: d, v: v)),
      const SizedBox(height: 26),
      const SectionHeader(title: 'Estadísticas generales'),
      Text('Todas sus partidas confirmadas, no solo entre vosotros.', style: PlobbyText.help),
      const SizedBox(height: 12),
      AppearOnce(index: 1, child: SurfaceCard(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: Column(children: [
        Row(children: [
          Expanded(child: Text(d.me.player.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.cardTitle)),
          Expanded(child: Text(d.other.player.first, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.cardTitle)),
        ]),
        const SizedBox(height: 6),
        for (final s in d.stats) _StatRow(s),
        _StreakRow(d: d),
      ]))),
      if (d.me.monthly.any((m) => m.played > 0) || d.other.monthly.any((m) => m.played > 0)) ...[
        const SizedBox(height: 26),
        const SectionHeader(title: 'Evolución'),
        Text('% de victorias de los últimos 6 meses.', style: PlobbyText.help),
        const SizedBox(height: 12),
        AppearOnce(index: 2, child: SurfaceCard(child: _Evolution(d: d))),
      ],
      const SizedBox(height: 26),
      const SectionHeader(title: 'Enfrentamientos directos'),
      const SizedBox(height: 4),
      if (d.directTotal == 0)
        EmptyStateCard(icon: Icons.sports_tennis, title: 'Aún no os habéis enfrentado.', text: d.togetherTotal > 0
            ? 'Habéis jugado ${d.togetherTotal} ${d.togetherTotal == 1 ? 'partido' : 'partidos'} como pareja, pero nunca como rivales.'
            : 'Cuando juguéis en equipos contrarios, el historial aparecerá aquí.')
      else ...[
        Text('Último enfrentamiento: ${shortDate(d.lastAt!)}', style: PlobbyText.help),
        const SizedBox(height: 10),
        if (d.directTotal >= 2) Padding(padding: const EdgeInsets.only(bottom: 12), child: SurfaceCard(child: _Balance(d: d))),
        for (final (i, m) in d.matches.take(10).indexed) AppearOnce(index: 3 + i, child: _DirectTile(d: d, m: m)),
      ],
      if (d.togetherTotal > 0) ...[
        const SizedBox(height: 26),
        const SectionHeader(title: 'Como pareja'),
        SurfaceCard(child: Row(children: [
          const PlobbyIcon(PlobbyIcons.users, size: 20), const SizedBox(width: 12),
          Expanded(child: Text('${d.togetherTotal} ${d.togetherTotal == 1 ? 'partido juntos' : 'partidos juntos'} · ${d.togetherWins} '
              '${d.togetherWins == 1 ? 'victoria' : 'victorias'} (${(100 * d.togetherWins / d.togetherTotal).round()}%)', style: PlobbyText.value)),
        ])),
      ],
    ]);
  }
}

/// Cabecera: los dos jugadores enfrentados, el marcador del cara a cara y la conclusión.
class _Hero extends StatelessWidget {
  const _Hero({required this.d, required this.v});
  final H2HData d;
  final H2HVerdict v;
  @override
  Widget build(BuildContext context) {
    Widget side(PlayerCard c, bool leads) => Expanded(child: Column(children: [
          GAvatar(c.player, size: 76, ring: leads ? AppColors.brand : const Color(0x40F6F8F1), ringWidth: leads ? 3 : 2),
          const SizedBox(height: 10),
          Text(c.player.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.25, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.ink50)),
          if (c.elo != null) Text('ELO ${c.elo} · Nv. ${c.level}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, letterSpacing: 0, color: Color(0x99F6F8F1))),
        ]));
    return Semantics(container: true, label: '${d.me.player.name} contra ${d.other.player.name}. Cara a cara ${d.myWins} a ${d.theirWins}. ${v.title}.',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
        decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            side(d.me, v.leader == H2HLeader.me),
            Padding(padding: const EdgeInsets.only(top: 14), child: Column(children: [
              FittedBox(child: Text('${d.myWins}–${d.theirWins}', style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1, color: AppColors.ink50))),
              const SizedBox(height: 4),
              Text(d.directTotal == 1 ? '1 PARTIDO' : '${d.directTotal} PARTIDOS', style: PlobbyText.eb.copyWith(color: const Color(0x99F6F8F1))),
            ])),
            side(d.other, v.leader == H2HLeader.other),
          ]),
          const SizedBox(height: 16),
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: v.leader == H2HLeader.unknown ? const Color(0x14F6F8F1) : AppColors.brand, borderRadius: AppRadius.rMd),
            child: Column(children: [
              Text(v.title, textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: 0,
                  color: v.leader == H2HLeader.unknown ? AppColors.ink50 : AppColors.brandInk)),
              const SizedBox(height: 2),
              Text(v.detail, textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0,
                  color: v.leader == H2HLeader.unknown ? const Color(0xB3F6F8F1) : AppColors.brandInk.withValues(alpha: .8))),
            ]),
          ),
        ]),
      ));
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.s);
  final H2HStat s;
  @override
  Widget build(BuildContext context) {
    TextStyle num(bool lead) => TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2,
        color: lead ? AppColors.text : AppColors.textMuted);
    return Semantics(label: '${s.label}: ${s.mineText} contra ${s.theirsText}', excludeSemantics: true, child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(children: [
          SizedBox(width: 72, child: Text(s.mineText, style: num(s.leader == H2HLeader.me))),
          Expanded(child: Text(s.label, textAlign: TextAlign.center, style: PlobbyText.help.copyWith(fontWeight: FontWeight.w600))),
          SizedBox(width: 72, child: Text(s.theirsText, textAlign: TextAlign.right, style: num(s.leader == H2HLeader.other))),
        ]),
        const SizedBox(height: 6),
        VersusBar(share: s.myShare, leader: s.leader),
      ]),
    ));
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.d});
  final H2HData d;
  String _streak(int v) => v == 0 ? '—' : v > 0 ? '$v V' : '${-v} D';
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 8), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Racha ${_streak(d.me.currentStreak)}', style: PlobbyText.value), const SizedBox(height: 6), FormDots(d.me.form)])),
        Text('FORMA', style: PlobbyText.eb),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Racha ${_streak(d.other.currentStreak)}', style: PlobbyText.value), const SizedBox(height: 6), FormDots(d.other.form)])),
      ]));
}

/// Dos líneas (% de victorias por mes): tinta = yo, lima = el otro. Los meses sin partidos no se dibujan.
class _Evolution extends StatelessWidget {
  const _Evolution({required this.d});
  final H2HData d;
  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(height: 120, child: CustomPaint(size: Size.infinite, painter: _LinesPainter(d.me.monthly, d.other.monthly))),
        const SizedBox(height: 8),
        Row(children: [
          for (final m in d.me.monthly) Expanded(child: Text(monthName(m.month.month).substring(0, 3), textAlign: TextAlign.center, style: PlobbyText.help.copyWith(fontSize: 11))),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legend(AppColors.text, d.me.player.first), const SizedBox(width: 18), _legend(AppColors.brand, d.other.player.first, border: true),
        ]),
      ]);
  Widget _legend(Color c, String t, {bool border = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 4, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2), border: border ? Border.all(color: AppColors.text, width: .5) : null)),
        const SizedBox(width: 6), Text(t, style: PlobbyText.help),
      ]);
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.a, this.b);
  final List<MonthPoint> a, b;
  @override
  void paint(Canvas c, Size s) {
    final grid = Paint()..color = const Color(0x14171C19)..strokeWidth = 1;
    for (final y in [0.0, .5, 1.0]) { c.drawLine(Offset(0, s.height * y), Offset(s.width, s.height * y), grid); }
    void line(List<MonthPoint> pts, Color color) {
      final step = s.width / math.max(pts.length, 1);
      final p = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
      Offset? prev;
      for (final (i, m) in pts.indexed) {
        if (m.winRate == null) { prev = null; continue; }
        final o = Offset(step * i + step / 2, s.height - s.height * m.winRate! / 100);
        if (prev != null) c.drawLine(prev, o, p);
        c.drawCircle(o, 4, Paint()..color = color);
        prev = o;
      }
    }
    line(b, AppColors.brand);
    line(a, AppColors.text);
  }
  @override
  bool shouldRepaint(_LinesPainter o) => o.a != a || o.b != b;
}

/// Saldo acumulado del cara a cara (sube con mis victorias, baja con las suyas).
class _Balance extends StatelessWidget {
  const _Balance({required this.d});
  final H2HData d;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Historial del cara a cara', style: PlobbyText.cardTitle),
        const SizedBox(height: 4),
        Text('Sube con las victorias de ${d.me.player.first}, baja con las de ${d.other.player.first}.', style: PlobbyText.help),
        const SizedBox(height: 12),
        SizedBox(height: 70, child: CustomPaint(size: Size.infinite, painter: _BalancePainter(d.balance))),
      ]);
}

class _BalancePainter extends CustomPainter {
  _BalancePainter(this.values);
  final List<int> values;
  @override
  void paint(Canvas c, Size s) {
    final maxAbs = values.fold<int>(1, (a, v) => math.max(a, v.abs()));
    final mid = s.height / 2;
    c.drawLine(Offset(0, mid), Offset(s.width, mid), Paint()..color = const Color(0x22171C19)..strokeWidth = 1);
    final step = s.width / math.max(values.length, 1);
    for (final (i, v) in values.indexed) {
      final h = (s.height / 2 - 4) * v / maxAbs;
      final r = Rect.fromLTRB(step * i + step * .2, h >= 0 ? mid - h : mid, step * i + step * .8, h >= 0 ? mid : mid - h);
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), Paint()..color = v >= 0 ? AppColors.text : AppColors.brand);
    }
  }
  @override
  bool shouldRepaint(_BalancePainter o) => o.values != values;
}

class _DirectTile extends StatelessWidget {
  const _DirectTile({required this.d, required this.m});
  final H2HData d;
  final DirectMatch m;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SurfaceCard(
      onTap: () => context.push('/match/${m.matchId}'),
      child: Row(children: [
        Container(width: 6, height: 44, decoration: BoxDecoration(color: m.won ? AppColors.text : AppColors.brand, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Gana ${m.won ? d.me.player.first : d.other.player.first}', style: PlobbyText.cardTitle),
          const SizedBox(height: 2),
          Text([shortDate(m.playedAt), if (m.myPartner != null) 'con ${m.myPartner}', if (m.theirPartner != null) 'vs ${d.other.player.first} y ${m.theirPartner}'].join(' · '),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: PlobbyText.help),
        ])),
        const SizedBox(width: 10),
        Text(m.score, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
      ])));
}

