import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../../../core/theme/plobby_text.dart';
import '../../../../core/widgets/plobby_components.dart';
import '../../../../core/widgets/plobby_icon.dart';
import '../../../../core/widgets/state_views.dart';
import 'activity_cards.dart' show avatar, timeAgo;
import '../../application/feed_providers.dart';
import '../../domain/feed_models.dart';

void showCommentsSheet(BuildContext context, FeedPost post) => showPlobbySheet(context, (_) => CommentsSheet(postId: post.id));

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.postId});
  final String postId;
  @override
  ConsumerState<CommentsSheet> createState() => _S();
}

class _S extends ConsumerState<CommentsSheet> {
  final ctl = TextEditingController();
  bool empty = false;
  @override
  void dispose() { ctl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(commentsProvider(widget.postId));
    final me = ref.read(feedRepositoryProvider).me;
    Widget small(PlobbyIcons i, String tip, VoidCallback f) => Tooltip(message: tip, child: Semantics(button: true, label: tip, excludeSemantics: true,
        child: InkResponse(onTap: f, radius: 20, child: SizedBox(width: 36, height: 36, child: Center(child: PlobbyIcon(i, size: 17, color: AppColors.textMuted))))));
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Comentarios'),
        Flexible(child: async.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.text))),
          error: (_, __) => ErrorStateCard(title: 'No se pudieron cargar', onRetry: () => ref.invalidate(commentsProvider(widget.postId))),
          data: (list) => list.isEmpty ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aún no hay comentarios. Escribe el primero.', style: PlobbyText.sub))
              : ListView(shrinkWrap: true, children: [for (final c in list) Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    avatar(c.author, 17), const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [TextSpan(text: '${c.author.id == me.id ? 'Tú' : c.author.name} ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: c.content)]),
                          style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.4, letterSpacing: 0, color: AppColors.text)),
                      const SizedBox(height: 2),
                      Text(timeAgo(c.createdAt), style: PlobbyText.help.copyWith(fontSize: 12)),
                    ])),
                    c.author.id == me.id
                        ? small(PlobbyIcons.trash, 'Eliminar mi comentario', () => ref.read(commentsProvider(widget.postId).notifier).remove(c))
                        : small(PlobbyIcons.flag, 'Denunciar', () { ref.read(commentsProvider(widget.postId).notifier).report(c); showPlobbySnack(context, 'Gracias. Hemos ocultado el comentario y lo revisaremos.'); }),
                  ]),
                )]),
        )),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: TextField(controller: ctl, maxLength: 140, style: PlobbyText.input, cursorColor: AppColors.text, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(),
              decoration: plobbyInputDecoration(hint: 'Añade un comentario', error: empty ? 'Escribe algo antes de enviar.' : null), onChanged: (_) => empty ? setState(() => empty = false) : null)),
          const SizedBox(width: 8),
          Tooltip(message: 'Enviar', child: Semantics(button: true, label: 'Enviar comentario', excludeSemantics: true, child: Material(color: AppColors.brand, borderRadius: AppRadius.rMd,
              child: InkWell(borderRadius: AppRadius.rMd, onTap: _send, child: const SizedBox(width: 48, height: 48, child: Center(child: PlobbyIcon(PlobbyIcons.plane, size: 18, color: AppColors.brandInk))))))),
        ]),
      ]),
    );
  }

  Future<void> _send() async {
    if (ctl.text.trim().isEmpty) { setState(() => empty = true); return; }
    await ref.read(commentsProvider(widget.postId).notifier).add(ctl.text);
    ctl.clear();
  }
}
