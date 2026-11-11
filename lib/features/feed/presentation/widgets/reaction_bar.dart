import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/feed_providers.dart';
import '../../domain/feed_models.dart';
import 'comments_sheet.dart';

class ReactionBar extends ConsumerWidget {
  const ReactionBar({super.key, required this.post, this.onDark = false});
  final FeedPost post;
  final bool onDark;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = post.reactions;
    final fg = onDark ? PlobbyColors.ivory.withOpacity(.7) : PlobbyColors.mute;
    final names = r.recent.take(2).map((u) => u.name.split(' ').first).join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final t in ReactionType.values) _Pill(t: t, count: r.counts[t] ?? 0, selected: r.mine == t, onDark: onDark, onTap: () => ref.read(feedControllerProvider.notifier).react(post.id, t))]),
      const SizedBox(height: 10),
      Row(children: [
        if (r.total > 0) ...[
          InkWell(onTap: () => _who(context, ref), child: Row(children: [
            SizedBox(width: 22.0 + 15 * (r.recent.length.clamp(1, 3) - 1), height: 22, child: Stack(children: [for (var i = 0; i < r.recent.length.clamp(0, 3); i++) Positioned(left: i * 15.0, child: CircleAvatar(radius: 11, backgroundColor: PlobbyColors.sage, child: Text(r.recent[i].name[0], style: const TextStyle(fontSize: 10, color: PlobbyColors.forest, fontWeight: FontWeight.w800)))) ])),
            const SizedBox(width: 8),
            Text('$names${r.total > 2 ? ' y ${r.total - 2} más' : ''}', style: TextStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w600)),
          ])),
        ] else Text('Sé el primero en reaccionar', style: TextStyle(fontSize: 12.5, color: fg)),
        const Spacer(),
        TextButton(onPressed: () => showCommentsSheet(context, post), style: TextButton.styleFrom(foregroundColor: fg, minimumSize: Size.zero, padding: EdgeInsets.zero),
            child: Text(post.commentCount == 0 ? 'Comentar' : '${post.commentCount} ${post.commentCount == 1 ? 'comentario' : 'comentarios'}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
      ]),
      if (post.previewComments.isNotEmpty) ...[
        Divider(height: 18, color: onDark ? const Color(0x24F6F8F1) : null),
        for (final c in post.previewComments) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text.rich(TextSpan(children: [TextSpan(text: '${c.author.name.split(' ').first} ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: c.content)]), style: TextStyle(fontSize: 13, color: onDark ? PlobbyColors.ivory : PlobbyColors.charcoal))),
        if (post.commentCount > 2) TextButton(onPressed: () => showCommentsSheet(context, post), style: TextButton.styleFrom(foregroundColor: fg, padding: EdgeInsets.zero, minimumSize: Size.zero), child: Text('Ver los ${post.commentCount} comentarios', style: const TextStyle(fontSize: 12.5))),
      ],
    ]);
  }

  Future<void> _who(BuildContext context, WidgetRef ref) async {
    final list = await ref.read(feedRepositoryProvider).reactionsFor(post.id);
    if (!context.mounted) return;
    showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
      const Text('Reacciones', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      for (final e in list) ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundColor: PlobbyColors.forest, child: Text(e.$1.name[0], style: const TextStyle(color: PlobbyColors.ivory))), title: Text(e.$1.name), subtitle: Text('@${e.$1.username}'), trailing: Text(e.$2.emoji, style: const TextStyle(fontSize: 22))),
    ]));
  }
}

class _Pill extends StatefulWidget {
  const _Pill({required this.t, required this.count, required this.selected, required this.onDark, required this.onTap});
  final ReactionType t; final int count; final bool selected, onDark; final VoidCallback onTap;
  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  @override
  void didUpdateWidget(covariant _Pill o) { super.didUpdateWidget(o); if (widget.selected && !o.selected) c.forward(from: 0); }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return Semantics(button: true, selected: sel, label: 'Reaccionar con ${widget.t.emoji}', child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(animation: c, builder: (_, child) {
        final s = 1 + .3 * Curves.elasticOut.transform(c.value) * (1 - c.value);
        return Transform.scale(scale: c.isAnimating ? s : 1, child: child);
      }, child: AnimatedContainer(
        duration: const Duration(milliseconds: 150), height: 32, constraints: const BoxConstraints(minWidth: 40), padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: sel ? PlobbyColors.lime : (widget.onDark ? const Color(0x1FF6F8F1) : const Color(0xFFEEF1EA)), borderRadius: BorderRadius.circular(16), border: sel ? Border.all(color: PlobbyColors.forest, width: 1.5) : null),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.t.emoji, style: const TextStyle(fontSize: 15)),
          if (widget.count > 0) ...[const SizedBox(width: 5), Text('${widget.count}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: sel ? PlobbyColors.forest : (widget.onDark ? const Color(0xBFF6F8F1) : PlobbyColors.mute)))],
        ]))),
    ));
  }
}
