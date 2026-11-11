import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
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
      appBar: AppBar(actions: [IconButton(tooltip: 'Unirme con código', onPressed: () => showJoinByCodeSheet(context), icon: const Icon(Icons.qr_code_2_rounded))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        const Text('Descubrir ligas', style: TextStyle(fontFamily: 'Unbounded', fontSize: 28, fontWeight: FontWeight.w700)),
        const Text('Encuentra tu próxima competición.', style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 16),
        TextField(controller: _q, textInputAction: TextInputAction.search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, club o zona'),
            onChanged: (v) { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 350), () => _set((x) => x.copyWith(query: v.trim()))); }),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in const [(DiscoverKind.all, 'Todas'), (DiscoverKind.friends, 'Amigos'), (DiscoverKind.public, 'Públicas'), (DiscoverKind.club, 'Clubes')])
            ChoiceChip(label: Text(k.$2), selected: f.kind == k.$1, onSelected: (_) => _set((x) => x.copyWith(kind: k.$1))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String?>(value: f.zone, isExpanded: true, decoration: const InputDecoration(labelText: 'Zona', isDense: true),
              items: [const DropdownMenuItem(value: null, child: Text('Todas')), for (final z in {...zones, if (f.zone != null) f.zone!}) DropdownMenuItem(value: z, child: Text(z, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => _set((x) => x.copyWith(zone: v)))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<LeagueStatus?>(value: f.status, isExpanded: true, decoration: const InputDecoration(labelText: 'Estado', isDense: true),
              items: const [DropdownMenuItem(value: null, child: Text('Todos')), DropdownMenuItem(value: LeagueStatus.open, child: Text('Inscripción')), DropdownMenuItem(value: LeagueStatus.running, child: Text('En curso'))],
              onChanged: (v) => _set((x) => x.copyWith(status: v)))),
        ]),
        const SizedBox(height: 18),
        res.when(
          loading: () => const Column(children: [LoadingBlock(height: 88), SizedBox(height: 12), LoadingBlock(height: 88), SizedBox(height: 12), LoadingBlock(height: 88)]),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(discoverProvider)),
          data: (l) => l.isEmpty
              ? EmptyStateCard(icon: Icons.search_off, title: 'No hay ligas con esos filtros', text: 'Prueba con otra zona o nivel, o crea tu propia liga.',
                  primary: f.isDefault ? null : 'Borrar filtros', onPrimary: () { _q.clear(); ref.read(discoverFiltersProvider.notifier).state = const DiscoverFilters(); },
                  secondary: 'Crear liga', onSecondary: () => context.push('/leagues/new'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${l.length} ${l.length == 1 ? 'liga' : 'ligas'}'.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  for (final d in l) DiscoverLeagueCard(league: d, busy: _busy.contains(d.id),
                      onJoin: () => joinLeague(context, ref, d, (b) => setState(() => b ? _busy.add(d.id) : _busy.remove(d.id)))),
                ]),
        ),
      ]),
    );
  }
}
