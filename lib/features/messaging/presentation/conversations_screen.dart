import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../social/presentation/player_tile.dart';
import '../application/messaging_providers.dart';
import 'group_avatar.dart';

String _when(DateTime d) {
  final n = DateTime.now(), t = DateTime(n.year, n.month, n.day), x = DateTime(d.year, d.month, d.day);
  if (x == t) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (t.difference(x).inDays == 1) return 'Ayer';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// «Mensajes» — `scChats` del prototipo HTML: cabecera con nuevo grupo / nuevo mensaje, búsqueda y filas `.cvr`.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(conversationSearchProvider).toLowerCase();
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Row(children: [
          IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', onPressed: () => context.pop()),
          const SizedBox(width: 12),
          Expanded(child: Semantics(header: true, child: const Text('Mensajes', textAlign: TextAlign.center, style: PlobbyHeaderBar.titleStyle))),
          IconSquareButton(icon: PlobbyIcons.userplus, tooltip: 'Nuevo grupo', onPressed: () => context.push('/messages/group/new')),
          const SizedBox(width: 8),
          IconSquareButton(icon: PlobbyIcons.edit, tooltip: 'Nuevo mensaje', onPressed: () => context.push('/friends')),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 8), child: SearchField(hint: 'Buscar conversaciones', onChanged: (v) => ref.read(conversationSearchProvider.notifier).state = v)),
        Expanded(child: ref.watch(conversationsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(conversationsProvider))),
          data: (all) {
            final l = all.where((c) => q.isEmpty || c.title.toLowerCase().contains(q)).toList();
            if (l.isEmpty) {
              return Padding(padding: const EdgeInsets.all(20), child: Align(alignment: Alignment.topCenter, child: EmptyStateCard(icon: Icons.forum_outlined,
                  title: q.isEmpty ? 'Aún no tienes conversaciones' : 'Sin resultados',
                  text: q.isEmpty ? 'Escribe a un amigo o crea un grupo para empezar a hablar.' : 'Prueba con otro nombre.',
                  primary: q.isEmpty ? 'Nuevo mensaje' : null, onPrimary: () => context.push('/friends'))));
            }
            return ListView.builder(padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom), itemCount: l.length, itemBuilder: (_, i) {
              final c = l[i], un = c.unread > 0;
              return Semantics(button: true, label: '${c.title}${c.isGroup ? ', grupo' : ''}. ${c.preview}${un ? '. ${c.unread} sin leer' : ''}', excludeSemantics: true, child: InkWell(
                onTap: () => context.push('/messages/${c.id}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0x1A171C19)))),
                  child: Row(children: [
                    c.isGroup ? GroupAvatar(url: c.groupAvatarUrl, bytes: c.groupAvatarBytes, presetId: c.groupAvatarId, size: 48) : PlayerAvatar(c.other!, size: 48),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))),
                        if (c.isGroup) const Padding(padding: EdgeInsets.only(left: 6), child: PlobbyIcon(PlobbyIcons.users, size: 14, color: AppColors.textMuted)),
                      ]),
                      const SizedBox(height: 2),
                      Text(c.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, letterSpacing: 0,
                          fontWeight: un ? FontWeight.w700 : FontWeight.w400, color: un ? AppColors.text : AppColors.textMuted)),
                    ])),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if (c.last != null) Text(_when(c.last!.createdAt), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, letterSpacing: 0, color: AppColors.textMuted)),
                      if (un) Padding(padding: const EdgeInsets.only(top: 6), child: Container(
                        height: 20, constraints: const BoxConstraints(minWidth: 20), padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.inverse, borderRadius: BorderRadius.circular(10)),
                        child: Text('${c.unread}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.brand)))),
                    ]),
                  ]),
                ),
              ));
            });
          },
        )),
      ])),
    );
  }
}
