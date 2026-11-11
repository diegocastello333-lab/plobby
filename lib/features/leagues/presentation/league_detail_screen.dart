import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../matches/application/lifecycle_providers.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../../matches/presentation/match_widgets.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';

enum LeagueTab { rank, activity, matches, members }
enum RankSort { points, elo, pct, played }

/// Detalle de liga (prototipo `scLeague`): portada, ficha, «tu posición» y pestañas Clasificación · Actividad · Partidos · Miembros.
class LeagueDetailScreen extends ConsumerStatefulWidget {
  const LeagueDetailScreen({super.key, required this.leagueId, this.initialTab = LeagueTab.rank});
  final String leagueId; final LeagueTab initialTab;
  @override
  ConsumerState<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends ConsumerState<LeagueDetailScreen> {
  late LeagueTab _tab = widget.initialTab;
  RankSort _sort = RankSort.points;
  bool _all = false, _upcoming = true, _busy = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.leagueId;
    final detail = ref.watch(leagueDetailProvider(id));
    return Scaffold(
      body: detail.when(
        loading: () => const _Skeleton(),
        error: (e, _) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(tooltip: 'Volver', onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back))),
          const SizedBox(height: 20),
          ErrorStateCard(onRetry: () => ref.invalidate(leagueDetailProvider(id))),
        ]))),
        data: (l) {
          final standings = ref.watch(standingsProvider(id));
          final uid = ref.watch(currentUserIdProvider);
          final mine = standings.valueOrNull?.where((r) => r.userId == uid || r.userId == 'me').firstOrNull;
          return RefreshIndicator(
            onRefresh: () async { ref.invalidate(leagueDetailProvider(id)); ref.invalidate(standingsProvider(id)); ref.invalidate(leagueMatchesProvider(id)); },
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _Header(league: l, onMenu: () => _menu(l))),
              SliverPadding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), sliver: SliverList.list(children: [
                _InfoGrid(league: l, members: standings.valueOrNull?.length),
                if (l.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text(l.description, style: const TextStyle(height: 1.45))),
                const SizedBox(height: 16),
                if (l.isMember) _Performance(row: mine, total: standings.valueOrNull?.length ?? 0) else _JoinCta(league: l, busy: _busy, onJoin: () => _join(l)),
                const SizedBox(height: 16),
                Container(decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd), padding: const EdgeInsets.all(2),
                  child: SlidingTabs(labels: const ['Clasificación', 'Actividad', 'Partidos', 'Miembros'], index: _tab.index, onChanged: (i) => setState(() => _tab = LeagueTab.values[i]))),
                const SizedBox(height: 12),
                switch (_tab) {
                  LeagueTab.rank => _rank(standings, uid),
                  LeagueTab.activity => _activity(l),
                  LeagueTab.matches => _matches(l),
                  LeagueTab.members => _members(l, standings),
                },
                const SizedBox(height: 120),
              ])),
            ]),
          );
        },
      ),
    );
  }

  // ── Clasificación ──
  Widget _rank(AsyncValue<List<StandingRow>> s, String uid) => s.when(
        loading: () => const Column(children: [LoadingBlock(height: 56), SizedBox(height: 8), LoadingBlock(height: 56), SizedBox(height: 8), LoadingBlock(height: 56)]),
        error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(standingsProvider(widget.leagueId))),
        data: (rows) {
          if (rows.every((r) => r.played == 0)) {
            return EmptyStateCard(icon: Icons.leaderboard_outlined, title: 'La clasificación empieza con el primer partido',
                text: 'Cuando se confirme un resultado de liga, los puntos aparecerán aquí.', primary: 'Registrar resultado',
                onPrimary: () => context.push('/match/new?type=league&leagueId=${widget.leagueId}&result=1'));
          }
          final sorted = sortStandings(rows, _sort);
          final meIdx = sorted.indexWhere((r) => r.userId == uid || r.userId == 'me');
          var show = [for (var i = 0; i < sorted.length; i++) i];
          var cut = false;
          if (!_all && sorted.length > 10) { show = [0, 1, 2, 3, 4, 5, 6, 7, if (meIdx >= 8) meIdx]; cut = true; }
          final metric = switch (_sort) { RankSort.elo => 'ELO', RankSort.pct => '%V', RankSort.played => 'PJ', RankSort.points => 'PTS' };
          return Column(children: [
            Wrap(spacing: 8, children: [
              for (final x in const [(RankSort.points, 'Puntos'), (RankSort.elo, 'ELO'), (RankSort.pct, '% victorias'), (RankSort.played, 'Partidos')])
                ChoiceChip(label: Text(x.$2), selected: _sort == x.$1, onSelected: (_) => setState(() => _sort = x.$1)),
            ]),
            const SizedBox(height: 8),
            Row(children: [const SizedBox(width: 34), const Expanded(child: Text('JUGADOR', style: _eb)), SizedBox(width: 44, child: Text(metric, textAlign: TextAlign.right, style: _eb))]),
            for (var k = 0; k < show.length; k++) ...[
              if (cut && k == 8) const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('···', style: TextStyle(color: AppColors.textMuted))),
              _RankRow(pos: show[k] + 1, row: sorted[show[k]], me: show[k] == meIdx, metric: switch (_sort) {
                RankSort.elo => '${sorted[show[k]].elo}', RankSort.pct => '${sorted[show[k]].winPct}%', RankSort.played => '${sorted[show[k]].played}', RankSort.points => '${sorted[show[k]].points}' }),
            ],
            if (cut) TextButton(onPressed: () => setState(() => _all = true), child: Text('Ver clasificación completa (${sorted.length})')),
            const SizedBox(height: 6),
            const Text('Solo cuentan partidos de liga confirmados por los dos capitanes.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]);
        },
      );

  // ── Actividad: resultados confirmados y disputas recientes de la liga ──
  Widget _activity(LeagueDetail l) {
    if (!l.isMember) return const EmptyStateCard(icon: Icons.lock_outline, title: 'Actividad solo para miembros', text: 'Únete a la liga para ver sus resultados y novedades.');
    return ref.watch(leagueMatchesProvider(l.id)).when(
      loading: () => const LoadingBlock(height: 120),
      error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(leagueMatchesProvider(l.id))),
      data: (ms) {
        final items = ms.where((m) => m.status == MatchStatus.confirmed || m.status == MatchStatus.disputed).toList();
        if (items.isEmpty) return const EmptyStateCard(icon: Icons.bolt_outlined, title: 'Aún no hay actividad', text: 'Los resultados confirmados de la liga aparecerán aquí.');
        return Column(children: [for (final m in items.take(20)) _ActivityItem(match: m)]);
      },
    );
  }

  // ── Partidos ──
  Widget _matches(LeagueDetail l) {
    if (!l.isMember) return const EmptyStateCard(icon: Icons.lock_outline, title: 'Partidos solo para miembros', text: 'Únete a la liga para ver y registrar partidos.');
    return ref.watch(leagueMatchesProvider(l.id)).when(
      loading: () => const Column(children: [MatchCardSkeleton(), SizedBox(height: 12), MatchCardSkeleton()]),
      error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(leagueMatchesProvider(l.id))),
      data: (ms) {
        final upcoming = ms.where((m) => m.status.isUpcoming).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
        final done = ms.where((m) => m.status == MatchStatus.confirmed).toList();
        final list = _upcoming ? upcoming : done;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ChoiceChip(label: Text('Próximos (${upcoming.length})'), selected: _upcoming, onSelected: (_) => setState(() => _upcoming = true)),
            const SizedBox(width: 8),
            ChoiceChip(label: Text('Jugados (${done.length})'), selected: !_upcoming, onSelected: (_) => setState(() => _upcoming = false)),
          ]),
          const SizedBox(height: 12),
          if (list.isEmpty)
            EmptyStateCard(icon: Icons.sports_tennis, title: _upcoming ? 'No hay partidos programados' : 'Todavía no se ha jugado ningún partido',
                text: _upcoming ? 'Organiza el primero con otros miembros de la liga.' : 'Registra un resultado para empezar la clasificación.',
                primary: _upcoming ? 'Crear partido de liga' : 'Registrar resultado',
                onPrimary: () => context.push('/match/new?type=league&leagueId=${l.id}${_upcoming ? '' : '&result=1'}'))
          else
            for (final m in list) _LeagueMatchTile(match: m),
          if (list.isNotEmpty) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(onPressed: () => context.push('/match/new?type=league&leagueId=${l.id}&result=1'), icon: const Icon(Icons.add), label: const Text('Registrar resultado')),
          ],
        ]);
      },
    );
  }

  // ── Miembros ──
  Widget _members(LeagueDetail l, AsyncValue<List<StandingRow>> s) => s.when(
        loading: () => const LoadingBlock(height: 160),
        error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(standingsProvider(l.id))),
        data: (rows) {
          final list = [...rows]..sort((a, b) => a.role.index != b.role.index ? a.role.index - b.role.index : a.name.compareTo(b.name));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${list.length} de ${l.maxPlayers} jugadores', style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            if (list.length <= 1)
              EmptyStateCard(icon: Icons.group_add_outlined, title: 'Solo estás tú', text: 'Invita a tus amigos o comparte el código para que se unan.',
                  primary: l.canManage ? 'Invitar amigos' : null, onPrimary: () => context.push('/leagues/${l.id}/manage')),
            for (final r in list)
              ListTile(contentPadding: EdgeInsets.zero, onTap: () => context.push('/player/${r.userId}'),
                  leading: LeagueAvatar(name: r.name, avatarUrl: r.avatarUrl, avatarId: r.avatarId),
                  title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('ELO ${r.elo}'),
                  trailing: r.role == LeagueRole.player ? null : LeagueChip(r.role.label, tone: ChipTone.dark)),
            if (l.canManage && list.length > 1) OutlinedButton.icon(onPressed: () => context.push('/leagues/${l.id}/manage'), icon: const Icon(Icons.person_add_alt), label: const Text('Invitar jugadores')),
          ]);
        },
      );

  Future<void> _join(LeagueDetail l) async {
    if (l.visibility == LeagueVisibility.private) { context.push('/leagues/join'); return; }
    setState(() => _busy = true);
    try {
      final r = await ref.read(leagueActionsProvider).join(l.id);
      if (mounted) showPlobbySnack(context, r == JoinOutcome.requested ? 'Solicitud enviada al organizador.' : 'Ya formas parte de ${l.name}');
    } on LeagueException catch (e) { if (mounted) showPlobbySnack(context, e.message, error: true); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _menu(LeagueDetail l) async {
    final code = l.isMember ? await ref.read(inviteCodeProvider(l.id).future).catchError((_) => null) : null;
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (l.canManage) ListTile(leading: const Icon(Icons.tune), title: const Text('Gestionar liga'), onTap: () { Navigator.pop(c); context.push('/leagues/${l.id}/manage'); }),
      if (code != null) ListTile(leading: const Icon(Icons.copy), title: const Text('Copiar código de invitación'), subtitle: Text(code), onTap: () {
        Clipboard.setData(ClipboardData(text: code)); Navigator.pop(c); showPlobbySnack(context, 'Código copiado'); }),
      if (l.isMember && l.status != LeagueStatus.ended) ListTile(leading: const Icon(Icons.add_circle_outline), title: const Text('Crear partido de liga'),
          onTap: () { Navigator.pop(c); context.push('/match/new?type=league&leagueId=${l.id}'); }),
      if (l.isMember && l.myRole != LeagueRole.organizer) ListTile(leading: const Icon(Icons.logout, color: AppColors.danger), title: const Text('Salir de la liga', style: TextStyle(color: AppColors.danger)),
          onTap: () async { Navigator.pop(c); await _leave(l); }),
      if (!l.isMember) ListTile(leading: const Icon(Icons.info_outline), title: Text(l.visibility.description)),
    ])));
  }

  Future<void> _leave(LeagueDetail l) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('¿Salir de la liga?'), content: const Text('Tus partidos jugados se mantienen, pero dejarás de aparecer en la clasificación.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir'))]));
    if (ok != true) return;
    try { await ref.read(leagueActionsProvider).leave(l.id); if (mounted) context.go('/leagues'); }
    on LeagueException catch (e) { if (mounted) showPlobbySnack(context, e.message, error: true); }
  }
}

const _eb = TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: AppColors.textMuted);

/// Orden de la clasificación según el selector (puro, testeable). El orden por puntos respeta el `rank` del servidor.
List<StandingRow> sortStandings(List<StandingRow> rows, RankSort s) {
  final l = [...rows];
  int by(int Function(StandingRow) f, StandingRow a, StandingRow b) => f(b) - f(a);
  l.sort((a, b) => switch (s) {
        RankSort.points => a.rank != b.rank ? a.rank - b.rank : a.name.compareTo(b.name),
        RankSort.elo => by((r) => r.elo, a, b),
        RankSort.pct => by((r) => r.winPct, a, b) != 0 ? by((r) => r.winPct, a, b) : by((r) => r.played, a, b),
        RankSort.played => by((r) => r.played, a, b),
      });
  return l;
}

class _Header extends StatelessWidget {
  const _Header({required this.league, required this.onMenu});
  final LeagueDetail league; final VoidCallback onMenu;
  @override
  Widget build(BuildContext context) {
    final l = league, top = MediaQuery.paddingOf(context).top;
    Widget glass(IconData i, String tip, VoidCallback f) => Material(color: const Color(0x33FFFFFF), shape: const CircleBorder(), child: IconButton(tooltip: tip, onPressed: f, icon: Icon(i, color: Colors.white)));
    return SizedBox(height: 200 + top, child: Stack(children: [
      Positioned.fill(child: LeagueCover(cover: l.cover, height: 200 + top, radius: 0)),
      Positioned(left: 12, right: 12, top: top + 6, child: Row(children: [
        glass(Icons.arrow_back, 'Volver', () => context.canPop() ? context.pop() : context.go('/leagues')), const Spacer(), glass(Icons.more_horiz, 'Opciones de la liga', onMenu)])),
      Positioned(left: 20, right: 20, bottom: 18, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          LeagueChip(l.visibility.label, icon: visibilityIcon(l.visibility), tone: ChipTone.glass),
          LeagueChip('Temporada ${l.season}', tone: ChipTone.glass),
          if (l.status == LeagueStatus.ended) const LeagueChip('Cerrada', tone: ChipTone.lime),
          if (l.status == LeagueStatus.open) const LeagueChip('Inscripción abierta', tone: ChipTone.lime),
        ]),
        const SizedBox(height: 8),
        Text(l.name, style: const TextStyle(fontFamily: 'Unbounded', fontSize: 24, height: 1.1, fontWeight: FontWeight.w700, color: Colors.white)),
      ])),
    ]));
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.league, this.members});
  final LeagueDetail league; final int? members;
  @override
  Widget build(BuildContext context) {
    final l = league;
    Widget cell(IconData i, String k, String v, [Widget? extra]) => Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(i, size: 13, color: AppColors.textMuted), const SizedBox(width: 4), Text(k, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))]),
          const SizedBox(height: 2),
          Row(children: [Flexible(child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))), if (extra != null) ...[const SizedBox(width: 6), extra]]),
        ])));
    return Column(children: [
      Row(children: [
        cell(Icons.place_outlined, 'Ubicación', l.location.isEmpty ? '—' : l.location),
        cell(Icons.apartment_outlined, 'Organiza', l.organizerName.isEmpty ? '—' : l.organizerName, l.myRole?.isManager == true ? LeagueChip(l.myRole!.label, tone: ChipTone.dark) : null),
      ]),
      Row(children: [
        cell(Icons.group_outlined, 'Jugadores', members == null ? '—' : '$members jugadores'),
        cell(Icons.calendar_today_outlined, 'Temporada', '${fmtDay(l.startsOn)} – ${fmtDay(l.endsOn)}'),
      ]),
    ]);
  }
}

class _Performance extends StatelessWidget {
  const _Performance({required this.row, required this.total});
  final StandingRow? row; final int total;
  @override
  Widget build(BuildContext context) {
    final r = row;
    Widget cell(String v, String l) => Expanded(child: Column(children: [
          Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          Text(l, style: const TextStyle(fontSize: 11, color: Color(0xB3FFFFFF))),
        ]));
    return Container(
      padding: const EdgeInsets.all(16), decoration: AppCardStylesDark.block,
      child: Column(children: [
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('TU POSICIÓN', style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: Color(0xB3FFFFFF))),
            Text(r == null ? '—' : '#${r.rank}', style: const TextStyle(fontFamily: 'Unbounded', fontSize: 40, fontWeight: FontWeight.w700, color: AppColors.lime300)),
          ]),
          const Spacer(),
          Text(total == 0 ? '' : 'de $total', style: const TextStyle(color: Color(0xB3FFFFFF))),
        ]),
        const SizedBox(height: 10),
        Row(children: [cell('${r?.points ?? 0}', 'Puntos'), cell('${r?.played ?? 0}', 'Jugados'), cell('${r?.winPct ?? 0}%', 'Victorias')]),
        const SizedBox(height: 10),
        Row(children: [cell('${r?.wins ?? 0}', 'Ganados'), cell('${r?.losses ?? 0}', 'Perdidos'), cell(r == null || r.bonus == 0 ? '—' : '+${r.bonus}', 'Bonus')]),
      ]),
    );
  }
}

class AppCardStylesDark { static const block = BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg); }

class _JoinCta extends StatelessWidget {
  const _JoinCta({required this.league, required this.busy, required this.onJoin});
  final LeagueDetail league; final bool busy; final VoidCallback onJoin;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16), decoration: AppCardStylesDark.block,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(league.visibility == LeagueVisibility.club ? 'Liga de club' : '¿Te apuntas?', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16)),
        const SizedBox(height: 4),
        Text(league.visibility.description, style: const TextStyle(color: Color(0xB3FFFFFF))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: busy || league.status == LeagueStatus.ended ? null : onJoin,
            child: Text(league.visibility == LeagueVisibility.club ? 'Solicitar acceso' : league.visibility == LeagueVisibility.private ? 'Unirme con código' : 'Unirme a la liga'))),
      ]));
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.pos, required this.row, required this.me, required this.metric});
  final int pos; final StandingRow row; final bool me; final String metric;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: me ? AppColors.brandSoft : AppColors.surface, borderRadius: AppRadius.rMd, border: me ? Border.all(color: AppColors.brand, width: 1.5) : null),
      child: Semantics(label: 'Puesto $pos, ${row.name}, $metric', child: Row(children: [
        SizedBox(width: 24, child: Text('$pos', style: TextStyle(fontWeight: FontWeight.w800, color: pos <= 3 ? AppColors.text : AppColors.textMuted))),
        LeagueAvatar(name: row.name, avatarUrl: row.avatarUrl, avatarId: row.avatarId, size: 34, highlight: me),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(me ? '${row.name} (tú)' : row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${row.played} PJ · ${row.wins} G · ${row.losses} P', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ])),
        SizedBox(width: 44, child: Text(metric, textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w700))),
      ])));
}

class _LeagueMatchTile extends StatelessWidget {
  const _LeagueMatchTile({required this.match});
  final LifecycleMatch match;
  @override
  Widget build(BuildContext context) {
    final m = match;
    String names(int t) => m.team(t).map((p) => p.name.split(' ').first).join(' y ');
    return Card(margin: const EdgeInsets.only(bottom: 10), child: InkWell(
      borderRadius: AppRadius.rMd, onTap: () => context.push(m.status == MatchStatus.confirmed ? '/match/${m.id}/final' : '/match/${m.id}'),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [StatusChip(status: m.status), const Spacer(), Text(fmtDay(m.scheduledAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted))]),
        const SizedBox(height: 10),
        Text('${names(1)}  vs  ${names(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (m.sets.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.sets.map((s) => '${s.a}-${s.b}').join('  '), style: const TextStyle(fontFamily: 'Unbounded', fontSize: 13))),
        if (m.club.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.club, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
      ])),
    ));
  }
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({required this.match});
  final LifecycleMatch match;
  @override
  Widget build(BuildContext context) {
    final m = match, w = m.winnerTeam;
    String names(int t) => m.team(t).map((p) => p.name.split(' ').first).join(' y ');
    final text = m.status == MatchStatus.disputed
        ? 'Resultado en disputa entre ${names(1)} y ${names(2)}'
        : '${names(w ?? 1)} ganaron a ${names(w == 1 ? 2 : 1)} · ${m.sets.map((s) => '${s.a}-${s.b}').join(' ')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: m.status == MatchStatus.disputed ? AppColors.warningSoft : AppColors.brandSoft,
          child: Icon(m.status == MatchStatus.disputed ? Icons.report_gmailerrorred : Icons.emoji_events_outlined, color: m.status == MatchStatus.disputed ? AppColors.warning : AppColors.brandText)),
      title: Text(text), subtitle: Text(fmtDay(m.scheduledAt)),
      onTap: () => context.push('/match/${m.id}'),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => ListView(padding: EdgeInsets.zero, children: const [
        LoadingBlock(height: 240, radius: 0),
        Padding(padding: EdgeInsets.all(20), child: Column(children: [LoadingBlock(height: 80), SizedBox(height: 14), LoadingBlock(height: 150), SizedBox(height: 14), LoadingBlock(height: 220)])),
      ]);
}
