import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/social_models.dart';
import '../application/messaging_providers.dart';
import '../data/messaging_repository.dart';
import '../domain/messaging_models.dart';
import 'group_avatar.dart';

/// Info del grupo (desde la cabecera del chat): participantes con rol, edición de nombre/foto (admins), añadir/quitar, abandonar.
class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.conversationId});
  final String conversationId;

  Future<void> _run(BuildContext c, WidgetRef ref, Future<void> Function() f, {String? ok}) async {
    try {
      await f();
      ref..invalidate(groupMembersProvider(conversationId))..invalidate(conversationProvider(conversationId))..invalidate(conversationsProvider);
      if (ok != null && c.mounted) showPlobbySnack(c, ok);
    } on MessagingException catch (e) {
      if (c.mounted) showPlobbySnack(c, switch (e.code) {
        'not_group_admin' => 'Solo los administradores pueden hacerlo',
        'last_admin' => 'Debe quedar al menos un administrador',
        'demote_admin_first' => 'Quita antes el rol de administrador',
        'only_friends_allowed' => 'Solo puedes añadir a tus amigos',
        _ => 'No se pudo completar la acción',
      }, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(conversationProvider(conversationId)).valueOrNull, members = ref.watch(groupMembersProvider(conversationId)).valueOrNull;
    final me = ref.read(messagingRepositoryProvider).meId, repo = ref.read(messagingRepositoryProvider);
    if (conv == null || members == null) {
      return Scaffold(body: Column(children: [PlobbyHeaderBar(title: 'Info del grupo', onBack: () => context.pop()), const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.text)))]));
    }
    final perms = GroupPerms(members, me);
    final sorted = [...members]..sort((a, b) => a.isAdmin == b.isAdmin ? a.name.compareTo(b.name) : (a.isAdmin ? -1 : 1));
    return Scaffold(
      body: Column(children: [
        PlobbyHeaderBar(title: 'Info del grupo', onBack: () => context.pop()),
        Expanded(child: ListView(padding: EdgeInsets.fromLTRB(20, 18, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          Center(child: SizedBox(width: 100, height: 100, child: Stack(clipBehavior: Clip.none, children: [
            GroupAvatar(url: conv.groupAvatarUrl, bytes: conv.groupAvatarBytes, presetId: conv.groupAvatarId, size: 96),
            if (perms.canEdit) Positioned(right: -2, bottom: -2, child: IconSquareButton(icon: PlobbyIcons.edit, tooltip: 'Cambiar foto', size: 34, onPressed: () => _photo(context, ref, repo))),
          ]))),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Semantics(header: true, child: Text(conv.title, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.text)))),
            if (perms.canEdit) ...[const SizedBox(width: 8), IconSquareButton(icon: PlobbyIcons.edit, tooltip: 'Cambiar nombre', size: 32, onPressed: () => _rename(context, ref, repo, conv.title))],
          ]),
          const SizedBox(height: 4),
          Text('${members.length} participantes', textAlign: TextAlign.center, style: PlobbyText.sub),
          const SizedBox(height: 26),
          Row(children: [
            const Expanded(child: Text('PARTICIPANTES', style: PlobbyText.eb)),
            if (perms.canAdd) Semantics(button: true, label: 'Añadir participantes', excludeSemantics: true, child: InkWell(onTap: () => _add(context, ref, repo, members),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('+ Añadir', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))))),
          ]),
          const SizedBox(height: 6),
          for (final m in sorted) Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
            child: Row(children: [
              Expanded(child: Semantics(button: m.id != me, label: '${m.id == me ? '${m.name} (tú)' : m.name}${m.isAdmin ? ', administrador' : ''}', excludeSemantics: true, child: InkWell(
                onTap: m.id == me ? null : () => context.push('/player/${m.id}'),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 11), child: Row(children: [
                  ClipOval(child: Container(width: 44, height: 44, color: AppColors.ink900, alignment: Alignment.center,
                      child: m.avatarUrl == null ? Text(m.initials, style: const TextStyle(fontFamily: AppTypography.sansFamily, color: AppColors.lime300, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0))
                          : Image.network(m.avatarUrl!, width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 132, errorBuilder: (_, __, ___) => Text(m.initials, style: const TextStyle(color: AppColors.lime300, fontWeight: FontWeight.w800))))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(m.id == me ? '${m.name} (tú)' : m.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))),
                      if (m.isAdmin) const _AdminBadge(),
                    ]),
                    Text('@${m.username}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: AppColors.textMuted)),
                  ])),
                ])),
              ))),
              if (m.id != me && (perms.canRemove(m) || perms.canPromote(m) || perms.canDemote(m)))
                IconSquareButton(icon: PlobbyIcons.more, tooltip: 'Acciones para ${m.name}', size: 36, onPressed: () => showPlobbySheet(context, (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SheetHeader(title: m.name, subtitle: '@${m.username}'),
                  if (perms.canPromote(m)) SheetListItem(icon: PlobbyIcons.shield, label: 'Hacer administrador', onTap: () { Navigator.pop(c); _run(context, ref, () => repo.setAdmin(conversationId, m.id, true)); }),
                  if (perms.canDemote(m)) SheetListItem(icon: PlobbyIcons.shield, label: 'Quitar administrador', onTap: () { Navigator.pop(c); _run(context, ref, () => repo.setAdmin(conversationId, m.id, false)); }),
                  if (perms.canRemove(m)) SheetListItem(icon: PlobbyIcons.trash, label: 'Quitar del grupo', danger: true, onTap: () { Navigator.pop(c); _run(context, ref, () => repo.removeMember(conversationId, m.id)); }),
                ]))),
            ]),
          ),
          const SizedBox(height: 24),
          if (perms.canLeave) PlobbyButton(label: 'Abandonar grupo', kind: PlobbyButtonKind.danger,
              onPressed: () => _leave(context, ref, repo, perms.isAdmin && perms.adminCount == 1 && members.length > 1)),
        ])),
      ]),
    );
  }

  Future<void> _rename(BuildContext c, WidgetRef ref, MessagingRepository repo, String cur) async {
    final v = await showPlobbySheet<String>(c, (_) => _RenameSheet(current: cur));
    if (v == null || v.trim().isEmpty || v.trim() == cur || !c.mounted) return;
    await _run(c, ref, () => repo.updateGroup(conversationId, name: v), ok: 'Nombre actualizado');
  }

  Future<void> _photo(BuildContext c, WidgetRef ref, MessagingRepository repo) async {
    String? preset; Uint8List? bytes;
    final ok = await showPlobbySheet<bool>(c, (_) => StatefulBuilder(builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHeader(title: 'Foto del grupo'),
          GroupAvatarPicker(presetId: preset ?? 'p1', bytes: bytes, onPreset: (id) => set(() { preset = id; bytes = null; }),
              onGallery: () async { final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85); if (f != null) { final b = await f.readAsBytes(); set(() => bytes = b); } }),
          const SizedBox(height: 16),
          PlobbyButton(label: 'Guardar foto', onPressed: preset == null && bytes == null ? null : () => Navigator.pop(ctx, true)),
        ])));
    if (ok != true || !c.mounted) return;
    await _run(c, ref, () => repo.updateGroup(conversationId, avatarId: bytes == null ? preset : null, avatarBytes: bytes), ok: 'Foto actualizada');
  }

  Future<void> _add(BuildContext c, WidgetRef ref, MessagingRepository repo, List<GroupMember> cur) async {
    final friends = (await ref.read(friendsProvider.future)).where((f) => cur.every((m) => m.id != f.player.id)).toList();
    if (!c.mounted) return;
    final sel = <String>{};
    final ok = await showPlobbySheet<bool>(c, (_) => StatefulBuilder(builder: (ctx, set) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Añadir participantes'),
        if (friends.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Todos tus amigos ya están en el grupo.', style: PlobbyText.sub)),
        Flexible(child: ListView(shrinkWrap: true, children: [for (final Friend f in friends) CheckboxListTile(contentPadding: EdgeInsets.zero, value: sel.contains(f.player.id), activeColor: AppColors.inverse, checkColor: AppColors.brand,
            title: Text(f.player.name, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w700)), subtitle: Text('@${f.player.username}', style: PlobbyText.help),
            onChanged: (v) => set(() => v == true ? sel.add(f.player.id) : sel.remove(f.player.id)))])),
        const SizedBox(height: 12),
        PlobbyButton(label: sel.isEmpty ? 'Añadir' : 'Añadir (${sel.length})', onPressed: sel.isEmpty ? null : () => Navigator.pop(ctx, true)),
      ]))));
    if (ok != true || !c.mounted) return;
    await _run(c, ref, () => repo.addMembers(conversationId, sel.toList()), ok: 'Participantes añadidos');
  }

  Future<void> _leave(BuildContext c, WidgetRef ref, MessagingRepository repo, bool lastAdmin) async {
    final ok = await showPlobbySheet<bool>(c, (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: '¿Abandonar el grupo?'),
        Text(lastAdmin ? 'Eres el único administrador: el participante más antiguo pasará a administrar el grupo.' : 'Dejarás de recibir sus mensajes.', style: PlobbyText.sub),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(d, false))),
          const SizedBox(width: 10),
          Expanded(child: PlobbyButton(label: 'Abandonar', kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(d, true))),
        ]),
      ]));
    if (ok != true || !c.mounted) return;
    try {
      await repo.leaveGroup(conversationId);
      ref.invalidate(conversationsProvider);
      if (c.mounted) c.go('/messages');
    } on MessagingException {
      if (c.mounted) showPlobbySnack(c, 'No se pudo abandonar el grupo', error: true);
    }
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge();
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(5)),
      child: const Text('ADMIN', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: .76, color: AppColors.brandInk)));
}

/// Hoja «Nombre del grupo»: es dueña de su controlador (se libera al cerrarse la hoja). Devuelve el nombre o null.
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.current});
  final String current;
  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _c = TextEditingController(text: widget.current);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Nombre del grupo'),
        LabeledField(label: 'Nombre', controller: _c, maxLength: maxGroupName, autofocus: true),
        Row(children: [
          Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(child: PlobbyButton(label: 'Guardar', onPressed: () => Navigator.pop(context, _c.text))),
        ]),
      ]);
}
