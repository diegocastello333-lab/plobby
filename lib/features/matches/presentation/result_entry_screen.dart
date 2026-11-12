import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/lifecycle_providers.dart';
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';
import 'match_detail_screen.dart' show errorText, durationText;
import 'match_widgets.dart';

/// Introducir o corregir el resultado — `scMResult` del prototipo HTML. Valida contra el formato configurado
/// (al mejor de 3 sets) y determina el ganador. Enviarlo crea una NUEVA versión: los capitanes deben aceptarla
/// (las aceptaciones previas quedan invalidadas).
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

  /// Fila con algún valor y set no válido → borde rojo en sus dos casillas (como `.inp.err`).
  bool _bad(int i) {
    final a = _c[i * 2].text, b = _c[i * 2 + 1].text;
    if (a.isEmpty && b.isEmpty) return false;
    final x = int.tryParse(a), y = int.tryParse(b);
    return x == null || y == null || !isValidSet(x, y);
  }

  Future<void> _send(LifecycleMatch m, SetsCheck check) async {
    setState(() => _busy = true);
    try {
      await ref.read(lifecycleActionsProvider).submit(m.id, [for (final s in check.sets) SetScoreInput(s.a, s.b)]);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showPlobbySnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(matchProvider(widget.matchId)).valueOrNull;
    if (m == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.text)));
    if (!_seeded) { _seeded = true; for (var i = 0; i < m.sets.length; i++) { _c[i * 2].text = '${m.sets[i].a}'; _c[i * 2 + 1].text = '${m.sets[i].b}'; } }
    final sets = _sets(), check = validateSets(sets), edit = m.resultVersion > 0;
    String names(int t) => m.team(t).map((p) => p.name.split(' ').first).join(' y ');
    const muted = TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.4, letterSpacing: 0, color: AppColors.textMuted);
    return Scaffold(
      body: Column(children: [
        PlobbyHeaderBar(title: 'Resultado', onBack: () => context.pop()),
        Expanded(child: ListView(padding: EdgeInsets.fromLTRB(20, 4, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          Text.rich(TextSpan(style: muted, children: [
            if (m.durationSeconds != null) ...[const TextSpan(text: 'Duración: '), TextSpan(text: durationText(m.durationSeconds!), style: const TextStyle(fontWeight: FontWeight.w700)), const TextSpan(text: ' · ')],
            const TextSpan(text: 'Formato: al mejor de 3 sets.'),
            if (edit) ...[
              const TextSpan(text: '\nEstás proponiendo una '), const TextSpan(text: 'corrección', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' (versión ${m.resultVersion + 1}): invalidará las aceptaciones anteriores.'),
            ],
          ])),
          const SizedBox(height: 14),
          // .rs-g: rejilla 1fr · 74 · 74
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: AppColors.border)),
            child: Column(children: [
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                const Spacer(),
                for (final t in [1, 2]) ...[const SizedBox(width: 8), SizedBox(width: 74, child: Text(names(t), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)))],
              ])),
              for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text), children: [
                  TextSpan(text: 'Set ${i + 1}'),
                  if (i == 2) const TextSpan(text: ' (solo si 1-1)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textMuted)),
                ]))),
                for (var j = 0; j < 2; j++) ...[const SizedBox(width: 8), SizedBox(width: 74, height: 50, child: _GameField(controller: _c[i * 2 + j], label: 'Set ${i + 1} equipo ${j + 1}', error: _bad(i), onChanged: () => setState(() {})))],
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          if (sets.isEmpty) Text('Introduce los games de cada set.', style: PlobbyText.help.copyWith(fontSize: 12))
          else if (!check.valid) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
            const PlobbyIcon(PlobbyIcons.alert, size: 14, color: AppColors.danger), const SizedBox(width: 6),
            Expanded(child: Text(check.error!, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.danger))),
          ]))
          else Container(   // .rs-pv
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('VISTA PREVIA', style: PlobbyText.eb),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: ScoreBoard(match: m, sets: check.sets)),
              Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
                const PlobbyIcon(PlobbyIcons.trophy, size: 16), const SizedBox(width: 8),
                Expanded(child: Text('Ganan ${names(check.winner!)} · ${check.sets.where((s) => s.a > s.b).length}-${check.sets.where((s) => s.b > s.a).length}',
                    style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))),
              ])),
            ]),
          ),
          const SizedBox(height: 18),
          MatchCtaButton(label: edit ? 'Enviar corrección' : 'Enviar resultado', busy: _busy, onTap: !check.valid ? null : () => _send(m, check)),
          const SizedBox(height: 14),
          Text('Los dos capitanes tendrán que aceptar exactamente esta versión. Hasta entonces no afecta a ELO, estadísticas, racha ni clasificación.',
              textAlign: TextAlign.center, style: PlobbyText.help.copyWith(fontSize: 12)),
        ])),
      ]),
    );
  }
}

/// Casilla de games (`.rs-r .inp`): 74×50, radio 14, Unbounded 20 centrado; borde rojo si el set no es válido.
class _GameField extends StatelessWidget {
  const _GameField({required this.controller, required this.label, required this.error, required this.onChanged});
  final TextEditingController controller; final String label; final bool error; final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: BorderSide(color: c, width: w));
    return Semantics(label: label, textField: true, child: TextField(
      controller: controller, keyboardType: TextInputType.number, textAlign: TextAlign.center, textAlignVertical: TextAlignVertical.center, maxLength: 1, expands: true, maxLines: null, minLines: null,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => onChanged(),
      style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text),
      decoration: InputDecoration(
        counterText: '', filled: true, fillColor: AppColors.surface, isDense: true, contentPadding: EdgeInsets.zero,
        enabledBorder: b(error ? AppColors.danger : AppColors.borderStrong, error ? 1.5 : 1), focusedBorder: b(error ? AppColors.danger : AppColors.text, 2), border: b(AppColors.borderStrong),
      ),
    ));
  }
}
