import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';
import '../application/messaging_providers.dart';
import '../domain/messaging_models.dart';
import 'group_avatar.dart';
import 'match_picker_sheet.dart';
import 'match_result_card.dart';

/// Chat directo o de grupo. Mismo widget para ambos: en grupos añade cabecera con foto/nombre (→ info),
/// remitente en cada burbuja ajena y mensajes de sistema centrados. El icono 🏆 del compositor sirve para los dos.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId, required this.title, this.otherId, this.startWithInvite = false});
  final String conversationId, title;
  final String? otherId;
  final bool startWithInvite;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() { _c.dispose(); _scroll.dispose(); super.dispose(); }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(chatProvider(widget.conversationId));
    final conv = ref.watch(conversationProvider(widget.conversationId)).valueOrNull;
    final isGroup = conv?.isGroup ?? false;
    final members = isGroup ? ref.watch(groupMembersProvider(widget.conversationId)).valueOrNull ?? const <GroupMember>[] : const <GroupMember>[];
    final byId = {for (final m in members) m.id: m};
    final me = ref.read(messagingRepositoryProvider).meId;
    ref.listen(chatProvider(widget.conversationId), (_, __) => _toEnd());
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: isGroup
            ? InkWell(onTap: () => context.push('/messages/${widget.conversationId}/info'), child: Row(children: [
                GroupAvatar(url: conv!.groupAvatarUrl, bytes: conv.groupAvatarBytes, presetId: conv.groupAvatarId, size: 36),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('${conv.memberCount} participantes · toca para ver info', style: const TextStyle(fontSize: 11, color: PlobbyColors.mute, fontWeight: FontWeight.w500)),
                ])),
              ]))
            : GestureDetector(onTap: widget.otherId == null ? null : () => context.push('/player/${widget.otherId}'), child: Text(conv?.title ?? widget.title)),
        actions: [if (isGroup) IconButton(tooltip: 'Info del grupo', icon: const Icon(Icons.info_outline), onPressed: () => context.push('/messages/${widget.conversationId}/info'))],
      ),
      body: Column(children: [
        Expanded(child: msgs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('No se pudo cargar la conversación')),
          data: (l) => l.isEmpty
              ? const Center(child: Text('Aún no hay mensajes. Saluda 👋'))
              : ListView.builder(controller: _scroll, padding: const EdgeInsets.all(16), itemCount: l.length, itemBuilder: (_, i) {
                  final m = l[i], mine = m.senderId == me;
                  if (m.kind == MessageKind.system) return _SystemMsg(m.body);
                  // en grupos: nombre+foto del remitente al empezar una racha de mensajes ajenos
                  final showSender = isGroup && !mine && (i == 0 || l[i - 1].senderId != m.senderId || l[i - 1].kind == MessageKind.system);
                  return _Bubble(m, mine: mine, sender: isGroup && !mine ? byId[m.senderId] : null, showSender: showSender, meId: me,
                      onRetry: () => ref.read(chatProvider(widget.conversationId).notifier).send(m.body));
                }),
        )),
        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(8, 6, 12, 8), child: Row(children: [
          IconButton(tooltip: 'Acciones rápidas', icon: const Icon(Icons.add_circle_outline), onPressed: _quick),
          IconButton(tooltip: 'Compartir resultado de partido', icon: const Icon(Icons.emoji_events_outlined), onPressed: _shareMatch),
          Expanded(child: TextField(controller: _c, maxLength: 500, decoration: const InputDecoration(hintText: 'Escribe un mensaje', counterText: ''), onSubmitted: (_) => _send())),
          IconButton.filled(tooltip: 'Enviar', icon: const Icon(Icons.send), onPressed: _send),
        ]))),
      ]),
    );
  }

  void _send() {
    final t = _c.text;
    if (t.trim().isEmpty) return;
    _c.clear();
    ref.read(chatProvider(widget.conversationId).notifier).send(t);
  }

  /// Selector de partidos finalizados y confirmados → tarjeta generada por el servidor a partir del partido original.
  Future<void> _shareMatch() async {
    final id = await showMatchPicker(context);
    if (id == null || !mounted) return;
    try {
      await ref.read(chatProvider(widget.conversationId).notifier).sendMatchCard(id);
    } on MessagingException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(switch (e.code) {
        'recap_not_confirmed' => 'Solo se pueden compartir partidos finalizados y confirmados',
        'recap_not_participant' => 'Solo puedes compartir partidos en los que has jugado',
        'not_a_member' => 'Ya no formas parte de esta conversación',
        _ => 'No se pudo enviar el resultado. Inténtalo de nuevo',
      })));
    }
  }

  void _quick() => showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.sports_tennis), title: const Text('Invitar a jugar'), onTap: () { Navigator.pop(context); _invite(); }),
        ListTile(leading: const Icon(Icons.emoji_events_outlined), title: const Text('Compartir resultado de un partido'), onTap: () { Navigator.pop(context); _shareMatch(); }),
        ListTile(leading: const Icon(Icons.groups_outlined), title: const Text('Compartir una liga'), onTap: () { Navigator.pop(context); /* TODO: selector de ligas del usuario */ }),
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('Compartir mi perfil'), onTap: () { Navigator.pop(context); ref.read(chatProvider(widget.conversationId).notifier).send('Mi perfil', kind: MessageKind.profile, refId: ref.read(messagingRepositoryProvider).meId); }),
      ])));

  Future<void> _invite() async {
    final day = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)), initialDate: DateTime.now().add(const Duration(days: 1)));
    if (day == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 0));
    if (t == null || !mounted) return;
    ref.read(chatProvider(widget.conversationId).notifier).send('${day.day}/${day.month} ${t.format(context)}', kind: MessageKind.invite);
  }
}

class _SystemMsg extends StatelessWidget {
  const _SystemMsg(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: PlobbyColors.sage.withOpacity(.25), borderRadius: BorderRadius.circular(12)),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: PlobbyColors.mute, fontWeight: FontWeight.w600)))));
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m, {required this.mine, required this.onRetry, required this.meId, this.sender, this.showSender = false});
  final ChatMessage m; final bool mine, showSender; final VoidCallback onRetry; final GroupMember? sender; final String meId;

  void _openMatch(BuildContext c) {
    final payload = m.payload;
    final participant = payload != null && (payload['players'] as List?)?.any((p) => (p as Map)['user_id'] == meId) == true;
    // participante → detalle vivo del partido; no participante (RLS) → snapshot guardado en el mensaje
    if (participant || payload == null) { c.push('/match/${m.refId}/final'); return; }
    showModalBottomSheet(context: c, isScrollControlled: true, showDragHandle: true, builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: Column(mainAxisSize: MainAxisSize.min, children: [MatchResultCard(payload: payload, sharerId: m.senderId, width: 320)]))));
  }

  @override
  Widget build(BuildContext context) {
    final time = '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';
    final status = !mine ? '' : switch (m.status) { MessageStatus.sending => ' …', MessageStatus.sent => ' ✓', MessageStatus.read => ' ✓✓', MessageStatus.failed => ' ⚠ Reintentar' };
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;

    // La tarjeta de resultado va sin burbuja: es el contenido.
    if (m.kind == MessageKind.match && m.payload != null) {
      return Align(alignment: align, child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (showSender && sender != null) _senderLabel(sender!),
        MatchResultCard(payload: m.payload!, sharerId: m.senderId, onTap: () => _openMatch(context)),
        Padding(padding: const EdgeInsets.only(top: 3), child: Text('$time$status', style: const TextStyle(fontSize: 10, color: PlobbyColors.mute))),
      ])));
    }

    final fg = mine ? PlobbyColors.ivory : PlobbyColors.charcoal;
    final body = switch (m.kind) {
      MessageKind.text || MessageKind.system => Text(m.body, style: TextStyle(color: fg)),
      MessageKind.invite => Text('🎾 Invitación a jugar\n${m.body}', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
      MessageKind.match => InkWell(onTap: () => context.push('/match/${m.refId}/final'), child: Text('🏆 Partido compartido', style: TextStyle(color: fg, fontWeight: FontWeight.w700))), // mensajes antiguos sin snapshot
      MessageKind.league => Text('🏅 Liga compartida\n${m.body}', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
      MessageKind.profile => InkWell(onTap: () => context.push('/player/${m.refId}'), child: Text('👤 Perfil compartido', style: TextStyle(color: fg, fontWeight: FontWeight.w700))),
    };
    return Align(
      alignment: align,
      child: GestureDetector(
        onTap: m.status == MessageStatus.failed ? onRetry : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
          decoration: BoxDecoration(color: mine ? PlobbyColors.forest : Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (showSender && sender != null) _senderLabel(sender!),
            body,
            Align(alignment: Alignment.centerRight, child: Text('$time$status', style: TextStyle(fontSize: 10, color: fg.withOpacity(.6)))),
          ]),
        ),
      ),
    );
  }

  Widget _senderLabel(GroupMember s) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 9, backgroundColor: PlobbyColors.forest, foregroundImage: s.avatarUrl == null ? null : NetworkImage(s.avatarUrl!),
            child: Text(s.initials.characters.first, style: const TextStyle(fontSize: 9, color: PlobbyColors.lime, fontWeight: FontWeight.w800))),
        const SizedBox(width: 6),
        Text(s.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: PlobbyColors.forest)),
        if (s.isAdmin) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.shield_outlined, size: 11, color: PlobbyColors.mute)),
      ]));
}
