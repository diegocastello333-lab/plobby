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

/// Botón compacto de las filas (`.sbtn`: 36 px, radio 8, Inter 13/600): tinta o con borde.
Widget _act(String label, VoidCallback? onTap, {bool dark = true, PlobbyIcons? icon}) => PlobbyButton(
    label: label, icon: icon, onPressed: onTap, expand: false, height: 36,
    kind: dark ? PlobbyButtonKind.dark : PlobbyButtonKind.smallOutline);

/// «Añadir amigos» — `scAddFr` del prototipo HTML: búsqueda, solicitudes recibidas y enviadas, y sugerencias.
class AddFriendsScreen extends ConsumerWidget {
  const AddFriendsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(addFriendsQueryProvider);
    final reqs = ref.watch(requestsProvider).valueOrNull ?? const FriendRequests();
    return Scaffold(
      body: Column(children: [
        PlobbyHeaderBar(title: 'Añadir amigos', onBack: () => context.pop()),
        Expanded(child: ListView(padding: EdgeInsets.fromLTRB(20, 14, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          SearchField(hint: 'Nombre o usuario', onChanged: (v) => ref.read(addFriendsQueryProvider.notifier).state = v),
          if (q.trim().isNotEmpty) ...[
            const _Header('Resultados'),
            ...ref.watch(addFriendsSearchProvider).when(
              loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.text)))],
              error: (_, __) => [ErrorStateCard(title: 'No se pudo buscar', message: 'Inténtalo de nuevo.', onRetry: () => ref.invalidate(addFriendsSearchProvider))],
              data: (hits) => hits.isEmpty
                  ? [Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('No encontramos a nadie con “$q”.', textAlign: TextAlign.center, style: PlobbyText.sub))]
                  : hits.map((h) => _HitTile(h)).toList()),
          ] else ...[
            if (reqs.incoming.isNotEmpty) ...[
              _Header('Solicitudes recibidas', reqs.incoming.length),
              for (final r in reqs.incoming)
                PersonRow(
                  leading: PlayerAvatar(r.player), title: r.player.name, subtitle: '@${r.player.username} · ELO ${r.player.elo}',
                  onTap: () => context.push('/player/${r.player.id}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _act('Aceptar', () => ref.read(requestsProvider.notifier).respond(r.id, true)),
                    const SizedBox(width: 6),
                    _act('Rechazar', () => ref.read(requestsProvider.notifier).respond(r.id, false), dark: false),
                  ]),
                ),
            ],
            if (reqs.outgoing.isNotEmpty) ...[
              _Header('Solicitudes enviadas', reqs.outgoing.length),
              for (final r in reqs.outgoing)
                PersonRow(
                  leading: PlayerAvatar(r.player), title: r.player.name, subtitle: '@${r.player.username} · Pendiente',
                  onTap: () => context.push('/player/${r.player.id}'),
                  trailing: _act('Cancelar', () => ref.read(requestsProvider.notifier).cancel(r.id), dark: false),
                ),
            ],
            const _Header('Sugerencias para ti'),
            ...ref.watch(suggestionsProvider).maybeWhen(data: (l) => l.map((h) => _HitTile(h)).toList(), orElse: () => const <Widget>[]),
          ],
        ])),
      ]),
    );
  }
}

/// Encabezado de sección: eyebrow + contador a la derecha.
class _Header extends StatelessWidget {
  const _Header(this.t, [this.n]);
  final String t; final int? n;
  @override
  Widget build(BuildContext c) => Padding(padding: const EdgeInsets.fromLTRB(0, 24, 0, 10), child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(t.toUpperCase(), style: PlobbyText.eb))),
        if (n != null) Text('$n', style: PlobbyText.eb),
      ]));
}

class _HitTile extends ConsumerWidget {
  const _HitTile(this.h);
  final SearchHit h;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = h.player;
    // Relación desde la fuente común (amigos + solicitudes) cuando ya está cargada; si no, la que dio la búsqueda.
    final loaded = ref.watch(friendsProvider).hasValue && ref.watch(requestsProvider).hasValue;
    final rel = loaded ? ref.watch(relationProvider(p.id)) : h.relation;
    final Widget trailing = switch (rel) {
      RelationState.friend => const Pill('Amigos', tone: PillTone.soft, icon: PlobbyIcons.check),
      RelationState.requestSent => const Pill('Solicitud enviada', tone: PillTone.neutral), // deshabilitado: evita duplicados
      RelationState.requestReceived => _act('Aceptar', () async {
          final r = (await ref.read(requestsProvider.future)).incoming.where((x) => x.player.id == p.id).firstOrNull;
          if (r == null) return;
          await ref.read(requestsProvider.notifier).respond(r.id, true);
          if (context.mounted) showPlobbySnack(context, 'Ahora sois amigos');
        }),
      RelationState.none => _act('Añadir', () async {
          await ref.read(requestsProvider.notifier).send(p.id);
          if (context.mounted) showPlobbySnack(context, 'Solicitud enviada');
        }, icon: PlobbyIcons.userplus),
    };
    return PersonRow(
      leading: PlayerAvatar(p), title: p.name,
      subtitle: '@${p.username} · ELO ${p.elo} · ${p.level}${h.reason == null ? '' : '\n${h.reason}'}',
      trailing: trailing,
      onTap: () => context.push('/player/${p.id}'),
    );
  }
}
