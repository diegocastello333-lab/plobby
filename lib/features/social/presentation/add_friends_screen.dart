import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';
import '../application/social_providers.dart';
import '../domain/social_models.dart';
import 'player_tile.dart';

class AddFriendsScreen extends ConsumerWidget {
  const AddFriendsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(addFriendsQueryProvider);
    final reqs = ref.watch(requestsProvider).valueOrNull ?? const FriendRequests();
    return Scaffold(
      appBar: AppBar(title: const Text('Añadir amigos')),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: SearchBar(
            hintText: 'Nombre o usuario', leading: const Icon(Icons.search),
            onChanged: (v) => ref.read(addFriendsQueryProvider.notifier).state = v)),
        if (q.trim().isNotEmpty) ...[
          _Header('Resultados'),
          ...ref.watch(addFriendsSearchProvider).when(
            loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
            error: (_, __) => [const ListTile(title: Text('No se pudo buscar. Inténtalo de nuevo.'))],
            data: (hits) => hits.isEmpty
                ? [Padding(padding: const EdgeInsets.all(24), child: Text('No encontramos a nadie con “$q”.'))]
                : hits.map((h) => _HitTile(h)).toList()),
        ] else ...[
          if (reqs.incoming.isNotEmpty) ...[
            _Header('Solicitudes recibidas', reqs.incoming.length),
            for (final r in reqs.incoming)
              ListTile(
                leading: PlayerAvatar(r.player),
                title: Text(r.player.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('@${r.player.username} · ELO ${r.player.elo}'),
                onTap: () => context.push('/player/${r.player.id}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton(onPressed: () => ref.read(requestsProvider.notifier).respond(r.id, true), child: const Text('Aceptar')),
                  const SizedBox(width: 6),
                  OutlinedButton(onPressed: () => ref.read(requestsProvider.notifier).respond(r.id, false), child: const Text('Rechazar')),
                ]),
              ),
          ],
          if (reqs.outgoing.isNotEmpty) ...[
            _Header('Solicitudes enviadas', reqs.outgoing.length),
            for (final r in reqs.outgoing)
              ListTile(
                leading: PlayerAvatar(r.player),
                title: Text(r.player.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('@${r.player.username} · Pendiente'),
                trailing: OutlinedButton(onPressed: () => ref.read(requestsProvider.notifier).cancel(r.id), child: const Text('Cancelar')),
              ),
          ],
          _Header('Sugerencias para ti'),
          ...ref.watch(suggestionsProvider).maybeWhen(data: (l) => l.map((h) => _HitTile(h)).toList(), orElse: () => const <Widget>[]),
        ],
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.t, [this.n]);
  final String t; final int? n;
  @override
  Widget build(BuildContext c) => Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 6), child: Row(children: [
        Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: PlobbyColors.mute)),
        const Spacer(), if (n != null) Text('$n', style: const TextStyle(color: PlobbyColors.mute)),
      ]));
}

class _HitTile extends ConsumerWidget {
  const _HitTile(this.h);
  final SearchHit h;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = h.player;
    Widget trailing;
    switch (h.relation) {
      case RelationState.friend:
        trailing = const Chip(label: Text('Amigos'), avatar: Icon(Icons.check, size: 16));
      case RelationState.requestSent:
        trailing = const Chip(label: Text('Solicitud enviada')); // deshabilitado: evita duplicados
      case RelationState.requestReceived:
        trailing = FilledButton(onPressed: () async {
          final r = (await ref.read(requestsProvider.future)).incoming.firstWhere((x) => x.player.id == p.id);
          await ref.read(requestsProvider.notifier).respond(r.id, true);
        }, child: const Text('Aceptar'));
      case RelationState.none:
        trailing = FilledButton.icon(
          icon: const Icon(Icons.person_add_alt_1, size: 16), label: const Text('Añadir'),
          onPressed: () async {
            await ref.read(requestsProvider.notifier).send(p.id);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitud enviada')));
          });
    }
    return ListTile(
      leading: PlayerAvatar(p),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('@${p.username} · ELO ${p.elo} · ${p.level}${h.reason == null ? '' : '\n${h.reason}'}'),
      trailing: trailing,
      onTap: () => context.push('/player/${p.id}'),
    );
  }
}
