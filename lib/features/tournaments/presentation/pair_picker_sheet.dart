import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../profile/application/profile_providers.dart';
import '../../social/application/social_providers.dart';
import '../domain/tournament_models.dart';
import 'tournament_widgets.dart';

/// Hoja «Añadir pareja»: elige dos jugadores entre tú, tus amigos o cualquier usuario de Plobby (buscador).
/// Los ya inscritos aparecen bloqueados: nadie puede estar en dos parejas del mismo torneo.
Future<(TPlayer, TPlayer)?> showPairPicker(BuildContext context, {required Set<String> used}) =>
    showPlobbySheet<(TPlayer, TPlayer)>(context, (_) => _PairPicker(used: used));

class _PairPicker extends ConsumerStatefulWidget {
  const _PairPicker({required this.used});
  final Set<String> used;
  @override
  ConsumerState<_PairPicker> createState() => _PairPickerState();
}

class _PairPickerState extends ConsumerState<_PairPicker> {
  TPlayer? _a, _b;
  final _q = TextEditingController();
  Timer? _debounce;
  List<TPlayer> _results = const [];
  bool _searching = false;

  @override
  void dispose() { _q.dispose(); _debounce?.cancel(); super.dispose(); }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() { _results = const []; _searching = false; }); return; }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final hits = await ref.read(socialRepositoryProvider).search(q.trim());
        if (mounted) setState(() { _results = [for (final h in hits) TPlayer(id: h.player.id, name: h.player.name, username: h.player.username, avatarUrl: h.player.avatarUrl)]; _searching = false; });
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _pick(TPlayer p) => setState(() {
        if (_a?.id == p.id) { _a = null; } else if (_b?.id == p.id) { _b = null; }
        else if (_a == null) { _a = p; } else if (_b == null) { _b = p; } else { _b = p; }
      });

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider('me')).valueOrNull?.profile;
    final friends = ref.watch(friendsProvider).valueOrNull ?? const [];
    final candidates = <TPlayer>[
      if (me != null) TPlayer(id: me.id, name: me.fullName, username: me.username, avatarUrl: me.avatarUrl),
      for (final f in friends) TPlayer(id: f.player.id, name: f.player.name, username: f.player.username, avatarUrl: f.player.avatarUrl),
    ];
    final searching = _q.text.trim().length >= 2;
    final list = searching ? _results : candidates;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHeader(title: 'Añadir pareja', subtitle: 'Elige a los dos jugadores que formarán la pareja.'),
      Row(children: [Expanded(child: _Slot(label: 'Jugador 1', p: _a, onClear: () => setState(() => _a = null))), const SizedBox(width: 10),
          Expanded(child: _Slot(label: 'Jugador 2', p: _b, onClear: () => setState(() => _b = null)))]),
      const SizedBox(height: 14),
      TextField(controller: _q, onChanged: _search, style: PlobbyText.input, textInputAction: TextInputAction.search,
          decoration: plobbyInputDecoration(hint: 'Buscar en Plobby por nombre o usuario').copyWith(prefixIcon: const Padding(padding: EdgeInsets.all(12), child: PlobbyIcon(PlobbyIcons.search, size: 18, color: AppColors.textMuted)))),
      const SizedBox(height: 10),
      Text(searching ? 'RESULTADOS' : 'TÚ Y TUS AMIGOS', style: PlobbyText.eb),
      const SizedBox(height: 4),
      if (searching && _searching) const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text)))),
      if (!_searching && list.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(searching ? 'No hay jugadores con ese nombre.' : 'Aún no tienes amigos: búscalos arriba por su nombre.', style: PlobbyText.help)),
      ConstrainedBox(constraints: const BoxConstraints(maxHeight: 300), child: ListView(shrinkWrap: true, children: [
        for (final p in list)
          _Candidate(p: p, used: widget.used.contains(p.id), selected: _a?.id == p.id || _b?.id == p.id, isMe: me?.id == p.id, onTap: () => _pick(p)),
      ])),
      const SizedBox(height: 12),
      PlobbyButton(label: _a != null && _b != null ? 'Añadir pareja' : 'Elige dos jugadores', onPressed: _a != null && _b != null ? () => Navigator.pop(context, (_a!, _b!)) : null),
    ]);
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.label, required this.p, required this.onClear});
  final String label; final TPlayer? p; final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180), height: 56, padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: p == null ? AppColors.surfaceSunken : AppColors.brandSoft, borderRadius: AppRadius.rSm,
            border: Border.all(color: p == null ? const Color(0x1A171C19) : AppColors.brand, width: 1.5)),
        child: p == null
            ? Center(child: Text(label, style: PlobbyText.help))
            : Row(children: [
                TPlayerAvatar(p!, size: 30), const SizedBox(width: 8),
                Expanded(child: Text(p!.short, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))),
                Semantics(button: true, label: 'Quitar $label', excludeSemantics: true, child: InkResponse(onTap: onClear, radius: 18, child: const PlobbyIcon(PlobbyIcons.close, size: 16))),
              ]),
      );
}

class _Candidate extends StatelessWidget {
  const _Candidate({required this.p, required this.used, required this.selected, required this.isMe, required this.onTap});
  final TPlayer p; final bool used, selected, isMe; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Opacity(opacity: used ? .45 : 1, child: Semantics(button: true, enabled: !used, selected: selected,
      label: '${p.name}${isMe ? ' (tú)' : ''}${used ? ', ya está inscrito' : ''}', excludeSemantics: true,
      child: InkWell(onTap: used ? null : onTap, child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14171C19)))),
        child: Row(children: [
          TPlayerAvatar(p, size: 38), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isMe ? '${p.name} (tú)' : p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            Text(used ? 'Ya está en otra pareja' : (p.username.isEmpty ? '' : '@${p.username}'), style: PlobbyText.help.copyWith(fontSize: 12)),
          ])),
          AnimatedScale(scale: selected ? 1 : .85, duration: const Duration(milliseconds: 160), child: Container(width: 24, height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? AppColors.brand : null, border: selected ? null : Border.all(color: AppColors.borderStrong, width: 1.5)),
              child: selected ? const Center(child: PlobbyIcon(PlobbyIcons.check, size: 13, strokeWidth: 3, color: AppColors.brandInk)) : null)),
        ]),
      ))));
}
