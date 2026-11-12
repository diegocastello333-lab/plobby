import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/feed_providers.dart';
import '../domain/feed_models.dart';
import 'widgets/activity_cards.dart';

/// Título corto e icono de cada tipo (como `scFNotifs` del prototipo HTML).
(String, PlobbyIcons) notificationTitle(NotificationType t) => switch (t) {
      NotificationType.reaction => ('Reacciones a tu partido', PlobbyIcons.thumb),
      NotificationType.comment => ('Nuevo comentario', PlobbyIcons.feed),
      NotificationType.friendRequest => ('Solicitud de amistad', PlobbyIcons.userplus),
      NotificationType.friendAccepted => ('Solicitud aceptada', PlobbyIcons.check),
      NotificationType.playInvite => ('Te invita a jugar', PlobbyIcons.ball),
      NotificationType.matchConfirmationRequired => ('Confirma el resultado', PlobbyIcons.shield),
      NotificationType.matchConfirmed => ('Partido confirmado', PlobbyIcons.check),
      NotificationType.matchDisputed => ('Resultado en disputa', PlobbyIcons.alert),
      NotificationType.matchEvent => ('Novedad en tu partido', PlobbyIcons.ball),
      NotificationType.achievement => ('Nueva insignia', PlobbyIcons.star),
      NotificationType.streak => ('Racha de victorias', PlobbyIcons.flame),
      NotificationType.eloMilestone => ('Nuevo hito de ELO', PlobbyIcons.arrup),
      NotificationType.ratingChange => ('Tu ELO ha cambiado', PlobbyIcons.arrup),
      NotificationType.leagueInvite => ('Invitación a una liga', PlobbyIcons.trophy),
      NotificationType.leagueStarting => ('Tu liga empieza pronto', PlobbyIcons.trophy),
      NotificationType.leaguePositionChange => ('Cambio en la clasificación', PlobbyIcons.trophy),
      NotificationType.directMessage => ('Nuevo mensaje', PlobbyIcons.plane),
      NotificationType.groupMessage => ('Mensaje en un grupo', PlobbyIcons.users),
      NotificationType.groupAdded => ('Nuevo grupo', PlobbyIcons.users),
    };

/// Notificaciones — `scFNotifs` del prototipo HTML: agrupadas por día, sin leer con fondo lima suave y punto,
/// y acciones en línea (aceptar / rechazar, confirmar / disputar, unirme / ignorar).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);
    final n = ref.read(notificationsProvider.notifier);
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Row(children: [
          IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', onPressed: () => context.pop()),
          const SizedBox(width: 14),
          Expanded(child: Semantics(header: true, child: const Text('Notificaciones', maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyHeaderBar.titleStyle))),
          if (unread > 0) PlobbyButton(label: 'Marcar leídas', kind: PlobbyButtonKind.smallOutline, onPressed: () => n.markRead()),
        ])),
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(notificationsProvider))),
          data: (list) {
            if (list.isEmpty) {
              return const Padding(padding: EdgeInsets.all(20), child: EmptyStateCard(icon: Icons.notifications_none, title: 'Todo al día',
                  text: 'Aquí verás solicitudes, partidos por confirmar, logros e invitaciones.'));
            }
            final now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
            String bucket(DateTime d) { final day = DateTime(d.year, d.month, d.day); return day == today ? 'Hoy' : day == today.subtract(const Duration(days: 1)) ? 'Ayer' : 'Anteriores'; }
            final sorted = [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final rows = <Object>[]; String? last;
            for (final x in sorted) { final b = bucket(x.createdAt); if (b != last) { rows.add(b); last = b; } rows.add(x); }
            return ListView.builder(
              padding: EdgeInsets.only(top: 8, bottom: 40 + MediaQuery.paddingOf(context).bottom),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final x = rows[i];
                if (x is String) return Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 10), child: Semantics(header: true, child: Text(x.toUpperCase(), style: PlobbyText.eb)));
                return _Row(n: x as AppNotification, onTap: () { n.markRead(x.id); context.push(x.type.route(x)); }, onRespond: (ok) => n.respond(x.id, ok));
              },
            );
          },
        )),
      ])),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.n, required this.onTap, required this.onRespond});
  final AppNotification n; final VoidCallback onTap; final ValueChanged<bool> onRespond;
  @override
  Widget build(BuildContext context) {
    final (title, icon) = notificationTitle(n.type);
    final (yes, no) = switch (n.type) {
      NotificationType.friendRequest => ('Aceptar', 'Rechazar'),
      NotificationType.matchConfirmationRequired => ('Confirmar', 'Disputar'),
      NotificationType.playInvite => ('Aceptar', 'Ignorar'),
      _ => ('Unirme', 'Ignorar'),
    };
    // Material propio: el fondo lima de «sin leer» no oculta el efecto al pulsar (antes daba un aviso de ListTile).
    return Material(
      color: n.isRead ? Colors.transparent : const Color(0x24D2F548),
      child: InkWell(onTap: onTap, child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 44, height: 44, child: Stack(clipBehavior: Clip.none, children: [
            n.actors.isEmpty
                ? Container(width: 40, height: 40, decoration: const BoxDecoration(color: AppColors.inverse, shape: BoxShape.circle), child: Center(child: PlobbyIcon(icon, size: 18, color: AppColors.brand)))
                : avatar(n.actors.first, 20),
            Positioned(left: 26, top: 26, child: Container(width: 18, height: 18, decoration: BoxDecoration(color: AppColors.inverse, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.bg, width: 1.5)),
                child: Center(child: PlobbyIcon(icon, size: 10, strokeWidth: 2.2, color: AppColors.brand)))),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            const SizedBox(height: 2),
            Text(n.text, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, height: 1.4, letterSpacing: 0, color: AppColors.ink700)),
            const SizedBox(height: 3),
            Text(timeAgo(n.createdAt), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted)),
            if (n.actionable) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, runSpacing: 8, children: [
              PlobbyButton(label: yes, kind: PlobbyButtonKind.small, onPressed: () => onRespond(true)),
              PlobbyButton(label: no, kind: PlobbyButtonKind.smallOutline, onPressed: () => onRespond(false)),
            ])),
          ])),
          if (!n.isRead) Padding(padding: const EdgeInsets.only(left: 8, top: 6), child: Semantics(label: 'Sin leer', child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle)))),
        ]),
      )),
    );
  }
}
