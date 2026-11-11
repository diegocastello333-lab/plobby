import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';
import '../application/feed_providers.dart';
import '../domain/feed_models.dart';
import 'widgets/activity_cards.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);
    final n = ref.read(notificationsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones'), backgroundColor: PlobbyColors.ivory, actions: [if (unread > 0) TextButton(onPressed: () => n.markRead(), child: const Text('Marcar leídas'))]),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: TextButton(onPressed: () => ref.invalidate(notificationsProvider), child: const Text('No se pudo cargar. Reintentar'))),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Todo al día. Aquí verás solicitudes, partidos por confirmar, logros e invitaciones.'));
          final now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
          String bucket(DateTime d) { final day = DateTime(d.year, d.month, d.day); return day == today ? 'Hoy' : day == today.subtract(const Duration(days: 1)) ? 'Ayer' : 'Anteriores'; }
          final sorted = [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final rows = <Object>[]; String? last;
          for (final x in sorted) { final b = bucket(x.createdAt); if (b != last) { rows.add(b); last = b; } rows.add(x); }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final x = rows[i];
              if (x is String) return Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 6), child: Text(x.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: PlobbyColors.mute)));
              final nn = x as AppNotification;
              return Container(color: nn.isRead ? null : const Color(0x14D2F548), child: ListTile(
                leading: nn.actors.isEmpty ? const CircleAvatar(backgroundColor: PlobbyColors.forest, child: Icon(Icons.notifications, color: PlobbyColors.lime)) : avatar(nn.actors.first, 21),
                title: Text(nn.text, style: const TextStyle(fontSize: 14)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(timeAgo(nn.createdAt)),
                  if (nn.actionable) Row(children: [
                    FilledButton(onPressed: () => n.respond(nn.id, true), child: Text(nn.type == NotificationType.friendRequest ? 'Aceptar' : nn.type == NotificationType.matchConfirmationRequired ? 'Confirmar' : 'Unirme')),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: () => n.respond(nn.id, false), child: Text(nn.type == NotificationType.friendRequest ? 'Rechazar' : nn.type == NotificationType.matchConfirmationRequired ? 'Disputar' : 'Ignorar')),
                  ]),
                ]),
                trailing: nn.isRead ? null : const Icon(Icons.circle, size: 8, color: PlobbyColors.forest),
                onTap: () { n.markRead(nn.id); context.push(nn.type.route(nn)); },
              ));
            },
          );
        },
      ),
    );
  }
}
