import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../social/application/social_providers.dart';
import '../../social/domain/social_models.dart';
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
      body: Column(children: [
        PlobbyHeaderBar(title: 'Nuevo grupo', onBack: () => context.pop()),
        Expanded(child: friends.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(onRetry: () => ref.invalidate(friendsProvider))),
          data: (all) {
            final l = all.where((f) => q.isEmpty || f.player.name.toLowerCase().contains(q) || f.player.username.toLowerCase().contains(q)).toList();
            return Column(children: [
              Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
                GroupAvatarPicker(presetId: presetId, bytes: bytes, onPreset: (id) => setState(() { presetId = id; bytes = null; }), onGallery: _pick),
                const SizedBox(height: 18),
                LabeledField(label: 'Nombre del grupo', controller: _name, maxLength: maxGroupName, hint: 'Pádel de los jueves', textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() => error = null)),
                Text('Participantes (${_sel.length})', style: PlobbyText.label),
                const SizedBox(height: 4),
                Text(_sel.isEmpty ? 'Elige al menos un amigo' : 'Solo puedes añadir a tus amigos.', style: PlobbyText.help.copyWith(fontSize: 12)),
                const SizedBox(height: 10),
                if (_sel.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final f in all.where((f) => _sel.contains(f.player.id))) Semantics(button: true, label: 'Quitar a ${f.player.name}', excludeSemantics: true, child: InkWell(
                    borderRadius: AppRadius.rPill, onTap: () => setState(() => _sel.remove(f.player.id)),
                    child: Container(height: 30, padding: const EdgeInsets.only(left: 4, right: 10), decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rPill),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        pt.PlayerAvatar(f.player, size: 22), const SizedBox(width: 6),
                        Text(f.player.name.split(' ').first, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.ink50)),
                        const SizedBox(width: 6), const PlobbyIcon(PlobbyIcons.close, size: 12, strokeWidth: 2.4, color: AppColors.brand),
                      ])),
                  )),
                ])),
                SearchField(hint: 'Buscar por nombre o usuario', onChanged: (v) => setState(() => q = v.trim().toLowerCase())),
                const SizedBox(height: 6),
                if (all.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Añade amigos para poder crear un grupo.', textAlign: TextAlign.center, style: PlobbyText.sub))
                else if (l.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Sin resultados', textAlign: TextAlign.center, style: PlobbyText.sub)),
                for (final f in l) _Pick(f: f, selected: _sel.contains(f.player.id), onTap: () => setState(() => _sel.contains(f.player.id) ? _sel.remove(f.player.id) : _sel.add(f.player.id))),
              ])),
              Container(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + MediaQuery.paddingOf(context).bottom),
                decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: Color(0x14171C19)))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedSwitcher(duration: AppAnimations.scaled(context, AppAnimations.tab), child: error == null ? const SizedBox(height: 0) : Padding(padding: const EdgeInsets.only(bottom: 8),
                      child: Text(error!, key: ValueKey(error), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600, letterSpacing: 0)))),
                  PlobbyButton(label: 'Crear grupo', busy: busy, onPressed: _create),
                ]),
              ),
            ]);
          },
        )),
      ]),
    );
  }
}

/// Fila de amigo con selección circular (como `gntog` del prototipo).
class _Pick extends StatelessWidget {
  const _Pick({required this.f, required this.selected, required this.onTap});
  final Friend f; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(checked: selected, label: '${f.player.name}, @${f.player.username}', excludeSemantics: true, child: InkWell(onTap: onTap, child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
        child: Row(children: [
          pt.PlayerAvatar(f.player, size: 40), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.player.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            Text('@${f.player.username}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: AppColors.textMuted)),
          ])),
          Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? AppColors.inverse : null, border: selected ? null : Border.all(color: AppColors.borderStrong, width: 1.5)),
              child: selected ? const Center(child: PlobbyIcon(PlobbyIcons.check, size: 13, strokeWidth: 3, color: AppColors.brand)) : null),
        ]),
      )));
}
