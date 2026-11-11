import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/design_tokens.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/social_models.dart';
import '../application/messaging_providers.dart';
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
      if (ok != null && c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(ok)));
    } on MessagingException catch (e) {
      if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(switch (e.code) {
        'not_group_admin' => 'Solo los administradores pueden hacerlo',
        'last_admin' => 'Debe quedar al menos un administrador',
        'demote_admin_first' => 'Quita antes el rol de administrador',
        'only_friends_allowed' => 'Solo puedes añadir a tus amigos',
        _ => 'No se pudo completar la acción',
      })));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(conversationProvider(conversationId)).valueOrNull, members = ref.watch(groupMembersProvider(conversationId)).valueOrNull;
    final me = ref.read(messagingRepositoryProvider).meId, repo = ref.read(messagingRepositoryProvider);
    if (conv == null || members == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final perms = GroupPerms(members, me);
    final sorted = [...members]..sort((a, b) => a.isAdmin == b.isAdmin ? a.name.compareTo(b.name) : (a.isAdmin ? -1 : 1));
    return Scaffold(
      appBar: AppBar(title: const Text('Info del grupo'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 8, AppSpacing.screenH, 32), children: [
        Center(child: Stack(children: [
          GroupAvatar(url: conv.groupAvatarUrl, bytes: conv.groupAvatarBytes, presetId: conv.groupAvatarId, size: 96),
          if (perms.canEdit) Positioned(right: 0, bottom: 0, child: Material(color: AppColors.brand, shape: const CircleBorder(), child: IconButton(tooltip: 'Cambiar foto', iconSize: 18, constraints: const BoxConstraints(minWidth: 44, minHeight: 44), icon: const Icon(Icons.edit, color: AppColors.brandInk), onPressed: () => _photo(context, ref, repo)))),
        ])),
        const SizedBox(height: 12),
        Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(conv.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          if (perms.canEdit) IconButton(tooltip: 'Cambiar nombre', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _rename(context, ref, repo, conv.title)),
        ])),
        Center(child: Text('${members.length} participantes', style: const TextStyle(color: AppColors.textMuted))),
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(child: Text('Participantes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          if (perms.canAdd) TextButton.icon(onPressed: () => _add(context, ref, repo, members), icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text('Añadir')),
        ]),
        for (final m in sorted) ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 22, backgroundColor: AppColors.ink900, foregroundImage: m.avatarUrl == null ? null : NetworkImage(m.avatarUrl!), child: Text(m.initials, style: const TextStyle(color: AppColors.lime300, fontWeight: FontWeight.w800, fontSize: 13))),
          title: Row(children: [Flexible(child: Text(m.id == me ? '${m.name} (tú)' : m.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))), if (m.isAdmin) const _AdminBadge()]),
          subtitle: Text('@${m.username}'),
          onTap: m.id == me ? null : () => context.push('/player/${m.id}'),
          trailing: m.id == me || !(perms.canRemove(m) || perms.canPromote(m) || perms.canDemote(m)) ? null : PopupMenuButton<String>(
            tooltip: 'Acciones', onSelected: (v) => _run(context, ref, () => switch (v) {
              'promote' => repo.setAdmin(conversationId, m.id, true),
              'demote' => repo.setAdmin(conversationId, m.id, false),
              _ => repo.removeMember(conversationId, m.id),
            }),
            itemBuilder: (_) => [
              if (perms.canPromote(m)) const PopupMenuItem(value: 'promote', child: Text('Hacer administrador')),
              if (perms.canDemote(m)) const PopupMenuItem(value: 'demote', child: Text('Quitar administrador')),
              if (perms.canRemove(m)) const PopupMenuItem(value: 'remove', child: Text('Quitar del grupo')),
            ]),
        ),
        const SizedBox(height: 16),
        if (perms.canLeave) OutlinedButton.icon(
          onPressed: () => _leave(context, ref, repo, perms.isAdmin && perms.adminCount == 1 && members.length > 1),
          icon: const Icon(Icons.logout, size: 18, color: AppColors.danger), label: const Text('Abandonar grupo', style: TextStyle(color: AppColors.danger)),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: const BorderSide(color: AppColors.danger))),
      ]),
    );
  }

  Future<void> _rename(BuildContext c, WidgetRef ref, MessagingRepository repo, String cur) async {
    final ctl = TextEditingController(text: cur);
    final v = await showDialog<String>(context: c, builder: (d) => AlertDialog(title: const Text('Nombre del grupo'), content: TextField(controller: ctl, maxLength: maxGroupName, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('Guardar'))]));
    if (v == null || v.trim().isEmpty || v.trim() == cur || !c.mounted) return;
    await _run(c, ref, () => repo.updateGroup(conversationId, name: v), ok: 'Nombre actualizado');
  }

  Future<void> _photo(BuildContext c, WidgetRef ref, MessagingRepository repo) async {
    String? preset; Uint8List? bytes;
    final ok = await showModalBottomSheet<bool>(context: c, showDragHandle: true, isScrollControlled: true, builder: (_) => StatefulBuilder(builder: (ctx, set) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          GroupAvatarPicker(presetId: preset ?? 'p1', bytes: bytes, onPreset: (id) => set(() { preset = id; bytes = null; }),
              onGallery: () async { final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85); if (f != null) { final b = await f.readAsBytes(); set(() => bytes = b); } }),
          const SizedBox(height: 16),
          FilledButton(onPressed: preset == null && bytes == null ? null : () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Guardar foto')),
        ]))));
    if (ok != true || !c.mounted) return;
    await _run(c, ref, () => repo.updateGroup(conversationId, avatarId: bytes == null ? preset : null, avatarBytes: bytes), ok: 'Foto actualizada');
  }

  Future<void> _add(BuildContext c, WidgetRef ref, MessagingRepository repo, List<GroupMember> cur) async {
    final friends = (await ref.read(friendsProvider.future)).where((f) => cur.every((m) => m.id != f.player.id)).toList();
    if (!c.mounted) return;
    final sel = <String>{};
    final ok = await showModalBottomSheet<bool>(context: c, showDragHandle: true, isScrollControlled: true, builder: (_) => StatefulBuilder(builder: (ctx, set) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('Añadir participantes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))),
      if (friends.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Todos tus amigos ya están en el grupo.')),
      Flexible(child: ListView(shrinkWrap: true, children: [for (final Friend f in friends) CheckboxListTile(value: sel.contains(f.player.id), title: Text(f.player.name), subtitle: Text('@${f.player.username}'), onChanged: (v) => set(() => v == true ? sel.add(f.player.id) : sel.remove(f.player.id)))])),
      Padding(padding: const EdgeInsets.all(20), child: FilledButton(onPressed: sel.isEmpty ? null : () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Añadir'))),
    ]))));
    if (ok != true || !c.mounted) return;
    await _run(c, ref, () => repo.addMembers(conversationId, sel.toList()), ok: 'Participantes añadidos');
  }

  Future<void> _leave(BuildContext c, WidgetRef ref, MessagingRepository repo, bool lastAdmin) async {
    final ok = await showDialog<bool>(context: c, builder: (d) => AlertDialog(
        title: const Text('¿Abandonar el grupo?'),
        content: Text(lastAdmin ? 'Eres el único administrador: el participante más antiguo pasará a administrar el grupo.' : 'Dejarás de recibir sus mensajes.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(d, true), style: FilledButton.styleFrom(backgroundColor: AppColors.danger), child: const Text('Abandonar'))]));
    if (ok != true || !c.mounted) return;
    try {
      await repo.leaveGroup(conversationId);
      ref.invalidate(conversationsProvider);
      if (c.mounted) c.go('/messages');
    } on MessagingException {
      if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('No se pudo abandonar el grupo')));
    }
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge();
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: AppRadius.rSm),
      child: const Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6, color: AppColors.brandText)));
}
