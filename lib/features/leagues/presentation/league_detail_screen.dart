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
import '../../matches/application/lifecycle_providers.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../../matches/presentation/match_widgets.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';

enum LeagueTab { rank, activity, matches, members }
enum RankSort { points, elo, pct, played }

const _muted = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1.4, letterSpacing: 0, color: AppColors.textMuted);

/// Detalle de liga — `scLeague` del prototipo HTML: portada con título, ficha, «tu posición» y pestañas fijas
/// Clasificación · Actividad · Partidos · Miembros. Mismos datos y acciones que antes (RPC/RLS de ligas).
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
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final id = widget.leagueId;
    final detail = ref.watch(leagueDetailProvider(id));
    return Scaffold(
      body: detail.when(
        loading: () => const _Skeleton(),
        error: (e, _) => Column(children: [
          PlobbyHeaderBar(title: 'Liga', onBack: () => context.canPop() ? context.pop() : context.go('/leagues')),
          Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(leagueDetailProvider(id)))),
        ]),
        data: (l) {
          final standings = ref.watch(standingsProvider(id));
          final uid = ref.watch(currentUserIdProvider);
          final mine = standings.valueOrNull?.where((r) => r.userId == uid || r.userId == 'me').firstOrNull;
          return RefreshIndicator(
            color: AppColors.text,
            onRefresh: () async { ref.invalidate(leagueDetailProvider(id)); ref.invalidate(standingsProvider(id)); ref.invalidate(leagueMatchesProvider(id)); },
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _Header(league: l, onMenu: () => _menu(l))),
              SliverPadding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), sliver: SliverList.list(children: [
                _InfoGrid(league: l, members: standings.valueOrNull?.length, uid: uid),
                if (l.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text(l.description,
                    style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.5, letterSpacing: 0, color: AppColors.ink700))),
                const SizedBox(height: 18),
                if (l.isMember) _Performance(row: mine, total: standings.valueOrNull?.length ?? 0) else _JoinCta(league: l, busy: _busy, onJoin: () => _join(l)),
                const SizedBox(height: 6),
              ])),
              SliverPersistentHeader(pinned: true, delegate: _TabsDelegate(_tab.index, (i) => setState(() => _tab = LeagueTab.values[i]))),
              SliverPadding(padding: EdgeInsets.fromLTRB(20, 8, 20, 130 + MediaQuery.paddingOf(context).bottom), sliver: SliverToBoxAdapter(child: switch (_tab) {
                LeagueTab.rank => _rank(l, standings, uid),
                LeagueTab.activity => _activity(l),
                LeagueTab.matches => _matches(l),
                LeagueTab.members => _members(l, standings, uid),
              })),
            ]),
          );
        },
      ),
    );
  }

  // ── Clasificación (`.fcs` + `.card2.tbl`) ──
  Widget _rank(LeagueDetail l, AsyncValue<List<StandingRow>> s, String uid) => s.when(
        loading: () => const LoadingBlock(height: 320, radius: AppRadius.md),
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
          final r = l.rules;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SingleChildScrollView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, child: Row(children: [
              const Text('ORDENAR', style: PlobbyText.eb),
              const SizedBox(width: 10),
              for (final x in const [(RankSort.points, 'Puntos'), (RankSort.elo, 'ELO'), (RankSort.pct, '% victorias'), (RankSort.played, 'Partidos')]) ...[
                PlobbyFilterChip(label: x.$2, selected: _sort == x.$1, onTap: () => setState(() => _sort = x.$1)),
                const SizedBox(width: 8),
              ],
            ])),
            const SizedBox(height: 12),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
              child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 6), child: _TableRow(cells: [
                  const Text('#', textAlign: TextAlign.center, style: _th), const SizedBox.shrink(), const Text('JUGADOR', style: _th),
                  const Text('PJ', textAlign: TextAlign.center, style: _th), const Text('V', textAlign: TextAlign.center, style: _th), const Text('D', textAlign: TextAlign.center, style: _th),
                  Text(metric, textAlign: TextAlign.center, style: _th.copyWith(color: AppColors.text)),
                ])),
                for (var k = 0; k < show.length; k++) ...[
                  if (cut && k == 8) const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('···', style: _muted)),
                  _RankRow(pos: show[k] + 1, row: sorted[show[k]], me: show[k] == meIdx, metric: switch (_sort) {
                    RankSort.elo => '${sorted[show[k]].elo}', RankSort.pct => '${sorted[show[k]].winPct}%', RankSort.played => '${sorted[show[k]].played}', RankSort.points => '${sorted[show[k]].points}' }),
                ],
              ]),
            ),
            if (cut) Padding(padding: const EdgeInsets.only(top: 14), child: PlobbyButton(label: 'Ver clasificación completa (${sorted.length})', kind: PlobbyButtonKind.outline, onPressed: () => setState(() => _all = true))),
            const SizedBox(height: 12),
            Text('Victoria: ${r.pointsWin} ${r.pointsWin == 1 ? 'punto' : 'puntos'} · Derrota: ${r.pointsLoss} ${r.pointsLoss == 1 ? 'punto' : 'puntos'}${r.bonusEnabled ? ' · Bonus por ganar sin ceder sets' : ''}. Solo cuentan partidos confirmados por los dos capitanes.', style: _muted),
          ]);
        },
      );

  // ── Actividad: resultados confirmados y disputas recientes, agrupados por día ──
  Widget _activity(LeagueDetail l) {
    if (!l.isMember) return const EmptyStateCard(icon: Icons.lock_outline, title: 'Actividad solo para miembros', text: 'Únete a la liga para ver sus resultados y novedades.');
    return ref.watch(leagueMatchesProvider(l.id)).when(
      loading: () => const LoadingBlock(height: 160, radius: AppRadius.md),
      error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(leagueMatchesProvider(l.id))),
      data: (ms) {
        final items = ms.where((m) => m.status == MatchStatus.confirmed || m.status == MatchStatus.disputed).toList()
          ..sort((a, b) => (b.endedAt ?? b.scheduledAt).compareTo(a.endedAt ?? a.scheduledAt));
        if (items.isEmpty) return const EmptyStateCard(icon: Icons.bolt_outlined, title: 'Aún no hay actividad', text: 'Los resultados confirmados de la liga aparecerán aquí.');
        final out = <Widget>[];
        String? last;
        for (final m in items.take(20)) {
          final g = dayGroupLabel(m.endedAt ?? m.scheduledAt, DateTime.now());
          if (g != last) { out.add(Padding(padding: EdgeInsets.fromLTRB(0, last == null ? 14 : 10, 0, 10), child: Text(g.toUpperCase(), style: PlobbyText.eb))); last = g; }
          out.add(_ActivityItem(match: m));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
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
          const SizedBox(height: 10),
          if (l.status != LeagueStatus.ended) ...[
            PlobbyButton(label: 'Registrar partido', icon: PlobbyIcons.plus, onPressed: () => context.push('/match/new?type=league&leagueId=${l.id}&result=1')),
            const SizedBox(height: 16),
          ],
          SlidingTabs(labels: ['Próximos (${upcoming.length})', 'Jugados (${done.length})'], index: _upcoming ? 0 : 1, onChanged: (i) => setState(() => _upcoming = i == 0)),
          const SizedBox(height: 12),
          if (list.isEmpty)
            EmptyStateCard(icon: Icons.sports_tennis, title: _upcoming ? 'No hay partidos programados' : 'Todavía no se ha jugado ningún partido',
                text: _upcoming ? 'Organiza el primero con otros miembros de la liga.' : 'Registra un resultado para empezar la clasificación.',
                primary: _upcoming ? 'Crear partido de liga' : 'Registrar resultado',
                onPrimary: () => context.push('/match/new?type=league&leagueId=${l.id}${_upcoming ? '' : '&result=1'}'))
          else
            for (final m in list) _LeagueMatchTile(match: m),
        ]);
      },
    );
  }

  // ── Miembros ──
  Widget _members(LeagueDetail l, AsyncValue<List<StandingRow>> s, String uid) => s.when(
        loading: () => const LoadingBlock(height: 240, radius: AppRadius.md),
        error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(standingsProvider(l.id))),
        data: (rows) {
          final q = _q.trim().toLowerCase();
          final list = [...rows]..sort((a, b) => a.rank != b.rank ? a.rank - b.rank : a.name.compareTo(b.name));
          final shown = q.isEmpty ? list : list.where((r) => r.name.toLowerCase().contains(q) || r.username.toLowerCase().contains(q)).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 10),
            SearchField(hint: 'Buscar jugadores', onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 14),
            if (l.canManage) ...[PlobbyButton(label: 'Invitar amigos', icon: PlobbyIcons.userplus, kind: PlobbyButtonKind.outline, onPressed: () => context.push('/leagues/${l.id}/manage')), const SizedBox(height: 14)],
            Text('${list.length} de ${l.maxPlayers} jugadores', style: _muted),
            const SizedBox(height: 8),
            if (list.length <= 1)
              EmptyStateCard(icon: Icons.group_add_outlined, title: 'Solo estás tú', text: 'Invita a tus amigos o comparte el código para que se unan.',
                  primary: l.canManage ? 'Invitar amigos' : null, onPrimary: () => context.push('/leagues/${l.id}/manage'))
            else if (shown.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('Ningún jugador coincide con «$_q».', textAlign: TextAlign.center, style: _muted))
            else Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
              child: Column(children: [for (var i = 0; i < shown.length; i++) _MemberRow(row: shown[i], me: shown[i].userId == uid || shown[i].userId == 'me', first: i == 0)]),
            ),
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

  /// `ACT.lmenu`: hoja «Opciones» con el nombre de la liga.
  Future<void> _menu(LeagueDetail l) async {
    final code = l.isMember ? await ref.read(inviteCodeProvider(l.id).future).catchError((_) => null) : null;
    if (!mounted) return;
    await showPlobbySheet<void>(context, (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(title: 'Opciones', subtitle: l.name.toUpperCase()),
      if (l.canManage) SheetListItem(icon: PlobbyIcons.userplus, label: 'Invitar amigos', onTap: () { Navigator.pop(c); context.push('/leagues/${l.id}/manage'); }),
      if (code != null) SheetListItem(icon: PlobbyIcons.copy, label: 'Copiar código de invitación · $code', onTap: () {
        Clipboard.setData(ClipboardData(text: code)); Navigator.pop(c); showPlobbySnack(context, 'Código copiado'); }),
      SheetListItem(icon: PlobbyIcons.info, label: 'Ver reglas de la liga', onTap: () { Navigator.pop(c); _rules(l); }),
      if (l.isMember && l.status != LeagueStatus.ended) SheetListItem(icon: PlobbyIcons.plus, label: 'Crear partido de liga',
          onTap: () { Navigator.pop(c); context.push('/match/new?type=league&leagueId=${l.id}'); }),
      if (l.canManage) SheetListItem(icon: PlobbyIcons.sliders, label: 'Gestionar liga', onTap: () { Navigator.pop(c); context.push('/leagues/${l.id}/manage'); }),
      if (l.isMember && l.myRole != LeagueRole.organizer) SheetListItem(icon: PlobbyIcons.close, label: 'Salir de la liga', danger: true, onTap: () { Navigator.pop(c); _leave(l); }),
      if (!l.isMember) Padding(padding: const EdgeInsets.only(top: 12), child: Text(l.visibility.description, style: PlobbyText.sub)),
    ]));
  }

  /// Hoja «Reglas» (solo lectura): puntuación, bonus, partidos por jugador y plazas, tal y como están guardadas.
  void _rules(LeagueDetail l) {
    final r = l.rules;
    Widget row(String k, String v) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
          child: Row(children: [Expanded(child: Text(k, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w400))), Text(v, style: PlobbyText.value)]));
    showPlobbySheet<void>(context, (_) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(title: 'Reglas', subtitle: l.name.toUpperCase()),
      row('Victoria', '${r.pointsWin} ${r.pointsWin == 1 ? 'punto' : 'puntos'}'),
      row('Derrota', '${r.pointsLoss} ${r.pointsLoss == 1 ? 'punto' : 'puntos'}'),
      row('Bonus por ganar sin ceder sets', r.bonusEnabled ? '+1 punto' : 'No'),
      row('Partidos por jugador', '${l.matchesPerPlayer}'),
      row('Plazas', '${l.minPlayers}–${l.maxPlayers} jugadores'),
      const SizedBox(height: 8),
      const Text('Solo cuentan los partidos de liga confirmados por los dos capitanes.', style: _muted),
    ]));
  }

  Future<void> _leave(LeagueDetail l) async {
    final ok = await showPlobbySheet<bool>(context, (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHeader(title: '¿Salir de la liga?'),
      const Text('Tus partidos jugados se mantienen, pero dejarás de aparecer en la clasificación.', style: PlobbyText.sub),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(c, false))),
        const SizedBox(width: 10),
        Expanded(child: PlobbyButton(label: 'Salir', kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(c, true))),
      ]),
    ]));
    if (ok != true) return;
    try { await ref.read(leagueActionsProvider).leave(l.id); if (mounted) context.go('/leagues'); }
    on LeagueException catch (e) { if (mounted) showPlobbySnack(context, e.message, error: true); }
  }
}

/// «Hoy», «Ayer» o la fecha (`d mmm`) para agrupar la actividad.
String dayGroupLabel(DateTime d, DateTime now) {
  final a = DateTime(d.year, d.month, d.day), b = DateTime(now.year, now.month, now.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${d.day} ${m[d.month - 1]}';
}

/// «hace 2 h», «hace 1 d», «ahora».
String agoLabel(DateTime d, DateTime now) {
  final x = now.difference(d);
  if (x.inMinutes < 1) return 'ahora';
  if (x.inMinutes < 60) return 'hace ${x.inMinutes} min';
  if (x.inHours < 24) return 'hace ${x.inHours} h';
  return 'hace ${x.inDays} d';
}

const _th = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textMuted);

/// Rejilla de `.th`/`.tr`: 24 · 30 · 1fr · 22 · 22 · 22 · 42, separación 8.
class _TableRow extends StatelessWidget {
  const _TableRow({required this.cells});
  final List<Widget> cells;
  static const _w = [24.0, 30.0, null, 22.0, 22.0, 22.0, 42.0];
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          if (_w[i] == null) Expanded(child: cells[i]) else SizedBox(width: _w[i], child: cells[i]),
        ],
      ]);
}


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

/// Cabecera `.dh`: portada 200 px con degradado, botones de cristal y título (chips + nombre Inter 24/800 +.03em).
class _Header extends StatelessWidget {
  const _Header({required this.league, required this.onMenu});
  final LeagueDetail league; final VoidCallback onMenu;
  @override
  Widget build(BuildContext context) {
    final l = league, top = MediaQuery.paddingOf(context).top;
    return SizedBox(height: 200 + top, child: Stack(children: [
      Positioned.fill(child: LeagueCover(cover: l.cover, height: 200 + top, radius: 0, shade: true)),
      Positioned(left: 16, right: 16, top: top + 14, child: Row(children: [
        IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', glass: true, onPressed: () => context.canPop() ? context.pop() : context.go('/leagues')),
        const Spacer(),
        IconSquareButton(icon: PlobbyIcons.more, tooltip: 'Opciones de la liga', glass: true, onPressed: onMenu),
      ])),
      Positioned(left: 20, right: 20, bottom: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          LeagueChip(l.visibility.label, icon: visibilityIcon(l.visibility), tone: ChipTone.glass),
          LeagueChip('Temporada ${l.season}', tone: ChipTone.glass),
          if (l.status == LeagueStatus.ended) const LeagueChip('Cerrada', tone: ChipTone.lime),
          if (l.status == LeagueStatus.open) const LeagueChip('Inscripción abierta', tone: ChipTone.lime),
        ]),
        const SizedBox(height: 8),
        Semantics(header: true, child: Text(l.name.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 24, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: .72, color: Colors.white))),
      ])),
    ]));
  }
}

/// `.info`: 2 columnas (separación 14/16); clave 10.5/700 +.12em con icono, valor 14/600.
class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.league, required this.uid, this.members});
  final LeagueDetail league; final int? members; final String uid;
  @override
  Widget build(BuildContext context) {
    final l = league;
    final iOrganize = l.createdBy != null && (l.createdBy == uid);
    Widget cell(PlobbyIcons i, String k, String v, [Widget? extra]) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [PlobbyIcon(i, size: 13, color: AppColors.textMuted), const SizedBox(width: 6),
            Flexible(child: Text(k.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.key))]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(v, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text)),
            if (extra != null) extra,
          ]),
        ]));
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cell(PlobbyIcons.pin, 'Ubicación', l.location.isEmpty ? '—' : l.location),
        const SizedBox(width: 16),
        cell(PlobbyIcons.building, 'Organiza', iOrganize ? 'Tú' : (l.organizerName.isEmpty ? '—' : l.organizerName), l.myRole?.isManager == true ? RoleBadge(l.myRole!, compact: true) : null),
      ]),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cell(PlobbyIcons.users, 'Jugadores', members == null ? '—' : '$members ${members == 1 ? 'jugador' : 'jugadores'}'),
        const SizedBox(width: 16),
        cell(PlobbyIcons.cal, 'Temporada', '${fmtDay(l.startsOn)} – ${fmtDay(l.endsOn)}'),
      ]),
    ]);
  }
}

/// `.perf`: posición grande (Unbounded 64/800 lima) y rejilla 3×2 de estadísticas (Inter 22/800).
class _Performance extends StatelessWidget {
  const _Performance({required this.row, required this.total});
  final StandingRow? row; final int total;
  @override
  Widget build(BuildContext context) {
    final r = row;
    Widget cell(String v, String l) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 22, height: 1, fontWeight: FontWeight.w800, letterSpacing: -0.44, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]))),
          const SizedBox(height: 5),
          FittedBox(fit: BoxFit.scaleDown, child: Text(l.toUpperCase(), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: .63, color: Color(0xADF6F8F1)))),
        ]));
    return Semantics(
      label: r == null ? 'Aún no tienes posición en la liga' : 'Tu posición: ${r.rank} de $total. ${r.points} puntos, ${r.played} jugados, ${r.winPct}% victorias, ${r.wins} ganados, ${r.losses} perdidos, bonus ${r.bonus}.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16), decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rMd),
        child: Row(children: [
          ConstrainedBox(constraints: const BoxConstraints(minWidth: 112), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('TU POSICIÓN', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Color(0xA6F6F8F1))),
            const SizedBox(height: 4),
            Text(r == null ? '—' : '#${r.rank}', style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 64, height: .9, fontWeight: FontWeight.w800, letterSpacing: -3.2, color: AppColors.brand)),
            if (total > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('de $total', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: Color(0xA6F6F8F1)))),
          ])),
          const SizedBox(width: 18),
          Expanded(child: Column(children: [
            Row(children: [cell('${r?.points ?? 0}', 'Puntos'), const SizedBox(width: 8), cell('${r?.played ?? 0}', 'Jugados'), const SizedBox(width: 8), cell('${r?.winPct ?? 0}%', 'Victorias')]),
            const SizedBox(height: 14),
            Row(children: [cell('${r?.wins ?? 0}', 'Ganados'), const SizedBox(width: 8), cell('${r?.losses ?? 0}', 'Perdidos'), const SizedBox(width: 8), cell(r == null || r.bonus == 0 ? '0' : '+${r.bonus}', 'Bonus')]),
          ])),
        ]),
      ),
    );
  }
}

/// Invitación a unirse (no miembro): bloque tinta con la acción según la visibilidad.
class _JoinCta extends StatelessWidget {
  const _JoinCta({required this.league, required this.busy, required this.onJoin});
  final LeagueDetail league; final bool busy; final VoidCallback onJoin;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(18), decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(league.visibility == LeagueVisibility.club ? 'Liga de club' : '¿Te apuntas?', style: const TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, letterSpacing: -0.17, color: Colors.white, fontSize: 17)),
        const SizedBox(height: 6),
        Text(league.visibility.description, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.4, letterSpacing: 0, color: Color(0xB3FFFFFF))),
        const SizedBox(height: 14),
        PlobbyButton(busy: busy, onPressed: league.status == LeagueStatus.ended ? null : onJoin,
            label: league.visibility == LeagueVisibility.club ? 'Solicitar acceso' : league.visibility == LeagueVisibility.private ? 'Unirme con código' : 'Unirme a la liga'),
      ]));
}

/// Pestañas fijas `.tabs` (marfil, padding 14 20 10) con `.seg`.
class _TabsDelegate extends SliverPersistentHeaderDelegate {
  _TabsDelegate(this.sel, this.onTap);
  final int sel; final ValueChanged<int> onTap;
  @override double get minExtent => 70;
  @override double get maxExtent => 70;
  @override
  Widget build(BuildContext c, double shrink, bool overlaps) => Container(
      color: AppColors.bg, padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: SlidingTabs(labels: const ['Clasificación', 'Actividad', 'Partidos', 'Miembros'], index: sel, onChanged: onTap));
  @override
  bool shouldRebuild(_TabsDelegate o) => o.sel != sel;
}

/// Fila `.tr` (52 px): posición (1.º lima, 2.º–3.º con aro), avatar 30, nombre + ELO, PJ · V · D y la métrica.
/// `.top1` con degradado lima suave; `.me` en gris con barra de 3 px a la izquierda.
class _RankRow extends StatelessWidget {
  const _RankRow({required this.pos, required this.row, required this.me, required this.metric});
  final int pos; final StandingRow row; final bool me; final String metric;
  static const _c = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, letterSpacing: 0, color: AppColors.ink700, fontFeatures: [FontFeature.tabularFigures()]);
  @override
  Widget build(BuildContext context) {
    final pn = Container(width: 24, height: 24, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: pos == 1 ? AppColors.brand : null, border: pos == 2 || pos == 3 ? Border.all(color: AppColors.borderStrong, width: 1.5) : null),
        child: Text('$pos', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0, color: pos <= 3 ? AppColors.text : AppColors.textMuted)));
    return Semantics(button: true, label: 'Puesto $pos, ${row.name}${me ? ' (tú)' : ''}, ${row.played} jugados, ${row.wins} ganados, ${row.losses} perdidos, $metric', excludeSemantics: true,
      child: Material(color: Colors.transparent, child: InkWell(
        onTap: () => context.push('/player/${row.userId}'),
        child: Container(
          height: 52, padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: me ? const Color(0x17171C19) : null,
            gradient: !me && pos == 1 ? const LinearGradient(colors: [Color(0x29D2F548), Color(0x00D2F548)], stops: [0, .7]) : null,
            border: me ? const Border(left: BorderSide(color: AppColors.text, width: 3)) : null,
          ),
          child: _TableRow(cells: [
            Center(child: pn),
            LeagueAvatar(name: row.name, avatarUrl: row.avatarUrl, avatarId: row.avatarId, size: 30),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me ? '${row.name} (tú)' : row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
              const SizedBox(height: 1),
              Text('ELO ${row.elo}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, letterSpacing: 0, color: AppColors.textMuted)),
            ]),
            Text('${row.played}', textAlign: TextAlign.center, style: _c),
            Text('${row.wins}', textAlign: TextAlign.center, style: _c),
            Text('${row.losses}', textAlign: TextAlign.center, style: _c),
            FittedBox(fit: BoxFit.scaleDown, child: Text(metric, textAlign: TextAlign.center, style: _c.copyWith(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
          ]),
        ),
      )),
    );
  }
}

/// Fila de «Miembros»: avatar 40, nombre, @usuario · ELO, rol y puesto (`#n`, lima en el podio).
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.row, required this.me, required this.first});
  final StandingRow row; final bool me, first;
  @override
  Widget build(BuildContext context) {
    final top = row.rank <= 3 && row.played > 0;
    return Semantics(button: true, label: '${row.name}${me ? ' (tú)' : ''}, ELO ${row.elo}, puesto ${row.rank}${row.role == LeagueRole.player ? '' : ', ${row.role.label}'}', excludeSemantics: true,
      child: InkWell(onTap: () => context.push('/player/${row.userId}'), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: Color(0x1A171C19)))),
        child: Row(children: [
          LeagueAvatar(name: row.name, avatarUrl: row.avatarUrl, avatarId: row.avatarId, size: 40),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(me ? '${row.name} (tú)' : row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            Text([if (row.username.isNotEmpty) '@${row.username}', 'ELO ${row.elo}'].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted)),
          ])),
          if (row.role != LeagueRole.player) ...[const SizedBox(width: 8), RoleBadge(row.role, compact: true)],
          const SizedBox(width: 8),
          Container(height: 24, constraints: const BoxConstraints(minWidth: 36), padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.center,
              decoration: BoxDecoration(color: top ? AppColors.brand : null, borderRadius: AppRadius.rPill, border: top ? null : Border.all(color: AppColors.border, width: 1.5)),
              child: Text('#${row.rank}', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0, color: top ? AppColors.brandInk : AppColors.textMuted))),
        ]),
      )),
    );
  }
}

/// Partido de liga: fecha y estado, las dos parejas (caja con barra lima a la izquierda) separadas por «VS» y la pista.
class _LeagueMatchTile extends StatelessWidget {
  const _LeagueMatchTile({required this.match});
  final LifecycleMatch match;
  @override
  Widget build(BuildContext context) {
    final m = match, w = m.winnerTeam;
    String names(int t) => m.team(t).map((p) => p.name.split(' ').first).join(' y ');
    Widget team(int t) => Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10),
              border: const Border(left: BorderSide(color: AppColors.brand, width: 3)), boxShadow: const [BoxShadow(color: Color(0x0F171C19), blurRadius: 8, offset: Offset(0, 2))]),
          child: Row(children: [
            SizedBox(width: 42, height: 28, child: Stack(children: [
              for (var i = 0; i < m.team(t).length && i < 2; i++) Positioned(left: i * 14.0, child: PlayerAvatar(player: m.team(t)[i], size: 26)),
            ])),
            Expanded(child: Text(names(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: w == t ? FontWeight.w700 : FontWeight.w500, letterSpacing: 0, color: AppColors.text))),
            for (final s in m.sets) Padding(padding: const EdgeInsets.only(left: 8), child: Text('${t == 1 ? s.a : s.b}',
                style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: (t == 1 ? s.a > s.b : s.b > s.a) ? AppColors.text : AppColors.textMuted))),
          ]));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
      child: Material(color: AppColors.surface, borderRadius: AppRadius.rMd, clipBehavior: Clip.antiAlias, child: InkWell(
        onTap: () => context.push(m.status == MatchStatus.confirmed ? '/match/${m.id}/final' : '/match/${m.id}'),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(formatWhen(m.scheduledAt), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))),
            StatusChip(status: m.status),
          ]),
          const SizedBox(height: 12),
          team(1),
          const Padding(padding: EdgeInsets.fromLTRB(4, 10, 0, 10), child: Text('VS', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.47, color: AppColors.textMuted))),
          team(2),
          if (m.club.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
            const PlobbyIcon(PlobbyIcons.pin, size: 14, color: AppColors.textMuted), const SizedBox(width: 6),
            Expanded(child: Text('${m.club}${m.court != null && m.court!.isNotEmpty ? ' · ${m.court}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _muted.copyWith(fontSize: 12.5))),
          ])),
        ])),
      )),
    );
  }
}

/// Elemento de «Actividad»: avatar del ganador, frase con nombres en negrita, marcador y hace cuánto.
class _ActivityItem extends StatelessWidget {
  const _ActivityItem({required this.match});
  final LifecycleMatch match;
  @override
  Widget build(BuildContext context) {
    final m = match, w = m.winnerTeam ?? 1, dis = m.status == MatchStatus.disputed;
    String names(int t) => m.team(t).map((p) => p.name).join(' y ');
    const base = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.45, letterSpacing: 0, color: AppColors.text);
    const b = TextStyle(fontWeight: FontWeight.w700);
    final lead = m.team(dis ? 1 : w).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
      child: Material(color: AppColors.surface, borderRadius: AppRadius.rMd, clipBehavior: Clip.antiAlias, child: InkWell(
        onTap: () => context.push(m.status == MatchStatus.confirmed ? '/match/${m.id}/final' : '/match/${m.id}'),
        child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (lead != null) PlayerAvatar(player: lead, size: 40) else const SizedBox(width: 40),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(style: base, children: dis
                ? [const TextSpan(text: 'Resultado en disputa entre '), TextSpan(text: names(1), style: b), const TextSpan(text: ' y '), TextSpan(text: names(2), style: b)]
                : [TextSpan(text: names(w), style: b), const TextSpan(text: ' vencieron a '), TextSpan(text: names(w == 1 ? 2 : 1), style: b)])),
            if (m.sets.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(6)),
              child: Text(m.sets.map((s) => '${s.a}-${s.b}').join(' '), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: AppColors.text)))),
            const SizedBox(height: 6),
            Text(agoLabel(m.endedAt ?? m.scheduledAt, DateTime.now()), style: _muted),
          ])),
        ])),
      )),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => ListView(padding: EdgeInsets.zero, children: const [
        LoadingBlock(height: 240, radius: 0),
        Padding(padding: EdgeInsets.all(20), child: Column(children: [LoadingBlock(height: 104, radius: AppRadius.md), SizedBox(height: 14), LoadingBlock(height: 140, radius: AppRadius.md), SizedBox(height: 14), LoadingBlock(height: 320, radius: AppRadius.md)])),
      ]);
}
