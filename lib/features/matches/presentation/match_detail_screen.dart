import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../application/lifecycle_providers.dart';
import '../data/lifecycle_repository.dart';
import '../domain/match_lifecycle.dart';
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

/// Detalle del partido. Todos los participantes ven lo mismo (Realtime vía `matchProvider`).
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final String matchId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(matchProvider(matchId)); final uid = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del partido'), centerTitle: true, actions: [
        async.maybeWhen(data: (m) => m != null && MatchPerms(m, uid).canEdit ? PopupMenuButton<String>(onSelected: (v) => v == 'edit' ? showEditMatchSheet(context, m) : _confirmDelete(context, ref, m), itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Editar partido')), PopupMenuItem(value: 'del', child: Text('Eliminar partido'))]) : const SizedBox.shrink(), orElse: () => const SizedBox.shrink()),
      ]),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: TextButton(onPressed: () => ref.invalidate(matchProvider(matchId)), child: const Text('No se pudo cargar. Reintentar'))),
        data: (m) => m == null ? const Center(child: Text('Este partido ya no existe')) : _Body(m: m, uid: uid),
      ),
    );
  }
}

Future<void> _confirmDelete(BuildContext context, WidgetRef ref, LifecycleMatch m) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('¿Eliminar este partido?'), content: Text('${formatWhen(m.scheduledAt)} · ${m.club}. Los otros tres jugadores recibirán un aviso. Esta acción no se puede deshacer.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar', style: TextStyle(color: AppColors.danger)))]));
  if (ok != true) return;
  try { await ref.read(lifecycleActionsProvider).cancel(m.id); if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partido eliminado'))); context.pop(); } }
  catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)))); }
}

class _Body extends ConsumerWidget {
  const _Body({required this.m, required this.uid});
  final LifecycleMatch m; final String uid;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = MatchPerms(m, uid), act = ref.read(lifecycleActionsProvider);
    void snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    Future<void> run(Future<void> Function() f) async { try { await f(); } catch (e) { if (context.mounted) snack(errorText(e)); } }
    final w = m.winnerTeam;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
      // Cabecera
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [StatusChip(status: m.status), const SizedBox(width: 8), Text(m.type == MatchType.league ? 'Liga' : 'Amistoso', style: const TextStyle(color: Color(0xBFFFFFFF), fontSize: 12, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 12),
        Text(formatWhen(m.scheduledAt), style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 22, color: Colors.white)),
        const SizedBox(height: 8),
        Text('${m.club}${m.court != null && m.court!.isNotEmpty ? ' · ${m.court}' : ''}', style: const TextStyle(color: Color(0xC7FFFFFF))),
        if (m.leagueName != null) Text(m.leagueName!, style: const TextStyle(color: Color(0xC7FFFFFF))),
      ])),
      const SizedBox(height: 12),
      if (m.status == MatchStatus.live) _TimerCard(m: m, title: 'Cronómetro oficial · hora del servidor')
      else if (m.durationSeconds != null) _TimerCard(m: m, title: 'Duración total'),
      if (m.sets.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: ScoreBoard(match: m)),
      for (final t in [1, 2]) _TeamCard(m: m, team: t, winner: w == t),
      const Padding(padding: EdgeInsets.only(bottom: 14), child: Text('C = capitán. Si no se designa otro, lo es el primer jugador de cada equipo.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
      if (m.status == MatchStatus.pendingConfirmation || m.status == MatchStatus.disputed) _ConfirmationCard(m: m, perms: perms, run: run, act: act),
      // Acciones del ciclo
      if (m.status == MatchStatus.scheduled && perms.canStart) _BigButton(label: 'EMPEZAR PARTIDO', icon: Icons.play_arrow_rounded, onTap: () => run(() async { final r = await act.start(m.id); snack(r.started ? '¡Partido iniciado! Cronómetro en marcha para los cuatro.' : 'El partido ya estaba iniciado: se mantiene la hora oficial.'); })),
      if (m.status == MatchStatus.live && perms.canFinish) _BigButton(label: 'FINALIZAR PARTIDO', icon: Icons.stop_rounded, dark: true, onTap: () => run(() async {
        final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('¿Finalizar el partido?'), content: const Text('Se guardará la hora de fin del servidor y la duración total. Después podréis introducir el resultado.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir jugando')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finalizar'))]));
        if (ok != true) return;
        await act.finish(m.id);
        if (context.mounted) context.push('/match/${m.id}/result');        // abre automáticamente la pantalla de resultado
      })),
      if (m.status == MatchStatus.pendingResult && perms.canSubmitResult) _BigButton(label: 'Introducir resultado', onTap: () => context.push('/match/${m.id}/result')),
      if (m.status == MatchStatus.confirmed) Padding(padding: const EdgeInsets.only(top: 8), child: ElevatedButton(onPressed: () => context.push('/match/${m.id}/final'), style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppColors.brand, foregroundColor: AppColors.brandInk), child: const Text('Ver resultado final'))),
      if (m.status == MatchStatus.confirmed && m.bothCaptainsAccepted && m.player(uid) != null) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton.icon(onPressed: () => context.push('/match/${m.id}/share'), icon: const Icon(Icons.ios_share, size: 18), label: const Text('COMPARTIR RESULTADO'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)))),
      if (m.status == MatchStatus.scheduled) Padding(padding: const EdgeInsets.only(top: 12), child: perms.canEdit
          ? Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => showEditMatchSheet(context, m), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Editar partido'))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: () => _confirmDelete(context, ref, m), style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger), icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Eliminar partido')))])
          : const Text('Solo quien creó el partido puede editarlo o eliminarlo.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
      if (m.events.isNotEmpty) ExpansionTile(title: Text('Historial de cambios (${m.events.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), children: [for (final e in m.events) ListTile(dense: true, title: Text('${m.player(e.actorId ?? '')?.name ?? 'Servidor'} ${e.text}'), trailing: Text('${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}'))]),
    ]);
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.onTap, this.icon, this.dark = false});
  final String label; final VoidCallback onTap; final IconData? icon; final bool dark;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(
      onPressed: onTap, icon: Icon(icon ?? Icons.check, size: 22), label: Text(label, style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: .3)),
      style: ElevatedButton.styleFrom(shape: const StadiumBorder(), elevation: 6, backgroundColor: dark ? AppColors.inverse : AppColors.brand, foregroundColor: dark ? Colors.white : AppColors.brandInk))))));
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({required this.m, required this.title});
  final LifecycleMatch m; final String title;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), width: double.infinity, decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        MatchStopwatch(match: m),
        if (m.startedAt != null) Text('Inicio ${_hm(m.startedAt!)}${m.endedAt != null ? ' → ${_hm(m.endedAt!)}' : ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]));
  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.m, required this.team, required this.winner});
  final LifecycleMatch m; final int team; final bool winner;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: winner ? AppColors.brandSoft : AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: winner ? AppColors.brand : AppColors.border, width: winner ? 2 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('EQUIPO $team${winner ? ' · GANADOR' : ''}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
        for (final p in m.team(team)) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
          PlayerAvatar(player: p, size: 40), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)), Text('${p.level} · ELO ${p.elo}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted))])),
          if (p.isCaptain) Container(width: 22, height: 22, alignment: Alignment.center, decoration: const BoxDecoration(color: AppColors.inverse, shape: BoxShape.circle), child: const Text('C', style: TextStyle(color: AppColors.brand, fontSize: 11, fontWeight: FontWeight.w800))),
        ])),
      ]));
}

/// Confirmación de los DOS capitanes. El botón «Aceptar» envía la versión que ve el capitán; el servidor la compara con la vigente.
class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({required this.m, required this.perms, required this.run, required this.act});
  final LifecycleMatch m; final MatchPerms perms; final Future<void> Function(Future<void> Function()) run; final LifecycleActions act;
  @override
  Widget build(BuildContext context) {
    final dis = m.status == MatchStatus.disputed, acc = m.acceptedTeams;
    Widget row(int t) { final c = m.captainOf(t); final ok = acc.contains(t); return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
      Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? AppColors.success : AppColors.borderStrong, size: 22), const SizedBox(width: 10),
      Expanded(child: Text('Capitán equipo $t · ${c?.name ?? '—'}')), Text(ok ? 'Aceptado' : 'Pendiente', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted))])); }
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: dis ? AppColors.danger : AppColors.border, width: dis ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dis ? 'RESULTADO EN DISPUTA' : 'CONFIRMACIÓN DE CAPITANES · VERSIÓN ${m.resultVersion}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
          const SizedBox(height: 10), ScoreBoard(match: m), const SizedBox(height: 8),
          if (dis) Text('Un capitán rechazó el resultado${m.rejectionReason != null ? ': «${m.rejectionReason}»' : ''}. Corregidlo y se volverá a pedir la confirmación a los dos capitanes.') else ...[row(1), row(2)],
          const SizedBox(height: 8),
          if (perms.canConfirm) Row(children: [
            Expanded(child: ElevatedButton(onPressed: () => run(() async { final s = await act.respond(m.id, m.resultVersion, accept: true); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s == MatchStatus.confirmed ? 'Resultado confirmado. ELO y estadísticas actualizados.' : 'Has aceptado. Falta el otro capitán.'))); }), style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: AppColors.brandInk), child: const Text('Aceptar resultado'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () => _reject(context), style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger), child: const Text('Rechazar'))),
          ]),
          if (perms.canSubmitResult) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton(onPressed: () => context.push('/match/${m.id}/result'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)), child: Text(dis ? 'Corregir resultado' : 'Proponer corrección'))),
          if (!perms.canConfirm && !dis && perms.isParticipant) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Solo los capitanes pueden aceptar o rechazar. Cualquier corrección invalida las aceptaciones.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
        ]));
  }
  Future<void> _reject(BuildContext context) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Rechazar resultado'), content: TextField(controller: ctl, maxLength: 200, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rechazar', style: TextStyle(color: AppColors.danger)))]));
    if (ok == true) await run(() async { await act.respond(m.id, m.resultVersion, accept: false, reason: ctl.text); });
  }
}
