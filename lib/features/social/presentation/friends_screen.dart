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

/// «Amigos» — `scFriends` del prototipo HTML: cabecera con contador, búsqueda y filas con ELO y opciones.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(friendsProvider);
    final list = ref.watch(friendFilterProvider);
    final count = ref.watch(friendCountProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(children: [
        // .top: volver · «Amigos n» · añadir
        Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Row(children: [
          IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', onPressed: () => context.pop()),
          Expanded(child: Semantics(header: true, child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Amigos '),
            TextSpan(text: '$count', style: const TextStyle(color: AppColors.borderStrong)),
          ]), textAlign: TextAlign.center, style: PlobbyHeaderBar.titleStyle))),
          IconSquareButton(icon: PlobbyIcons.userplus, tooltip: 'Añadir amigos', onPressed: () => context.push('/friends/add')),
        ])),
        Expanded(child: all.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(friendsProvider))),
          data: (friends) => friends.isEmpty
              ? Padding(padding: const EdgeInsets.all(20), child: EmptyStateCard(icon: Icons.groups_2_outlined, title: 'Tu comunidad de pádel empieza aquí',
                  text: 'Añade a tus compañeros para ver sus partidos, hablar con ellos e invitarles a jugar.', primary: 'Buscar amigos', onPrimary: () => context.push('/friends/add')))
              : ListView(padding: EdgeInsets.fromLTRB(20, 14, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
                  SearchField(hint: 'Buscar por nombre o usuario', onChanged: (v) => ref.read(friendSearchQueryProvider.notifier).state = v),
                  const SizedBox(height: 12),
                  ...list.maybeWhen(
                    data: (l) => l.isEmpty
                        ? [const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Ningún amigo coincide con tu búsqueda', textAlign: TextAlign.center, style: PlobbyText.sub))]
                        : [for (final f in l) _FriendTile(f)],
                    orElse: () => const <Widget>[]),
                ]),
        )),
      ])),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile(this.f);
  final Friend f;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = f.player;
    final elo = p.elo >= 1000 ? '${p.elo ~/ 1000}.${(p.elo % 1000).toString().padLeft(3, '0')}' : '${p.elo}';
    return PersonRow(
      leading: PlayerAvatar(p),
      title: p.name,
      semanticsLabel: '${p.name}, ELO ${p.elo}',
      titleTrailing: f.activity.streak >= 3 ? Row(mainAxisSize: MainAxisSize.min, children: [
        const PlobbyIcon(PlobbyIcons.flame, size: 13, color: AppColors.brandText),
        Text('${f.activity.streak}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.brandText)),
      ]) : null,
      subtitle: '@${p.username} · ${p.level}${f.activity.lastMatch == null ? '' : '\n${f.activity.lastMatch}'}',
      onTap: () => context.push('/player/${p.id}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(elo, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.16, color: AppColors.text)),
          const Text('ELO', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10, letterSpacing: 0, color: AppColors.textMuted)),
        ]),
        const SizedBox(width: 4),
        Tooltip(message: 'Opciones de ${p.name}', child: Semantics(button: true, label: 'Opciones de ${p.name}', excludeSemantics: true, child: InkResponse(
            onTap: () => _options(context, ref), radius: 22,
            child: const SizedBox(width: 40, height: 44, child: Center(child: PlobbyIcon(PlobbyIcons.more, size: 20)))))),
      ]),
    );
  }

  void _options(BuildContext context, WidgetRef ref) => showPlobbySheet(context, (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeader(title: f.player.name, subtitle: '@${f.player.username}'),
        SheetListItem(icon: PlobbyIcons.user, label: 'Ver perfil', onTap: () { Navigator.pop(c); context.push('/player/${f.player.id}'); }),
        SheetListItem(icon: PlobbyIcons.plane, label: 'Enviar mensaje', onTap: () { Navigator.pop(c); context.push('/messages/with/${f.player.id}'); }),
        SheetListItem(icon: PlobbyIcons.racket, label: 'Invitar a jugar', onTap: () { Navigator.pop(c); context.push('/messages/with/${f.player.id}?invite=1'); }),
        SheetListItem(icon: PlobbyIcons.trash, label: 'Eliminar amigo', danger: true, onTap: () async {
          Navigator.pop(c);
          final ok = await showPlobbySheet<bool>(context, (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(title: '¿Eliminar a ${f.player.name}?'),
            const Text('Dejaréis de ver vuestra actividad y se cerrará la conversación privada.', style: PlobbyText.sub),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(d, false))),
              const SizedBox(width: 10),
              Expanded(child: PlobbyButton(label: 'Eliminar', kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(d, true))),
            ]),
          ]));
          if (ok == true) await ref.read(friendsProvider.notifier).remove(f.player.id);
        }),
      ]));
}
