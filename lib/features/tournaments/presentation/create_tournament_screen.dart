import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/application/profile_providers.dart';
import '../application/tournament_providers.dart';
import '../domain/tournament_models.dart';
import 'pair_picker_sheet.dart';
import 'tournament_widgets.dart';

/// Portada 16:9 recortada al centro, 1200 px como mucho y JPEG 82 (en un isolate): ligera y sin deformar.
Uint8List prepareTournamentCover(Uint8List raw) {
  var im = img.decodeImage(raw);
  if (im == null) throw const FormatException('imagen no válida');
  im = img.bakeOrientation(im);
  const ratio = 16 / 9;
  var w = im.width, h = (im.width / ratio).round();
  if (h > im.height) { h = im.height; w = (im.height * ratio).round(); }
  im = img.copyCrop(im, x: (im.width - w) ~/ 2, y: (im.height - h) ~/ 2, width: w, height: h);
  if (im.width > 1200) im = img.copyResize(im, width: 1200, height: (1200 / ratio).round(), interpolation: img.Interpolation.cubic);
  return Uint8List.fromList(img.encodeJpg(im, quality: 82));
}

/// «Crear torneo» en 4 pasos. Nada se guarda en Supabase hasta pulsar «Crear torneo» en el resumen; entonces se crea
/// todo de una vez (torneo, parejas y estructura) en una única operación del servidor.
class CreateTournamentScreen extends ConsumerStatefulWidget {
  const CreateTournamentScreen({super.key});
  @override
  ConsumerState<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends ConsumerState<CreateTournamentScreen> {
  static const _steps = ['Información', 'Formato', 'Parejas', 'Resumen'];
  int _step = 0;
  TournamentDraft _d = TournamentDraft(startsOn: DateTime.now().add(const Duration(days: 7)));
  final _name = TextEditingController(), _desc = TextEditingController(), _slot = TextEditingController(), _loc = TextEditingController();
  String? _error;
  bool _busy = false, _coverBusy = false;

  @override
  void dispose() { for (final c in [_name, _desc, _slot, _loc]) { c.dispose(); } super.dispose(); }

  TournamentDraft get _draft => _d.copyWith(name: _name.text, description: _desc.text, timeSlot: _slot.text, location: _loc.text);

  String? _validate(int step) => switch (step) {
        0 => validateTournamentInfo(_draft),
        2 || 3 => validateTournamentFormat(_draft),
        _ => null,
      };

  void _next() {
    final e = _validate(_step);
    setState(() => _error = e);
    if (e != null) return;
    if (_step < _steps.length - 1) setState(() { _step++; _error = null; });
  }

  void _back() { if (_step == 0) { context.pop(); } else { setState(() { _step--; _error = null; }); } }

  Future<void> _create() async {
    if (_busy) return;   // doble toque: un solo torneo
    final d = _draft;
    final e = validateTournamentInfo(d) ?? validateTournamentFormat(d);
    if (e != null) { setState(() => _error = e); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final repo = ref.read(tournamentRepositoryProvider);
      final cover = d.coverBytes == null ? null : await repo.uploadCover(d.coverBytes!);
      final id = await repo.create(d, coverUrl: cover);
      ref.invalidate(myTournamentsProvider);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showPlobbySnack(context, 'Torneo creado. ¡Cuadro y partidos listos!');
      context.pushReplacement('/tournaments/$id');
    } on TournamentException catch (x) {
      if (mounted) setState(() { _busy = false; _error = x.message; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'No se pudo crear el torneo. Comprueba tu conexión e inténtalo de nuevo.'; });
    }
  }

  Future<void> _pickCover() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 92);
    if (x == null || !mounted) return;
    setState(() => _coverBusy = true);
    try {
      final bytes = await compute(prepareTournamentCover, await x.readAsBytes());
      if (mounted) setState(() { _d = _d.copyWith(coverBytes: bytes); _coverBusy = false; });
    } catch (_) {
      if (mounted) { setState(() => _coverBusy = false); showPlobbySnack(context, 'No se pudo usar esa imagen.', error: true); }
    }
  }

  Future<void> _addPair() async {
    final r = await showPairPicker(context, used: _d.playerIds);
    if (r == null || !mounted) return;
    setState(() { _d = _d.copyWith(teams: [..._d.teams, r]); _error = null; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: Column(children: [
          PlobbyHeaderBar(title: 'Crear torneo', onBack: _busy ? null : _back),
          // Progreso: 4 segmentos que se rellenan.
          Padding(padding: const EdgeInsets.fromLTRB(20, 6, 20, 0), child: Row(children: [
            for (var i = 0; i < _steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 250), height: 4,
                  decoration: BoxDecoration(color: i <= _step ? AppColors.text : const Color(0x1F171C19), borderRadius: BorderRadius.circular(2)))),
            ],
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Align(alignment: Alignment.centerLeft,
              child: Text('PASO ${_step + 1} DE ${_steps.length} · ${_steps[_step].toUpperCase()}', style: PlobbyText.eb))),
          Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(.04, 0), end: Offset.zero).animate(a), child: c)),
              child: KeyedSubtree(key: ValueKey(_step), child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: switch (_step) {
                0 => _info(),
                1 => _format(),
                2 => _pairs(),
                _ => _summary(),
              })))),
          if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 1, right: 6), child: PlobbyIcon(PlobbyIcons.alert, size: 14, color: AppColors.danger)),
            Expanded(child: Text(_error!, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.danger))),
          ])),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(flex: 10, child: PlobbyButton(label: _step == 0 ? 'Cancelar' : 'Atrás', kind: PlobbyButtonKind.outline, onPressed: _busy ? null : _back)),
              const SizedBox(width: 10),
              Expanded(flex: 18, child: _step == _steps.length - 1
                  ? PlobbyButton(label: 'Crear torneo', icon: PlobbyIcons.trophy, busy: _busy, onPressed: _create)
                  : PlobbyButton(label: 'Siguiente', onPressed: _next)),
            ]),
          ),
        ])),
      );

  // ─────────────────────────── Paso 1: información ───────────────────────────
  List<Widget> _info() => [
        Semantics(button: true, label: _d.coverBytes == null ? 'Añadir foto de portada' : 'Cambiar foto de portada', excludeSemantics: true, child: GestureDetector(
          onTap: _coverBusy ? null : _pickCover,
          child: Stack(children: [
            TournamentCover(bytes: _d.coverBytes == null ? null : Uint8List.fromList(_d.coverBytes!), seed: _name.text, height: 150),
            Positioned.fill(child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: const Color(0x99171C19), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _coverBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.lime300))
                      : const PlobbyIcon(PlobbyIcons.image, size: 16, color: AppColors.surface),
                  const SizedBox(width: 8),
                  Text(_d.coverBytes == null ? 'Añadir portada' : 'Cambiar portada', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.surface)),
                ])))),
          ]),
        )),
        if (_d.coverBytes != null) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => _d = _d.copyWith(clearCover: true)),
            child: const Text('Quitar portada', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.danger)))),
        const SizedBox(height: 14),
        LabeledField(label: 'Nombre del torneo', controller: _name, maxLength: 60, hint: 'p. ej. Open de Otoño', textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
        LabeledField(label: 'Descripción (opcional)', controller: _desc, maxLength: 500, maxLines: 4, minLines: 2, hint: 'Normas, premios, cómo se juega…', textCapitalization: TextCapitalization.sentences),
        Row(children: [
          Expanded(child: _DateBox(label: 'Inicio', value: _d.startsOn, onPick: (v) => setState(() => _d = _d.copyWith(startsOn: v)))),
          const SizedBox(width: 10),
          Expanded(child: _DateBox(label: 'Fin (opcional)', value: _d.endsOn, first: _d.startsOn, onPick: (v) => setState(() => _d = _d.copyWith(endsOn: v)),
              onClear: _d.endsOn == null ? null : () => setState(() => _d = _d.copyWith(clearEnd: true)))),
        ]),
        const SizedBox(height: 16),
        LabeledField(label: 'Horario (opcional)', controller: _slot, maxLength: 60, hint: 'p. ej. Sábado 10:00–14:00'),
        LabeledField(label: 'Club o ubicación (opcional)', controller: _loc, maxLength: 120, hint: 'p. ej. Club La Moraleja', textCapitalization: TextCapitalization.words),
        _Stepper(label: 'Máximo de parejas', value: _d.maxTeams, min: 2, max: 64, onChanged: (v) => setState(() => _d = _d.copyWith(maxTeams: v))),
      ];

  // ─────────────────────────── Paso 2: formato ───────────────────────────
  List<Widget> _format() {
    final n = _d.teams.length;
    return [
      const Text('¿Cómo se juega?', style: PlobbyText.t2),
      const SizedBox(height: 4),
      const Text('Plobby crea los partidos, los grupos y el cuadro automáticamente.', style: PlobbyText.sub),
      const SizedBox(height: 14),
      for (final f in TournamentFormat.values) _FormatCard(format: f, selected: _d.format == f, onTap: () => setState(() { _d = _d.copyWith(format: f); _error = null; })),
      if (_d.format == TournamentFormat.groupsKnockout) ...[
        const SizedBox(height: 6),
        _Stepper(label: 'Número de grupos', value: _d.groupsCount, min: 1, max: 8, onChanged: (v) => setState(() => _d = _d.copyWith(groupsCount: v))),
        _Stepper(label: 'Pasan de cada grupo', value: _d.qualifiersPerGroup, min: 1, max: 4, onChanged: (v) => setState(() => _d = _d.copyWith(qualifiersPerGroup: v))),
        Text('Clasificación: 3 puntos por victoria; desempates por diferencia de sets y de juegos. '
            'Pasan ${_d.groupsCount * _d.qualifiersPerGroup} parejas a la eliminatoria.', style: PlobbyText.help),
      ],
      if (n > 0) ...[const SizedBox(height: 14), Text('Con las $n parejas actuales: ${estimatedMatches(_d.format, n, groups: _d.groupsCount, qualifiers: _d.qualifiersPerGroup)} partidos.', style: PlobbyText.help)],
    ];
  }

  // ─────────────────────────── Paso 3: parejas ───────────────────────────
  List<Widget> _pairs() {
    final me = ref.watch(profileProvider('me')).valueOrNull?.profile;
    final partner = me?.partner;
    final canPartner = me != null && partner != null && !_d.playerIds.contains(me.id) && !_d.playerIds.contains(partner.userId);
    return [
      Row(children: [
        Expanded(child: Text('${_d.teams.length} ${_d.teams.length == 1 ? 'pareja' : 'parejas'} · ${_d.playerIds.length} jugadores', style: PlobbyText.t2)),
        Text('máx. ${_d.maxTeams}', style: PlobbyText.help),
      ]),
      const SizedBox(height: 4),
      Text(switch (_d.format) {
        TournamentFormat.knockout => 'Mínimo 2 parejas. Si no es potencia de 2, las mejores semillas pasan directas (BYE).',
        TournamentFormat.roundRobin => 'Mínimo 3 parejas: todas juegan contra todas.',
        TournamentFormat.groupsKnockout => 'Mínimo ${2 * _d.groupsCount} parejas (2 por grupo).',
      }, style: PlobbyText.help),
      const SizedBox(height: 14),
      PlobbyButton(label: 'Añadir pareja', icon: PlobbyIcons.userplus, onPressed: _d.teams.length >= _d.maxTeams ? null : _addPair),
      if (canPartner) Padding(padding: const EdgeInsets.only(top: 8), child: PlobbyButton(label: 'Añadirme con mi pareja habitual', icon: PlobbyIcons.users, kind: PlobbyButtonKind.outline,
          onPressed: _d.teams.length >= _d.maxTeams ? null : () => setState(() => _d = _d.copyWith(teams: [..._d.teams,
            (TPlayer(id: me.id, name: me.fullName, username: me.username, avatarUrl: me.avatarUrl), TPlayer(id: partner.userId, name: partner.name, username: partner.username, avatarUrl: partner.avatarUrl))])))),
      const SizedBox(height: 16),
      if (_d.teams.isEmpty)
        const EmptyStateCard(icon: Icons.groups_2_outlined, title: 'Sin parejas todavía', text: 'Añade parejas de dos jugadores: amigos o cualquier usuario de Plobby.')
      else ...[
        for (var i = 0; i < _d.teams.length; i++) _TeamRow(seed: i + 1, a: _d.teams[i].$1, b: _d.teams[i].$2,
            onRemove: () => setState(() => _d = _d.copyWith(teams: [..._d.teams]..removeAt(i)))),
        if (_d.teams.length > 2) Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: () => setState(() => _d = _d.copyWith(teams: [..._d.teams]..shuffle())),
            icon: const PlobbyIcon(PlobbyIcons.refresh, size: 16), label: const Text('Sortear el orden de las semillas', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)))),
      ],
    ];
  }

  // ─────────────────────────── Paso 4: resumen ───────────────────────────
  List<Widget> _summary() {
    final d = _draft;
    final n = d.teams.length;
    final rows = <(String, String)>[
      ('Nombre', d.name.trim()),
      ('Fechas', tournamentDates(d.startsOn!, d.endsOn)),
      if (d.timeSlot.trim().isNotEmpty) ('Horario', d.timeSlot.trim()),
      if (d.location.trim().isNotEmpty) ('Lugar', d.location.trim()),
      ('Formato', d.format.label),
      if (d.format == TournamentFormat.groupsKnockout) ('Grupos', '${d.groupsCount} grupos · pasan ${d.qualifiersPerGroup} por grupo'),
      ('Parejas', '$n de ${d.maxTeams} · ${d.playerIds.length} jugadores'),
      ('Partidos', '${estimatedMatches(d.format, n, groups: d.groupsCount, qualifiers: d.qualifiersPerGroup)} en total'),
    ];
    return [
      if (d.coverBytes != null) ...[TournamentCover(bytes: Uint8List.fromList(d.coverBytes!), seed: d.name, height: 120), const SizedBox(height: 14)],
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0x14171C19)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 92, child: Text(rows[i].$1.toUpperCase(), style: PlobbyText.eb)),
              Expanded(child: Text(rows[i].$2, style: PlobbyText.value)),
            ]),
          ),
        ]),
      ),
      if (d.description.trim().isNotEmpty) ...[const SizedBox(height: 12), Text(d.description.trim(), style: PlobbyText.desc)],
      const SizedBox(height: 18),
      const Text('PAREJAS INSCRITAS', style: PlobbyText.eb),
      const SizedBox(height: 6),
      for (var i = 0; i < n; i++) _TeamRow(seed: i + 1, a: d.teams[i].$1, b: d.teams[i].$2),
      const SizedBox(height: 10),
      const Text('Al crear el torneo se generan los partidos y el cuadro, y se avisa a todos los jugadores.', style: PlobbyText.help),
    ];
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({required this.format, required this.selected, required this.onTap});
  final TournamentFormat format; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (format) {
      TournamentFormat.knockout => (PlobbyIcons.trophy, 'Cuadro de octavos, cuartos, semifinales y final. Quien pierde queda fuera.'),
      TournamentFormat.groupsKnockout => (PlobbyIcons.users, 'Grupos de todos contra todos y, después, eliminatoria con los mejores de cada grupo.'),
      TournamentFormat.roundRobin => (PlobbyIcons.refresh, 'Todas las parejas juegan entre sí. Gana quien suma más puntos.'),
    };
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Semantics(button: true, selected: selected, label: '${format.label}. $text', excludeSemantics: true,
      child: Material(color: selected ? AppColors.brandSoft : AppColors.surface, borderRadius: AppRadius.rMd, child: InkWell(borderRadius: AppRadius.rMd, onTap: onTap,
        child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: AppRadius.rMd, border: Border.all(color: selected ? AppColors.text : const Color(0x1F171C19), width: selected ? 2 : 1)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: selected ? AppColors.inverse : AppColors.surfaceSunken, borderRadius: BorderRadius.circular(10)),
                child: Center(child: PlobbyIcon(icon, size: 18, color: selected ? AppColors.brand : AppColors.text))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(format.label, style: PlobbyText.cardTitle),
              const SizedBox(height: 3),
              Text(text, style: PlobbyText.help),
            ])),
          ]),
        )))));
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.seed, required this.a, required this.b, this.onRemove});
  final int seed; final TPlayer a, b; final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14171C19)))),
        child: Row(children: [
          Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(8)),
              child: Text('$seed', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text))),
          const SizedBox(width: 12),
          Expanded(child: TeamLine(team: TTeam(id: '$seed', seed: seed, p1: a, p2: b), size: 28)),
          if (onRemove != null) IconButton(onPressed: onRemove, tooltip: 'Quitar pareja $seed', icon: const PlobbyIcon(PlobbyIcons.close, size: 18, color: AppColors.textMuted)),
        ]),
      );
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.label, required this.value, required this.onPick, this.first, this.onClear});
  final String label; final DateTime? value, first; final ValueChanged<DateTime> onPick; final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: PlobbyText.label),
        const SizedBox(height: 8),
        Semantics(button: true, label: '$label: ${value == null ? 'sin fecha' : tournamentDates(value!, null)}', excludeSemantics: true, child: Material(
          color: AppColors.surface, shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: BorderSide(color: AppColors.borderStrong)),
          child: InkWell(borderRadius: AppRadius.rMd, onTap: () async {
            final now = DateTime.now();
            final d = await showDatePicker(context: context, firstDate: first ?? DateTime(now.year - 1), lastDate: DateTime(now.year + 3), initialDate: value ?? first ?? now);
            if (d != null) onPick(d);
          }, child: SizedBox(height: 48, child: Row(children: [
            const SizedBox(width: 12), const PlobbyIcon(PlobbyIcons.cal, size: 17, color: AppColors.textMuted), const SizedBox(width: 8),
            Expanded(child: Text(value == null ? 'Sin fecha' : tournamentDates(value!, null), style: PlobbyText.input.copyWith(color: value == null ? AppColors.textMuted : AppColors.text))),
            if (onClear != null) IconButton(onPressed: onClear, tooltip: 'Quitar fecha de fin', icon: const PlobbyIcon(PlobbyIcons.close, size: 15)),
          ]))),
        )),
      ]);
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label; final int value, min, max; final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [
        Expanded(child: Text(label, style: PlobbyText.label)),
        IconSquareButton(icon: PlobbyIcons.dash, tooltip: 'Menos', size: 36, onPressed: value > min ? () => onChanged(value - 1) : null),
        SizedBox(width: 44, child: Text('$value', textAlign: TextAlign.center, style: PlobbyText.stat.copyWith(fontSize: 18))),
        IconSquareButton(icon: PlobbyIcons.plus, tooltip: 'Más', size: 36, onPressed: value < max ? () => onChanged(value + 1) : null),
      ]));
}
