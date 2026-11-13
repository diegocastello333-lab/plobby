import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/tournament_providers.dart';
import '../domain/tournament_models.dart';
import 'tournament_widgets.dart';

/// Hoja de un partido: parejas, resultado y estado. La organización puede registrar, corregir o anular el resultado y
/// marcarlo «en juego». Los participantes solo lo consultan.
Future<void> showTournamentMatch(BuildContext context, String tournamentId, TMatch m) =>
    showPlobbySheet<void>(context, (_) => _MatchSheet(tournamentId: tournamentId, matchId: m.id));

class _MatchSheet extends ConsumerStatefulWidget {
  const _MatchSheet({required this.tournamentId, required this.matchId});
  final String tournamentId, matchId;
  @override
  ConsumerState<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends ConsumerState<_MatchSheet> {
  final _c = List.generate(3, (_) => [TextEditingController(), TextEditingController()]);
  bool _editing = false, _busy = false;
  String? _error;

  @override
  void dispose() { for (final r in _c) { for (final x in r) { x.dispose(); } } super.dispose(); }

  List<(int, int)> get _sets => [
        for (final r in _c)
          if (r[0].text.isNotEmpty || r[1].text.isNotEmpty) (int.tryParse(r[0].text) ?? -1, int.tryParse(r[1].text) ?? -1),
      ];

  void _startEdit(TMatch m) {
    for (var i = 0; i < 3; i++) {
      final s = (m.sets != null && i < m.sets!.length) ? m.sets![i] : null;
      _c[i][0].text = s == null ? '' : '${s.$1}';
      _c[i][1].text = s == null ? '' : '${s.$2}';
    }
    setState(() { _editing = true; _error = null; });
  }

  Future<void> _run(Future<void> Function() job, String ok) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await job();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.pop(context);
      showPlobbySnack(context, ok);
    } on TournamentException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; if (e.code == 'result_conflict') _editing = false; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'Sin conexión. Comprueba tu red e inténtalo de nuevo.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tournamentDetailProvider(widget.tournamentId));
    final d = async.valueOrNull;
    final m = d?.matches.where((x) => x.id == widget.matchId).firstOrNull;
    if (d == null || m == null) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.text)));
    final n = ref.read(tournamentDetailProvider(widget.tournamentId).notifier);
    final t1 = d.team(m.team1Id), t2 = d.team(m.team2Id);
    final sets = _sets;
    final err = sets.isEmpty ? null : validateTournamentSets(sets);
    final winner = sets.isEmpty || err != null ? null : (setsWinner(sets) == 1 ? t1 : t2);
    final next = m.nextMatchId == null ? null : d.matches.where((x) => x.id == m.nextMatchId).firstOrNull;
    final affectsLater = m.finished && next != null && (next.finished || next.status == TMatchStatus.live);

    Widget teamRow(TTeam? t, int slot) {
      final won = m.winnerTeamId != null && m.winnerTeamId == t?.id && m.finished;
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        Expanded(child: TeamLine(team: t, emptyLabel: m.status == TMatchStatus.bye && t == null ? 'Pasa directo' : d.slotLabel(m, slot), bold: won, size: 30,
            style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, letterSpacing: 0, fontWeight: won ? FontWeight.w800 : FontWeight.w600, color: AppColors.text))),
        if (m.sets != null) for (final s in m.sets!) SizedBox(width: 22, child: Text('${slot == 1 ? s.$1 : s.$2}', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0,
                color: (slot == 1 ? s.$1 > s.$2 : s.$2 > s.$1) ? AppColors.text : AppColors.textMuted))),
      ]));
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(title: d.matchLabel(m), subtitle: switch (m.status) {
        TMatchStatus.finished => 'Finalizado · ${m.score}',
        TMatchStatus.live => 'En juego',
        TMatchStatus.bye => 'Pasa directo a la siguiente ronda',
        TMatchStatus.pending => m.ready ? 'Pendiente de jugar' : 'Esperando a que se decidan las parejas',
      }),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: Column(children: [teamRow(t1, 1), Container(height: 1, color: const Color(0x14171C19)), teamRow(t2, 2)]),
      ),
      if (next != null && m.stage == MatchStage.knockout) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
        const PlobbyIcon(PlobbyIcons.arrup, size: 14, color: AppColors.textMuted), const SizedBox(width: 6),
        Expanded(child: Text('El ganador pasa a ${d.matchLabel(next).toLowerCase()}.', style: PlobbyText.help)),
      ])),
      if (d.isAdmin && m.ready) ...[
        const SizedBox(height: 16),
        if (_editing) ...[
          Text(m.finished ? 'CORREGIR RESULTADO' : 'RESULTADO POR SETS', style: PlobbyText.eb),
          const SizedBox(height: 8),
          Row(children: [const Spacer(), for (final t in [t1, t2]) SizedBox(width: 80, child: Text(t?.p1.short ?? '', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.help.copyWith(fontSize: 11.5)))]),
          for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
            Expanded(child: Text(i == 2 ? 'Set 3 (si hace falta)' : 'Set ${i + 1}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text))),
            for (var j = 0; j < 2; j++) Padding(padding: const EdgeInsets.only(left: 8), child: SizedBox(width: 72, height: 44, child: Semantics(label: 'Set ${i + 1}, pareja ${j + 1}', textField: true, child: TextField(
              controller: _c[i][j], keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
              textAlign: TextAlign.center, style: PlobbyText.input, onChanged: (_) => setState(() => _error = null),
              decoration: plobbyInputDecoration(hint: '–', padding: EdgeInsets.zero))))),
          ])),
          const SizedBox(height: 10),
          if (winner != null) Row(children: [const PlobbyIcon(PlobbyIcons.trophy, size: 15), const SizedBox(width: 6), Expanded(child: Text('Gana ${winner.name}', style: PlobbyText.value))])
          else if (err != null) Text(err, style: PlobbyText.help.copyWith(color: AppColors.danger)),
          if (affectsLater) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Si cambia el ganador, se anularán los partidos posteriores en los que jugaba.', style: PlobbyText.help)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 10, child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: _busy ? null : () => setState(() => _editing = false))),
            const SizedBox(width: 10),
            Expanded(flex: 16, child: PlobbyButton(label: 'Guardar resultado', busy: _busy, onPressed: winner == null ? null : () => _run(() => n.record(m, sets), 'Resultado guardado'))),
          ]),
        ] else ...[
          PlobbyButton(label: m.finished ? 'Corregir resultado' : 'Introducir resultado', icon: PlobbyIcons.edit, onPressed: () => _startEdit(m)),
          const SizedBox(height: 8),
          if (!m.finished) PlobbyButton(label: m.status == TMatchStatus.live ? 'Quitar «en juego»' : 'Marcar «en juego»', kind: PlobbyButtonKind.outline, icon: PlobbyIcons.play, busy: _busy,
              onPressed: () => _run(() => n.setLive(m, m.status != TMatchStatus.live), m.status == TMatchStatus.live ? 'Partido pendiente' : 'Partido en juego')),
          if (m.finished) PlobbyButton(label: 'Anular resultado', kind: PlobbyButtonKind.danger, busy: _busy, onPressed: () => _run(() => n.clear(m), 'Resultado anulado')),
        ],
      ],
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: PlobbyText.help.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600))),
      const SizedBox(height: 4),
    ]);
  }
}
