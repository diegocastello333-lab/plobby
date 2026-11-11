import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';
import '../../social/presentation/player_tile.dart';
import '../application/messaging_providers.dart';
import '../domain/messaging_models.dart';
import 'group_avatar.dart';

String _when(DateTime d) {
  final n = DateTime.now(), t = DateTime(n.year, n.month, n.day), x = DateTime(d.year, d.month, d.day);
  if (x == t) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (t.difference(x).inDays == 1) return 'Ayer';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(conversationSearchProvider).toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes'), actions: [
        IconButton(tooltip: 'Nuevo grupo', icon: const Icon(Icons.group_add_outlined), onPressed: () => context.push('/messages/group/new')),
        IconButton(tooltip: 'Nuevo mensaje', icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/friends')),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: SearchBar(hintText: 'Buscar conversaciones', leading: const Icon(Icons.search), onChanged: (v) => ref.read(conversationSearchProvider.notifier).state = v)),
        Expanded(child: ref.watch(conversationsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(child: TextButton(onPressed: () => ref.invalidate(conversationsProvider), child: const Text('No se pudo cargar. Reintentar'))),
          data: (all) {
            final l = all.where((c) => q.isEmpty || c.title.toLowerCase().contains(q)).toList();
            if (l.isEmpty) return Center(child: Text(q.isEmpty ? 'Aún no tienes conversaciones. Escribe a un amigo o crea un grupo.' : 'Sin resultados', textAlign: TextAlign.center));
            return ListView.builder(itemCount: l.length, itemBuilder: (_, i) {
              final c = l[i];
              return ListTile(
                leading: c.isGroup
                    ? GroupAvatar(url: c.groupAvatarUrl, bytes: c.groupAvatarBytes, presetId: c.groupAvatarId, size: 48)
                    : PlayerAvatar(c.other!, size: 48),
                title: Row(children: [
                  Flexible(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: c.unread > 0 ? FontWeight.w800 : FontWeight.w600))),
                  if (c.isGroup) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.group, size: 14, color: PlobbyColors.mute)),
                ]),
                subtitle: Text(c.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (c.last != null) Text(_when(c.last!.createdAt), style: TextStyle(fontSize: 11, color: c.unread > 0 ? PlobbyColors.forest : PlobbyColors.mute, fontWeight: c.unread > 0 ? FontWeight.w800 : FontWeight.w500)),
                  if (c.unread > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Badge(label: Text('${c.unread}'), backgroundColor: PlobbyColors.forest)),
                ]),
                onTap: () => context.push('/messages/${c.id}'),
              );
            });
          },
        )),
      ]),
    );
  }
}
