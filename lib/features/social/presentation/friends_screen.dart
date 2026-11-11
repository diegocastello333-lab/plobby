import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';
import '../application/social_providers.dart';
import '../domain/social_models.dart';
import 'player_tile.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(friendsProvider);
    final list = ref.watch(friendFilterProvider);
    final count = ref.watch(friendCountProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Amigos $count'),
        actions: [IconButton(tooltip: 'Añadir amigos', icon: const Icon(Icons.person_add_alt_1), onPressed: () => context.push('/friends/add'))],
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: TextButton(onPressed: () => ref.invalidate(friendsProvider), child: const Text('No se pudo cargar. Reintentar'))),
        data: (friends) => friends.isEmpty
            ? _Empty(onFind: () => context.push('/friends/add'))
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: SearchBar(hintText: 'Buscar por nombre o usuario', leading: const Icon(Icons.search),
                      onChanged: (v) => ref.read(friendSearchQueryProvider.notifier).state = v),
                ),
                Expanded(child: list.maybeWhen(
                  data: (l) => l.isEmpty
                      ? const Center(child: Text('Ningún amigo coincide con tu búsqueda'))
                      : ListView.separated(itemCount: l.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, i) => _FriendTile(l[i])),
                  orElse: () => const SizedBox())),
              ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onFind});
  final VoidCallback onFind;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.groups_2_outlined, size: 56, color: PlobbyColors.mute),
        const SizedBox(height: 12),
        Text('Tu comunidad de pádel empieza aquí', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Añade a tus compañeros para ver sus partidos, hablar con ellos e invitarles a jugar.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(onPressed: onFind, child: const Text('Buscar amigos')),
      ])));
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile(this.f);
  final Friend f;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = f.player;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: PlayerAvatar(p),
      title: Row(children: [
        Flexible(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
        if (f.activity.streak >= 3) Padding(padding: const EdgeInsets.only(left: 6), child: Text('🔥${f.activity.streak}', style: const TextStyle(fontSize: 12))),
      ]),
      subtitle: Text('@${p.username} · ${p.level}${f.activity.lastMatch == null ? '' : '\n${f.activity.lastMatch}'}'),
      isThreeLine: f.activity.lastMatch != null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${p.elo}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Text('ELO', style: TextStyle(fontSize: 11, color: PlobbyColors.mute)),
        ]),
        IconButton(tooltip: 'Opciones de ${p.name}', icon: const Icon(Icons.more_horiz), onPressed: () => _options(context, ref)),
      ]),
      onTap: () => context.push('/player/${p.id}'),
    );
  }

  void _options(BuildContext context, WidgetRef ref) => showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.person_outline), title: const Text('Ver perfil'), onTap: () { Navigator.pop(context); context.push('/player/${f.player.id}'); }),
          ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Enviar mensaje'), onTap: () { Navigator.pop(context); context.push('/messages/with/${f.player.id}'); }),
          ListTile(leading: const Icon(Icons.sports_tennis), title: const Text('Invitar a jugar'), onTap: () { Navigator.pop(context); context.push('/messages/with/${f.player.id}?invite=1'); }),
          ListTile(leading: const Icon(Icons.person_remove_outlined, color: PlobbyColors.loss), title: const Text('Eliminar amigo', style: TextStyle(color: PlobbyColors.loss)),
              onTap: () async {
                Navigator.pop(context);
                final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                  title: Text('¿Eliminar a ${f.player.name}?'),
                  content: const Text('Dejaréis de ver vuestra actividad y se cerrará la conversación privada.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Eliminar'))]));
                if (ok == true) await ref.read(friendsProvider.notifier).remove(f.player.id);
              }),
        ])),
      );
}
