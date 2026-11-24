import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/motion/app_motion.dart';
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
///
/// Movimiento (inspirado en los selectores de plan paginados): se cambia de sección tocando la pestaña o deslizando
/// en horizontal; la píldora y el color del fondo ([page] → `AmbientBackground` de la barra inferior) siguen al dedo
/// fotograma a fotograma, y la página que se aleja se encoge y se desplaza algo más despacio (profundidad).
class CompetitionsScreen extends ConsumerStatefulWidget {
  const CompetitionsScreen({super.key});
  /// Posición en vivo del PageView (0 = Ligas, 1 = Torneos). Solo presentación.
  static final page = ValueNotifier<double>(0);
  @override
  ConsumerState<CompetitionsScreen> createState() => _CompetitionsScreenState();
}

class _CompetitionsScreenState extends ConsumerState<CompetitionsScreen> {
  late final PageController _pc = PageController(initialPage: ref.read(competitionsTabProvider));
  bool _fromSwipe = false;

  @override
  void initState() {
    super.initState();
    CompetitionsScreen.page.value = _pc.initialPage.toDouble();
    _pc.addListener(_onScroll);
  }

  void _onScroll() { if (_pc.positions.length == 1) CompetitionsScreen.page.value = _pc.page ?? CompetitionsScreen.page.value; }

  void _goTo(int i) {
    if (!_pc.hasClients) return;
    if ((_pc.page ?? -1) == i) return;
    if (AppAnimations.reduceMotion(context)) { _pc.jumpToPage(i); } else { _pc.animateToPage(i, duration: AppAnimations.page, curve: AppAnimations.pageCurve); }
  }

  @override
  void dispose() { _pc.removeListener(_onScroll); _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // La pestaña también puede cambiarse desde fuera (p. ej. un aviso de torneo): se anima hasta ella.
    // Si el cambio viene del propio deslizamiento (onPageChanged), no se anima: interrumpiría el gesto.
    ref.listen<int>(competitionsTabProvider, (_, i) { if (_fromSwipe) { _fromSwipe = false; } else { _goTo(i); } });
    return Scaffold(
      backgroundColor: Colors.transparent,   // fondo vivo de la barra inferior
      body: SafeArea(bottom: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 26, 20, 0), child: Semantics(header: true, child: Text('Competiciones', style: PlobbyText.t1))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: ScrollLinkedTabs(labels: const ['Ligas', 'Torneos'], controller: _pc, onTap: (i) {
              AppHaptics.light();
              if (ref.read(competitionsTabProvider) == i) { _goTo(i); } else { ref.read(competitionsTabProvider.notifier).state = i; }
            })),
        // Cada sección conserva su desplazamiento y sus datos al cambiar de una a otra (keep-alive).
        Expanded(child: PageView(controller: _pc, onPageChanged: (i) { if (ref.read(competitionsTabProvider) != i) { _fromSwipe = true; ref.read(competitionsTabProvider.notifier).state = i; } }, children: [
          _DepthPage(controller: _pc, index: 0, child: const LeaguesScreen(embedded: true)),
          _DepthPage(controller: _pc, index: 1, child: const TournamentsTab()),
        ])),
      ])),
    );
  }
}

/// Página con profundidad: al alejarse se encoge hasta un 94 % hacia el borde por el que sale. Solo transformaciones
/// (sin opacidad ni capas extra), así el deslizamiento se mantiene a 60 FPS aunque la lista sea larga.
class _DepthPage extends StatefulWidget {
  const _DepthPage({required this.controller, required this.index, required this.child});
  final PageController controller;
  final int index;
  final Widget child;
  @override
  State<_DepthPage> createState() => _DepthPageState();
}

class _DepthPageState extends State<_DepthPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final reduce = AppAnimations.reduceMotion(context);
    // Misma estructura de widgets siempre (Transform neutro si no hay movimiento): cambiarla reconstruiría la sección.
    return AnimatedBuilder(animation: widget.controller, child: widget.child, builder: (context, child) {
      final c = widget.controller;
      final p = c.hasClients && c.positions.length == 1 && c.position.haveDimensions ? (c.page ?? c.initialPage.toDouble()) : c.initialPage.toDouble();
      final d = reduce ? 0.0 : (p - widget.index).clamp(-1.0, 1.0);
      // Solo escala, hacia el lado contrario a la otra página: quedan separadas por un hueco y nunca se solapan.
      return Transform.scale(scale: 1 - .06 * d.abs(), alignment: d > 0 ? Alignment.centerLeft : Alignment.centerRight, child: child);
    });
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
      child: ListView(padding: EdgeInsets.fromLTRB(20, 18, 20, AppInsets.tabBarClearance(context)), children: [
        Row(children: [
          Expanded(child: Text('Organiza cuadros y fases de grupos.', style: PlobbyText.sub)),
          PlobbyButton(label: 'Crear torneo', icon: PlobbyIcons.plus, kind: PlobbyButtonKind.small, onPressed: () => context.push('/tournaments/new')),
        ]),
        const SizedBox(height: 22),
        Semantics(header: true, child: Text('Mis torneos', style: PlobbyText.t2)),
        const SizedBox(height: 12),
        mine.when(
          loading: () => const Column(children: [LoadingBlock(height: 250, radius: AppRadius.md), SizedBox(height: 14), LoadingBlock(height: 250, radius: AppRadius.md)]),
          error: (e, __) => ErrorStateCard(error: e, onRetry: () => ref.invalidate(myTournamentsProvider)),
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
