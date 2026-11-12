import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../social/application/social_providers.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';

const _titles = ['Información básica', 'Participantes', 'Formato de competición', 'Temporada', 'Revisar y crear'];
const _subtitles = ['Ponle nombre, imagen y tipo a tu liga.', 'Invita a tus amigos y define el tamaño.', 'Elige cómo se compite y cómo se puntúa.',
  'Fechas, nivel y zona de juego.', 'Comprueba los ajustes antes de crear.'];
const _zones = ['Madrid · Centro', 'Madrid · Norte', 'Alcobendas', 'Chamartín', 'Moncloa'];

/// Asistente «Crear liga» — `scCreate` del prototipo HTML (5 pasos): cerrar · «PASO n DE 5» · barra de pasos, título
/// Unbounded 28, campos con etiqueta encima y pie fijo Atrás / Continuar. Valida cada paso en cliente y de nuevo en el
/// servidor (`create_league`); la lógica es la de siempre ([createLeagueProvider]).
class CreateLeagueScreen extends ConsumerWidget {
  const CreateLeagueScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(createLeagueProvider), c = ref.read(createLeagueProvider.notifier), d = s.draft;
    Future<void> next() async {
      final r = await c.next();
      if (r != null && context.mounted) context.pushReplacement('/leagues/${r.id}/created?code=${Uri.encodeComponent(r.code)}');
    }
    return PopScope(
      canPop: s.step == 1,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) c.back(); },
      child: Scaffold(
        body: SafeArea(bottom: false, child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Row(children: [
            IconSquareButton(icon: PlobbyIcons.close, tooltip: 'Cerrar sin crear', onPressed: () => context.pop()),
            Expanded(child: Center(child: Text('PASO ${s.step} DE 5', style: PlobbyText.eb))),
            const SizedBox(width: 40),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: StepBar(step: s.step, total: 5)),
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 24), children: [
            Semantics(header: true, child: Text(_titles[s.step - 1], style: PlobbyText.t1)),
            const SizedBox(height: 6),
            Text(_subtitles[s.step - 1], style: PlobbyText.sub),
            const SizedBox(height: 22),
            switch (s.step) { 1 => _Step1(d: d, e: s.errors), 2 => _Step2(d: d, e: s.errors), 3 => _Step3(d: d), 4 => _Step4(d: d, e: s.errors), _ => _Review(d: d, onEdit: c.goTo) },
            if (s.failure != null) Padding(padding: const EdgeInsets.only(top: 16), child: ErrorStateCard(title: 'No se pudo crear la liga', message: s.failure!, onRetry: next)),
          ])),
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: Color(0x14171C19)))),
            child: Row(children: [
              if (s.step > 1) ...[Expanded(flex: 10, child: PlobbyButton(label: 'Atrás', kind: PlobbyButtonKind.outline, onPressed: s.busy ? null : c.back)), const SizedBox(width: 10)],
              Expanded(flex: 23, child: PlobbyButton(label: s.step < 5 ? 'Continuar' : 'CREAR LIGA', busy: s.busy, onPressed: next)),
            ]),
          ),
        ])),
      ),
    );
  }
}

/// Etiqueta de grupo (`.lab`) con un complemento opcional a la derecha.
Widget _label(String t, [Widget? trailing]) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
      Expanded(child: Text(t, style: PlobbyText.label)), if (trailing != null) trailing,
    ]));

class _Step1 extends ConsumerWidget {
  const _Step1({required this.d, required this.e});
  final LeagueDraft d; final Map<String, String> e;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(createLeagueProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledField(label: 'Nombre de la liga', initialValue: d.name, maxLength: 40, hint: 'Ej. Liga de los jueves', error: e['name'], onChanged: (v) => c.edit((x) => x.copyWith(name: v))),
      LabeledField(label: 'Descripción', initialValue: d.description, maxLength: 180, maxLines: 3, hint: 'Cuenta de qué va la liga, cuándo se juega y quién puede entrar.',
          error: e['description'], onChanged: (v) => c.edit((x) => x.copyWith(description: v))),
      _label('Portada'),
      GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 110 / 64, children: [
        for (final cv in leagueCovers)
          Semantics(button: true, selected: d.cover == cv, label: 'Portada $cv', excludeSemantics: true, child: GestureDetector(onTap: () { HapticFeedback.selectionClick(); c.edit((x) => x.copyWith(cover: cv)); },
              child: Stack(children: [
                Positioned.fill(child: LeagueCover(cover: cv, height: 64, radius: 10)),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: d.cover == cv ? AppColors.text : const Color(0x1A171C19), width: d.cover == cv ? 3 : 1)))),
                if (d.cover == cv) Positioned(right: 6, top: 6, child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                    child: const Center(child: PlobbyIcon(PlobbyIcons.check, size: 12, strokeWidth: 3, color: AppColors.brandInk)))),
              ]))),
      ]),
      const SizedBox(height: 18),
      _label('Tipo de liga'),
      // Las ligas de club las crea el club desde el panel (supuesto S2 de la migración): aquí solo pública o privada.
      for (final v in const [LeagueVisibility.private, LeagueVisibility.public])
        OptionCard(icon: visibilityPlobbyIcon(v), title: v.label, description: v.description, selected: d.visibility == v, onTap: () => c.edit((x) => x.copyWith(visibility: v))),
    ]);
  }
}

class _Step2 extends ConsumerStatefulWidget {
  const _Step2({required this.d, required this.e});
  final LeagueDraft d; final Map<String, String> e;
  @override
  ConsumerState<_Step2> createState() => _Step2State();
}

class _Step2State extends ConsumerState<_Step2> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final d = widget.d, c = ref.read(createLeagueProvider.notifier);
    final friends = ref.watch(friendsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Invitados', Text('${d.invited.length} ${d.invited.length == 1 ? 'SELECCIONADO' : 'SELECCIONADOS'}', style: PlobbyText.eb)),
      if (d.invited.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Todavía no has invitado a nadie. Puedes hacerlo después.', style: PlobbyText.help.copyWith(fontSize: 12))),
      SearchField(hint: 'Buscar amigos', onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
      const SizedBox(height: 12),
      friends.when(
        loading: () => const LoadingBlock(height: 120, radius: AppRadius.md),
        error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(friendsProvider)),
        data: (fs) {
          final list = fs.where((f) => _q.isEmpty || f.player.name.toLowerCase().contains(_q) || f.player.username.toLowerCase().contains(_q)).toList();
          if (fs.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Todavía no tienes amigos en Plobby. Podrás invitar con el código cuando crees la liga.', style: PlobbyText.sub));
          return Column(children: [
            for (final f in list.take(30)) _InviteRow(
              name: f.player.name, sub: 'ELO ${f.player.elo} · ${f.player.level}', avatarUrl: f.player.avatarUrl, selected: d.invited.contains(f.player.id),
              onTap: () => c.edit((x) => x.copyWith(invited: x.invited.contains(f.player.id) ? x.invited.where((i) => i != f.player.id).toList() : [...x.invited, f.player.id])),
            ),
          ]);
        },
      ),
      const SizedBox(height: 12),
      NumberStepper(label: 'Mínimo de participantes', value: d.minPlayers, min: 2, max: 32, onChanged: (v) => c.edit((x) => x.copyWith(minPlayers: v, maxPlayers: v > x.maxPlayers ? v : null))),
      NumberStepper(label: 'Máximo de participantes', value: d.maxPlayers, min: 2, max: 64, error: widget.e['players'], onChanged: (v) => c.edit((x) => x.copyWith(maxPlayers: v, minPlayers: v < x.minPlayers ? v : null))),
      Text('Al crear la liga tendrás un código para compartir con quien quieras.', style: PlobbyText.help.copyWith(fontSize: 12)),
    ]);
  }
}

/// Fila de invitado: tarjeta blanca radio 12 con avatar 36, nombre, ELO · nivel y casilla cuadrada.
class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.name, required this.sub, required this.selected, required this.onTap, this.avatarUrl});
  final String name, sub; final String? avatarUrl; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Semantics(checked: selected, label: '$name, $sub', excludeSemantics: true, child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: selected ? AppColors.text : const Color(0x1A171C19), width: selected ? 1.5 : 1)),
        child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () { HapticFeedback.selectionClick(); onTap(); }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
          LeagueAvatar(name: name, avatarUrl: avatarUrl, size: 36),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: AppColors.textMuted)),
          ])),
          Container(width: 22, height: 22, decoration: BoxDecoration(color: selected ? AppColors.inverse : AppColors.surface, borderRadius: BorderRadius.circular(6),
              border: selected ? null : Border.all(color: AppColors.borderStrong, width: 1.5)),
              child: selected ? const Center(child: PlobbyIcon(PlobbyIcons.check, size: 13, strokeWidth: 3, color: AppColors.brand)) : null),
        ]))),
      )));
}

class _Step3 extends ConsumerWidget {
  const _Step3({required this.d});
  final LeagueDraft d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(createLeagueProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Formato'),
      OptionCard(icon: PlobbyIcons.user, title: 'Liga individual', description: 'Cada partido se juega con parejas distintas; puntúa cada jugador.', selected: d.format == 'individual', onTap: () => c.edit((x) => x.copyWith(format: 'individual'))),
      OptionCard(icon: PlobbyIcons.users, title: 'Liga por parejas', description: 'Parejas fijas durante toda la temporada.', selected: d.format == 'pairs', onTap: () => c.edit((x) => x.copyWith(format: 'pairs'))),
      const SizedBox(height: 8),
      NumberStepper(label: 'Partidos por jugador', value: d.matchesPerPlayer, min: 2, max: 30, onChanged: (v) => c.edit((x) => x.copyWith(matchesPerPlayer: v))),
      NumberStepper(label: 'Puntos por victoria', value: d.pointsWin, min: 1, max: 5, suffix: ' pts', onChanged: (v) => c.edit((x) => x.copyWith(pointsWin: v))),
      _ToggleRow(title: 'Puntos de bonus', text: '+1 punto por ganar sin ceder ningún set.', value: d.bonus, onChanged: (v) => c.edit((x) => x.copyWith(bonus: v))),
      _ToggleRow(title: 'Retos entre jugadores', text: 'Permite retar directamente a otros miembros.', value: d.challenges, onChanged: (v) => c.edit((x) => x.copyWith(challenges: v))),
      const SizedBox(height: 10),
      _label('Validación de resultados'),
      Container(
        padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PlobbyIcon(PlobbyIcons.shield, size: 18), const SizedBox(width: 10),
          Expanded(child: Text('Confirman los capitanes de los dos equipos. Si no coinciden, el resultado queda en disputa.', style: PlobbyText.sub.copyWith(color: AppColors.ink700))),
        ]),
      ),
    ]);
  }
}

/// Interruptor con título y descripción (tarjeta blanca radio 12).
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.title, required this.text, required this.value, required this.onChanged});
  final String title, text; final bool value; final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(
        color: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0x1A171C19))),
        child: MergeSemantics(child: SwitchListTile(
          value: value, onChanged: onChanged, contentPadding: const EdgeInsets.symmetric(horizontal: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          activeThumbColor: AppColors.brand, activeTrackColor: AppColors.inverse,
          title: Text(title, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
          subtitle: Text(text, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, letterSpacing: 0, color: AppColors.textMuted)),
        )),
      ));
}

class _Step4 extends ConsumerWidget {
  const _Step4({required this.d, required this.e});
  final LeagueDraft d; final Map<String, String> e;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(createLeagueProvider.notifier);
    Future<void> pick(bool start) async {
      final now = DateTime.now();
      final v = await showDatePicker(context: context, initialDate: start ? d.startsOn : d.endsOn, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 2));
      if (v != null) c.edit((x) => start ? x.copyWith(startsOn: v) : x.copyWith(endsOn: v));
    }
    final bad = e['dates'] != null;
    Widget date(String l, DateTime v, bool start) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(l),
          Semantics(button: true, label: '$l: ${fmtDay(v)}', excludeSemantics: true, child: Material(
            color: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: BorderSide(color: bad ? AppColors.danger : AppColors.borderStrong)),
            child: InkWell(borderRadius: AppRadius.rMd, onTap: () => pick(start), child: SizedBox(height: 48, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
              Expanded(child: Text(fmtDay(v), maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.input)), const PlobbyIcon(PlobbyIcons.cal, size: 18, color: AppColors.textMuted),
            ])))),
          )),
        ]));
    Widget select(String label, String value, List<String> items, ValueChanged<String?> on, {String? error}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(label),
          DropdownButtonFormField<String>(value: value, isExpanded: true, style: PlobbyText.input, decoration: plobbyInputDecoration(error: error),
              icon: const PlobbyIcon(PlobbyIcons.down, size: 18, color: AppColors.textMuted),
              items: [for (final l in items) DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis))], onChanged: on),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [date('Inicio', d.startsOn, true), const SizedBox(width: 12), date('Fin', d.endsOn, false)]),
      if (bad) Padding(padding: const EdgeInsets.only(top: 6), child: Text(e['dates']!, style: PlobbyText.help.copyWith(color: AppColors.danger))),
      const SizedBox(height: 18),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: select('Nivel mínimo', d.levelMin, leagueLevels, (v) => c.edit((x) => x.copyWith(levelMin: v)), error: e['level'])),
        const SizedBox(width: 12),
        Expanded(child: select('Nivel máximo', d.levelMax, leagueLevels, (v) => c.edit((x) => x.copyWith(levelMax: v)))),
      ]),
      const SizedBox(height: 18),
      select('Zona o club', _zones.contains(d.location) ? d.location : _zones.first, _zones, (v) => c.edit((x) => x.copyWith(location: v))),
    ]);
  }
}

/// Paso 5: vista previa (portada + nombre + descripción) y tabla de ajustes con «Editar» por bloque.
class _Review extends StatelessWidget {
  const _Review({required this.d, required this.onEdit});
  final LeagueDraft d; final void Function(int) onEdit;
  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v, {bool first = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: Color(0x1A171C19)))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, letterSpacing: 0, color: AppColors.textMuted)),
            const SizedBox(width: 16),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))),
          ]));
    const card = BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(clipBehavior: Clip.antiAlias, decoration: card, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LeagueCover(cover: d.cover, height: 70, radius: 0),
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.name.trim().toUpperCase(), style: leagueNameStyle),
          const SizedBox(height: 4),
          Text(d.description.trim().isEmpty ? 'Sin descripción' : d.description.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: PlobbyText.help.copyWith(fontSize: 12.5)),
        ])),
      ])),
      const SizedBox(height: 14),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), decoration: card, child: Column(children: [
        row('Tipo', d.visibility.label, first: true),
        row('Invitados', d.invited.isEmpty ? 'Ninguno todavía' : '${d.invited.length}'),
        row('Participantes', '${d.minPlayers} a ${d.maxPlayers}'),
        row('Formato', d.format == 'pairs' ? 'Liga por parejas' : 'Liga individual'),
        row('Partidos por jugador', '${d.matchesPerPlayer}'),
        row('Victoria', '${d.pointsWin} ${d.pointsWin == 1 ? 'punto' : 'puntos'}${d.bonus ? ' + bonus' : ''}'),
        row('Validación', 'Confirman ambos equipos'),
        row('Retos', d.challenges ? 'Permitidos' : 'No'),
        row('Temporada', '${fmtDay(d.startsOn)} – ${fmtDay(d.endsOn)}'),
        row('Nivel', '${d.levelMin} – ${d.levelMax}'),
        row('Zona', d.location),
      ])),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: PlobbyButton(label: 'Editar información', icon: PlobbyIcons.edit, kind: PlobbyButtonKind.outline, height: 44, onPressed: () => onEdit(1))),
        const SizedBox(width: 10),
        Expanded(child: PlobbyButton(label: 'Editar formato', icon: PlobbyIcons.sliders, kind: PlobbyButtonKind.outline, height: 44, onPressed: () => onEdit(3))),
      ]),
    ]);
  }
}

/// «Liga creada» (prototipo `scCreated`): código para compartir, invitar amigos e ir a la liga.
class LeagueCreatedScreen extends ConsumerWidget {
  const LeagueCreatedScreen({super.key, required this.leagueId, this.code});
  final String leagueId; final String? code;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(leagueDetailProvider(leagueId)).valueOrNull;
    final link = code == null ? null : 'plobby.app/l/${code!.toLowerCase()}';
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
      Container(width: 88, height: 88, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle), child: const Center(child: PlobbyIcon(PlobbyIcons.check, size: 44, strokeWidth: 2.6, color: AppColors.brandInk))),
      const SizedBox(height: 18),
      const Text('LIGA CREADA', style: PlobbyText.eb),
      const SizedBox(height: 8),
      Text((l?.name ?? '').toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 24, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: .72, color: AppColors.text)),
      const SizedBox(height: 6),
      Text('Temporada ${l?.season ?? '01'}', style: PlobbyText.sub),
      const SizedBox(height: 24),
      if (code != null) Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6), decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(code!, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
            Text(link!, style: PlobbyText.help.copyWith(fontSize: 12))])),
          PlobbyButton(label: 'Copiar', icon: PlobbyIcons.copy, kind: PlobbyButtonKind.small, onPressed: () { Clipboard.setData(ClipboardData(text: code!)); showPlobbySnack(context, 'Código copiado'); }),
        ])),
      const SizedBox(height: 8),
      Text('Comparte este código para que tus amigos se unan.', style: PlobbyText.help),
      const SizedBox(height: 26),
      PlobbyButton(label: 'Invitar amigos', icon: PlobbyIcons.userplus, kind: PlobbyButtonKind.outline, onPressed: () => context.push('/leagues/$leagueId/manage')),
      const SizedBox(height: 10),
      PlobbyButton(label: 'Ir a la liga', onPressed: () => context.pushReplacement('/leagues/$leagueId?tab=members')),
    ])))));
  }
}
