import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/feed_providers.dart';
import '../../domain/feed_models.dart';

void showCommentsSheet(BuildContext context, FeedPost post) => showModalBottomSheet(
    context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => CommentsSheet(postId: post.id));

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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Comentarios', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Flexible(child: async.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (_, __) => TextButton(onPressed: () => ref.invalidate(commentsProvider(widget.postId)), child: const Text('No se pudieron cargar. Reintentar')),
          data: (list) => list.isEmpty ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aún no hay comentarios. Escribe el primero.', style: TextStyle(color: PlobbyColors.mute)))
              : ListView(shrinkWrap: true, children: [for (final c in list) ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 17, backgroundColor: PlobbyColors.forest, child: Text(c.author.name[0], style: const TextStyle(color: PlobbyColors.ivory, fontSize: 13))),
                  title: Text.rich(TextSpan(children: [TextSpan(text: '${c.author.id == me.id ? 'Tú' : c.author.name} ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: c.content)]), style: const TextStyle(fontSize: 14)),
                  trailing: c.author.id == me.id
                      ? IconButton(tooltip: 'Eliminar mi comentario', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => ref.read(commentsProvider(widget.postId).notifier).remove(c))
                      : IconButton(tooltip: 'Denunciar', icon: const Icon(Icons.flag_outlined, size: 18), onPressed: () { ref.read(commentsProvider(widget.postId).notifier).report(c); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gracias. Hemos ocultado el comentario y lo revisaremos.'))); }),
                )]),
        )),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: ctl, maxLength: 140, decoration: InputDecoration(hintText: 'Añade un comentario', counterText: '', errorText: empty ? 'Escribe algo antes de enviar.' : null), onChanged: (_) => empty ? setState(() => empty = false) : null)),
          IconButton.filled(onPressed: _send, icon: const Icon(Icons.send, size: 18), tooltip: 'Enviar'),
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
