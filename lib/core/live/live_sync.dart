import 'dart:async';
import 'package:flutter/material.dart';
import '../motion/app_motion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/domain/auth_models.dart' show isValidAvatarId;
import '../../features/leagues/application/league_providers.dart' show standingsProvider;
import '../../features/matches/application/lifecycle_providers.dart' show upcomingMatchesProvider, matchProvider;
import '../../features/matches/application/match_providers.dart' show leagueMembersProvider;
import '../../features/profile/application/profile_providers.dart' show profileProvider;
import '../../features/profile/presentation/widgets/avatar_gallery_sheet.dart' show renderAvatarPng;
import '../errors/app_errors.dart';
import '../errors/failure.dart';
import '../net/network_status.dart';
import '../theme/plobby_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../supabase/user_channel.dart' show ProfileEvent;
import 'presence.dart';
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
  StreamSubscription<ProfileEvent>? _profiles;
  Timer? _peopleDebounce, _healTimer;
  DateTime? _hiddenAt;
  bool _offline = false;
  StreamSubscription<bool>? _offlineSub;
  StreamSubscription<void>? _restoredSub;
  /// Ausencia mínima para recargar los datos sociales al volver a la app.
  static const resumeRefreshAfter = Duration(seconds: 10);
  LiveBanner? _banner;
  Timer? _hide;
  int _seq = 0;
  /// Sin sesión (bienvenida) no hay nada que sincronizar. El ProviderScope se recrea al iniciar o cerrar sesión,
  /// así que basta con comprobarlo una vez.
  late final bool _signedIn = ref.read(authRepositoryProvider).currentUser != null;

  @override
  void initState() {
    super.initState();
    // Conexión: aviso discreto SOLO cuando el dispositivo no tiene red (navigator.onLine == false es fiable; == true no
    // garantiza Internet, por eso no se usa para afirmar que «no hay conexión»). También en la bienvenida (sin sesión).
    _offline = NetworkStatus.isDeviceOffline;
    _offlineSub = NetworkStatus.offlineChanges.listen((off) { if (mounted && off != _offline) setState(() => _offline = off); });
    if (!_signedIn) return;
    WidgetsBinding.instance.addObserver(this);
    _incoming = ref.read(messagingRepositoryProvider).watchIncoming().listen(_onMessage);
    _profiles = ref.read(socialRepositoryProvider).profileUpdates().listen(_onProfile);
    ref.read(presenceServiceProvider).setActive(true);   // «En línea» para mis amigos mientras uso la app
    _healTimer = Timer(const Duration(seconds: 2), () => unawaited(_healAvatar()));
    // Al volver la red: sesión al día y datos frescos.
    _restoredSub = NetworkStatus.restored.listen((_) => unawaited(_onConnectionRestored()));
  }

  /// La red ha vuelto: renovar el token si caducó mientras no había red (en el iPhone el temporizador de renovación no
  /// corre con la app en segundo plano) y recargar lo social. Las pantallas con error reintentan solas (ErrorStateCard).
  /// Solo LECTURAS: ninguna acción (crear partido, confirmar resultado…) se repite sola.
  Future<void> _onConnectionRestored() async {
    try {
      final s = Supabase.instance.client.auth.currentSession;
      if (s != null && s.isExpired) await refreshSessionIfPossible();
    } catch (_) {/* modo demostración: sin cliente de Supabase */}
    if (!mounted) return;
    refreshSocial(ref);
    ref.invalidate(chatProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incoming?.cancel();
    _profiles?.cancel();
    _hide?.cancel();
    _peopleDebounce?.cancel();
    _healTimer?.cancel();
    _offlineSub?.cancel();
    _restoredSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(presenceServiceProvider).setActive(true);
        // Realtime no reenvía lo ocurrido mientras la app estaba en segundo plano: se recarga lo que puede haber cambiado.
        // Solo tras una ausencia real (≥ [resumeRefreshAfter] oculta): en la web «resumed» llega también al recuperar el
        // foco (cerrar la hoja de compartir, volver de otra pestaña un segundo…) y cada vez se recargaban ~8 fuentes de
        // datos (≈12 peticiones). En ausencias cortas la conexión de tiempo real sigue viva y, si se cortó, el canal
        // compartido ya hace su propia resincronización al reconectar.
        final away = _hiddenAt == null ? Duration.zero : DateTime.now().difference(_hiddenAt!);
        _hiddenAt = null;
        if (away >= resumeRefreshAfter) {
          refreshSocial(ref);
          ref.invalidate(chatProvider);
        }
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        _hiddenAt ??= DateTime.now();
        ref.read(presenceServiceProvider).setActive(false);   // en segundo plano o cerrada → «Desconectado»
      case AppLifecycleState.inactive:
        break;   // transitorio (llamada, persiana de notificaciones): no cambia la presencia
    }
  }

  /// Un jugador visible en mis pantallas cambió su foto, avatar o nombre: se vuelven a pedir los datos que lo muestran
  /// (las URLs de foto son únicas por subida, así que la imagen nueva no sale de la caché; al eliminarla, la URL pasa a
  /// nula y se dibuja el avatar). Varios cambios seguidos → una sola recarga.
  void _onProfile(ProfileEvent e) {
    _peopleDebounce?.cancel();
    _peopleDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      for (final p in <ProviderOrFamily>[friendsProvider, requestsProvider, conversationsProvider, conversationProvider, groupMembersProvider,
          profileProvider, feedControllerProvider, notificationsProvider, upcomingMatchesProvider, matchProvider, standingsProvider, leagueMembersProvider]) {
        ref.invalidate(p);
      }
    });
  }

  /// Perfiles que eligieron un avatar antes de que se guardara como imagen (solo `avatar_id`, sin URL): los demás veían
  /// sus iniciales. Se genera la imagen del avatar UNA vez y se guarda; a partir de ahí todos lo ven.
  Future<void> _healAvatar() async {
    if (!mounted) return;
    try {
      final auth = ref.read(authRepositoryProvider);
      final d = await auth.loadOnboarding();
      final id = d.avatarId;
      if (!isValidAvatarId(id) || (d.avatarUrl ?? '').isNotEmpty) return;
      final url = await auth.uploadAvatar(await renderAvatarPng(id!), 'image/png');
      await auth.saveStep(3, d.copyWith(avatarUrl: url, avatarId: id));
      await auth.deleteAvatarFiles(keepUrl: url);
      if (mounted) ref.invalidate(profileProvider);
    } catch (e, s) {
      AppErrors.record(e, s, origin: 'avatar');
    }
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
    AppHaptics.tap();
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
    if (!_signedIn) return Stack(children: [widget.child, _offlinePill()]);
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
      _offlinePill(),
    ]);
  }
}

/// Cápsula discreta mientras el dispositivo no tiene red (no tapa nada ni bloquea la navegación).
extension on _LiveSyncState {
  Widget _offlinePill() => Positioned(left: 0, right: 0, top: 0, child: IgnorePointer(child: SafeArea(bottom: false, child: Center(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        // Material: la cápsula se dibuja por encima del Navigator (sin Material el texto saldría subrayado en amarillo).
        child: !_offline ? const SizedBox.shrink() : Semantics(liveRegion: true, label: 'Sin conexión', excludeSemantics: true, child: Material(type: MaterialType.transparency, child: Container(
          margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rPill, boxShadow: AppShadows.pop),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('Sin conexión', style: PlobbyText.value.copyWith(fontSize: 12.5, color: AppColors.ink50)),
          ]),
        ))),
      )))));
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
