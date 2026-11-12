import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/live/presence.dart';
import '../../../core/theme/plobby_theme.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../social/presentation/player_tile.dart';
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

/// Verde de «En línea» (indicador de presencia).
const _onlineGreen = Color(0xFF1FA463);

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  /// Mensajes cargados al abrir: esos se muestran sin animar; los que lleguen o se envíen después entran deslizándose.
  int? _initialCount;

  @override
  void initState() { super.initState(); activeConversation.value = widget.conversationId; }

  @override
  void dispose() {
    if (activeConversation.value == widget.conversationId) activeConversation.value = null;
    _c.dispose(); _scroll.dispose(); super.dispose();
  }

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
    // Si me sacan del grupo (o lo abandono desde otro dispositivo) mientras estoy dentro, salgo con un aviso en vez de
    // quedarme en un chat al que ya no puedo escribir.
    ref.listen(conversationProvider(widget.conversationId), (prev, next) {
      if (prev?.valueOrNull != null && next.hasValue && next.value == null && mounted) {
        showPlobbySnack(context, 'Ya no formas parte de esta conversación');
        context.pop();
      }
    });
    final other = conv?.other;
    // Presencia real del amigo (Realtime Presence en su canal `presence:<id>`), no un dato guardado.
    final online = !isGroup && other != null && (ref.watch(onlineProvider(other.id)).valueOrNull ?? false);
    return Scaffold(
      body: SafeArea(child: Column(children: [
        // .chh: volver · avatar con punto «en línea» · nombre y estado (grupo: participantes → info)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          decoration: const BoxDecoration(color: AppColors.bg, border: Border(bottom: BorderSide(color: Color(0x1A171C19)))),
          child: Row(children: [
            IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', onPressed: () => context.pop()),
            const SizedBox(width: 10),
            Expanded(child: Semantics(button: true, label: isGroup ? 'Info del grupo ${conv!.title}' : 'Perfil de ${conv?.title ?? widget.title}', excludeSemantics: true, child: InkWell(
              onTap: isGroup ? () => context.push('/messages/${widget.conversationId}/info') : widget.otherId == null ? null : () => context.push('/player/${widget.otherId}'),
              child: Row(children: [
                if (isGroup) GroupAvatar(url: conv!.groupAvatarUrl, bytes: conv.groupAvatarBytes, presetId: conv.groupAvatarId, size: 40)
                else if (other != null) Stack(clipBehavior: Clip.none, children: [
                  PlayerAvatar(other, size: 40),
                  Positioned(right: -1, bottom: -1, child: AnimatedContainer(duration: const Duration(milliseconds: 250), width: 12, height: 12,
                      decoration: BoxDecoration(color: online ? _onlineGreen : const Color(0xFFB9C0BB), shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)))),
                ]),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(conv?.title ?? widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
                  AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: Text(
                      isGroup ? '${conv!.memberCount} participantes · toca para ver info' : (online ? 'En línea' : 'Desconectado'),
                      key: ValueKey(isGroup ? 'g${conv!.memberCount}' : '$online'), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0,
                          fontWeight: online ? FontWeight.w600 : FontWeight.w400, color: online ? _onlineGreen : AppColors.textMuted))),
                ])),
              ]),
            ))),
            if (isGroup) IconSquareButton(icon: PlobbyIcons.info, tooltip: 'Info del grupo', onPressed: () => context.push('/messages/${widget.conversationId}/info')),
          ]),
        ),
        Expanded(child: msgs.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(title: 'No se pudo cargar la conversación', onRetry: () => ref.invalidate(chatProvider(widget.conversationId)))),
          data: (l) { _initialCount ??= l.length; return ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), itemCount: l.length + 1, itemBuilder: (_, i) {
                  if (i == 0) {
                    return Column(children: [
                      Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(isGroup ? 'GRUPO' : 'CONVERSACIÓN PRIVADA', textAlign: TextAlign.center, style: PlobbyText.eb)),
                      if (l.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Aún no hay mensajes. Saluda 👋', textAlign: TextAlign.center, style: PlobbyText.help.copyWith(fontSize: 12))),
                    ]);
                  }
                  final k = i - 1;
                  final m = l[k], mine = m.senderId == me;
                  if (m.kind == MessageKind.system) return _SystemMsg(m.body);
                  // en grupos: nombre+foto del remitente al empezar una racha de mensajes ajenos
                  final showSender = isGroup && !mine && (k == 0 || l[k - 1].senderId != m.senderId || l[k - 1].kind == MessageKind.system);
                  final bubble = _Bubble(m, mine: mine, sender: isGroup && !mine ? byId[m.senderId] : null, showSender: showSender, meId: me,
                      onRetry: () => ref.read(chatProvider(widget.conversationId).notifier).retry(m.id));
                  return k < (_initialCount ?? 0) ? bubble : _NewMessage(fromRight: mine, child: bubble);
                }); },
        )),
        // .chi: acciones rápidas · compartir resultado · campo en píldora · enviar (lima)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: Color(0x1A171C19)))),
          child: Row(children: [
            IconSquareButton(icon: PlobbyIcons.plus, tooltip: 'Acciones rápidas', size: 40, onPressed: _quick),
            const SizedBox(width: 8),
            IconSquareButton(icon: PlobbyIcons.trophy, tooltip: 'Compartir resultado de partido', size: 40, onPressed: _shareMatch),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _c, maxLength: 500, style: PlobbyText.input, cursorColor: AppColors.text, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(),
                decoration: plobbyInputDecoration(hint: 'Escribe un mensaje', radius: 22, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
            const SizedBox(width: 8),
            Tooltip(message: 'Enviar', child: Semantics(button: true, label: 'Enviar', excludeSemantics: true, child: Material(color: AppColors.brand, shape: const CircleBorder(),
                child: InkWell(customBorder: const CircleBorder(), onTap: _send, child: const SizedBox(width: 44, height: 44, child: Center(child: PlobbyIcon(PlobbyIcons.plane, size: 18, color: AppColors.brandInk))))))),
          ]),
        ),
      ])),
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
      showPlobbySnack(context, switch (e.code) {
        'recap_not_confirmed' => 'Solo se pueden compartir partidos finalizados y confirmados',
        'recap_not_participant' => 'Solo puedes compartir partidos en los que has jugado',
        'not_a_member' => 'Ya no formas parte de esta conversación',
        _ => 'No se pudo enviar el resultado. Inténtalo de nuevo',
      }, error: true);
    }
  }

  void _quick() => showPlobbySheet(context, (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Acciones rápidas'),
        SheetListItem(icon: PlobbyIcons.racket, label: 'Invitar a jugar', onTap: () { Navigator.pop(c); _invite(); }),
        SheetListItem(icon: PlobbyIcons.trophy, label: 'Compartir resultado de un partido', onTap: () { Navigator.pop(c); _shareMatch(); }),
        // «Compartir una liga» seguía sin selector de ligas (TODO previo): se avisa en vez de no hacer nada.
        SheetListItem(icon: PlobbyIcons.users, label: 'Compartir una liga', onTap: () { Navigator.pop(c); showPlobbySnack(context, 'Compartir ligas por mensaje estará disponible pronto.'); }),
        SheetListItem(icon: PlobbyIcons.user, label: 'Compartir mi perfil', onTap: () { Navigator.pop(c); ref.read(chatProvider(widget.conversationId).notifier).send('Mi perfil', kind: MessageKind.profile, refId: ref.read(messagingRepositoryProvider).meId); }),
      ]));

  Future<void> _invite() async {
    final day = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)), initialDate: DateTime.now().add(const Duration(days: 1)));
    if (day == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 0));
    if (t == null || !mounted) return;
    ref.read(chatProvider(widget.conversationId).notifier).send('${day.day}/${day.month} ${t.format(context)}', kind: MessageKind.invite);
  }
}

/// Entrada de un mensaje nuevo: 12 px desde su lado + fundido, 240 ms. Sin clave propia: al pasar de «enviando» a
/// «enviado» (cambia el id) el elemento se reutiliza y no se repite la animación.
class _NewMessage extends StatelessWidget {
  const _NewMessage({required this.child, required this.fromRight});
  final Widget child; final bool fromRight;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic, child: child,
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset((fromRight ? 12 : -12) * (1 - t), 8 * (1 - t)), child: c)),
    );
  }
}

class _SystemMsg extends StatelessWidget {
  const _SystemMsg(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .86),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(12)),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0)))));
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m, {required this.mine, required this.onRetry, required this.meId, this.sender, this.showSender = false});
  final ChatMessage m; final bool mine, showSender; final VoidCallback onRetry; final GroupMember? sender; final String meId;

  void _openMatch(BuildContext c) {
    final payload = m.payload;
    final participant = payload != null && (payload['players'] as List?)?.any((p) => (p as Map)['user_id'] == meId) == true;
    // participante → detalle vivo del partido; no participante (RLS) → snapshot guardado en el mensaje
    if (participant || payload == null) { c.push('/match/${m.refId}/final'); return; }
    showPlobbySheet(c, (_) => Column(mainAxisSize: MainAxisSize.min, children: [MatchResultCard(payload: payload, sharerId: m.senderId, width: 320)]));
  }

  @override
  Widget build(BuildContext context) {
    final time = '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';
    final status = !mine ? '' : switch (m.status) { MessageStatus.sending => ' …', MessageStatus.sent => ' ✓', MessageStatus.read => ' ✓✓', MessageStatus.failed => ' · No enviado, toca para reintentar' };
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;

    // La tarjeta de resultado va sin burbuja: es el contenido.
    if (m.kind == MessageKind.match && m.payload != null) {
      return Align(alignment: align, child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (showSender && sender != null) _senderLabel(sender!),
        MatchResultCard(payload: m.payload!, sharerId: m.senderId, onTap: () => _openMatch(context)),
        Padding(padding: const EdgeInsets.only(top: 3), child: Text('$time$status', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10.5, letterSpacing: 0, color: AppColors.textMuted))),
      ])));
    }

    // `.cbb.me`: tinta con texto lima; `.cbb.thb`: blanca con sombra. Radio 16 con la esquina de la cola a 5.
    final fg = mine ? AppColors.onInverse : AppColors.text;
    final ts = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, height: 1.4, letterSpacing: 0, color: fg);
    final body = switch (m.kind) {
      MessageKind.text || MessageKind.system => Text(m.body, style: ts),
      MessageKind.invite => _card(PlobbyIcons.racket, 'Invitación a jugar', m.body, fg),
      MessageKind.match => InkWell(onTap: () => context.push('/match/${m.refId}/final'), child: _card(PlobbyIcons.trophy, 'Partido compartido', null, fg)), // mensajes antiguos sin snapshot
      MessageKind.league => _card(PlobbyIcons.trophy, 'Liga compartida', m.body, fg),
      MessageKind.profile => InkWell(onTap: () => context.push('/player/${m.refId}'), child: _card(PlobbyIcons.user, 'Perfil compartido', null, fg)),
    };
    return Align(
      alignment: align,
      child: AnimatedOpacity(opacity: m.status == MessageStatus.sending ? .7 : 1, duration: const Duration(milliseconds: 200), child: GestureDetector(
        onTap: m.status == MessageStatus.failed ? onRetry : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
          decoration: BoxDecoration(color: mine ? AppColors.inverse : AppColors.surface,
              borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 5), bottomRight: Radius.circular(mine ? 5 : 16)),
              boxShadow: mine ? null : AppShadows.card),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (showSender && sender != null) _senderLabel(sender!),
            body,
            Padding(padding: const EdgeInsets.only(top: 3), child: Align(alignment: Alignment.centerRight, widthFactor: 1, child: Text('$time$status', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10.5, letterSpacing: 0, color: fg.withValues(alpha: .7))))),
          ]),
        ),
      )),
    );
  }

  /// Tarjeta dentro de la burbuja (`.cardm`): icono + título 13.5/700 + detalle 12.
  Widget _card(PlobbyIcons i, String title, String? sub, Color fg) => Row(mainAxisSize: MainAxisSize.min, children: [
        PlobbyIcon(i, size: 18, color: fg), const SizedBox(width: 10),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: fg)),
          if (sub != null && sub.isNotEmpty) Text(sub, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: fg.withValues(alpha: .8))),
        ])),
      ]);

  /// `.gsn`: nombre del remitente 11.5/800 con la etiqueta ADMIN en lima.
  Widget _senderLabel(GroupMember s) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(s.name, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text)),
        if (s.isAdmin) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(5)),
            child: const Text('ADMIN', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: .76, color: AppColors.brandInk))),
      ]));
}
