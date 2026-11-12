import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/lifecycle_providers.dart';
import '../application/match_providers.dart';
import '../domain/match_models.dart';

/// Formulario ÚNICO de creación de partido — hoja «Crear partido» del prototipo HTML (aquí como pantalla, misma ruta). `type` decide si pide liga (liga) o no (amistoso).
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
  /// Club escrito a mano cuando la tabla `clubs` está vacía o no se pudo leer (antes: `clubs.first` sobre una lista
  /// vacía lanzaba «Bad state: No element» al construir la pantalla → pantalla gris/negra en la APK).
  final _clubText = TextEditingController();
  late DateTime _when = DateTime.now().add(const Duration(hours: 2));
  final _sets = List.generate(3, (_) => [TextEditingController(), TextEditingController()]);
  String? _error;
  bool _busy = false;

  @override
  void initState() { super.initState(); _league = widget.leagueId; }
  @override
  void dispose() { for (final s in _sets) { for (final c in s) { c.dispose(); } } _clubText.dispose(); super.dispose(); }

  bool get _friendly => widget.type == MatchType.friendly;

  List<SetScore> get _scores => [
        for (final s in _sets) if (s[0].text.isNotEmpty || s[1].text.isNotEmpty) SetScore(int.tryParse(s[0].text) ?? -1, int.tryParse(s[1].text) ?? -1),
      ];

  /// Club que se envía: el elegido en la lista (o el primero, que es el que se ve seleccionado) o el escrito a mano.
  String _selectedClub(List<String> clubs) => clubs.isNotEmpty ? (_club ?? clubs.first) : _clubText.text.trim();

  Future<void> _submit(List<String> clubs) async {
    final club = _selectedClub(clubs);
    final d = MatchDraft(type: widget.type, leagueId: _friendly ? null : _league, partnerId: _partner, rival1Id: _r1, rival2Id: _r2, when: _when, club: club, sets: _scores);
    final err = validateDraft(d, resultRequired: widget.resultRequired) ?? (club.isEmpty ? 'Indica el club donde se juega el partido.' : null);
    if (err != null) { setState(() => _error = err); return; }
    setState(() { _error = null; _busy = true; });
    try {
      await ref.read(matchRepositoryProvider).create(d);
      if (!mounted) return;
      ref.invalidate(upcomingMatchesProvider);   // el nuevo partido aparece en «Próximos partidos» sin esperar a Realtime
      showPlobbySnack(context, d.sets.isEmpty ? 'Partido creado.' : 'Resultado enviado. Pendiente de confirmación.');
      context.pop();
    } on MatchCreateException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'No se pudo enviar. Comprueba tu conexión e inténtalo de nuevo.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagues = ref.watch(myLeaguesProvider);
    final pool = _friendly ? ref.watch(friendOptionsProvider) : (_league == null ? const AsyncData<List<PlayerOption>>([]) : ref.watch(leagueMembersProvider(_league!)));
    final clubsAsync = ref.watch(clubsProvider);
    final clubs = clubsAsync.valueOrNull ?? const <String>[];
    final hasSets = _scores.isNotEmpty;
    String p2(int n) => n.toString().padLeft(2, '0');
    return Scaffold(
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 28), children: [
        // .hr: etiqueta del tipo (.mtag), «Crear partido» y cerrar
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _TypeTag(friendly: _friendly),
            const SizedBox(height: 20),
            Semantics(header: true, child: const Text('Crear partido', style: PlobbyText.t2)),
          ])),
          const SizedBox(width: 12),
          IconSquareButton(icon: PlobbyIcons.close, tooltip: 'Cerrar', onPressed: () => context.pop()),
        ]),
        const SizedBox(height: 16),
        if (!_friendly && widget.leagueId == null) leagues.when(
          loading: () => const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator(color: AppColors.brand, backgroundColor: AppColors.surfaceSunken)),
          error: (_, __) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('No se pudieron cargar tus ligas.', style: PlobbyText.help.copyWith(color: AppColors.danger))),
          data: (l) => l.isEmpty
              ? Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Aún no estás en ninguna liga. Únete a una o crea la tuya para registrar partidos de liga.', style: PlobbyText.sub))
              : _Field(label: 'Liga', child: _Select<String>(
                  value: _league, hint: 'Elige una de tus ligas',
                  items: [for (final x in l) DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() { _league = v; _partner = _r1 = _r2 = null; }),
                )),
        ),
        _Team('Pareja 1', [
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
            Container(width: 30, height: 30, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.inverse),
                child: const Center(child: PlobbyIcon(PlobbyIcons.user, size: 16, color: AppColors.brand))),
            const SizedBox(width: 10),
            const Text('Tú', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
          ])),
          _pick('Tu compañero', _partner, pool, (v) => _partner = v),
        ]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: Text('VS', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.2, color: AppColors.textMuted)))),
        _Team('Pareja 2', [_pick('Rival 1', _r1, pool, (v) => _r1 = v), _pick('Rival 2', _r2, pool, (v) => _r2 = v)]),
        // Estado de la lista de jugadores (antes, un error o una lista vacía dejaba los desplegables vacíos sin explicación).
        if (_friendly || _league != null) pool.when(
          loading: () => Padding(padding: const EdgeInsets.only(top: 8), child: Text('Cargando jugadores…', style: PlobbyText.help.copyWith(fontSize: 12))),
          error: (_, __) => Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
            Expanded(child: Text('No se pudieron cargar los jugadores.', style: PlobbyText.help.copyWith(fontSize: 12, color: AppColors.danger))),
            PlobbyButton(label: 'Reintentar', kind: PlobbyButtonKind.smallOutline, onPressed: () => ref.invalidate(_friendly ? friendOptionsProvider : leagueMembersProvider(_league!))),
          ])),
          data: (l) => l.length >= 3 ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
            Expanded(child: Text(_friendly
                ? 'Para un amistoso necesitas tres amigos que hayan aceptado tu solicitud (tienes ${l.length}).'
                : 'La liga necesita al menos tres miembros más para crear un partido (tiene ${l.length}).', style: PlobbyText.help.copyWith(fontSize: 12))),
            if (_friendly) ...[const SizedBox(width: 8), PlobbyButton(label: 'Añadir amigos', kind: PlobbyButtonKind.smallOutline, onPressed: () => context.push('/friends/add'))],
          ])),
        ),
        if (!_friendly && _league == null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Elige primero la liga para ver a sus jugadores.', style: PlobbyText.help.copyWith(fontSize: 12))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Field(label: 'Fecha', child: _PickerBox(value: '${p2(_when.day)}/${p2(_when.month)}/${_when.year}', icon: PlobbyIcons.cal, label: 'Fecha', onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _when, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
          }))),
          const SizedBox(width: 10),
          Expanded(child: _Field(label: 'Hora', child: _PickerBox(value: '${p2(_when.hour)}:${p2(_when.minute)}', icon: PlobbyIcons.clock, label: 'Hora', onTap: () async {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
            if (t != null) setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
          }))),
        ]),
        // Club: lista de `clubs` si hay; si la tabla está vacía o falla la lectura, campo de texto (la RPC guarda texto).
        if (clubsAsync.isLoading && !clubsAsync.hasValue) const _Field(label: 'Club', child: LoadingBlock(height: 48, radius: AppRadius.md))
        else if (clubs.isNotEmpty) _Field(label: 'Club', child: _Select<String>(value: clubs.contains(_club) ? _club : clubs.first, items: [for (final c in clubs) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))], onChanged: (v) => setState(() => _club = v)))
        else LabeledField(label: 'Club', controller: _clubText, maxLength: 80, hint: 'p. ej. Club La Moraleja', textCapitalization: TextCapitalization.words, onChanged: (_) { if (_error != null) setState(() => _error = null); }),
        Text.rich(TextSpan(style: PlobbyText.label, children: [
          const TextSpan(text: 'Resultado (sets)'),
          if (!widget.resultRequired) TextSpan(text: ' · opcional si aún no se ha jugado', style: PlobbyText.label.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0, color: AppColors.textMuted)),
        ])),
        const SizedBox(height: 8),
        // .card2 con la rejilla de sets (casillas 60×42)
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
          child: Column(children: [
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
              const Spacer(),
              for (final t in ['Pareja 1', 'Pareja 2']) ...[const SizedBox(width: 8), SizedBox(width: 60, child: Text(t, textAlign: TextAlign.center, style: PlobbyText.help.copyWith(fontSize: 12)))],
            ])),
            for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
              Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text), children: [
                TextSpan(text: 'Set ${i + 1}'),
                if (i == 2) const TextSpan(text: ' (opcional)', style: TextStyle(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
              ]))),
              for (var j = 0; j < 2; j++) ...[const SizedBox(width: 8), SizedBox(width: 60, height: 42, child: Semantics(label: 'Set ${i + 1} pareja ${j + 1}', textField: true, child: TextField(
                controller: _sets[i][j], keyboardType: TextInputType.number, textAlign: TextAlign.center, textAlignVertical: TextAlignVertical.center, expands: true, maxLines: null, minLines: null, onChanged: (_) => setState(() {}),
                style: PlobbyText.input, decoration: plobbyInputDecoration(hint: '–', padding: EdgeInsets.zero),
              )))],
            ])),
          ]),
        ),
        const SizedBox(height: 6),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1, right: 6), child: PlobbyIcon(PlobbyIcons.alert, size: 14, color: AppColors.danger)),
          Expanded(child: Text(_error!, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.danger))),
        ])),
        const SizedBox(height: 6),
        Text(_friendly ? 'Un amistoso no pertenece a ninguna liga.' : 'El partido quedará vinculado a la liga elegida.', style: PlobbyText.help.copyWith(fontSize: 12)),
        const SizedBox(height: 14),
        PlobbyButton(label: hasSets ? 'Enviar resultado' : 'Crear partido', busy: _busy, onPressed: () => _submit(clubs)),
      ])),
    );
  }

  Widget _pick(String label, String? value, AsyncValue<List<PlayerOption>> pool, ValueChanged<String?> set) => _Field(label: label, child: _Select<String>(
        value: value, hint: 'Elige un jugador',
        items: [for (final p in pool.valueOrNull ?? const <PlayerOption>[]) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
        onChanged: pool.valueOrNull?.isEmpty ?? true ? null : (v) => setState(() => set(v)),
      ));
}

/// `.mtag`: pastilla lima suave 26 px con el tipo de partido.
class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.friendly});
  final bool friendly;
  @override
  Widget build(BuildContext context) => Container(
        height: 26, padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(color: AppColors.brandSoft, borderRadius: AppRadius.rPill),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PlobbyIcon(friendly ? PlobbyIcons.racket : PlobbyIcons.trophy, size: 14, color: AppColors.text), const SizedBox(width: 6),
          Text(friendly ? 'Partido amistoso' : 'Partido de liga', style: PlobbyText.chip.copyWith(color: AppColors.text)),
        ]),
      );
}

/// `.fld`: etiqueta encima (12/700) + control; 12 px de separación inferior.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label; final Widget child;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: PlobbyText.label), const SizedBox(height: 7), child,
      ]));
}

/// `select.inp`: 48 px, radio 14, borde 1 px, flecha a la derecha.
class _Select<T> extends StatelessWidget {
  const _Select({required this.value, required this.items, required this.onChanged, this.hint});
  final T? value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?>? onChanged; final String? hint;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: value, isExpanded: true, style: PlobbyText.input, decoration: plobbyInputDecoration(),
        hint: hint == null ? null : Text(hint!, style: PlobbyText.input.copyWith(color: AppColors.textMuted)),
        icon: const PlobbyIcon(PlobbyIcons.down, size: 18, color: AppColors.textMuted),
        items: items, onChanged: onChanged,
      );
}

/// Campo de fecha u hora: caja `.inp` que abre el selector nativo.
class _PickerBox extends StatelessWidget {
  const _PickerBox({required this.value, required this.icon, required this.label, required this.onTap});
  final String value, label; final PlobbyIcons icon; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: '$label: $value', excludeSemantics: true, child: Material(
        color: AppColors.surface, shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: BorderSide(color: AppColors.borderStrong)),
        child: InkWell(borderRadius: AppRadius.rMd, onTap: onTap, child: SizedBox(height: 48, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
          Expanded(child: Text(value, style: PlobbyText.input)), PlobbyIcon(icon, size: 18, color: AppColors.textMuted),
        ])))),
      ));
}

/// `.mteam`: caja hundida radio 14, padding 12 14 2, con eyebrow de pareja.
class _Team extends StatelessWidget {
  const _Team(this.title, this.children);
  final String title; final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
        decoration: const BoxDecoration(color: AppColors.surfaceSunken, borderRadius: AppRadius.rMd),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: PlobbyText.eb), const SizedBox(height: 8), ...children,
        ]),
      );
}
