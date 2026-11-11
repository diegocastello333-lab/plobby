import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/design_tokens.dart';
import '../../social/application/social_providers.dart';
import '../../social/presentation/player_tile.dart' as pt;
import '../application/messaging_providers.dart';
import '../domain/messaging_models.dart';
import 'group_avatar.dart';

/// «Nuevo grupo»: elegir amigos (lista o búsqueda por nombre/usuario), nombre y foto. Solo amigos aceptados (el servidor lo exige).
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});
  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupState();
}

class _NewGroupState extends ConsumerState<NewGroupScreen> {
  final _name = TextEditingController();
  final _sel = <String>{};
  String q = '', presetId = 'p1';
  Uint8List? bytes;
  bool busy = false;
  String? error;

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (f == null) return;
    final b = await f.readAsBytes();
    if (mounted) setState(() => bytes = b);
  }

  Future<void> _create() async {
    final err = validateGroupDraft(name: _name.text, selected: _sel.length);
    if (err != null) { setState(() => error = err); return; }
    setState(() { busy = true; error = null; });
    try {
      final id = await ref.read(messagingRepositoryProvider).createGroup(name: _name.text, memberIds: _sel.toList(), avatarId: bytes == null ? presetId : null, avatarBytes: bytes);
      ref.invalidate(conversationsProvider);
      if (mounted) context.pushReplacement('/messages/$id?name=${Uri.encodeComponent(_name.text.trim())}');
    } on MessagingException catch (e) {
      if (mounted) setState(() { busy = false; error = e.code == 'only_friends_allowed' ? 'Solo puedes añadir a tus amigos' : 'No se pudo crear el grupo'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo grupo'), centerTitle: true),
      body: friends.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: TextButton(onPressed: () => ref.invalidate(friendsProvider), child: const Text('No se pudo cargar. Reintentar'))),
        data: (all) {
          final l = all.where((f) => q.isEmpty || f.player.name.toLowerCase().contains(q) || f.player.username.toLowerCase().contains(q)).toList();
          return Column(children: [
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 8, AppSpacing.screenH, 24), children: [
              GroupAvatarPicker(presetId: presetId, bytes: bytes, onPreset: (id) => setState(() { presetId = id; bytes = null; }), onGallery: _pick),
              const SizedBox(height: 16),
              TextField(controller: _name, maxLength: maxGroupName, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nombre del grupo', hintText: 'Pádel de los jueves'), onChanged: (_) => setState(() => error = null)),
              const SizedBox(height: 8),
              Text('Participantes (${_sel.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 8),
              if (_sel.isNotEmpty) SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final f in all.where((f) => _sel.contains(f.player.id))) Padding(padding: const EdgeInsets.only(right: 8), child: InputChip(
                    label: Text(f.player.name.split(' ').first), onDeleted: () => setState(() => _sel.remove(f.player.id)), deleteButtonTooltipMessage: 'Quitar')),
              ])),
              const SizedBox(height: 8),
              SearchBar(hintText: 'Buscar por nombre o usuario', leading: const Icon(Icons.search), onChanged: (v) => setState(() => q = v.trim().toLowerCase())),
              const SizedBox(height: 8),
              if (all.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Añade amigos para poder crear un grupo.', textAlign: TextAlign.center))
              else if (l.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Sin resultados', textAlign: TextAlign.center)),
              for (final f in l) CheckboxListTile(
                contentPadding: EdgeInsets.zero, value: _sel.contains(f.player.id), controlAffinity: ListTileControlAffinity.trailing,
                onChanged: (v) => setState(() => v == true ? _sel.add(f.player.id) : _sel.remove(f.player.id)),
                secondary: pt.PlayerAvatar(f.player, size: 40), title: Text(f.player.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('@${f.player.username}'),
              ),
            ])),
            SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 8, AppSpacing.screenH, 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(duration: AppAnimations.scaled(context, AppAnimations.tab), child: error == null ? const SizedBox(height: 0) : Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, key: ValueKey(error), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)))),
              FilledButton(onPressed: busy ? null : _create, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Crear grupo')),
            ]))),
          ]);
        },
      ),
    );
  }
}
