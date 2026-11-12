import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../../../core/theme/plobby_text.dart';
import '../../../../core/widgets/motion_widgets.dart';
import '../../../../core/widgets/plobby_components.dart';
import '../../../../core/widgets/plobby_icon.dart';
import '../../../../core/widgets/silhouette_avatar.dart';
import '../../../../core/widgets/state_views.dart' show showPlobbySnack;
import '../../domain/models.dart';
import '../../../social/application/social_providers.dart';
import '../../../social/domain/social_models.dart' show RelationState;
import '../../../auth/domain/auth_models.dart' show isValidAvatarId;
import '../../../auth/presentation/avatar_catalog.dart' show PlobbyAvatar;

/// Cabecera oscura del perfil — `.ph` del prototipo HTML (medidas de getComputedStyle):
/// fila superior «MI PERFIL» (o Volver) + botones de cristal; avatar 84 px con aro lima (padding 3 + anillo 2);
/// nombre Inter 24/800; usuario y ubicación marfil .72; bio 14/1.5; chips 26 px radio 7; dos botones 44 px radio 11
/// en proporción 1 : 1.25. Mismas acciones que antes (compartir perfil, editar, añadir amigo, compartir stats).
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key, required this.profile, required this.isOwner});
  final PlayerProfile profile; final bool isOwner;

  static const _soft = Color(0xB8F6F8F1);   // rgba(246,248,241,.72)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    // Estado de amistad y contador: MISMA fuente que Amigos (friendsProvider + requestsProvider), así que cambian solos
    // al aceptar, cancelar o eliminar (aquí o en el otro dispositivo, vía Realtime).
    final rel = isOwner ? RelationState.none : ref.watch(relationProvider(p.id));
    final count = ref.watch(friendCountOfProvider(isOwner ? 'me' : p.id)).valueOrNull;
    return Container(
      color: AppColors.ink900,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (isOwner) Text('MI PERFIL', style: PlobbyText.eb.copyWith(color: const Color(0x99F6F8F1)))
          else IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', glass: true, onPressed: () => context.pop()),
          const Spacer(),
          IconSquareButton(icon: PlobbyIcons.share, tooltip: 'Compartir perfil', glass: true, onPressed: () => Share.share('https://plobby.app/@${p.username}')),
          if (isOwner) ...[const SizedBox(width: 8), IconSquareButton(icon: PlobbyIcons.sliders, tooltip: 'Ajustes del perfil', glass: true, onPressed: () => context.push('/profile/edit'))],
        ]),
        const SizedBox(height: 14),
        Row(children: [
          // .avb: padding 3 + anillo lima de 2 px alrededor del avatar de 84 px
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.lime300, width: 2)),
            child: ClipOval(child: SizedBox(width: 84, height: 84, child: p.avatarUrl != null && p.avatarUrl!.isNotEmpty
                ? Image.network(p.avatarUrl!, fit: BoxFit.cover, cacheWidth: 252, errorBuilder: (_, __, ___) => SilhouetteAvatar(seed: p.id, size: 84))
                : p.avatarId != null && isValidAvatarId(p.avatarId!) ? PlobbyAvatar(id: p.avatarId!, size: 84) : SilhouetteAvatar(seed: p.id, size: 84))),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.fullName, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: AppTypography.sansFamily, color: AppColors.ink50, fontSize: 24, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.48))),
              if (p.verified) Padding(padding: const EdgeInsets.only(left: 7), child: Semantics(label: 'Perfil verificado', child: Container(width: 20, height: 20,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.lime300),
                  child: const Center(child: PlobbyIcon(PlobbyIcons.check, size: 12, strokeWidth: 3.2, color: AppColors.ink900))))),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Flexible(child: Text('@${p.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, color: _soft, fontSize: 14, letterSpacing: 0))),
              if (count != null) Semantics(button: isOwner, label: '$count ${count == 1 ? 'amigo' : 'amigos'}', excludeSemantics: true, child: GestureDetector(
                onTap: isOwner ? () => context.push('/friends') : null,
                child: Text.rich(TextSpan(text: '  ·  ', children: [
                  TextSpan(text: '$count', style: const TextStyle(color: AppColors.lime300, fontWeight: FontWeight.w800)),
                  TextSpan(text: count == 1 ? ' amigo' : ' amigos'),
                ]), style: const TextStyle(fontFamily: AppTypography.sansFamily, color: _soft, fontSize: 14, letterSpacing: 0)),
              )),
            ]),
            if (p.location.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const PlobbyIcon(PlobbyIcons.pin, size: 13, color: _soft), const SizedBox(width: 5),
                Flexible(child: Text(p.location, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, color: _soft, fontSize: 12.5, letterSpacing: 0))),
              ]),
            ],
          ])),
        ]),
        if (p.bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(p.bio,
            style: const TextStyle(fontFamily: AppTypography.sansFamily, color: Color(0xEBF6F8F1), fontSize: 14, height: 1.5, letterSpacing: 0))),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _Chip('Nivel declarado', p.declaredLevel), _Chip('Posición', p.side == PlaySide.right ? 'Derecha' : 'Izquierda'), _Chip('Mano', p.dominantHand),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(flex: 100, child: isOwner
              ? _Btn('Editar perfil', PlobbyIcons.edit, false, () => context.push('/profile/edit'))
              : AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: _friendButton(context, ref, rel, p))),
          const SizedBox(width: 10),
          Expanded(flex: 125, child: isOwner
              ? _Btn('Compartir mis stats', PlobbyIcons.share, true, () => context.push('/profile/share'))
              : rel == RelationState.friend
                  ? _Btn('Enviar mensaje', PlobbyIcons.plane, true, () => context.push('/messages/with/${p.id}'))
                  : _Btn('Compartir perfil', PlobbyIcons.share, true, () => Share.share('https://plobby.app/@${p.username}'))),
        ]),
      ]),
    );
  }
}

/// Botón de amistad del perfil ajeno según la relación real. Cada acción llama a la RPC correspondiente y refresca
/// la fuente común (amigos/solicitudes), así que el botón cambia de estado solo.
Widget _friendButton(BuildContext context, WidgetRef ref, RelationState rel, PlayerProfile p) {
  final id = p.id, name = p.fullName;
  Future<void> run(Future<void> Function() job, String ok, String fail) async {
    try {
      await job();
      HapticFeedback.mediumImpact();
      if (context.mounted) showPlobbySnack(context, ok);
    } catch (_) {
      if (context.mounted) showPlobbySnack(context, fail, error: true);
    }
  }
  final requests = ref.read(requestsProvider.notifier);
  return switch (rel) {
    RelationState.friend => _Btn('Amigos', PlobbyIcons.check, false, key: const ValueKey('friend'), () => showPlobbySheet(context, (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(title: name, subtitle: 'Sois amigos en Plobby'),
          SheetListItem(icon: PlobbyIcons.plane, label: 'Enviar mensaje', onTap: () { Navigator.pop(c); context.push('/messages/with/$id'); }),
          SheetListItem(icon: PlobbyIcons.racket, label: 'Invitar a jugar', onTap: () { Navigator.pop(c); context.push('/messages/with/$id?invite=1'); }),
          SheetListItem(icon: PlobbyIcons.trash, label: 'Eliminar amigo', danger: true, onTap: () {
            Navigator.pop(c);
            run(() => ref.read(friendsProvider.notifier).remove(id), '$name ya no está en tus amigos', 'No se pudo eliminar. Inténtalo de nuevo.');
          }),
        ]))),
    RelationState.requestSent => _Btn('Solicitud enviada', PlobbyIcons.clock, false, key: const ValueKey('sent'), () {
        final r = ref.read(requestWithProvider(id));
        if (r != null) run(() => requests.cancel(r.id), 'Solicitud cancelada', 'No se pudo cancelar. Inténtalo de nuevo.');
      }),
    RelationState.requestReceived => _Btn('Aceptar solicitud', PlobbyIcons.userplus, true, key: const ValueKey('received'), () {
        final r = ref.read(requestWithProvider(id));
        if (r != null) run(() => requests.respond(r.id, true), 'Ahora sois amigos', 'No se pudo aceptar. Inténtalo de nuevo.');
      }),
    RelationState.none => _Btn('Añadir amigo', PlobbyIcons.userplus, false, key: const ValueKey('none'),
        () => run(() => requests.send(id), 'Solicitud enviada a $name', 'No se pudo enviar la solicitud. Inténtalo de nuevo.')),
  };
}

/// `.ph .ch span`: 26 px, radio 7, marfil .12, Inter 12/600 con el valor en lima 800.
class _Chip extends StatelessWidget {
  const _Chip(this.k, this.v);
  final String k, v;
  @override
  Widget build(BuildContext context) => Container(
      height: 26, padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: const Color(0x1FF6F8F1), borderRadius: BorderRadius.circular(7)),
      child: Center(widthFactor: 1, child: Text.rich(TextSpan(text: '$k ', style: const TextStyle(fontFamily: AppTypography.sansFamily, color: AppColors.ink50, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0),
          children: [TextSpan(text: v, style: const TextStyle(color: AppColors.lime300, fontWeight: FontWeight.w800))]))));
}

/// `.ph .acts button`: 44 px, radio 11, Inter 14/700; `.g` marfil .14 · `.l` lima.
class _Btn extends StatelessWidget {
  const _Btn(this.t, this.i, this.hi, this.f, {super.key});
  final String t; final PlobbyIcons i; final bool hi; final VoidCallback f;
  @override
  Widget build(BuildContext context) {
    final fg = hi ? AppColors.ink900 : AppColors.ink50;
    return Semantics(button: true, label: t, excludeSemantics: true, child: Pressable(child: Material(
      color: hi ? AppColors.lime300 : const Color(0x24F6F8F1), borderRadius: BorderRadius.circular(11),
      child: InkWell(borderRadius: BorderRadius.circular(11), onTap: f, child: SizedBox(height: 44, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        PlobbyIcon(i, size: 16, color: fg), const SizedBox(width: 7),
        Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: fg))),
      ]))),
    )));
  }
}
