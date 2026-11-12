import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/lifecycle_providers.dart';
import '../data/lifecycle_repository.dart';
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';
import 'match_detail_screen.dart' show errorText;

/// Editar partido (`editSheet` del prototipo HTML): fecha, hora, club, pista y capitanes. Llama a `update_match`, que
/// revalida las reglas de liga. Los jugadores se mantienen (esta pantalla nunca los ha cambiado).
Future<void> showEditMatchSheet(BuildContext context, LifecycleMatch m) => showPlobbySheet(context, (_) => _Sheet(m: m));

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.m});
  final LifecycleMatch m;
  @override
  ConsumerState<_Sheet> createState() => _SS();
}

class _SS extends ConsumerState<_Sheet> {
  late DateTime when = widget.m.scheduledAt;
  late final club = TextEditingController(text: widget.m.club), court = TextEditingController(text: widget.m.court ?? '');
  late String cap1 = widget.m.captainOf(1)?.id ?? widget.m.team(1).first.id, cap2 = widget.m.captainOf(2)?.id ?? widget.m.team(2).first.id;
  String? error; bool busy = false;

  @override
  void dispose() { club.dispose(); court.dispose(); super.dispose(); }

  String _p(int n) => n.toString().padLeft(2, '0');

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: when.isBefore(DateTime.now()) ? DateTime.now() : when, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null && mounted) setState(() => when = DateTime(d.year, d.month, d.day, when.hour, when.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(when));
    if (t != null && mounted) setState(() => when = DateTime(when.year, when.month, when.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final m = widget.m;
    if (!when.isAfter(DateTime.now())) { setState(() => error = 'La fecha y hora deben ser futuras.'); return; }
    setState(() { busy = true; error = null; });
    try {
      await ref.read(lifecycleActionsProvider).update(m.id, EditMatch(scheduledAt: when, club: club.text.trim(), court: court.text.trim(),
          players: [for (final p in m.players) MatchPlayer(id: p.id, name: p.name, team: p.team, isCaptain: p.id == (p.team == 1 ? cap1 : cap2), elo: p.elo, level: p.level, avatarUrl: p.avatarUrl, avatarId: p.avatarId)]));
      if (mounted) { Navigator.pop(context); showPlobbySnack(context, 'Cambios guardados. Los jugadores ya los ven.'); }
    } catch (e) { if (mounted) setState(() { busy = false; error = errorText(e); }); }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m, league = m.type == MatchType.league;
    Widget field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: PlobbyText.label), const SizedBox(height: 8), child]);
    Widget picker(String label, String value, PlobbyIcons icon, VoidCallback onTap) => field(label, Semantics(button: true, label: '$label: $value', excludeSemantics: true, child: Material(
          color: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: const BorderSide(color: AppColors.borderStrong)),
          child: InkWell(borderRadius: AppRadius.rMd, onTap: onTap, child: SizedBox(height: 48, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
            Expanded(child: Text(value, style: PlobbyText.input)), PlobbyIcon(icon, size: 18, color: AppColors.textMuted),
          ])))),
        )));
    Widget capSel(int t, String v, ValueChanged<String> on) => field('Capitán equipo $t', DropdownButtonFormField<String>(
          value: v, isExpanded: true, style: PlobbyText.input, decoration: plobbyInputDecoration(),
          icon: const PlobbyIcon(PlobbyIcons.down, size: 18, color: AppColors.textMuted),
          items: [for (final p in m.team(t)) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
          onChanged: (x) => setState(() => on(x!)),
        ));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // .hr con etiqueta del tipo (.mtag), título y liga
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Pill(league ? 'Partido de liga' : 'Partido amistoso', tone: PillTone.neutral, icon: league ? PlobbyIcons.trophy : PlobbyIcons.racket),
          const SizedBox(height: 8),
          Semantics(header: true, child: const Text('Editar partido', style: PlobbyText.t2)),
          if (m.leagueName != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.leagueName!, style: PlobbyText.sub)),
        ])),
        const SizedBox(width: 12),
        IconSquareButton(icon: PlobbyIcons.close, tooltip: 'Cerrar', onPressed: () => Navigator.pop(context)),
      ]),
      const SizedBox(height: 16),
      if (leagueLocked(m, DateTime.now())) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 1, right: 5), child: PlobbyIcon(PlobbyIcons.lock, size: 13, color: AppColors.textMuted)),
        Expanded(child: Text('Regla de liga: a menos de 2 h del inicio no se pueden cambiar los jugadores. Fecha, hora y pista sí.', style: PlobbyText.help.copyWith(fontSize: 12))),
      ])),
      Row(children: [
        Expanded(child: picker('Fecha', '${_p(when.day)}/${_p(when.month)}/${when.year}', PlobbyIcons.cal, _pickDate)),
        const SizedBox(width: 10),
        Expanded(child: picker('Hora', '${_p(when.hour)}:${_p(when.minute)}', PlobbyIcons.clock, _pickTime)),
      ]),
      const SizedBox(height: 12),
      LabeledField(label: 'Club', controller: club, maxLength: 80),
      LabeledField(label: 'Pista (opcional)', controller: court, maxLength: 20, hint: 'p. ej. Pista 3'),
      capSel(1, cap1, (x) => cap1 = x),
      const SizedBox(height: 12),
      capSel(2, cap2, (x) => cap2 = x),
      const SizedBox(height: 12),
      if (error != null) Row(children: [
        const PlobbyIcon(PlobbyIcons.alert, size: 14, color: AppColors.danger), const SizedBox(width: 6),
        Expanded(child: Text(error!, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.danger))),
      ])
      else Text('Los otros jugadores verán los cambios al instante.', style: PlobbyText.help.copyWith(fontSize: 12)),
      const SizedBox(height: 16),
      PlobbyButton(label: 'Guardar cambios', busy: busy, onPressed: _save),
    ]);
  }
}
