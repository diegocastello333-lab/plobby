import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';

/// Pestaña «Ligas» — `scLeagues` del prototipo HTML: cabecera, resumen (activas · jugados · títulos), «Mis ligas»,
/// crear liga y «Descubrir ligas». Datos reales de `my_leagues` / `discover_leagues`.
class LeaguesScreen extends ConsumerWidget {
  const LeaguesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(leagueListProvider);
    final teasers = ref.watch(discoverTeasersProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: RefreshIndicator(
        color: AppColors.text,
        onRefresh: () async { ref.invalidate(leagueListProvider); ref.invalidate(discoverTeasersProvider); await ref.read(leagueListProvider.future).catchError((_) => <LeagueSummary>[]); },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 26, 20, 130), children: [
          // .lgh
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: const Text('Ligas', style: PlobbyText.t1)),
              const SizedBox(height: 6),
              const Text('Compite con tu comunidad.', style: PlobbyText.sub),
            ])),
            IconSquareButton(icon: PlobbyIcons.link, tooltip: 'Unirme con código', onPressed: () => showJoinByCodeSheet(context)),
          ]),
          const SizedBox(height: 22),
          mine.when(
            loading: () => const LoadingBlock(height: 119, radius: AppRadius.md),
            error: (_, __) => const SizedBox.shrink(),
            data: (l) => _Overview(leagues: l),
          ),
          const SizedBox(height: 30),
          // .sec «Mis ligas» + .sbtn «Crear liga»
          Row(children: [
            Expanded(child: Semantics(header: true, child: const Text('Mis ligas', style: PlobbyText.t2))),
            PlobbyButton(label: 'Crear liga', icon: PlobbyIcons.plus, kind: PlobbyButtonKind.small, onPressed: () => context.push('/leagues/new')),
          ]),
          const SizedBox(height: 12),
          mine.when(
            loading: () => const Column(children: [LoadingBlock(height: 241, radius: AppRadius.md), SizedBox(height: 14), LoadingBlock(height: 241, radius: AppRadius.md)]),
            error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(leagueListProvider)),
            data: (l) => l.isEmpty
                ? EmptyStateCard(icon: Icons.emoji_events_outlined, title: 'Todavía no estás en ninguna liga',
                    text: 'Crea una liga con tus amigos o únete a una de tu zona para empezar a competir.',
                    primary: 'Crear liga', onPrimary: () => context.push('/leagues/new'), secondary: 'Descubrir ligas', onSecondary: () => context.push('/leagues/discover'))
                : Column(children: [
                    for (var i = 0; i < l.length; i++) Padding(padding: const EdgeInsets.only(bottom: 14), child: AppearOnce(animationKey: 'lg:${l[i].id}', index: i, child: MyLeagueCard(league: l[i]))),
                    _AddLeagueButton(onTap: () => context.push('/leagues/new')),
                  ]),
          ),
          const SizedBox(height: 34),
          Semantics(header: true, child: const Text('Descubrir ligas', style: PlobbyText.t2)),
          const SizedBox(height: 4),
          // En el HTML `.sub` hereda la tipografía de `.sec` (Unbounded 14/700): se reproduce tal cual.
          const Text('Encuentra tu próxima competición.', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 14, height: 1.4, fontWeight: FontWeight.w700, letterSpacing: -0.28, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          Semantics(button: true, label: 'Buscar ligas por nombre, club o zona', excludeSemantics: true, child: Material(
            color: AppColors.surface, shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: BorderSide(color: AppColors.borderStrong)),
            child: InkWell(borderRadius: AppRadius.rMd, onTap: () => context.push('/leagues/discover'),
              child: const SizedBox(height: 48, child: Row(children: [
                SizedBox(width: 14), PlobbyIcon(PlobbyIcons.search, size: 18, color: AppColors.textMuted), SizedBox(width: 10),
                Expanded(child: Text('Buscar por nombre, club o zona', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 16, letterSpacing: 0, color: AppColors.textMuted))),
              ]))),
          )),
          const SizedBox(height: 14),
          teasers.when(
            loading: () => const LoadingBlock(height: 260, radius: AppRadius.md),
            error: (_, __) => const SizedBox.shrink(),
            data: (l) => Column(children: [for (final d in l.take(2)) _TeaserCard(league: d)]),
          ),
          PlobbyButton(label: 'Ver todas las ligas', kind: PlobbyButtonKind.outline, onPressed: () => context.push('/leagues/discover')),
        ]),
      )),
    );
  }
}

/// `.card2.ov3`: tres columnas separadas por una línea (eyebrow, número Inter 28/800, etiqueta 12).
class _Overview extends StatelessWidget {
  const _Overview({required this.leagues});
  final List<LeagueSummary> leagues;
  @override
  Widget build(BuildContext context) {
    final active = leagues.where((l) => l.status != LeagueStatus.ended).length;
    final played = leagues.fold<int>(0, (s, l) => s + l.myPlayed);
    final titles = leagues.where((l) => l.status == LeagueStatus.ended && l.myRank == 1).length;
    Widget cell(String eb, int n, String l, {bool first = false}) => Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: first ? null : const Border(left: BorderSide(color: Color(0x1A171C19)))),
          child: Semantics(label: '$eb: $n $l', excludeSemantics: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(eb.toUpperCase(), maxLines: 1, style: PlobbyText.eb),
            const SizedBox(height: 6),
            Text('$n', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 28, height: 1, fontWeight: FontWeight.w800, letterSpacing: -0.56, color: AppColors.text)),
            const SizedBox(height: 6),
            Text(l, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1.25, letterSpacing: 0, color: AppColors.textMuted)),
          ])),
        ));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16), decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
      child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        cell('Activas', active, active == 1 ? 'liga' : 'ligas', first: true),
        cell('Jugados', played, 'partidos de liga'),
        cell('Títulos', titles, titles == 1 ? 'liga ganada' : 'ligas ganadas'),
      ])));
  }
}

/// `.addc`: «Crear una liga nueva», 58 px, borde interior 1.5 px, Inter 14/700.
class _AddLeagueButton extends StatelessWidget {
  const _AddLeagueButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: 'Crear una liga nueva', excludeSemantics: true, child: Material(
        color: Colors.transparent, shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: BorderSide(color: AppColors.borderStrong, width: 1.5)),
        child: InkWell(borderRadius: AppRadius.rMd, onTap: onTap, child: const SizedBox(height: 58, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          PlobbyIcon(PlobbyIcons.plus, size: 18, strokeWidth: 2.2), SizedBox(width: 8),
          Text('Crear una liga nueva', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
        ]))),
      ));
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
Future<void> showJoinByCodeSheet(BuildContext context, {String? initial}) => showPlobbySheet(context, (_) => _JoinByCode(initial: initial));

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
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Unirme con código', subtitle: 'Pide el código al organizador de la liga.'),
        LabeledField(label: 'Código de invitación', controller: _c, hint: 'JUEVES-01', error: _error, autofocus: true,
            textCapitalization: TextCapitalization.characters, onSubmitted: (_) => _go()),
        PlobbyButton(label: 'Unirme', busy: _busy, onPressed: _go),
      ]);
}
