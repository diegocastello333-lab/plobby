import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/state_views.dart';
import '../../social/application/social_providers.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';

const _titles = ['Información básica', 'Participantes', 'Formato de competición', 'Temporada', 'Revisar y crear'];
const _subtitles = ['Ponle nombre, imagen y tipo a tu liga.', 'Invita a tus amigos y define el tamaño.', 'Elige cómo se compite y cómo se puntúa.',
  'Fechas, nivel y zona de juego.', 'Comprueba los ajustes antes de crear.'];
const _zones = ['Madrid · Centro', 'Madrid · Norte', 'Alcobendas', 'Chamartín', 'Moncloa'];

/// Asistente «Crear liga» (prototipo `scCreate`, 5 pasos). Valida cada paso en cliente y de nuevo en servidor (`create_league`).
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
        appBar: AppBar(
          leading: IconButton(tooltip: 'Cerrar sin crear', icon: const Icon(Icons.close), onPressed: () => context.pop()),
          centerTitle: true, title: Text('Paso ${s.step} de 5', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
          bottom: PreferredSize(preferredSize: const Size.fromHeight(8), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Semantics(label: 'Paso ${s.step} de 5', child: Row(children: [for (var i = 1; i <= 5; i++) Expanded(child: Container(height: 4, margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(color: i <= s.step ? AppColors.brand : AppColors.border, borderRadius: AppRadius.rPill)))])))),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
          Text(_titles[s.step - 1], style: const TextStyle(fontFamily: 'Unbounded', fontSize: 23, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_subtitles[s.step - 1], style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 22),
          switch (s.step) { 1 => _Step1(d: d, e: s.errors), 2 => _Step2(d: d, e: s.errors), 3 => _Step3(d: d), 4 => _Step4(d: d, e: s.errors), _ => _Review(d: d, onEdit: c.goTo) },
          if (s.failure != null) Padding(padding: const EdgeInsets.only(top: 16), child: ErrorStateCard(title: 'No se pudo crear la liga', message: s.failure!, onRetry: next)),
        ]),
        bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Row(children: [
          if (s.step > 1) ...[Expanded(child: OutlinedButton(onPressed: s.busy ? null : c.back, child: const Text('Atrás'))), const SizedBox(width: 12)],
          Expanded(flex: 2, child: FilledButton(onPressed: s.busy ? null : next,
              child: s.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.step < 5 ? 'Continuar' : 'CREAR LIGA'))),
        ]))),
      ),
    );
  }
}

InputDecoration _dec(String label, {String? hint, String? error}) => InputDecoration(labelText: label, hintText: hint, errorText: error);

class _Step1 extends ConsumerWidget {
  const _Step1({required this.d, required this.e});
  final LeagueDraft d; final Map<String, String> e;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(createLeagueProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(initialValue: d.name, maxLength: 40, decoration: _dec('Nombre de la liga', hint: 'Ej. Liga de los jueves', error: e['name']),
          onChanged: (v) => c.edit((x) => x.copyWith(name: v))),
      const SizedBox(height: 8),
      TextFormField(initialValue: d.description, maxLength: 180, maxLines: 3, decoration: _dec('Descripción', hint: 'Cuenta de qué va la liga, cuándo se juega y quién puede entrar.', error: e['description']),
          onChanged: (v) => c.edit((x) => x.copyWith(description: v))),
      const SizedBox(height: 12),
      const Text('Portada', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2, children: [
        for (final cv in leagueCovers)
          Semantics(button: true, selected: d.cover == cv, label: 'Portada $cv', child: InkWell(onTap: () => c.edit((x) => x.copyWith(cover: cv)), borderRadius: AppRadius.rMd,
              child: Stack(children: [LeagueCover(cover: cv, height: 64, radius: AppRadius.md),
                if (d.cover == cv) Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: AppRadius.rMd, border: Border.all(color: AppColors.brand, width: 3)),
                    child: const Align(alignment: Alignment.topRight, child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.check_circle, color: AppColors.brand, size: 18)))))]))),
      ]),
      const SizedBox(height: 18),
      const Text('Tipo de liga', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      // Las ligas de club las crea el club desde el panel (supuesto S2 de la migración): aquí solo pública o privada.
      for (final v in const [LeagueVisibility.private, LeagueVisibility.public])
        _Option(icon: visibilityIcon(v), title: v.label, text: v.description, selected: d.visibility == v, onTap: () => c.edit((x) => x.copyWith(visibility: v))),
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
      Row(children: [const Expanded(child: Text('Invitados', style: TextStyle(fontWeight: FontWeight.w600))),
        Text('${d.invited.length} seleccionados', style: const TextStyle(fontSize: 12, color: AppColors.textMuted))]),
      const SizedBox(height: 8),
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar amigos'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
      const SizedBox(height: 8),
      friends.when(
        loading: () => const LoadingBlock(height: 120),
        error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(friendsProvider)),
        data: (fs) {
          final list = fs.where((f) => _q.isEmpty || f.player.name.toLowerCase().contains(_q) || f.player.username.toLowerCase().contains(_q)).toList();
          if (fs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Todavía no tienes amigos en Plobby. Podrás invitar con el código cuando crees la liga.', style: TextStyle(color: AppColors.textMuted)));
          return Column(children: [
            for (final f in list.take(30))
              CheckboxListTile(contentPadding: EdgeInsets.zero, value: d.invited.contains(f.player.id),
                  secondary: LeagueAvatar(name: f.player.name, avatarUrl: f.player.avatarUrl), title: Text(f.player.name), subtitle: Text('ELO ${f.player.elo} · ${f.player.level}'),
                  onChanged: (v) => c.edit((x) => x.copyWith(invited: v == true ? [...x.invited, f.player.id] : x.invited.where((i) => i != f.player.id).toList()))),
          ]);
        },
      ),
      const SizedBox(height: 12),
      NumberStepper(label: 'Mínimo de participantes', value: d.minPlayers, min: 2, max: 32, onChanged: (v) => c.edit((x) => x.copyWith(minPlayers: v, maxPlayers: v > x.maxPlayers ? v : null))),
      NumberStepper(label: 'Máximo de participantes', value: d.maxPlayers, min: 2, max: 64, error: widget.e['players'], onChanged: (v) => c.edit((x) => x.copyWith(maxPlayers: v, minPlayers: v < x.minPlayers ? v : null))),
      const Text('Al crear la liga tendrás un código para compartir con quien quieras.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
    ]);
  }
}

class _Step3 extends ConsumerWidget {
  const _Step3({required this.d});
  final LeagueDraft d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(createLeagueProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Formato', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _Option(icon: Icons.person_outline, title: 'Individual', text: 'Cada partido se juega con parejas distintas; puntúa cada jugador.', selected: d.format == 'individual', onTap: () => c.edit((x) => x.copyWith(format: 'individual'))),
      _Option(icon: Icons.people_outline, title: 'Por parejas', text: 'Parejas fijas durante toda la temporada.', selected: d.format == 'pairs', onTap: () => c.edit((x) => x.copyWith(format: 'pairs'))),
      const SizedBox(height: 12),
      NumberStepper(label: 'Partidos por jugador', value: d.matchesPerPlayer, min: 2, max: 30, onChanged: (v) => c.edit((x) => x.copyWith(matchesPerPlayer: v))),
      NumberStepper(label: 'Puntos por victoria', value: d.pointsWin, min: 1, max: 5, suffix: ' pts', onChanged: (v) => c.edit((x) => x.copyWith(pointsWin: v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: d.bonus, onChanged: (v) => c.edit((x) => x.copyWith(bonus: v)),
          title: const Text('Puntos de bonus'), subtitle: const Text('+1 punto por ganar sin ceder ningún set.')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: d.challenges, onChanged: (v) => c.edit((x) => x.copyWith(challenges: v)),
          title: const Text('Retos entre jugadores'), subtitle: const Text('Permite retar directamente a otros miembros.')),
      const SizedBox(height: 8),
      const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.verified_outlined), title: Text('Validación de resultados'),
          subtitle: Text('Confirman los capitanes de los dos equipos. Si no coinciden, el resultado queda en disputa.')),
    ]);
  }
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
    Widget date(String l, DateTime v, bool start) => Expanded(child: InkWell(onTap: () => pick(start), child: InputDecorator(
        decoration: _dec(l, error: e['dates'] == null ? null : ''), child: Text(fmtDay(v)))));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [date('Inicio', d.startsOn, true), const SizedBox(width: 12), date('Fin', d.endsOn, false)]),
      if (e['dates'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(e['dates']!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(value: d.levelMin, decoration: _dec('Nivel mínimo', error: e['level']),
            items: [for (final l in leagueLevels) DropdownMenuItem(value: l, child: Text(l))], onChanged: (v) => c.edit((x) => x.copyWith(levelMin: v)))),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<String>(value: d.levelMax, decoration: _dec('Nivel máximo'),
            items: [for (final l in leagueLevels) DropdownMenuItem(value: l, child: Text(l))], onChanged: (v) => c.edit((x) => x.copyWith(levelMax: v)))),
      ]),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(value: _zones.contains(d.location) ? d.location : _zones.first, decoration: _dec('Zona de juego'),
          items: [for (final z in _zones) DropdownMenuItem(value: z, child: Text(z))], onChanged: (v) => c.edit((x) => x.copyWith(location: v))),
    ]);
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.d, required this.onEdit});
  final LeagueDraft d; final void Function(int) onEdit;
  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v, int step) => ListTile(contentPadding: EdgeInsets.zero, title: Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        subtitle: Text(v, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)), trailing: TextButton(onPressed: () => onEdit(step), child: const Text('Editar')));
    return Column(children: [
      LeagueCover(cover: d.cover, height: 110),
      const SizedBox(height: 8),
      row('Nombre', d.name.trim().toUpperCase(), 1),
      row('Tipo', d.visibility.label, 1),
      row('Participantes', '${d.minPlayers}–${d.maxPlayers} jugadores · ${d.invited.length} invitados', 2),
      row('Formato', '${d.format == 'pairs' ? 'Por parejas' : 'Individual'} · ${d.matchesPerPlayer} partidos · ${d.pointsWin} pts/victoria${d.bonus ? ' · bonus' : ''}', 3),
      row('Temporada', '${fmtDay(d.startsOn)} – ${fmtDay(d.endsOn)}', 4),
      row('Nivel y zona', '${d.levelMin} – ${d.levelMax} · ${d.location}', 4),
    ]);
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, required this.text, required this.selected, required this.onTap});
  final IconData icon; final String title, text; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Semantics(selected: selected, button: true, child: Material(
      color: selected ? AppColors.brandSoft : AppColors.surface, borderRadius: AppRadius.rMd,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: BorderSide(color: selected ? AppColors.brand : AppColors.border, width: 1.5)),
      child: InkWell(borderRadius: AppRadius.rMd, onTap: () { HapticFeedback.selectionClick(); onTap(); }, child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        Icon(icon), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))])),
        Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.text : AppColors.borderStrong),
      ]))))));
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
      Container(width: 88, height: 88, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle), child: const Icon(Icons.check, size: 46, color: AppColors.brandInk)),
      const SizedBox(height: 18),
      const Text('LIGA CREADA', style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
      const SizedBox(height: 6),
      Text(l?.name ?? '', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Unbounded', fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Temporada ${l?.season ?? '01'}', style: const TextStyle(color: AppColors.textMuted)),
      const SizedBox(height: 24),
      if (code != null) Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6), decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(code!, style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w700)),
            Text(link!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))])),
          FilledButton.tonalIcon(onPressed: () { Clipboard.setData(ClipboardData(text: code!)); showPlobbySnack(context, 'Código copiado'); }, icon: const Icon(Icons.copy, size: 16), label: const Text('Copiar')),
        ])),
      const SizedBox(height: 8),
      const Text('Comparte este código para que tus amigos se unan.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      const SizedBox(height: 26),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => context.push('/leagues/$leagueId/manage'), icon: const Icon(Icons.person_add_alt), label: const Text('Invitar amigos'))),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: () => context.pushReplacement('/leagues/$leagueId?tab=members'), child: const Text('Ir a la liga'))),
    ])))));
  }
}
