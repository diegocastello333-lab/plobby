import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/social_providers.dart';
import '../domain/social_models.dart';
import 'player_tile.dart';
import '../../matches/application/match_providers.dart' show leagueMembersProvider;
import '../../matches/domain/match_models.dart' show PlayerOption;

/// Petición para usar la pantalla de Amigos como selector (jugadores de un partido o pareja habitual).
/// [max] = cuántos se pueden elegir (1 = elección única). [selected] = ya elegidos, en orden. [blocked] = ids que no se
/// pueden elegir (p. ej. jugadores ya puestos en otro hueco del partido) para no repetir a nadie.
/// Si [leagueId] no es null, la lista son los miembros de esa liga (las reglas de liga exigen que lo sean).
class FriendPick {
  const FriendPick({required this.title, this.max = 1, this.selected = const [], this.blocked = const {}, this.confirmLabel = 'Confirmar', this.leagueId});
  final String title, confirmLabel;
  final int max;
  final List<PlayerOption> selected;
  final Set<String> blocked;
  final String? leagueId;
}

/// Abre Amigos en modo selección y devuelve los elegidos (en el orden en que se marcaron) o null si se cancela.
Future<List<PlayerOption>?> pickFriends(BuildContext context, FriendPick pick) => context.push<List<PlayerOption>>('/friends/pick', extra: pick);

/// «Amigos» — `scFriends` del prototipo HTML: cabecera con contador, solicitudes pendientes, búsqueda y filas con ELO y
/// opciones. Con [pick] la misma pantalla sirve para elegir jugadores o pareja habitual (indicador de selección y botón
/// de confirmar).
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key, this.pick});
  final FriendPick? pick;
  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  late final List<PlayerOption> _sel = [...?widget.pick?.selected];
  String _q = '';

  FriendPick? get _pick => widget.pick;

  void _toggle(PlayerOption p) {
    final k = _pick!;
    setState(() {
      final i = _sel.indexWhere((x) => x.id == p.id);
      if (i >= 0) { _sel.removeAt(i); return; }
      if (k.max == 1) { _sel..clear()..add(p); return; }
      if (_sel.length < k.max) _sel.add(p);
    });
    if (_sel.length > k.max) _sel.removeRange(k.max, _sel.length);
  }

  @override
  Widget build(BuildContext context) {
    final pick = _pick;
    final count = ref.watch(friendCountProvider);
    final header = Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Row(children: [
      IconSquareButton(icon: pick == null ? PlobbyIcons.back : PlobbyIcons.close, tooltip: pick == null ? 'Volver' : 'Cancelar', onPressed: () => context.pop()),
      Expanded(child: Semantics(header: true, child: pick != null
          ? Text(pick.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyHeaderBar.titleStyle)
          : Text.rich(TextSpan(children: [
              const TextSpan(text: 'Amigos '),
              TextSpan(text: '$count', style: const TextStyle(color: AppColors.borderStrong)),
            ]), textAlign: TextAlign.center, style: PlobbyHeaderBar.titleStyle))),
      if (pick == null) IconSquareButton(icon: PlobbyIcons.userplus, tooltip: 'Añadir amigos', onPressed: () => context.push('/friends/add'))
      else SizedBox(width: 40, child: Text('${_sel.length}/${pick.max}', textAlign: TextAlign.right,
          style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.textMuted))),
    ]));
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(children: [
        header,
        Expanded(child: pick == null ? _browse() : _picker(pick)),
        if (pick != null) Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
          decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: Color(0x14171C19)))),
          child: PlobbyButton(
            label: _sel.isEmpty ? 'Elige ${pick.max == 1 ? 'un amigo' : 'jugadores'}' : '${pick.confirmLabel}${pick.max > 1 ? ' (${_sel.length})' : ''}',
            onPressed: _sel.isEmpty ? null : () => context.pop(List<PlayerOption>.unmodifiable(_sel)),
          ),
        ),
      ])),
    );
  }

  // ───────────── Modo normal: solicitudes pendientes + lista de amigos ─────────────
  Widget _browse() {
    final all = ref.watch(friendsProvider);
    final list = ref.watch(friendFilterProvider);
    final reqs = ref.watch(requestsProvider);
    final incoming = reqs.valueOrNull?.incoming ?? const <FriendRequest>[];
    final outgoing = reqs.valueOrNull?.outgoing ?? const <FriendRequest>[];
    return ListView(padding: EdgeInsets.fromLTRB(20, 14, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
      // Solicitudes: quién la envía, aceptar/rechazar. Un error al cargarlas ya no se oculta.
      if (reqs.hasError) Padding(padding: const EdgeInsets.only(bottom: 14), child: ErrorStateCard(title: 'No se pudieron cargar las solicitudes', onRetry: () => ref.invalidate(requestsProvider))),
      if (incoming.isNotEmpty) ...[
        _Header('Solicitudes pendientes', incoming.length),
        for (final r in incoming) _IncomingRequest(r),
        const SizedBox(height: 18),
      ],
      if (outgoing.isNotEmpty) ...[
        _Header('Solicitudes enviadas', outgoing.length),
        for (final r in outgoing) PersonRow(
          leading: PlayerAvatar(r.player), title: r.player.name, subtitle: '@${r.player.username} · Pendiente de respuesta',
          trailing: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.smallOutline, onPressed: () => _run(() => ref.read(requestsProvider.notifier).cancel(r.id))),
        ),
        const SizedBox(height: 18),
      ],
      ...all.when(
        loading: () => [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: AppColors.text)))],
        error: (e, _) => [ErrorStateCard(onRetry: () => ref.invalidate(friendsProvider))],
        data: (friends) => friends.isEmpty
            ? [EmptyStateCard(icon: Icons.groups_2_outlined, title: 'Tu comunidad de pádel empieza aquí',
                text: 'Añade a tus compañeros para ver sus partidos, hablar con ellos e invitarles a jugar.', primary: 'Buscar amigos', onPrimary: () => context.push('/friends/add'))]
            : [
                if (incoming.isNotEmpty || outgoing.isNotEmpty) const _Header('Tus amigos'),
                SearchField(hint: 'Buscar por nombre o usuario', onChanged: (v) => ref.read(friendSearchQueryProvider.notifier).state = v),
                const SizedBox(height: 12),
                ...list.maybeWhen(
                  data: (l) => l.isEmpty
                      ? [const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Ningún amigo coincide con tu búsqueda', textAlign: TextAlign.center, style: PlobbyText.sub))]
                      : [for (final f in l) _FriendTile(f)],
                  orElse: () => const <Widget>[]),
              ],
      ),
    ]);
  }

  Future<void> _run(Future<void> Function() f) async {
    try { await f(); } catch (_) { if (mounted) showPlobbySnack(context, 'No se pudo completar. Revisa tu conexión e inténtalo de nuevo.', error: true); }
  }

  // ───────────── Modo selección ─────────────
  Widget _picker(FriendPick pick) {
    // Amigos (amistoso, pareja habitual) o miembros de la liga (partido de liga: las reglas exigen que lo sean).
    final AsyncValue<List<PlayerSummary>> source = pick.leagueId == null
        ? ref.watch(friendsProvider).whenData((l) => [for (final f in l) f.player])
        : ref.watch(leagueMembersProvider(pick.leagueId!)).whenData((l) => [for (final p in l) PlayerSummary(id: p.id, name: p.name, username: '', elo: 0, level: '')]);
    final q = _q.trim().toLowerCase();
    return source.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
      error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(title: 'No se pudieron cargar los jugadores',
          onRetry: () => pick.leagueId == null ? ref.invalidate(friendsProvider) : ref.invalidate(leagueMembersProvider(pick.leagueId!)))),
      data: (all) {
        if (all.isEmpty) {
          return Padding(padding: const EdgeInsets.all(20), child: Align(alignment: Alignment.topCenter, child: EmptyStateCard(icon: Icons.groups_2_outlined,
              title: pick.leagueId == null ? 'Todavía no tienes amigos' : 'La liga no tiene más miembros',
              text: pick.leagueId == null ? 'Solo puedes elegir entre tus amigos. Envía solicitudes y, cuando las acepten, aparecerán aquí.' : 'Invita a más jugadores a la liga para poder crear el partido.',
              primary: pick.leagueId == null ? 'Añadir amigos' : null, onPrimary: () => context.push('/friends/add'))));
        }
        final shown = q.isEmpty ? all : all.where((p) => p.name.toLowerCase().contains(q) || p.username.toLowerCase().contains(q)).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
          Text(pick.max == 1 ? 'Toca un amigo para elegirlo.' : 'Toca para seleccionar o quitar. Puedes elegir hasta ${pick.max}.', style: PlobbyText.help.copyWith(fontSize: 12)),
          const SizedBox(height: 10),
          SearchField(hint: 'Buscar por nombre o usuario', onChanged: (v) => setState(() => _q = v)),
          const SizedBox(height: 8),
          if (shown.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Ningún jugador coincide con tu búsqueda', textAlign: TextAlign.center, style: PlobbyText.sub)),
          for (final p in shown) _PickRow(
            player: p,
            order: _sel.indexWhere((x) => x.id == p.id),
            single: pick.max == 1,
            blocked: pick.blocked.contains(p.id) && !_sel.any((x) => x.id == p.id),
            full: pick.max > 1 && _sel.length >= pick.max,
            onTap: () => _toggle(PlayerOption(p.id, p.name)),
          ),
        ]);
      },
    );
  }
}

/// Fila del selector: indicador circular (número de orden en selección múltiple, check en elección única).
class _PickRow extends StatelessWidget {
  const _PickRow({required this.player, required this.order, required this.single, required this.blocked, required this.full, required this.onTap});
  final PlayerSummary player; final int order; final bool single, blocked, full; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final on = order >= 0;
    final disabled = blocked || (!on && full);
    final sub = blocked ? 'Ya está en el partido' : [if (player.username.isNotEmpty) '@${player.username}', if (player.elo > 0) 'ELO ${player.elo}'].join(' · ');
    return Opacity(opacity: disabled ? .45 : 1, child: Semantics(checked: on, enabled: !disabled, label: '${player.name}${on ? ', seleccionado' : ''}${blocked ? ', ya está en el partido' : ''}', excludeSemantics: true,
      child: PersonRow(
        leading: PlayerAvatar(player), title: player.name, subtitle: sub.isEmpty ? null : sub,
        onTap: disabled ? null : onTap,
        trailing: GestureDetector(onTap: disabled ? null : onTap, child: AnimatedContainer(
          duration: const Duration(milliseconds: 150), width: 26, height: 26, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? AppColors.brand : null, border: on ? null : Border.all(color: AppColors.borderStrong, width: 1.5)),
          child: on ? (single ? const PlobbyIcon(PlobbyIcons.check, size: 14, strokeWidth: 3, color: AppColors.brandInk)
              : Text('${order + 1}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.brandInk))) : null,
        )),
      )));
  }
}

/// Encabezado de sección (eyebrow + contador).
class _Header extends StatelessWidget {
  const _Header(this.t, [this.n]);
  final String t; final int? n;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(t.toUpperCase(), style: PlobbyText.eb))),
        if (n != null) Text('$n', style: PlobbyText.eb),
      ]));
}

/// Solicitud recibida: quién la envía y Aceptar / Rechazar. Al aceptar, los dos pasan a ser amigos (RPC).
class _IncomingRequest extends ConsumerStatefulWidget {
  const _IncomingRequest(this.r);
  final FriendRequest r;
  @override
  ConsumerState<_IncomingRequest> createState() => _IncomingRequestState();
}

class _IncomingRequestState extends ConsumerState<_IncomingRequest> {
  bool _busy = false;
  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      await ref.read(requestsProvider.notifier).respond(widget.r.id, accept);
      if (mounted) showPlobbySnack(context, accept ? 'Ahora sois amigos' : 'Solicitud rechazada');
    } catch (_) {
      if (mounted) { setState(() => _busy = false); showPlobbySnack(context, 'No se pudo responder a la solicitud. Inténtalo de nuevo.', error: true); }
    }
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.r.player;
    return PersonRow(
      leading: PlayerAvatar(p), title: p.name, subtitle: '@${p.username} quiere ser tu amigo',
      onTap: () => context.push('/player/${p.id}'),
      trailing: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text)) : Row(mainAxisSize: MainAxisSize.min, children: [
        PlobbyButton(label: 'Aceptar', kind: PlobbyButtonKind.small, onPressed: () => _respond(true)),
        const SizedBox(width: 6),
        PlobbyButton(label: 'Rechazar', kind: PlobbyButtonKind.smallOutline, onPressed: () => _respond(false)),
      ]),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile(this.f);
  final Friend f;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = f.player;
    final elo = p.elo >= 1000 ? '${p.elo ~/ 1000}.${(p.elo % 1000).toString().padLeft(3, '0')}' : '${p.elo}';
    return PersonRow(
      leading: PlayerAvatar(p),
      title: p.name,
      semanticsLabel: '${p.name}, ELO ${p.elo}',
      titleTrailing: f.activity.streak >= 3 ? Row(mainAxisSize: MainAxisSize.min, children: [
        const PlobbyIcon(PlobbyIcons.flame, size: 13, color: AppColors.brandText),
        Text('${f.activity.streak}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.brandText)),
      ]) : null,
      subtitle: '@${p.username} · ${p.level}${f.activity.lastMatch == null ? '' : '\n${f.activity.lastMatch}'}',
      onTap: () => context.push('/player/${p.id}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(elo, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.16, color: AppColors.text)),
          const Text('ELO', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10, letterSpacing: 0, color: AppColors.textMuted)),
        ]),
        const SizedBox(width: 4),
        Tooltip(message: 'Opciones de ${p.name}', child: Semantics(button: true, label: 'Opciones de ${p.name}', excludeSemantics: true, child: InkResponse(
            onTap: () => _options(context, ref), radius: 22,
            child: const SizedBox(width: 40, height: 44, child: Center(child: PlobbyIcon(PlobbyIcons.more, size: 20)))))),
      ]),
    );
  }

  void _options(BuildContext context, WidgetRef ref) => showPlobbySheet(context, (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeader(title: f.player.name, subtitle: '@${f.player.username}'),
        SheetListItem(icon: PlobbyIcons.user, label: 'Ver perfil', onTap: () { Navigator.pop(c); context.push('/player/${f.player.id}'); }),
        SheetListItem(icon: PlobbyIcons.plane, label: 'Enviar mensaje', onTap: () { Navigator.pop(c); context.push('/messages/with/${f.player.id}'); }),
        SheetListItem(icon: PlobbyIcons.racket, label: 'Invitar a jugar', onTap: () { Navigator.pop(c); context.push('/messages/with/${f.player.id}?invite=1'); }),
        SheetListItem(icon: PlobbyIcons.trash, label: 'Eliminar amigo', danger: true, onTap: () async {
          Navigator.pop(c);
          final ok = await showPlobbySheet<bool>(context, (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(title: '¿Eliminar a ${f.player.name}?'),
            const Text('Dejaréis de ver vuestra actividad y se cerrará la conversación privada.', style: PlobbyText.sub),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(d, false))),
              const SizedBox(width: 10),
              Expanded(child: PlobbyButton(label: 'Eliminar', kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(d, true))),
            ]),
          ]));
          if (ok == true) await ref.read(friendsProvider.notifier).remove(f.player.id);
        }),
      ]));
}
