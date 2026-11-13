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
import '../application/tournament_providers.dart';
import '../domain/tournament_models.dart';
import 'bracket_view.dart';
import 'pair_picker_sheet.dart';
import 'tournament_match_sheet.dart';
import 'tournament_widgets.dart';

enum _Tab { info, teams, groups, bracket, matches }

/// Pantalla de un torneo: portada y datos, y pestañas Información · Parejas · Grupos/Clasificación · Cuadro · Partidos.
/// Se actualiza sola (Realtime) cuando la organización registra resultados o cambia algo, en cualquier dispositivo.
class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});
  final String tournamentId;
  @override
  ConsumerState<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends ConsumerState<TournamentDetailScreen> {
  _Tab? _tab;

  List<(_Tab, String)> _tabs(TournamentDetail d) => [
        (_Tab.info, 'Información'),
        (_Tab.teams, 'Parejas'),
        if (d.tournament.format.hasGroups) (_Tab.groups, d.tournament.format == TournamentFormat.roundRobin ? 'Clasificación' : 'Grupos'),
        if (d.tournament.format.hasBracket) (_Tab.bracket, 'Cuadro'),
        (_Tab.matches, 'Partidos'),
      ];

  _Tab _defaultTab(TournamentDetail d) => switch (d.tournament.format) {
        TournamentFormat.knockout => _Tab.bracket,
        TournamentFormat.roundRobin => _Tab.groups,
        TournamentFormat.groupsKnockout => d.groupsDone ? _Tab.bracket : _Tab.groups,
      };

  void _openMatch(TMatch m) => showTournamentMatch(context, widget.tournamentId, m);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tournamentDetailProvider(widget.tournamentId));
    return Scaffold(
      body: async.when(
        loading: () => const SafeArea(child: Center(child: CircularProgressIndicator(color: AppColors.text))),
        error: (e, _) => SafeArea(child: Column(children: [
          PlobbyHeaderBar(title: 'Torneo', onBack: () => context.pop()),
          Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(
              title: e is TournamentException && e.code == 'not_allowed' ? 'No tienes acceso a este torneo' : 'No se pudo cargar el torneo',
              onRetry: () => ref.invalidate(tournamentDetailProvider(widget.tournamentId)))),
        ])),
        data: (d) {
          final tab = _tab ?? _defaultTab(d);
          final t = d.tournament;
          final phase = phaseOf(t.status, t.startsOn);
          final where = [tournamentDates(t.startsOn, t.endsOn), if (t.location != null) t.location!].join(' · ');
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              TournamentCover(url: t.coverUrl, seed: t.id, height: 150 + MediaQuery.paddingOf(context).top, radius: 0),
              const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Color(0x80171C19), Color(0x00171C19), Color(0xB3171C19)])))),
              Positioned(left: 16, top: MediaQuery.paddingOf(context).top + 10, child: IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', glass: true, onPressed: () => context.pop())),
              Positioned(left: 20, right: 20, bottom: 14, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, children: [TournamentStatusPill(phase, onCover: true), if (d.isAdmin) const Pill('Organizas', tone: PillTone.lime, icon: PlobbyIcons.shield)]),
                const SizedBox(height: 8),
                Text(t.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 22, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.44, color: AppColors.surface)),
                const SizedBox(height: 4),
                Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, letterSpacing: 0, color: Color(0xDDF6F8F1))),
              ])),
            ]),
            // Pestañas desplazables (en móviles estrechos no caben todas).
            SizedBox(height: 56, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), children: [
              for (final (k, label) in _tabs(d)) Padding(padding: const EdgeInsets.only(right: 8), child: _TabChip(label: label, selected: tab == k, onTap: () => setState(() => _tab = k))),
            ])),
            Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: KeyedSubtree(key: ValueKey(tab), child: switch (tab) {
              _Tab.info => _InfoTab(d: d),
              _Tab.teams => _TeamsTab(d: d),
              _Tab.groups => _GroupsTab(d: d, onMatch: _openMatch),
              _Tab.bracket => _BracketTab(d: d, onMatch: _openMatch),
              _Tab.matches => _MatchesTab(d: d, onMatch: _openMatch),
            }))),
          ]);
        },
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});
  final String label; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(button: true, selected: selected, label: label, excludeSemantics: true, child: Pressable(child: Material(
        color: selected ? AppColors.inverse : AppColors.surface, shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.inverse : const Color(0x26171C19))),
        child: InkWell(customBorder: const StadiumBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(label, style: PlobbyText.tab.copyWith(color: selected ? AppColors.onInverse : AppColors.text)))),
      )));
}

// ─────────────────────────── Información ───────────────────────────
class _InfoTab extends ConsumerWidget {
  const _InfoTab({required this.d});
  final TournamentDetail d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = d.tournament;
    final champion = d.champion;
    final rows = <(PlobbyIcons, String, String)>[
      (PlobbyIcons.cal, 'Fechas', tournamentDates(t.startsOn, t.endsOn)),
      if (t.timeSlot != null) (PlobbyIcons.clock, 'Horario', t.timeSlot!),
      if (t.location != null) (PlobbyIcons.pin, 'Lugar', t.location!),
      (PlobbyIcons.trophy, 'Formato', t.format == TournamentFormat.groupsKnockout ? '${t.format.label} · ${t.groupsCount} grupos, pasan ${t.qualifiersPerGroup}' : t.format.label),
      (PlobbyIcons.users, 'Parejas', '${d.teams.length} de ${t.maxTeams}'),
      (PlobbyIcons.flag, 'Fase actual', d.currentPhase),
      if (t.organizerName.isNotEmpty) (PlobbyIcons.shield, 'Organiza', t.organizerName),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
      if (champion != null) AppearOnce(child: Container(
        margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rMd, boxShadow: const [BoxShadow(color: Color(0x55D2F548), blurRadius: 22, spreadRadius: -6)]),
        child: Row(children: [
          const PlobbyIcon(PlobbyIcons.trophy, size: 30, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CAMPEONES', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.47, color: Color(0x99F6F8F1))),
            const SizedBox(height: 4),
            TeamLine(team: champion, bold: true, size: 26, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.lime300)),
          ])),
        ]),
      )),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0x14171C19)))),
            child: Row(children: [
              PlobbyIcon(rows[i].$1, size: 17, color: AppColors.textMuted), const SizedBox(width: 10),
              SizedBox(width: 92, child: Text(rows[i].$2, style: PlobbyText.help)),
              Expanded(child: Text(rows[i].$3, style: PlobbyText.value)),
            ]),
          ),
        ]),
      ),
      if (t.description != null) ...[const SizedBox(height: 16), Text(t.description!, style: PlobbyText.desc)],
      if (d.isAdmin) ...[
        const SizedBox(height: 24),
        const Text('ORGANIZACIÓN', style: PlobbyText.eb),
        const SizedBox(height: 8),
        PlobbyButton(label: 'Editar información', icon: PlobbyIcons.edit, kind: PlobbyButtonKind.outline, onPressed: () => _editInfo(context, d)),
        const SizedBox(height: 8),
        PlobbyButton(label: 'Cambiar parejas', icon: PlobbyIcons.users, kind: PlobbyButtonKind.outline, onPressed: d.started ? null : () => _editTeams(context, d)),
        if (d.started) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Las parejas no se pueden cambiar cuando ya hay resultados.', style: PlobbyText.help)),
        const SizedBox(height: 8),
        Text('Los resultados se introducen tocando cada partido (en Cuadro, Grupos o Partidos). El torneo termina solo al decidirse la final.', style: PlobbyText.help),
      ],
    ]);
  }
}

Future<void> _editInfo(BuildContext context, TournamentDetail d) => showPlobbySheet<void>(context, (_) => _EditInfoSheet(d: d));

class _EditInfoSheet extends ConsumerStatefulWidget {
  const _EditInfoSheet({required this.d});
  final TournamentDetail d;
  @override
  ConsumerState<_EditInfoSheet> createState() => _EditInfoSheetState();
}

class _EditInfoSheetState extends ConsumerState<_EditInfoSheet> {
  late final _name = TextEditingController(text: widget.d.tournament.name);
  late final _desc = TextEditingController(text: widget.d.tournament.description ?? '');
  late final _slot = TextEditingController(text: widget.d.tournament.timeSlot ?? '');
  late final _loc = TextEditingController(text: widget.d.tournament.location ?? '');
  bool _busy = false; String? _error;
  @override
  void dispose() { for (final c in [_name, _desc, _slot, _loc]) { c.dispose(); } super.dispose(); }
  Future<void> _save() async {
    if (_name.text.trim().length < 3) { setState(() => _error = 'El nombre necesita al menos 3 letras.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(tournamentDetailProvider(widget.d.tournament.id).notifier).updateInfo({
        'name': _name.text.trim(), 'description': _desc.text.trim(), 'time_slot': _slot.text.trim(), 'location': _loc.text.trim()});
      if (!mounted) return;
      Navigator.pop(context);
      showPlobbySnack(context, 'Información actualizada');
    } on TournamentException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    }
  }
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Editar información'),
        LabeledField(label: 'Nombre', controller: _name, maxLength: 60, error: _error),
        LabeledField(label: 'Descripción', controller: _desc, maxLength: 500, maxLines: 3),
        LabeledField(label: 'Horario', controller: _slot, maxLength: 60),
        LabeledField(label: 'Lugar', controller: _loc, maxLength: 120),
        PlobbyButton(label: 'Guardar', busy: _busy, onPressed: _save),
      ]);
}

Future<void> _editTeams(BuildContext context, TournamentDetail d) => showPlobbySheet<void>(context, (_) => _EditTeamsSheet(d: d));

/// Cambiar parejas antes de empezar: quitar o añadir; al guardar se regenera el cuadro (el servidor lo rechaza si
/// mientras tanto se registró algún resultado).
class _EditTeamsSheet extends ConsumerStatefulWidget {
  const _EditTeamsSheet({required this.d});
  final TournamentDetail d;
  @override
  ConsumerState<_EditTeamsSheet> createState() => _EditTeamsSheetState();
}

class _EditTeamsSheetState extends ConsumerState<_EditTeamsSheet> {
  late List<(TPlayer, TPlayer)> _teams = [for (final t in widget.d.teams) (t.p1, t.p2)];
  bool _busy = false; String? _error;
  @override
  Widget build(BuildContext context) {
    final used = {for (final t in _teams) ...[t.$1.id, t.$2.id]};
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(title: 'Cambiar parejas', subtitle: '${_teams.length} de ${widget.d.tournament.maxTeams} parejas. Al guardar se rehace el cuadro.'),
      ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: ListView(shrinkWrap: true, children: [
        for (var i = 0; i < _teams.length; i++) Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14171C19)))),
          child: Row(children: [
            SizedBox(width: 26, child: Text('${i + 1}', style: PlobbyText.value)),
            Expanded(child: TeamLine(team: TTeam(id: '$i', seed: i + 1, p1: _teams[i].$1, p2: _teams[i].$2), size: 26)),
            IconButton(tooltip: 'Quitar pareja ${i + 1}', onPressed: () => setState(() => _teams = [..._teams]..removeAt(i)), icon: const PlobbyIcon(PlobbyIcons.close, size: 18, color: AppColors.textMuted)),
          ]),
        ),
      ])),
      const SizedBox(height: 8),
      PlobbyButton(label: 'Añadir pareja', icon: PlobbyIcons.userplus, kind: PlobbyButtonKind.outline, onPressed: _teams.length >= widget.d.tournament.maxTeams ? null : () async {
        final r = await showPairPicker(context, used: used);
        if (r != null && mounted) setState(() => _teams = [..._teams, r]);
      }),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: PlobbyText.help.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600))),
      const SizedBox(height: 10),
      PlobbyButton(label: 'Guardar y rehacer cuadro', busy: _busy, onPressed: () async {
        final err = validateTournamentFormat(TournamentDraft(teams: _teams, maxTeams: widget.d.tournament.maxTeams, format: widget.d.tournament.format,
            groupsCount: widget.d.tournament.groupsCount, qualifiersPerGroup: widget.d.tournament.qualifiersPerGroup));
        if (err != null) { setState(() => _error = err); return; }
        setState(() { _busy = true; _error = null; });
        try {
          await ref.read(tournamentDetailProvider(widget.d.tournament.id).notifier).replaceTeams(_teams);
          if (!context.mounted) return;
          Navigator.pop(context);
          showPlobbySnack(context, 'Parejas actualizadas y cuadro rehecho');
        } on TournamentException catch (e) {
          if (mounted) setState(() { _busy = false; _error = e.message; });
        }
      }),
    ]);
  }
}

// ─────────────────────────── Parejas ───────────────────────────
class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.d});
  final TournamentDetail d;
  @override
  Widget build(BuildContext context) {
    final teams = [...d.teams]..sort((a, b) => a.seed.compareTo(b.seed));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
      Text('${teams.length} PAREJAS · ${teams.length * 2} JUGADORES', style: PlobbyText.eb),
      const SizedBox(height: 8),
      for (final t in teams) Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card,
            border: d.myTeam?.id == t.id ? Border.all(color: AppColors.brand, width: 2) : null),
        child: Row(children: [
          Container(width: 32, height: 32, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(9)),
              child: Text('${t.seed}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final p in [t.p1, t.p2]) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: InkWell(onTap: () => context.push('/player/${p.id}'), child: Row(children: [
              TPlayerAvatar(p, size: 28), const SizedBox(width: 8),
              Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.value)),
            ]))),
          ])),
          if (t.groupLabel != null && d.tournament.format == TournamentFormat.groupsKnockout) Pill('Grupo ${t.groupLabel}', tone: PillTone.neutral),
          if (d.myTeam?.id == t.id) const Padding(padding: EdgeInsets.only(left: 6), child: Pill('Tu pareja', tone: PillTone.lime)),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────── Grupos / clasificación ───────────────────────────
class _GroupsTab extends StatelessWidget {
  const _GroupsTab({required this.d, required this.onMatch});
  final TournamentDetail d;
  final ValueChanged<TMatch> onMatch;
  @override
  Widget build(BuildContext context) {
    final q = d.tournament.format == TournamentFormat.groupsKnockout ? d.tournament.qualifiersPerGroup : 1;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
      for (final g in d.groupLabels) ...[
        if (d.tournament.format == TournamentFormat.groupsKnockout) Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text('Grupo $g', style: PlobbyText.t2)),
        _StandingsTable(d: d, group: g, qualifiers: q),
        const SizedBox(height: 12),
        for (final m in d.groupMatches(g)) _MatchRow(d: d, m: m, onTap: () => onMatch(m)),
        const SizedBox(height: 18),
      ],
    ]);
  }
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.d, required this.group, required this.qualifiers});
  final TournamentDetail d; final String group; final int qualifiers;
  @override
  Widget build(BuildContext context) {
    final rows = d.standingsOf(group);
    const h = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: AppColors.textMuted);
    const c = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text);
    Widget num(String s, {bool bold = false}) => SizedBox(width: 30, child: Text(s, textAlign: TextAlign.center, style: bold ? c.copyWith(fontWeight: FontWeight.w800) : c));
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), child: Row(children: [
          const SizedBox(width: 22), const Expanded(child: Text('PAREJA', style: h)),
          for (final x in ['PJ', 'G', 'P', '±S']) SizedBox(width: 30, child: Text(x, textAlign: TextAlign.center, style: h)),
          const SizedBox(width: 30, child: Text('PTS', textAlign: TextAlign.center, style: h)),
        ])),
        for (final s in rows) Semantics(container: true, label: '${s.pos}.º ${d.team(s.teamId)?.name}: ${s.played} jugados, ${s.won} ganados, ${s.lost} perdidos, ${s.points} puntos', excludeSemantics: true,
          child: AnimatedContainer(duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: d.myTeam?.id == s.teamId ? AppColors.brandSoft : null,
              border: const Border(top: BorderSide(color: Color(0x14171C19))),
            ),
            child: Row(children: [
              Container(width: 4, height: 22, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: s.pos <= qualifiers ? AppColors.brand : Colors.transparent, borderRadius: BorderRadius.circular(2))),
              SizedBox(width: 12, child: Text('${s.pos}', style: c.copyWith(fontWeight: FontWeight.w800))),
              Expanded(child: TeamLine(team: d.team(s.teamId), size: 20, style: c.copyWith(fontSize: 12.5))),
              num('${s.played}'), num('${s.won}'), num('${s.lost}'), num('${s.setDiff > 0 ? '+' : ''}${s.setDiff}'), num('${s.points}', bold: true),
            ]),
          )),
        if (qualifiers > 0 && d.tournament.format == TournamentFormat.groupsKnockout)
          Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 10), child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 6),
            Text('Pasan a la eliminatoria', style: PlobbyText.help.copyWith(fontSize: 11.5)),
          ]))
        else const SizedBox(height: 6),
      ]),
    );
  }
}

// ─────────────────────────── Cuadro ───────────────────────────
class _BracketTab extends StatelessWidget {
  const _BracketTab({required this.d, required this.onMatch});
  final TournamentDetail d;
  final ValueChanged<TMatch> onMatch;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (d.tournament.format == TournamentFormat.groupsKnockout && !d.groupsDone)
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 6), child: Text('Los cruces se completan solos cuando terminen los grupos.', style: PlobbyText.help)),
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 6), child: Row(children: [
          const PlobbyIcon(PlobbyIcons.search, size: 13, color: AppColors.textMuted), const SizedBox(width: 6),
          Expanded(child: Text('Desliza para recorrer las rondas y pellizca para acercar.', style: PlobbyText.help.copyWith(fontSize: 11.5))),
        ])),
        Expanded(child: ClipRect(child: BracketView(detail: d, onMatch: onMatch))),
      ]);
}

// ─────────────────────────── Partidos ───────────────────────────
class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.d, required this.onMatch});
  final TournamentDetail d;
  final ValueChanged<TMatch> onMatch;
  @override
  Widget build(BuildContext context) {
    int order(TMatch a, TMatch b) => a.stage != b.stage ? (a.stage == MatchStage.group ? -1 : 1) : a.round != b.round ? a.round.compareTo(b.round) : a.position.compareTo(b.position);
    final all = d.matches.where((m) => m.status != TMatchStatus.bye).toList()..sort(order);
    final live = all.where((m) => m.status == TMatchStatus.live).toList();
    final next = all.where((m) => m.status == TMatchStatus.pending && m.ready).toList();
    final waiting = all.where((m) => m.status == TMatchStatus.pending && !m.ready).toList();
    final played = all.where((m) => m.finished).toList().reversed.toList();
    Widget section(String title, List<TMatch> l) => l.isEmpty ? const SizedBox.shrink() : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text('${title.toUpperCase()} · ${l.length}', style: PlobbyText.eb)),
          for (final m in l) _MatchRow(d: d, m: m, onTap: () => onMatch(m)),
        ]);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
      section('En juego', live), section('Próximos', next), section('Jugados', played), section('Por decidir', waiting),
      if (all.isEmpty) const Padding(padding: EdgeInsets.only(top: 20), child: Text('Aún no hay partidos.', style: PlobbyText.help)),
    ]);
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.d, required this.m, required this.onTap});
  final TournamentDetail d; final TMatch m; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final mine = d.myTeam != null && m.involves(d.myTeam!.id);
    Widget side(int slot) {
      final t = d.team(slot == 1 ? m.team1Id : m.team2Id);
      final won = m.finished && m.winnerTeamId == t?.id;
      return Row(children: [
        Expanded(child: TeamLine(team: t, emptyLabel: d.slotLabel(m, slot), bold: won, muted: m.finished && !won, size: 20)),
        if (m.sets != null) for (final s in m.sets!) SizedBox(width: 18, child: Text('${slot == 1 ? s.$1 : s.$2}', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0,
                color: (slot == 1 ? s.$1 > s.$2 : s.$2 > s.$1) ? AppColors.text : AppColors.textMuted))),
      ]);
    }
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Semantics(button: true, container: true,
      label: '${d.matchLabel(m)}: ${d.team(m.team1Id)?.name ?? d.slotLabel(m, 1)} contra ${d.team(m.team2Id)?.name ?? d.slotLabel(m, 2)}. ${m.finished ? 'Resultado ${m.score}' : m.status.label}',
      excludeSemantics: true,
      child: Material(color: AppColors.surface, borderRadius: AppRadius.rMd, clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(borderRadius: AppRadius.rMd, boxShadow: AppShadows.card,
            border: Border(left: BorderSide(color: m.status == TMatchStatus.live ? const Color(0xFF1FA463) : mine ? AppColors.brand : Colors.transparent, width: 4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(d.matchLabel(m).toUpperCase(), style: PlobbyText.eb.copyWith(fontSize: 9.5))),
            if (m.status == TMatchStatus.live) const Text('EN JUEGO', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: Color(0xFF1FA463))),
            if (d.isAdmin && m.ready && !m.finished) const PlobbyIcon(PlobbyIcons.edit, size: 13, color: AppColors.textMuted),
          ]),
          const SizedBox(height: 6),
          side(1), const SizedBox(height: 4), side(2),
        ]),
      ))),
    ));
  }
}
