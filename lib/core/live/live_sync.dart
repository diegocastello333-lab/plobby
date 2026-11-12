import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/feed/application/feed_providers.dart';
import '../../features/feed/domain/feed_models.dart';
import '../../features/feed/presentation/notifications_screen.dart' show notificationTitle;
import '../../features/messaging/application/messaging_providers.dart';
import '../../features/messaging/domain/messaging_models.dart';
import '../../features/social/application/social_providers.dart';
import '../router/app_router.dart';
import '../theme/design_tokens.dart';
import '../widgets/plobby_icon.dart';

/// Un aviso emergente dentro de la app (mensaje nuevo, solicitud, partido…).
@immutable
class LiveBanner {
  const LiveBanner({required this.title, required this.body, required this.icon, this.route});
  final String title, body;
  final PlobbyIcons icon;
  final String? route;
}

/// Sincronización en vivo de TODA la app (envuelve al Navigator desde `MaterialApp.builder`, así funciona en cualquier
/// pantalla, no solo en las pestañas):
///  - cambios sociales por Realtime (solicitudes, amistades, avisos) → refresco de amigos, solicitudes, contadores…;
///  - al volver la app a primer plano se recarga lo social y las conversaciones (Realtime no reenvía lo perdido);
///  - mensaje nuevo fuera de su chat o aviso nuevo → banner superior que lleva a la pantalla correspondiente.
class LiveSync extends ConsumerStatefulWidget {
  const LiveSync({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<LiveSync> createState() => _LiveSyncState();
}

class _LiveSyncState extends ConsumerState<LiveSync> with WidgetsBindingObserver {
  StreamSubscription<ChatMessage>? _incoming;
  LiveBanner? _banner;
  Timer? _hide;
  int _seq = 0;
  /// Sin sesión (bienvenida) no hay nada que sincronizar. El ProviderScope se recrea al iniciar o cerrar sesión,
  /// así que basta con comprobarlo una vez.
  late final bool _signedIn = ref.read(authRepositoryProvider).currentUser != null;

  @override
  void initState() {
    super.initState();
    if (!_signedIn) return;
    WidgetsBinding.instance.addObserver(this);
    _incoming = ref.read(messagingRepositoryProvider).watchIncoming().listen(_onMessage);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incoming?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    refreshSocial(ref);
    ref.invalidate(chatProvider);
  }

  Future<void> _onMessage(ChatMessage m) async {
    if (activeConversation.value == m.conversationId) return;   // ya lo está viendo
    Conversation? c;
    try { c = await ref.read(messagingRepositoryProvider).conversation(m.conversationId); } catch (_) {}
    if (!mounted || activeConversation.value == m.conversationId) return;
    final preview = switch (m.kind) {
      MessageKind.match => 'Compartió un resultado', MessageKind.invite => 'Te invita a jugar · ${m.body}',
      MessageKind.profile => 'Compartió un perfil', MessageKind.league => 'Compartió una liga', _ => m.body,
    };
    final group = c?.isGroup ?? false;
    final sender = group ? (c?.lastSenderName ?? '') : '';
    _show(LiveBanner(
      title: c?.title ?? 'Nuevo mensaje',
      body: sender.isEmpty ? preview : '$sender: $preview',
      icon: group ? PlobbyIcons.users : PlobbyIcons.plane,
      route: '/messages/${m.conversationId}?name=${Uri.encodeQueryComponent(c?.title ?? 'Chat')}',
    ));
  }

  /// Avisos nuevos que no son de mensajes (esos ya tienen su banner): solicitud recibida/aceptada, partidos, ligas…
  void _onNotifications(List<AppNotification>? before, List<AppNotification> now) {
    if (before == null) return;   // primera carga: no se anuncia lo antiguo
    final seen = {for (final n in before) n.id};
    final fresh = now.where((n) => !n.isRead && !seen.contains(n.id) &&
        n.type != NotificationType.directMessage && n.type != NotificationType.groupMessage).toList();
    if (fresh.isEmpty) return;
    final n = fresh.first;
    final (title, icon) = notificationTitle(n.type);
    _show(LiveBanner(title: title, body: n.text, icon: icon, route: n.type.route(n)));
  }

  void _show(LiveBanner b) {
    HapticFeedback.lightImpact();
    _hide?.cancel();
    setState(() { _banner = b; _seq++; });
    _hide = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() { if (mounted) setState(() => _banner = null); }

  void _open(LiveBanner b) {
    _dismiss();
    if (b.route != null) ref.read(routerProvider).push(b.route!);
  }

  @override
  Widget build(BuildContext context) {
    if (!_signedIn) return widget.child;
    // Realtime social → refrescar todas las vistas que dependen de amistades, solicitudes y avisos.
    ref.listen(socialChangesProvider, (_, c) { final v = c.valueOrNull; if (v != null) applySocialChange(ref, v); });
    ref.listen<AsyncValue<List<AppNotification>>>(notificationsProvider, (a, b) {
      final now = b.valueOrNull;
      if (now != null) _onNotifications(a?.valueOrNull, now);
    });
    final b = _banner;
    return Stack(children: [
      widget.child,
      Positioned(left: 0, right: 0, top: 0, child: SafeArea(bottom: false, child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280), reverseDuration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic, switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, a) => SlideTransition(position: Tween(begin: const Offset(0, -1.2), end: Offset.zero).animate(a), child: FadeTransition(opacity: a, child: child)),
        child: b == null ? const SizedBox.shrink() : LiveBannerCard(key: ValueKey(_seq), banner: b, onTap: () => _open(b), onClose: _dismiss),
      ))),
    ]);
  }
}

/// Tarjeta del aviso: blanca, radio 14, sombra de tarjeta, icono sobre tinta con trazo lima (como las notificaciones).
class LiveBannerCard extends StatelessWidget {
  const LiveBannerCard({super.key, required this.banner, required this.onTap, required this.onClose});
  final LiveBanner banner;
  final VoidCallback onTap, onClose;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Dismissible(
          key: const ValueKey('live-banner'), direction: DismissDirection.up, onDismissed: (_) => onClose(),
          child: Semantics(container: true, button: true, liveRegion: true, label: '${banner.title}. ${banner.body}', excludeSemantics: true,
            // Sombra y fondo FUERA del recorte (si no, el recorte se come la sombra y la tarjeta se ve gris).
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x14171C19)),
                  boxShadow: const [BoxShadow(color: Color(0x29171C19), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -6)]),
              child: Material(
              type: MaterialType.transparency, borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Row(children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.inverse, borderRadius: BorderRadius.circular(10)),
                      child: Center(child: PlobbyIcon(banner.icon, size: 18, color: AppColors.brand))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(banner.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(banner.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, height: 1.35, letterSpacing: 0, color: AppColors.ink700)),
                  ])),
                ]),
              )),
            )),
          ),
        ),
      );
}
