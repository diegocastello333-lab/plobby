import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/state_views.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../../social/application/social_providers.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';

/// «Gestión» (prototipo `scManage`): solo organizador / admin de club. El servidor vuelve a comprobar el rol en cada RPC.
class ManageLeagueScreen extends ConsumerWidget {
  const ManageLeagueScreen({super.key, required this.leagueId});
  final String leagueId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(leagueDetailProvider(leagueId));
    return Scaffold(
      appBar: AppBar(actions: [if (detail.valueOrNull?.myRole?.isManager == true) Padding(padding: const EdgeInsets.only(right: 16), child: LeagueChip(detail.value!.myRole!.label, tone: ChipTone.dark))]),
      body: detail.when(
        loading: () => const Padding(padding: EdgeInsets.all(20), child: Column(children: [LoadingBlock(height: 80), SizedBox(height: 12), LoadingBlock(height: 200)])),
        error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(leagueDetailProvider(leagueId)))),
        data: (l) => !l.canManage
            ? Padding(padding: const EdgeInsets.all(20), child: EmptyStateCard(icon: Icons.lock_outline, title: 'Acceso restringido',
                text: 'Solo el organizador o el administrador del club pueden gestionar esta liga.', secondary: 'Volver a la liga', onSecondary: () => context.pop()))
            : _Body(league: l),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.league});
  final LeagueDetail league;
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final _name = TextEditingController(text: widget.league.name);
  late final _desc = TextEditingController(text: widget.league.description);
  bool _saving = false;
  @override
  void dispose() { _name.dispose(); _desc.dispose(); super.dispose(); }

  LeagueActions get _a => ref.read(leagueActionsProvider);
  Future<void> _run(Future<void> Function() f, String ok) async {
    try { await f(); if (mounted) showPlobbySnack(context, ok); }
    on LeagueException catch (e) { if (mounted) showPlobbySnack(context, e.message, error: true); }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.league, admin = l.myRole == LeagueRole.admin;
    final reqs = ref.watch(joinRequestsProvider(l.id));
    final members = ref.watch(standingsProvider(l.id));
    final disputes = ref.watch(leagueMatchesProvider(l.id)).whenData((m) => m.where((x) => x.status == MatchStatus.disputed).toList());
    final code = ref.watch(inviteCodeProvider(l.id)).valueOrNull;
    Widget card(String title, List<Widget> children, {int? badge}) => Container(
        margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, boxShadow: AppShadows.card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), if (badge != null && badge > 0) ...[const SizedBox(width: 8), Badge(label: Text('$badge'))]]),
          const SizedBox(height: 10), ...children]));

    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
      const Text('Gestión', style: TextStyle(fontFamily: 'Unbounded', fontSize: 28, fontWeight: FontWeight.w700)),
      Text(l.name, style: const TextStyle(color: AppColors.textMuted)),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: AppColors.brandSoft, borderRadius: AppRadius.rMd), child: Row(children: [
        Icon(admin ? Icons.shield_outlined : Icons.star_outline), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(admin ? 'Administrador del club' : 'Organizador de la liga', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(admin ? 'Gestionas la liga, las sedes y las temporadas del club. Los resultados los validas tú.' : 'Gestionas participantes, reglas y resultados de esta liga.', style: const TextStyle(fontSize: 12.5)),
        ])),
      ])),
      const SizedBox(height: 16),
      card('Información', [
        TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 8),
        TextField(controller: _desc, maxLength: 180, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción')),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: FilledButton(onPressed: _saving ? null : () async {
          setState(() => _saving = true);
          await _run(() => _a.update(l.id, {'name': _name.text, 'description': _desc.text}), 'Cambios guardados');
          if (mounted) setState(() => _saving = false);
        }, child: const Text('Guardar cambios'))),
      ]),
      if (code != null) card('Código de invitación', [
        Row(children: [Expanded(child: Text(code, style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w700))),
          FilledButton.tonalIcon(onPressed: () { Clipboard.setData(ClipboardData(text: code)); showPlobbySnack(context, 'Código copiado'); }, icon: const Icon(Icons.copy, size: 16), label: const Text('Copiar'))]),
      ]),
      card('Solicitudes de acceso', badge: reqs.valueOrNull?.length, [
        reqs.when(
          loading: () => const LoadingBlock(height: 56),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(joinRequestsProvider(l.id))),
          data: (rs) => rs.isEmpty ? const Text('No hay solicitudes pendientes.', style: TextStyle(color: AppColors.textMuted)) : Column(children: [
            for (final r in rs) ListTile(contentPadding: EdgeInsets.zero, leading: LeagueAvatar(name: r.name, avatarUrl: r.avatarUrl), title: Text(r.name),
                subtitle: r.message.isEmpty ? null : Text(r.message), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton.outlined(tooltip: 'Rechazar a ${r.name}', onPressed: () => _run(() => _a.respond(l.id, r.id, false), 'Solicitud rechazada'), icon: const Icon(Icons.close)),
                  const SizedBox(width: 6),
                  IconButton.filled(tooltip: 'Aprobar a ${r.name}', onPressed: () => _run(() => _a.respond(l.id, r.id, true), '${r.name} ya está en la liga'), icon: const Icon(Icons.check)),
                ])),
          ]),
        ),
      ]),
      card('Participantes', [
        members.when(
          loading: () => const LoadingBlock(height: 100),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(standingsProvider(l.id))),
          data: (ms) {
            final others = ms.where((m) => m.role != LeagueRole.organizer).toList();
            return Column(children: [
              Align(alignment: Alignment.centerLeft, child: Text('${ms.length} de ${l.maxPlayers}', style: const TextStyle(color: AppColors.textMuted))),
              if (others.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aún no hay participantes.', style: TextStyle(color: AppColors.textMuted))),
              for (final m in others) ListTile(contentPadding: EdgeInsets.zero, leading: LeagueAvatar(name: m.name, avatarUrl: m.avatarUrl, avatarId: m.avatarId),
                  title: Text(m.name), subtitle: Text('ELO ${m.elo}'),
                  trailing: IconButton(tooltip: 'Quitar a ${m.name}', icon: const Icon(Icons.delete_outline), onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text('¿Quitar a ${m.name}?'),
                        content: const Text('Sus partidos jugados se conservan, pero dejará de aparecer en la clasificación.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitar'))]));
                    if (ok == true) await _run(() => _a.removeMember(l.id, m.userId), '${m.name} ya no está en la liga');
                  })),
            ]);
          },
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(onPressed: () => _invite(l), icon: const Icon(Icons.person_add_alt), label: const Text('Invitar jugadores')),
      ]),
      card('Resultados en disputa', badge: disputes.valueOrNull?.length, [
        disputes.when(
          loading: () => const LoadingBlock(height: 56),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(leagueMatchesProvider(l.id))),
          data: (ds) => ds.isEmpty ? const Text('No hay resultados en disputa.', style: TextStyle(color: AppColors.textMuted)) : Column(children: [
            for (final d in ds) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.report_gmailerrorred, color: AppColors.warning),
                title: Text('${d.team(1).map((p) => p.name.split(' ').first).join(' y ')} vs ${d.team(2).map((p) => p.name.split(' ').first).join(' y ')}'),
                subtitle: Text([fmtDay(d.scheduledAt), if (d.rejectionReason != null) '«${d.rejectionReason}»'].join(' · ')),
                trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/match/${d.id}')),
          ]),
        ),
      ]),
      if (l.status != LeagueStatus.ended) OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(48)),
        onPressed: () async {
          final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('¿Cerrar la temporada?'),
              content: const Text('La clasificación quedará fija y no se podrán registrar más partidos de liga.'),
              actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cerrar temporada'))]));
          if (ok == true) await _run(() => _a.update(l.id, {'ended': true}), 'Temporada cerrada');
        },
        icon: const Icon(Icons.flag_outlined), label: const Text('Cerrar temporada')),
    ]);
  }

  Future<void> _invite(LeagueDetail l) async {
    final picked = <String>{};
    final ids = await showModalBottomSheet<List<String>>(context: context, isScrollControlled: true, showDragHandle: true, builder: (c) => StatefulBuilder(builder: (c, set) {
      final fs = ref.watch(friendsProvider);
      return SizedBox(height: MediaQuery.sizeOf(c).height * .7, child: Column(children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Align(alignment: Alignment.centerLeft, child: Text('Invitar amigos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))),
        Expanded(child: fs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(friendsProvider))),
          data: (l) => l.isEmpty ? const Center(child: Text('Todavía no tienes amigos para invitar.')) : ListView(children: [
            for (final f in l) CheckboxListTile(value: picked.contains(f.player.id), title: Text(f.player.name), subtitle: Text('ELO ${f.player.elo}'),
                secondary: LeagueAvatar(name: f.player.name, avatarUrl: f.player.avatarUrl), onChanged: (v) => set(() => v == true ? picked.add(f.player.id) : picked.remove(f.player.id))),
          ]))),
        SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton(
            onPressed: picked.isEmpty ? null : () => Navigator.pop(c, picked.toList()), child: Text(picked.isEmpty ? 'Elige a quién invitar' : 'Invitar (${picked.length})'))))),
      ]));
    }));
    if (ids == null || ids.isEmpty) return;
    try {
      final n = await _a.invite(l.id, ids);
      if (mounted) showPlobbySnack(context, n == 1 ? 'Invitación enviada' : '$n invitaciones enviadas');
    } on LeagueException catch (e) { if (mounted) showPlobbySnack(context, e.message, error: true); }
  }
}
