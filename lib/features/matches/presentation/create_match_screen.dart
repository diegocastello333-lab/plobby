import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';
import '../application/match_providers.dart';
import '../domain/match_models.dart';

/// Formulario ÚNICO de creación de partido. `type` decide si pide liga (liga) o no (amistoso).
/// `leagueId` + `resultRequired` se usan al registrar el resultado desde una liga concreta (flujo previo).
class CreateMatchScreen extends ConsumerStatefulWidget {
  const CreateMatchScreen({super.key, required this.type, this.leagueId, this.resultRequired = false});
  final MatchType type;
  final String? leagueId;
  final bool resultRequired;
  @override
  ConsumerState<CreateMatchScreen> createState() => _S();
}

class _S extends ConsumerState<CreateMatchScreen> {
  String? _league, _partner, _r1, _r2, _club;
  late DateTime _when = DateTime.now().add(const Duration(hours: 2));
  final _sets = List.generate(3, (_) => [TextEditingController(), TextEditingController()]);
  String? _error;
  bool _busy = false;

  @override
  void initState() { super.initState(); _league = widget.leagueId; }
  @override
  void dispose() { for (final s in _sets) { for (final c in s) { c.dispose(); } } super.dispose(); }

  bool get _friendly => widget.type == MatchType.friendly;

  List<SetScore> get _scores => [
        for (final s in _sets) if (s[0].text.isNotEmpty || s[1].text.isNotEmpty) SetScore(int.tryParse(s[0].text) ?? -1, int.tryParse(s[1].text) ?? -1),
      ];

  Future<void> _submit() async {
    final d = MatchDraft(type: widget.type, leagueId: _friendly ? null : _league, partnerId: _partner, rival1Id: _r1, rival2Id: _r2, when: _when, club: _club ?? 'Club La Moraleja', sets: _scores);
    final err = validateDraft(d, resultRequired: widget.resultRequired);
    if (err != null) { setState(() => _error = err); return; }
    setState(() { _error = null; _busy = true; });
    try {
      await ref.read(matchRepositoryProvider).create(d);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(d.sets.isEmpty ? 'Partido creado.' : 'Resultado enviado. Pendiente de confirmación.')));
      context.pop();
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'No se pudo enviar. Comprueba tu conexión e inténtalo de nuevo.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagues = ref.watch(myLeaguesProvider);
    final pool = _friendly ? ref.watch(friendOptionsProvider) : (_league == null ? const AsyncData<List<PlayerOption>>([]) : ref.watch(leagueMembersProvider(_league!)));
    final clubs = ref.watch(clubsProvider).valueOrNull ?? const ['Club La Moraleja'];
    final hasSets = _scores.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(_friendly ? 'Partido amistoso' : 'Partido de liga')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        if (!_friendly && widget.leagueId == null) leagues.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('No se pudieron cargar tus ligas.'),
          data: (l) => l.isEmpty
              ? const Text('Aún no estás en ninguna liga. Únete a una o crea la tuya para registrar partidos de liga.')
              : DropdownButtonFormField<String>(
                  value: _league, decoration: const InputDecoration(labelText: 'Liga'), hint: const Text('Elige una de tus ligas'),
                  items: [for (final x in l) DropdownMenuItem(value: x.id, child: Text(x.name))],
                  onChanged: (v) => setState(() { _league = v; _partner = _r1 = _r2 = null; }),
                ),
        ),
        const SizedBox(height: 16),
        _Team('Pareja 1', [const ListTile(dense: true, leading: CircleAvatar(radius: 15, child: Text('Tú')), title: Text('Tú')), _pick('Tu compañero', _partner, pool, (v) => _partner = v)]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: Text('VS', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.textMuted)))),
        _Team('Pareja 2', [_pick('Rival 1', _r1, pool, (v) => _r1 = v), _pick('Rival 2', _r2, pool, (v) => _r2 = v)]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.calendar_today_outlined, size: 16), label: Text('${_when.day}/${_when.month}/${_when.year}'), onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _when, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
          })),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.schedule, size: 16), label: Text(TimeOfDay.fromDateTime(_when).format(context)), onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
            if (t != null) setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
          })),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _club ?? clubs.first, decoration: const InputDecoration(labelText: 'Club'), items: [for (final c in clubs) DropdownMenuItem(value: c, child: Text(c))], onChanged: (v) => setState(() => _club = v)),
        const SizedBox(height: 16),
        Text(widget.resultRequired ? 'Resultado (sets)' : 'Resultado (sets) · opcional si aún no se ha jugado', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
          Expanded(child: Text('Set ${i + 1}${i == 2 ? ' (opcional)' : ''}')),
          SizedBox(width: 64, child: TextField(controller: _sets[i][0], keyboardType: TextInputType.number, textAlign: TextAlign.center, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: '–'))),
          const SizedBox(width: 8),
          SizedBox(width: 64, child: TextField(controller: _sets[i][1], keyboardType: TextInputType.number, textAlign: TextAlign.center, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: '–'))),
        ])),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
        const SizedBox(height: 8),
        Text(_friendly ? 'Un amistoso no pertenece a ninguna liga.' : 'El partido quedará vinculado a la liga elegida.', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(hasSets ? 'Enviar resultado' : 'Crear partido')),
      ]),
    );
  }

  Widget _pick(String label, String? value, AsyncValue<List<PlayerOption>> pool, ValueChanged<String?> set) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: value, decoration: InputDecoration(labelText: label), hint: const Text('Elige un jugador'),
          items: [for (final p in pool.valueOrNull ?? const <PlayerOption>[]) DropdownMenuItem(value: p.id, child: Text(p.name))],
          onChanged: pool.valueOrNull?.isEmpty ?? true ? null : (v) => setState(() => set(v)),
        ),
      );
}

class _Team extends StatelessWidget {
  const _Team(this.title, this.children);
  final String title; final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0), decoration: AppCardStyles.sunken,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(height: 8), ...children,
        ]),
      );
}
