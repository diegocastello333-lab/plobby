import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../leagues/presentation/leagues_screen.dart';
import '../application/tournament_providers.dart';
import '../domain/tournament_models.dart';
import 'tournament_widgets.dart';

/// Pestaña «Competiciones» (antes «Ligas»): selector Ligas | Torneos. Ligas es la pantalla de siempre (mismos datos,
/// acciones y rutas `/leagues/...`); Torneos es el sistema nuevo e independiente.
class CompetitionsScreen extends ConsumerWidget {
  const CompetitionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(competitionsTabProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 26, 20, 0), child: Semantics(header: true, child: const Text('Competiciones', style: PlobbyText.t1))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SlidingTabs(labels: const ['Ligas', 'Torneos'], index: tab, onChanged: (i) => ref.read(competitionsTabProvider.notifier).state = i)),
        // IndexedStack: cada sección conserva su desplazamiento y sus datos al cambiar de una a otra.
        Expanded(child: IndexedStack(index: tab, children: const [LeaguesScreen(embedded: true), TournamentsTab()])),
      ])),
    );
  }
}

/// Sección «Torneos»: mis torneos (participo u organizo) y «Crear torneo».
class TournamentsTab extends ConsumerWidget {
  const TournamentsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myTournamentsProvider);
    return RefreshIndicator(
      color: AppColors.text,
      onRefresh: () async { ref.invalidate(myTournamentsProvider); await ref.read(myTournamentsProvider.future).catchError((_) => <TournamentSummary>[]); },
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 130), children: [
        Row(children: [
          const Expanded(child: Text('Organiza cuadros y fases de grupos.', style: PlobbyText.sub)),
          PlobbyButton(label: 'Crear torneo', icon: PlobbyIcons.plus, kind: PlobbyButtonKind.small, onPressed: () => context.push('/tournaments/new')),
        ]),
        const SizedBox(height: 22),
        Semantics(header: true, child: const Text('Mis torneos', style: PlobbyText.t2)),
        const SizedBox(height: 12),
        mine.when(
          loading: () => const Column(children: [LoadingBlock(height: 250, radius: AppRadius.md), SizedBox(height: 14), LoadingBlock(height: 250, radius: AppRadius.md)]),
          error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(myTournamentsProvider)),
          data: (l) => l.isEmpty
              ? EmptyStateCard(icon: Icons.account_tree_outlined, title: 'Aún no tienes torneos',
                  text: 'Crea uno con tus amigos: Plobby genera el cuadro, los grupos y los partidos por ti.',
                  primary: 'Crear torneo', onPrimary: () => context.push('/tournaments/new'))
              : Column(children: [
                  for (var i = 0; i < l.length; i++)
                    Padding(padding: const EdgeInsets.only(bottom: 14), child: AppearOnce(animationKey: 'tn:${l[i].id}', index: i,
                        child: Pressable(child: TournamentCard(t: l[i], onTap: () => context.push('/tournaments/${l[i].id}'))))),
                ]),
        ),
      ]),
    );
  }
}
