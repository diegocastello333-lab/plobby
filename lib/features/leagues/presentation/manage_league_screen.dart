import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../../social/application/social_providers.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';

/// «Gestión» — `scManage` del prototipo HTML: solo organizador / admin de club. El servidor vuelve a comprobar el rol en cada RPC.
class ManageLeagueScreen extends ConsumerWidget {
  const ManageLeagueScreen({super.key, required this.leagueId});
  final String leagueId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(leagueDetailProvider(leagueId));
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Row(children: [
          IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', onPressed: () => context.pop()),
          const Spacer(),
          if (detail.valueOrNull?.myRole?.isManager == true) RoleBadge(detail.value!.myRole!),
        ])),
        Expanded(child: detail.when(
        loading: () => const Padding(padding: EdgeInsets.all(20), child: Column(children: [LoadingBlock(height: 80), SizedBox(height: 12), LoadingBlock(height: 200)])),
        error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(leagueDetailProvider(leagueId)))),
        data: (l) => !l.canManage
            ? Padding(padding: const EdgeInsets.all(20), child: EmptyStateCard(icon: Icons.lock_outline, title: 'Acceso restringido',
                text: 'Solo el organizador o el administrador del club pueden gestionar esta liga.', secondary: 'Volver a la liga', onSecondary: () => context.pop()))
            : _Body(league: l),
        )),
      ])),
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
    // `.card2` (blanca, radio 14, sombra) con título 15/800 y contador lima opcional.
    Widget card(String title, List<Widget> children, {int? badge}) => Container(
        margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Flexible(child: Semantics(header: true, child: Text(title, style: PlobbyText.cardTitle))),
            if (badge != null && badge > 0) ...[const SizedBox(width: 8), Container(height: 20, constraints: const BoxConstraints(minWidth: 20), padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.brand, borderRadius: AppRadius.rPill),
                child: Text('$badge', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.brandInk)))]]),
          const SizedBox(height: 12), ...children]));
    Widget rowTile({required Widget leading, required String title, String? subtitle, Widget? trailing, VoidCallback? onTap}) => InkWell(onTap: onTap, child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
          leading, const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            if (subtitle != null) Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted)),
          ])),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ])));
    const muted = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, letterSpacing: 0, color: AppColors.textMuted);

    return ListView(padding: EdgeInsets.fromLTRB(20, 16, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
      Semantics(header: true, child: const Text('Gestión', style: PlobbyText.t1)),
      const SizedBox(height: 6),
      Text(l.name.toUpperCase(), style: PlobbyText.sub),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: AppColors.brandSoft, borderRadius: AppRadius.rMd), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.inverse, borderRadius: BorderRadius.circular(10)),
            child: Center(child: PlobbyIcon(admin ? PlobbyIcons.shield : PlobbyIcons.star, size: 18, color: AppColors.brand))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(admin ? 'Administrador del club' : 'Organizador de la liga', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text)),
          const SizedBox(height: 2),
          Text(admin ? 'Gestionas la liga, las sedes y las temporadas del club. Los resultados los validas tú.' : 'Gestionas participantes, reglas y resultados de esta liga.',
              style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, height: 1.4, letterSpacing: 0, color: AppColors.ink700)),
        ])),
      ])),
      const SizedBox(height: 16),
      card('Información', [
        LabeledField(label: 'Nombre', controller: _name, maxLength: 40),
        LabeledField(label: 'Descripción', controller: _desc, maxLength: 180, maxLines: 3),
        PlobbyButton(label: 'Guardar cambios', busy: _saving, onPressed: () async {
          setState(() => _saving = true);
          await _run(() => _a.update(l.id, {'name': _name.text, 'description': _desc.text}), 'Cambios guardados');
          if (mounted) setState(() => _saving = false);
        }),
      ]),
      if (code != null) card('Código de invitación', [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6), decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [Expanded(child: Text(code, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))),
            PlobbyButton(label: 'Copiar', icon: PlobbyIcons.copy, kind: PlobbyButtonKind.small, onPressed: () { Clipboard.setData(ClipboardData(text: code)); showPlobbySnack(context, 'Código copiado'); })])),
      ]),
      card('Solicitudes de acceso', badge: reqs.valueOrNull?.length, [
        reqs.when(
          loading: () => const LoadingBlock(height: 56, radius: AppRadius.md),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(joinRequestsProvider(l.id))),
          data: (rs) => rs.isEmpty ? const Text('No hay solicitudes pendientes.', style: muted) : Column(children: [
            for (final r in rs) rowTile(leading: LeagueAvatar(name: r.name, avatarUrl: r.avatarUrl, size: 40), title: r.name,
                subtitle: r.message.isEmpty ? null : r.message, trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  MiniAction(approve: false, tooltip: 'Rechazar a ${r.name}', onPressed: () => _run(() => _a.respond(l.id, r.id, false), 'Solicitud rechazada')),
                  const SizedBox(width: 8),
                  MiniAction(approve: true, tooltip: 'Aprobar a ${r.name}', onPressed: () => _run(() => _a.respond(l.id, r.id, true), '${r.name} ya está en la liga')),
                ])),
          ]),
        ),
      ]),
      card('Participantes', [
        members.when(
          loading: () => const LoadingBlock(height: 100, radius: AppRadius.md),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(standingsProvider(l.id))),
          data: (ms) {
            final others = ms.where((m) => m.role != LeagueRole.organizer).toList();
            return Column(children: [
              Align(alignment: Alignment.centerLeft, child: Text('${ms.length} de ${l.maxPlayers} jugadores', style: muted)),
              if (others.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Align(alignment: Alignment.centerLeft, child: Text('Aún no hay participantes.', style: muted))),
              for (final m in others) rowTile(leading: LeagueAvatar(name: m.name, avatarUrl: m.avatarUrl, avatarId: m.avatarId, size: 40),
                  title: m.name, subtitle: 'ELO ${m.elo}',
                  trailing: IconSquareButton(icon: PlobbyIcons.trash, tooltip: 'Quitar a ${m.name}', size: 38, onPressed: () async {
                    final ok = await _confirm('¿Quitar a ${m.name}?', 'Sus partidos jugados se conservan, pero dejará de aparecer en la clasificación.', 'Quitar');
                    if (ok == true) await _run(() => _a.removeMember(l.id, m.userId), '${m.name} ya no está en la liga');
                  })),
            ]);
          },
        ),
        const SizedBox(height: 10),
        PlobbyButton(label: 'Invitar jugadores', icon: PlobbyIcons.userplus, kind: PlobbyButtonKind.outline, onPressed: () => _invite(l)),
      ]),
      card('Resultados en disputa', badge: disputes.valueOrNull?.length, [
        disputes.when(
          loading: () => const LoadingBlock(height: 56, radius: AppRadius.md),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(leagueMatchesProvider(l.id))),
          data: (ds) => ds.isEmpty ? const Text('No hay resultados en disputa.', style: muted) : Column(children: [
            for (final d in ds) rowTile(
                leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: PlobbyIcon(PlobbyIcons.alert, size: 18, color: AppColors.danger))),
                title: '${d.team(1).map((p) => p.name.split(' ').first).join(' y ')} vs ${d.team(2).map((p) => p.name.split(' ').first).join(' y ')}',
                subtitle: [fmtDay(d.scheduledAt), if (d.rejectionReason != null) '«${d.rejectionReason}»'].join(' · '),
                trailing: const PlobbyIcon(PlobbyIcons.chev, size: 18, color: AppColors.textMuted), onTap: () => context.push('/match/${d.id}')),
          ]),
        ),
      ]),
      if (l.status != LeagueStatus.ended) PlobbyButton(label: 'Cerrar temporada', icon: PlobbyIcons.flag, kind: PlobbyButtonKind.danger, onPressed: () async {
        final ok = await _confirm('¿Cerrar la temporada?', 'La clasificación quedará fija y no se podrán registrar más partidos de liga.', 'Cerrar temporada');
        if (ok == true) await _run(() => _a.update(l.id, {'ended': true}), 'Temporada cerrada');
      }),
    ]);
  }

  /// Confirmación en hoja inferior (Cancelar / acción en rojo), como las del prototipo.
  Future<bool?> _confirm(String title, String text, String action) => showPlobbySheet<bool>(context, (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeader(title: title),
        Text(text, style: PlobbyText.sub),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(c, false))),
          const SizedBox(width: 10),
          Expanded(child: PlobbyButton(label: action, kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(c, true))),
        ]),
      ]));

  Future<void> _invite(LeagueDetail l) async {
    final picked = <String>{};
    final ids = await showPlobbySheet<List<String>>(context, (c) => StatefulBuilder(builder: (c, set) {
      final fs = ref.watch(friendsProvider);
      return SizedBox(height: MediaQuery.sizeOf(c).height * .62, child: Column(children: [
        const SheetHeader(title: 'Invitar amigos'),
        Expanded(child: fs.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(friendsProvider))),
          data: (l) => l.isEmpty ? Center(child: Text('Todavía no tienes amigos para invitar.', style: PlobbyText.sub)) : ListView(children: [
            for (final f in l) CheckboxListTile(contentPadding: EdgeInsets.zero, value: picked.contains(f.player.id), activeColor: AppColors.inverse, checkColor: AppColors.brand,
                title: Text(f.player.name, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
                subtitle: Text('ELO ${f.player.elo}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted)),
                secondary: LeagueAvatar(name: f.player.name, avatarUrl: f.player.avatarUrl, size: 36), onChanged: (v) => set(() => v == true ? picked.add(f.player.id) : picked.remove(f.player.id))),
          ]))),
        const SizedBox(height: 12),
        PlobbyButton(label: picked.isEmpty ? 'Elige a quién invitar' : 'Invitar (${picked.length})', onPressed: picked.isEmpty ? null : () => Navigator.pop(c, picked.toList())),
      ]));
    }));
    if (ids == null || ids.isEmpty) return;
    try {
      final n = await _a.invite(l.id, ids);
      if (mounted) showPlobbySnack(context, n == 1 ? 'Invitación enviada' : '$n invitaciones enviadas');
    } on LeagueException catch (e) { if (mounted) showPlobbySnack(context, e.message, error: true); }
  }
}
