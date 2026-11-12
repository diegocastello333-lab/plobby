import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/lifecycle_providers.dart';
import '../data/lifecycle_repository.dart';
import '../domain/match_lifecycle.dart';
import '../../rating/domain/elo_calculator.dart';
import '../domain/match_models.dart';
import 'edit_match_sheet.dart';
import 'match_widgets.dart';

String errorText(Object e) => switch (e is LifecycleException ? e.code : '') {
      'stale_version' => 'El resultado cambió: revisa la nueva versión antes de aceptar.',
      'only_captains_can_confirm' => 'Solo los capitanes pueden confirmar el resultado.',
      'league_rule_players_locked' => 'Regla de liga: no se pueden cambiar jugadores a menos de 2 h del inicio.',
      'league_rule_delete_locked' => 'Regla de liga: no se puede eliminar a menos de 2 h del inicio.',
      'not_a_participant' => 'No participas en este partido.',
      _ => 'No se pudo completar la acción. Comprueba tu conexión.',
    };

String _hms(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

/// Duración legible (`durTxt` del prototipo): «47 min», «1 h 05 min».
String durationText(int seconds) {
  final m = seconds ~/ 60;
  return m >= 60 ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min' : '$m min';
}

/// Detalle del partido — `scMDetail` del prototipo HTML. Todos los participantes ven lo mismo (Realtime vía `matchProvider`).
/// Sin cambios de comportamiento: mismas acciones y permisos ([MatchPerms]); los diálogos pasan a hojas inferiores como en el HTML.
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final String matchId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(matchProvider(matchId)); final uid = ref.watch(currentUserIdProvider);
    final m = async.valueOrNull;
    return Scaffold(
      body: Column(children: [
        PlobbyHeaderBar(
          title: 'Detalle del partido',
          onBack: () => context.pop(),
          trailing: m != null && MatchPerms(m, uid).canEdit ? IconSquareButton(icon: PlobbyIcons.more, tooltip: 'Más opciones', onPressed: () => _showOptions(context, ref, m)) : null,
        ),
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(message: 'No se pudo cargar el partido.', onRetry: () => ref.invalidate(matchProvider(matchId)))),
          data: (m) => m == null
              ? const Padding(padding: EdgeInsets.all(20), child: EmptyStateCard(icon: Icons.sports_tennis, title: 'Este partido ya no existe', text: 'Puede que se haya eliminado.'))
              : _Body(m: m, uid: uid),
        )),
      ]),
    );
  }
}

/// `ACT.mmenu`: «Opciones del partido» con Editar / Eliminar.
void _showOptions(BuildContext context, WidgetRef ref, LifecycleMatch m) => showPlobbySheet(context, (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      const SheetHeader(title: 'Opciones del partido'),
      SheetListItem(icon: PlobbyIcons.edit, label: 'Editar partido', onTap: () { Navigator.pop(ctx); showEditMatchSheet(context, m); }),
      SheetListItem(icon: PlobbyIcons.trash, label: 'Eliminar partido', onTap: () { Navigator.pop(ctx); _confirmDelete(context, ref, m); }),
    ]));

Future<void> _confirmDelete(BuildContext context, WidgetRef ref, LifecycleMatch m) async {
  final ok = await showPlobbySheet<bool>(context, (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: '¿Eliminar este partido?'),
        Text('${formatWhen(m.scheduledAt)} · ${m.club}. Los otros tres jugadores recibirán un aviso. Esta acción no se puede deshacer.', style: PlobbyText.sub),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(ctx, false))),
          const SizedBox(width: 10),
          Expanded(child: PlobbyButton(label: 'Eliminar', kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(ctx, true))),
        ]),
      ]));
  if (ok != true) return;
  try { await ref.read(lifecycleActionsProvider).cancel(m.id); if (context.mounted) { showPlobbySnack(context, 'Partido eliminado'); context.pop(); } }
  catch (e) { if (context.mounted) showPlobbySnack(context, errorText(e), error: true); }
}

class _Body extends ConsumerWidget {
  const _Body({required this.m, required this.uid});
  final LifecycleMatch m; final String uid;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = MatchPerms(m, uid), act = ref.read(lifecycleActionsProvider);
    void snack(String t, {bool error = false}) => showPlobbySnack(context, t, error: error);
    Future<void> run(Future<void> Function() f) async { try { await f(); } catch (e) { if (context.mounted) snack(errorText(e), error: true); } }
    final w = m.winnerTeam;
    Widget cta(Widget button, [String? help]) => Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Column(children: [
          button,
          if (help != null) Padding(padding: const EdgeInsets.only(top: 10), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 300),
              child: Text(help, textAlign: TextAlign.center, style: PlobbyText.help.copyWith(fontSize: 12)))),
        ]));
    return ListView(padding: EdgeInsets.fromLTRB(20, 16, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
      _Hero(m: m),
      const SizedBox(height: 12),
      MatchStepper(status: m.status),
      const SizedBox(height: 14),
      if (m.status == MatchStatus.live) _TimerCard(m: m, title: 'Cronómetro oficial · hora del servidor')
      else if (m.durationSeconds != null) _TimerCard(m: m, title: 'Duración total'),
      if (m.sets.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: ScoreBoard(match: m)),
      for (final t in [1, 2]) Padding(padding: const EdgeInsets.only(bottom: 10), child: TeamCard(match: m, team: t, winner: w == t, uid: uid)),
      const SizedBox(height: 2),
      const _CaptainHelp(),
      const SizedBox(height: 14),
      if (m.status == MatchStatus.pendingConfirmation || m.status == MatchStatus.disputed) _ConfirmationCard(m: m, perms: perms, run: run, act: act),
      // Acciones del ciclo (`ctaHtml` del prototipo)
      if (m.status == MatchStatus.scheduled && perms.canStart) cta(
          MatchCtaButton(label: 'EMPEZAR PARTIDO', icon: PlobbyIcons.play, onTap: () => run(() async { final r = await act.start(m.id); snack(r.started ? '¡Partido iniciado! Cronómetro en marcha para los cuatro.' : 'El partido ya estaba iniciado: se mantiene la hora oficial.'); })),
          'Se guarda la hora oficial de inicio del servidor y el cronómetro se activa para los cuatro jugadores.'),
      if (m.status == MatchStatus.live && perms.canFinish) cta(MatchCtaButton(label: 'FINALIZAR PARTIDO', icon: PlobbyIcons.stopi, dark: true, onTap: () => run(() async {
        final clock = ref.read(serverClockProvider).valueOrNull ?? ServerClock();
        final ok = await showPlobbySheet<bool>(context, (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SheetHeader(title: '¿Finalizar el partido?'),
              Text('Se guardará la hora de fin del servidor y la duración total (${durationText(elapsedOf(m, clock).inSeconds)} hasta ahora). Después podréis introducir el resultado.', style: PlobbyText.sub),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: PlobbyButton(label: 'Seguir jugando', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(child: PlobbyButton(label: 'Finalizar', onPressed: () => Navigator.pop(ctx, true))),
              ]),
            ]));
        if (ok != true) return;
        await act.finish(m.id);
        if (context.mounted) context.push('/match/${m.id}/result');        // abre automáticamente la pantalla de resultado
      }))),
      if (m.status == MatchStatus.pendingResult && perms.canSubmitResult) cta(
          MatchCtaButton(label: 'Introducir resultado', onTap: () => context.push('/match/${m.id}/result')),
          'Hasta que los dos capitanes lo confirmen, no cuenta para ELO, estadísticas, racha ni clasificación.'),
      if (m.status == MatchStatus.confirmed) Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Column(children: [
        PlobbyButton(label: 'Ver resultado final', onPressed: () => context.push('/match/${m.id}/final')),
        if (m.bothCaptainsAccepted && m.player(uid) != null) Padding(padding: const EdgeInsets.only(top: 10),
            child: PlobbyButton(label: 'Compartir resultado', icon: PlobbyIcons.share, kind: PlobbyButtonKind.outline, onPressed: () => context.push('/match/${m.id}/share'))),
      ])),
      if (m.status == MatchStatus.scheduled) Padding(padding: const EdgeInsets.only(top: 6, bottom: 16), child: perms.canEdit
          ? Row(children: [
              Expanded(child: PlobbyButton(label: 'Editar partido', icon: PlobbyIcons.edit, kind: PlobbyButtonKind.outline, onPressed: () => showEditMatchSheet(context, m))),
              const SizedBox(width: 10),
              Expanded(child: PlobbyButton(label: 'Eliminar partido', icon: PlobbyIcons.trash, kind: PlobbyButtonKind.danger, onPressed: () => _confirmDelete(context, ref, m))),
            ])
          : Text('Solo quien creó el partido puede editarlo o eliminarlo.', style: PlobbyText.help.copyWith(fontSize: 12))),
      if (m.events.isNotEmpty) MatchEventLog(m: m),
    ]);
  }
}

/// `.md-hero`: tarjeta tinta radio 22 con aro decorativo lima (140 px, 1.5 px al 25 %) en la esquina.
class _Hero extends StatelessWidget {
  const _Hero({required this.m});
  final LifecycleMatch m;
  static const _soft = Color(0xC7FFFFFF);   // rgba(255,255,255,.78)
  @override
  Widget build(BuildContext context) {
    final league = m.type == MatchType.league;
    Widget line(PlobbyIcons i, String t) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
          PlobbyIcon(i, size: 14, color: _soft), const SizedBox(width: 7),
          Expanded(child: Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, height: 16 / 13.5, letterSpacing: 0, color: _soft))),
        ]));
    return ClipRRect(borderRadius: AppRadius.rLg, child: Container(
      color: AppColors.inverse,
      child: Stack(children: [
        Positioned(right: -40, top: -40, child: IgnorePointer(child: Container(width: 140, height: 140,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x40D2F548), width: 1.5))))),
        Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusChip(status: m.status),
            Row(mainAxisSize: MainAxisSize.min, children: [
              PlobbyIcon(league ? PlobbyIcons.trophy : PlobbyIcons.racket, size: 13, color: const Color(0xBFFFFFFF)), const SizedBox(width: 6),
              Text(league ? 'Liga' : 'Amistoso', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0, color: Color(0xBFFFFFFF))),
            ]),
          ]),
          const SizedBox(height: 12),
          Text(formatWhen(m.scheduledAt), style: const TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, fontSize: 22, height: 27 / 22, letterSpacing: -0.44, color: Colors.white)),
          const SizedBox(height: 8),
          line(PlobbyIcons.pin, '${m.club}${m.court != null && m.court!.isNotEmpty ? ' · ${m.court}' : ''}'),
          if (m.leagueName != null) line(PlobbyIcons.trophy, m.leagueName!),
        ])),
      ]),
    ));
  }
}

/// `.md-tm`: cronómetro oficial (en juego) o duración total (finalizado). Inter/Unbounded 44/600 con cifras tabulares.
class _TimerCard extends StatelessWidget {
  const _TimerCard({required this.m, required this.title});
  final LifecycleMatch m; final String title;
  @override
  Widget build(BuildContext context) {
    final live = m.status == MatchStatus.live;
    final starter = m.startedBy == null ? null : m.player(m.startedBy!);
    final sub = m.startedAt == null ? null
        : live ? 'Inicio ${_hms(m.startedAt!)}${starter != null ? ' · lo inició ${starter.name.split(' ').first}' : ''}'
        : '${_hms(m.startedAt!)}${m.endedAt != null ? ' – ${_hms(m.endedAt!)}' : ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), width: double.infinity,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Text(title.toUpperCase(), textAlign: TextAlign.center, style: PlobbyText.eb),
        const SizedBox(height: 6),
        if (live) MatchStopwatch(match: m)
        else Text(durationText(m.durationSeconds ?? 0), style: const TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, fontSize: 44, height: 55 / 44, letterSpacing: -0.88, color: AppColors.text)),
        const SizedBox(height: 2),
        if (sub != null) Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 15 / 12, letterSpacing: 0, color: AppColors.textMuted)),
      ]),
    );
  }
}

/// `p.help` con icono de información: qué significa la «C».
class _CaptainHelp extends StatelessWidget {
  const _CaptainHelp();
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 1, right: 4), child: PlobbyIcon(PlobbyIcons.info, size: 13, color: AppColors.textMuted)),
        Expanded(child: Text.rich(TextSpan(style: PlobbyText.help.copyWith(fontSize: 12), children: const [
          TextSpan(text: 'C', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' = capitán. Si no se designa otro, lo es el primer jugador de cada equipo.'),
        ]))),
      ]);
}

/// Confirmación de los DOS capitanes (`confBox`). «Aceptar» envía la versión que ve el capitán; el servidor la compara con la vigente.
class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({required this.m, required this.perms, required this.run, required this.act});
  final LifecycleMatch m; final MatchPerms perms; final Future<void> Function(Future<void> Function()) run; final LifecycleActions act;
  @override
  Widget build(BuildContext context) {
    final dis = m.status == MatchStatus.disputed, acc = m.acceptedTeams;
    Widget row(int t) {
      final c = m.captainOf(t); final ok = acc.contains(t);
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? AppColors.brand : null, border: ok ? null : Border.all(color: AppColors.borderStrong, width: 2)),
            child: ok ? const Center(child: PlobbyIcon(PlobbyIcons.check, size: 14, strokeWidth: 3, color: AppColors.brandInk)) : null),
        const SizedBox(width: 10),
        Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, letterSpacing: 0, color: AppColors.text), children: [
          TextSpan(text: 'Capitán equipo $t', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' · ${c?.name.split(' ').first ?? '—'}'),
        ]), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(ok ? 'Aceptado' : 'Pendiente', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.textMuted)),
      ]));
    }
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: dis ? AppColors.danger : AppColors.border, width: dis ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(dis ? 'RESULTADO EN DISPUTA' : 'CONFIRMACIÓN DE CAPITANES · VERSIÓN ${m.resultVersion}', style: PlobbyText.eb.copyWith(color: dis ? AppColors.danger : null)),
          const SizedBox(height: 10), ScoreBoard(match: m), const SizedBox(height: 10),
          if (!dis) _EloEstimate(m: m, uid: perms.uid),
          if (dis) Text('Un capitán rechazó el resultado${m.rejectionReason != null && m.rejectionReason!.isNotEmpty ? ': «${m.rejectionReason}»' : ''}. Corregidlo y se volverá a pedir la confirmación a los dos capitanes.',
              style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.45, letterSpacing: 0, color: AppColors.text))
          else ...[row(1), row(2)],
          if (perms.canConfirm || perms.canSubmitResult) const SizedBox(height: 10),
          if (perms.canConfirm) ...[
            PlobbyButton(label: 'Aceptar resultado', onPressed: () => run(() async { final s = await act.respond(m.id, m.resultVersion, accept: true); if (context.mounted) showPlobbySnack(context, s == MatchStatus.confirmed ? 'Resultado confirmado. ELO y estadísticas actualizados.' : 'Has aceptado. Falta el otro capitán.'); })),
            const SizedBox(height: 8),
            PlobbyButton(label: 'Rechazar', kind: PlobbyButtonKind.danger, onPressed: () => _reject(context)),
          ],
          if (perms.canSubmitResult) Padding(padding: EdgeInsets.only(top: perms.canConfirm ? 8 : 0),
              child: PlobbyButton(label: dis ? 'Corregir resultado' : 'Proponer corrección', kind: PlobbyButtonKind.outline, onPressed: () => context.push('/match/${m.id}/result'))),
          if (!perms.canConfirm && !dis && perms.isParticipant) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Solo los capitanes pueden aceptar o rechazar. Cualquier corrección invalida las aceptaciones.', style: PlobbyText.help.copyWith(fontSize: 12))),
        ]));
  }

  /// `ACT.mrej`: hoja «Rechazar resultado» con motivo opcional (máx. 200). Devuelve el motivo o null si se cancela.
  Future<void> _reject(BuildContext context) async {
    final reason = await showPlobbySheet<String>(context, (_) => const _RejectSheet());
    if (reason != null) await run(() async { await act.respond(m.id, m.resultVersion, accept: false, reason: reason); });
  }
}

/// Contenido de la hoja de rechazo. Es dueña de su controlador, que se libera al cerrarse la hoja (no antes).
class _RejectSheet extends StatefulWidget {
  const _RejectSheet();
  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _ctl = TextEditingController();
  @override
  void dispose() { _ctl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Rechazar resultado'),
        const Text('El partido pasará a «En disputa».', style: PlobbyText.sub),
        const SizedBox(height: 12),
        LabeledField(label: 'Motivo (opcional)', controller: _ctl, maxLength: 200, maxLines: 3, hint: 'p. ej. el segundo set terminó 6-3'),
        Row(children: [
          Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(child: PlobbyButton(label: 'Rechazar', kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(context, _ctl.text))),
        ]),
      ]);
}

/// Estimación del cambio de ELO si se confirma la versión vigente (misma fórmula que el servidor, [EloCalculator]).
/// Solo informativa: el ELO real lo escribe `apply_match_rating` al confirmar.
class _EloEstimate extends StatelessWidget {
  const _EloEstimate({required this.m, required this.uid});
  final LifecycleMatch m; final String uid;
  @override
  Widget build(BuildContext context) {
    final me = m.player(uid);
    if (me == null || m.winnerTeam == null || m.players.any((p) => p.elo <= 0)) return const SizedBox.shrink();
    final d = const EloCalculator().deltas(team1: {for (final p in m.team(1)) p.id: p.elo}, team2: {for (final p in m.team(2)) p.id: p.elo}, winnerTeam: m.winnerTeam)[uid] ?? 0;
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Si se confirma: ${d > 0 ? '+' : ''}$d ELO para ti (estimación)',
        style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0, color: d >= 0 ? AppColors.success : AppColors.danger)));
  }
}

/// `.md-log`: «Historial de cambios (n)» plegable (blanca, radio 14, borde 1 px, Inter 12.5).
class MatchEventLog extends StatefulWidget {
  const MatchEventLog({super.key, required this.m});
  final LifecycleMatch m;
  @override
  State<MatchEventLog> createState() => _MatchEventLogState();
}

class _MatchEventLogState extends State<MatchEventLog> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    const base = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, height: 1.35, letterSpacing: 0, color: AppColors.text);
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(button: true, expanded: _open, child: InkWell(borderRadius: AppRadius.rMd, onTap: () => setState(() => _open = !_open), child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            AnimatedRotation(turns: _open ? .25 : 0, duration: const Duration(milliseconds: 150), child: const PlobbyIcon(PlobbyIcons.chev, size: 14, strokeWidth: 2.4)),
            const SizedBox(width: 6),
            Text('Historial de cambios (${m.events.length})', style: base.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ))),
        if (_open) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Column(children: [
          for (final e in m.events) Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text.rich(TextSpan(style: base, children: [
                TextSpan(text: m.player(e.actorId ?? '')?.name.split(' ').first ?? 'Servidor', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' ${e.text}'),
              ]))),
              const SizedBox(width: 8),
              Text(_hms(e.at), style: base.copyWith(color: AppColors.textMuted)),
            ]),
          ),
        ])),
      ]),
    );
  }
}
