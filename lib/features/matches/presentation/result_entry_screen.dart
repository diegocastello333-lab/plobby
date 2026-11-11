import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../application/lifecycle_providers.dart';
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';
import 'match_detail_screen.dart' show errorText;

/// Introducir o corregir el resultado. Valida contra el formato configurado (al mejor de 3 sets) y determina el ganador.
/// Enviarlo crea una NUEVA versión: los capitanes deben aceptarla (las aceptaciones previas quedan invalidadas).
class ResultEntryScreen extends ConsumerStatefulWidget {
  const ResultEntryScreen({super.key, required this.matchId});
  final String matchId;
  @override
  ConsumerState<ResultEntryScreen> createState() => _S();
}
class _S extends ConsumerState<ResultEntryScreen> {
  final _c = List.generate(6, (_) => TextEditingController());
  bool _busy = false, _seeded = false;
  @override
  void dispose() { for (final c in _c) { c.dispose(); } super.dispose(); }
  List<SetScore> _sets() {
    final out = <SetScore>[];
    for (var i = 0; i < 3; i++) { final a = int.tryParse(_c[i * 2].text), b = int.tryParse(_c[i * 2 + 1].text); if (a != null || b != null) out.add(SetScore(a ?? -1, b ?? -1)); }
    return out;
  }
  @override
  Widget build(BuildContext context) {
    final m = ref.watch(matchProvider(widget.matchId)).valueOrNull;
    if (m == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_seeded) { _seeded = true; for (var i = 0; i < m.sets.length; i++) { _c[i * 2].text = '${m.sets[i].a}'; _c[i * 2 + 1].text = '${m.sets[i].b}'; } }
    final sets = _sets(), check = validateSets(sets), edit = m.resultVersion > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Resultado'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('${m.durationSeconds != null ? 'Duración: ${m.durationSeconds! ~/ 60} min · ' : ''}Formato: al mejor de 3 sets.${edit ? '\nEstás proponiendo una corrección (versión ${m.resultVersion + 1}): invalidará las aceptaciones anteriores.' : ''}', style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: AppColors.border)), child: Column(children: [
          Row(children: [const SizedBox(width: 70), for (final t in [1, 2]) Expanded(child: Text(m.team(t).map((p) => p.name.split(' ').first).join(' y '), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))]),
          for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
            SizedBox(width: 70, child: Text('Set ${i + 1}${i == 2 ? '\n(si 1-1)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            for (var j = 0; j < 2; j++) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: TextField(controller: _c[i * 2 + j], keyboardType: TextInputType.number, textAlign: TextAlign.center, maxLength: 1, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}), style: const TextStyle(fontFamily: 'Unbounded', fontSize: 20), decoration: InputDecoration(counterText: '', border: OutlineInputBorder(borderRadius: AppRadius.rMd))))),
          ])),
        ])),
        const SizedBox(height: 14),
        if (sets.isEmpty) const Text('Introduce los games de cada set.', style: TextStyle(color: AppColors.textMuted))
        else if (!check.valid) Text(check.error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))
        else Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: AppColors.border)), child: Row(children: [
          const Icon(Icons.emoji_events_outlined), const SizedBox(width: 8),
          Expanded(child: Text('Ganan ${m.team(check.winner!).map((p) => p.name.split(' ').first).join(' y ')} · ${check.sets.where((s) => s.a > s.b).length}-${check.sets.where((s) => s.b > s.a).length}', style: const TextStyle(fontWeight: FontWeight.w700)))])),
        const SizedBox(height: 18),
        SizedBox(height: 56, child: ElevatedButton(
          onPressed: !check.valid || _busy ? null : () async {
            setState(() => _busy = true);
            try { await ref.read(lifecycleActionsProvider).submit(m.id, [for (final s in check.sets) SetScoreInput(s.a, s.b)]); if (context.mounted) context.pop(); }
            catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)))); }
            finally { if (mounted) setState(() => _busy = false); }
          },
          style: ElevatedButton.styleFrom(shape: const StadiumBorder(), backgroundColor: AppColors.brand, foregroundColor: AppColors.brandInk),
          child: _busy ? const CircularProgressIndicator(strokeWidth: 2) : Text(edit ? 'Enviar corrección' : 'Enviar resultado', style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600)))),
        const SizedBox(height: 10),
        const Text('Los dos capitanes tendrán que aceptar exactamente esta versión. Hasta entonces no afecta a ELO, estadísticas, racha ni clasificación.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]),
    );
  }
}
