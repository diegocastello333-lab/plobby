import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../application/lifecycle_providers.dart';
import '../data/lifecycle_repository.dart';
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';
import 'match_detail_screen.dart' show errorText;

/// Editar partido: fecha, hora, club, pista y capitanes (jugadores/equipos: reutiliza los selectores de CreateMatchScreen —
/// `leagueMembersProvider` en liga, `friendOptionsProvider` en amistoso— y llama a `update_match`, que revalida las reglas de liga).
Future<void> showEditMatchSheet(BuildContext context, LifecycleMatch m) => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: _Sheet(m: m)));

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
  Widget build(BuildContext context) {
    final m = widget.m;
    Widget capSel(int t, String v, ValueChanged<String> on) => DropdownButtonFormField<String>(value: v, decoration: InputDecoration(labelText: 'Capitán equipo $t', border: OutlineInputBorder(borderRadius: AppRadius.rMd)),
        items: [for (final p in m.team(t)) DropdownMenuItem(value: p.id, child: Text(p.name))], onChanged: (x) => setState(() => on(x!)));
    return SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Editar partido', style: Theme.of(context).textTheme.titleLarge),
      if (leagueLocked(m, DateTime.now())) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Regla de liga: a menos de 2 h del inicio no se pueden cambiar los jugadores. Fecha, hora y pista sí.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
      const SizedBox(height: 14),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Fecha y hora'), subtitle: Text('${when.day}/${when.month}/${when.year} · ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'), trailing: const Icon(Icons.edit_calendar_outlined), onTap: () async {
        final d = await showDatePicker(context: context, initialDate: when, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
        if (d == null || !context.mounted) return;
        final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(when));
        if (t != null) setState(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
      }),
      TextField(controller: club, decoration: InputDecoration(labelText: 'Club', border: OutlineInputBorder(borderRadius: AppRadius.rMd))), const SizedBox(height: 12),
      TextField(controller: court, decoration: InputDecoration(labelText: 'Pista (opcional)', border: OutlineInputBorder(borderRadius: AppRadius.rMd))), const SizedBox(height: 12),
      capSel(1, cap1, (x) => cap1 = x), const SizedBox(height: 12), capSel(2, cap2, (x) => cap2 = x),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 52, child: ElevatedButton(onPressed: busy ? null : () async {
        if (!when.isAfter(DateTime.now())) { setState(() => error = 'La fecha y hora deben ser futuras.'); return; }
        setState(() { busy = true; error = null; });
        try {
          await ref.read(lifecycleActionsProvider).update(m.id, EditMatch(scheduledAt: when, club: club.text.trim(), court: court.text.trim(),
              players: [for (final p in m.players) MatchPlayer(id: p.id, name: p.name, team: p.team, isCaptain: p.id == (p.team == 1 ? cap1 : cap2), elo: p.elo, level: p.level, avatarUrl: p.avatarUrl, avatarId: p.avatarId)]));
          if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cambios guardados. Los jugadores ya los ven.'))); }
        } catch (e) { if (mounted) setState(() { busy = false; error = errorText(e); }); }
      }, style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: AppColors.brandInk), child: const Text('Guardar cambios'))),
    ])));
  }
}
