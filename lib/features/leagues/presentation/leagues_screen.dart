import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';

/// Pestaña «Ligas» (prototipo `scLeagues`): resumen, mis ligas, crear liga y descubrir. Datos reales de `my_leagues` / `discover_leagues`.
class LeaguesScreen extends ConsumerWidget {
  const LeaguesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(leagueListProvider);
    final teasers = ref.watch(discoverTeasersProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: RefreshIndicator(
        onRefresh: () async { ref.invalidate(leagueListProvider); ref.invalidate(discoverTeasersProvider); await ref.read(leagueListProvider.future).catchError((_) => <LeagueSummary>[]); },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 120), children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ligas', style: TextStyle(fontFamily: 'Unbounded', fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.6)),
              SizedBox(height: 2),
              Text('Compite con tu comunidad.', style: TextStyle(color: AppColors.textMuted)),
            ])),
            IconButton(tooltip: 'Unirme con código', onPressed: () => showJoinByCodeSheet(context), icon: const Icon(Icons.qr_code_2_rounded)),
          ]),
          const SizedBox(height: 18),
          mine.when(
            loading: () => const LoadingBlock(height: 86),
            error: (_, __) => const SizedBox.shrink(),
            data: (l) => _Overview(leagues: l),
          ),
          const SizedBox(height: 8),
          SectionHeader(title: 'Mis ligas', actionLabel: 'Crear liga', onAction: () => context.push('/leagues/new')),
          mine.when(
            loading: () => const Column(children: [LoadingBlock(height: 200), SizedBox(height: 12), LoadingBlock(height: 200)]),
            error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(leagueListProvider)),
            data: (l) => l.isEmpty
                ? EmptyStateCard(icon: Icons.emoji_events_outlined, title: 'Todavía no estás en ninguna liga',
                    text: 'Crea una liga con tus amigos o únete a una de tu zona para empezar a competir.',
                    primary: 'Crear liga', onPrimary: () => context.push('/leagues/new'), secondary: 'Descubrir ligas', onSecondary: () => context.push('/leagues/discover'))
                : Column(children: [
                    for (var i = 0; i < l.length; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: AppearOnce(animationKey: 'lg:${l[i].id}', index: i, child: MyLeagueCard(league: l[i]))),
                    OutlinedButton.icon(onPressed: () => context.push('/leagues/new'), icon: const Icon(Icons.add), label: const Text('Crear una liga nueva'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
                  ]),
          ),
          const SizedBox(height: 30),
          const Text('Descubrir ligas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          const Text('Encuentra tu próxima competición.', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          Material(color: AppColors.surface, borderRadius: AppRadius.rMd, child: InkWell(
            borderRadius: AppRadius.rMd, onTap: () => context.push('/leagues/discover'),
            child: const SizedBox(height: 48, child: Row(children: [SizedBox(width: 14), Icon(Icons.search, color: AppColors.textMuted), SizedBox(width: 10),
              Text('Buscar por nombre, club o zona', style: TextStyle(color: AppColors.textMuted))])))),
          const SizedBox(height: 14),
          teasers.when(
            loading: () => const LoadingBlock(height: 88),
            error: (_, __) => const SizedBox.shrink(),
            data: (l) => Column(children: [for (final d in l.take(2)) _TeaserCard(league: d)]),
          ),
          OutlinedButton(onPressed: () => context.push('/leagues/discover'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Ver todas las ligas')),
        ]),
      )),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.leagues});
  final List<LeagueSummary> leagues;
  @override
  Widget build(BuildContext context) {
    final active = leagues.where((l) => l.status != LeagueStatus.ended).length;
    final played = leagues.fold<int>(0, (s, l) => s + l.myPlayed);
    final titles = leagues.where((l) => l.status == LeagueStatus.ended && l.myRank == 1).length;
    Widget cell(String eb, int n, String l) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(eb.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text('$n', style: const TextStyle(fontFamily: 'Unbounded', fontSize: 24, fontWeight: FontWeight.w700)),
          Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]));
    return Container(
      padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, boxShadow: AppShadows.card),
      child: Row(children: [
        cell('Activas', active, active == 1 ? 'liga' : 'ligas'),
        cell('Jugados', played, 'partidos de liga'),
        cell('Títulos', titles, titles == 1 ? 'liga ganada' : 'ligas ganadas'),
      ]));
  }
}

class _TeaserCard extends ConsumerStatefulWidget {
  const _TeaserCard({required this.league});
  final DiscoverLeague league;
  @override
  ConsumerState<_TeaserCard> createState() => _TeaserCardState();
}

class _TeaserCardState extends ConsumerState<_TeaserCard> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => DiscoverLeagueCard(league: widget.league, busy: _busy, onJoin: () => joinLeague(context, ref, widget.league, (b) => setState(() => _busy = b)));
}

/// Unirse/solicitar desde una tarjeta (lista o «Descubrir»). Ligas privadas sin invitación → pide el código.
Future<void> joinLeague(BuildContext context, WidgetRef ref, DiscoverLeague d, void Function(bool) busy) async {
  if (d.visibility == LeagueVisibility.private && !d.invited) { await showJoinByCodeSheet(context); return; }
  busy(true);
  try {
    final r = await ref.read(leagueActionsProvider).join(d.id);
    if (!context.mounted) return;
    if (r == JoinOutcome.requested) { showPlobbySnack(context, 'Solicitud enviada. Te avisaremos cuando la aprueben.'); }
    else { showPlobbySnack(context, 'Ya formas parte de ${d.name}'); context.push('/leagues/${d.id}'); }
  } on LeagueException catch (e) {
    if (context.mounted) showPlobbySnack(context, e.message, error: true);
  } finally { busy(false); }
}

/// Hoja «Unirme con código» (enlace/código de invitación de una liga privada).
Future<void> showJoinByCodeSheet(BuildContext context, {String? initial}) => showModalBottomSheet(
    context: context, isScrollControlled: true, showDragHandle: true,
    builder: (_) => _JoinByCode(initial: initial));

class _JoinByCode extends ConsumerStatefulWidget {
  const _JoinByCode({this.initial});
  final String? initial;
  @override
  ConsumerState<_JoinByCode> createState() => _JoinByCodeState();
}

class _JoinByCodeState extends ConsumerState<_JoinByCode> {
  late final _c = TextEditingController(text: widget.initial);
  bool _busy = false; String? _error;
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  Future<void> _go() async {
    final code = _c.text.trim();
    if (code.length < 4) { setState(() => _error = 'Escribe el código completo, p. ej. JUEVES-01.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final id = await ref.read(leagueActionsProvider).joinByCode(code);
      if (!mounted) return;
      Navigator.pop(context);
      context.push('/leagues/$id');
    } on LeagueException catch (e) { setState(() { _busy = false; _error = e.message; }); }
  }
  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Unirme con código', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Pide el código al organizador de la liga.', style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 16),
        TextField(controller: _c, autofocus: true, textCapitalization: TextCapitalization.characters, onSubmitted: (_) => _go(),
            decoration: InputDecoration(labelText: 'Código de invitación', hintText: 'JUEVES-01', errorText: _error)),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _go,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Unirme'))),
      ]));
}
