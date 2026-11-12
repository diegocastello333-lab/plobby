import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/league_providers.dart';
import '../domain/league_models.dart';
import 'league_widgets.dart';
import 'leagues_screen.dart';

/// «Descubrir ligas» (prototipo `scDiscover`): búsqueda en servidor (debounce), filtros de tipo/estado/zona y estados de carga, error y vacío.
class DiscoverLeaguesScreen extends ConsumerStatefulWidget {
  const DiscoverLeaguesScreen({super.key});
  @override
  ConsumerState<DiscoverLeaguesScreen> createState() => _DiscoverLeaguesScreenState();
}

class _DiscoverLeaguesScreenState extends ConsumerState<DiscoverLeaguesScreen> {
  Timer? _debounce;
  late final _q = TextEditingController(text: ref.read(discoverFiltersProvider).query);
  final _busy = <String>{};
  @override
  void dispose() { _debounce?.cancel(); _q.dispose(); super.dispose(); }

  void _set(DiscoverFilters Function(DiscoverFilters) f) => ref.read(discoverFiltersProvider.notifier).update(f);

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(discoverFiltersProvider);
    final res = ref.watch(discoverProvider);
    final zones = res.valueOrNull?.map((d) => d.location).where((z) => z.isNotEmpty).toSet().toList() ?? const <String>[];
    return Scaffold(
      body: SafeArea(bottom: false, child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 130), children: [
        Row(children: [
          IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', onPressed: () => context.pop()),
          const Spacer(),
          IconSquareButton(icon: PlobbyIcons.link, tooltip: 'Unirme con código', onPressed: () => showJoinByCodeSheet(context)),
        ]),
        const SizedBox(height: 20),
        Semantics(header: true, child: const Text('Descubrir ligas', style: PlobbyText.t1)),
        const SizedBox(height: 6),
        const Text('Encuentra tu próxima competición.', style: PlobbyText.sub),
        const SizedBox(height: 16),
        SearchField(hint: 'Buscar por nombre, club o zona', controller: _q,
            onChanged: (v) { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 350), () => _set((x) => x.copyWith(query: v.trim()))); }),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in const [(DiscoverKind.all, 'Todas'), (DiscoverKind.friends, 'Amigos'), (DiscoverKind.public, 'Públicas'), (DiscoverKind.club, 'Clubes')])
            PlobbyFilterChip(label: k.$2, selected: f.kind == k.$1, onTap: () => _set((x) => x.copyWith(kind: k.$1))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Dropdown<String?>(hint: 'Zona', value: f.zone,
              items: [const DropdownMenuItem(value: null, child: Text('Todas las zonas')), for (final z in {...zones, if (f.zone != null) f.zone!}) DropdownMenuItem(value: z, child: Text(z, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => _set((x) => x.copyWith(zone: v)))),
          const SizedBox(width: 8),
          Expanded(child: _Dropdown<LeagueStatus?>(hint: 'Estado', value: f.status,
              items: const [DropdownMenuItem(value: null, child: Text('Todos')), DropdownMenuItem(value: LeagueStatus.open, child: Text('Inscripción')), DropdownMenuItem(value: LeagueStatus.running, child: Text('En curso'))],
              onChanged: (v) => _set((x) => x.copyWith(status: v)))),
        ]),
        const SizedBox(height: 18),
        res.when(
          loading: () => const Column(children: [LoadingBlock(height: 260, radius: AppRadius.md), SizedBox(height: 14), LoadingBlock(height: 260, radius: AppRadius.md)]),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(discoverProvider)),
          data: (l) => l.isEmpty
              ? EmptyStateCard(icon: Icons.search_off, title: 'No hay ligas con esos filtros', text: 'Prueba con otra zona o nivel, o crea tu propia liga.',
                  primary: f.isDefault ? null : 'Borrar filtros', onPrimary: () { _q.clear(); ref.read(discoverFiltersProvider.notifier).state = const DiscoverFilters(); },
                  secondary: 'Crear liga', onSecondary: () => context.push('/leagues/new'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${l.length} ${l.length == 1 ? 'liga' : 'ligas'}'.toUpperCase(), style: PlobbyText.eb),
                  const SizedBox(height: 10),
                  for (final d in l) DiscoverLeagueCard(league: d, busy: _busy.contains(d.id),
                      onJoin: () => joinLeague(context, ref, d, (b) => setState(() => b ? _busy.add(d.id) : _busy.remove(d.id)))),
                ]),
        ),
      ])),
    );
  }
}

/// Desplegable de filtro (`select.inp` compacto: 40 px, radio 12, borde 1 px).
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.hint, required this.value, required this.items, required this.onChanged});
  final String hint; final T value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: value, isExpanded: true, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w400, fontSize: 14),
        hint: Text(hint, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w400, fontSize: 14)),
        icon: const PlobbyIcon(PlobbyIcons.down, size: 16, color: AppColors.textMuted),
        decoration: plobbyInputDecoration(radius: 12, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        items: items, onChanged: onChanged,
      );
}
