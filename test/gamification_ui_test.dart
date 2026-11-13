import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/gamification/application/gamification_providers.dart';
import 'package:plobby/features/gamification/data/mock_gamification_repository.dart';
import 'package:plobby/features/gamification/domain/gamification_models.dart';
import 'package:plobby/features/gamification/presentation/wrapped_screens.dart';

Future<void> _settle(WidgetTester t, [int n = 8]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 250)); } }

/// Repositorio de demo con un logro sin ver (para la celebración) y registro de llamadas.
class _Repo extends MockGamificationRepository {
  _Repo({this.unseen = false}) : super(now: () => DateTime(2026, 11, 13, 20));
  final bool unseen;
  var seenCalls = 0;
  NotificationPrefs? saved;
  @override
  Future<AchievementsData> achievements() async {
    final a = await super.achievements();
    if (!unseen || seenCalls > 0) return a;
    return AchievementsData(xp: a.xp, level: a.level, levelFloor: a.levelFloor, levelCeiling: a.levelCeiling,
        items: [for (final i in a.items) i.id == 'matches_1' ? AchievementItem(id: i.id, category: i.category, title: i.title, description: i.description,
            icon: i.icon, goal: i.goal, xp: i.xp, unlockedAt: i.unlockedAt, progress: i.progress, seen: false) : i]);
  }
  @override
  Future<void> markAchievementsSeen() async => seenCalls++;
  @override
  Future<void> savePrefs(NotificationPrefs p) async => saved = p;
}

Future<(GoRouter, _Repo)> _app(WidgetTester t, {double width = 390, bool unseen = false}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = _Repo(unseen: unseen);
  late GoRouter r;
  await t.pumpWidget(ProviderScope(overrides: [gamificationRepositoryProvider.overrideWithValue(repo)], child: Consumer(builder: (_, ref, __) {
    r = ref.watch(routerProvider);
    return MaterialApp.router(theme: buildPlobbyTheme(), routerConfig: r);
  })));
  await _settle(t);
  return (r, repo);
}

void main() {
  testWidgets('Head to Head: perfiles enfrentados, estadísticas, enfrentamientos directos y compartir', (t) async {
    final (r, repo) = await _app(t);
    r.push('/h2h/laura');
    await _settle(t);
    final h = repo.engine.headToHead('me', 'laura');
    expect(find.text('Estadísticas generales'), findsOneWidget);
    expect(find.text('${h.myWins}–${h.theirWins}'), findsOneWidget);
    expect(find.text(h.verdict.title), findsOneWidget);
    await t.scrollUntilVisible(find.text('Enfrentamientos directos'), 300);
    expect(find.text('Enfrentamientos directos'), findsOneWidget);
    await t.tap(find.byTooltip('Compartir comparativa'));
    await _settle(t, 4);
    expect(find.text('Story 9:16'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Ranking: podio, mi fila, cambio de periodo y de clasificación, temporadas anteriores', (t) async {
    final (r, _) = await _app(t);
    r.push('/ranking');
    await _settle(t);
    expect(find.text('Esta semana'), findsOneWidget);
    await t.tap(find.text('Histórico'));
    await _settle(t);
    expect(find.text('Desde siempre'), findsOneWidget);
    expect(find.textContaining('(tú)'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Podio:')), findsOneWidget);
    await t.tap(find.text('% victorias'));
    await _settle(t);
    await t.scrollUntilVisible(find.textContaining('Mejor % de victorias primero'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('Mejor % de victorias primero'), findsOneWidget);
    await t.tap(find.text('Mes'));
    await _settle(t);
    await t.tap(find.byTooltip('Temporada anterior'));
    await _settle(t);
    expect(find.text('Octubre 2026'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Wrapped: lista de periodos y la historia se recorre tocando hasta el resumen', (t) async {
    final (r, repo) = await _app(t);
    r.push('/wrapped');
    await _settle(t);
    expect(find.text('Tu 2026'), findsOneWidget);
    r.push('/wrapped/year/2026-01');
    await _settle(t);
    expect(find.byType(WrappedStoryScreen), findsOneWidget);
    final w = repo.engine.wrapped('me', WrappedKind.year, DateTime(2026));
    final n = wrappedSlides(w).length;
    for (var i = 0; i < n; i++) {
      await t.tapAt(const Offset(330, 500));
      await _settle(t, 3);
    }
    expect(find.text('Compartir mi Wrapped'), findsOneWidget);
    expect(find.text('${w.played}'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('Logros: nivel, próximos, catálogo; preferencias de avisos se guardan', (t) async {
    final (r, repo) = await _app(t);
    r.push('/achievements');
    await _settle(t);
    expect(find.textContaining('NIVEL'), findsWidgets);
    expect(find.text('Próximos logros'), findsOneWidget);
    await t.tap(find.byTooltip('Avisos de competición'));
    await _settle(t, 4);
    expect(find.text('Ranking'), findsOneWidget);
    await t.tap(find.byType(Switch).first);
    await _settle(t, 2);
    expect(repo.saved?.ranking, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('un logro nuevo se celebra una vez y queda marcado como visto', (t) async {
    final (_, repo) = await _app(t, unseen: true);
    await _settle(t, 6);
    expect(find.text('¡Logro desbloqueado!'), findsOneWidget);
    expect(find.text('Primer partido'), findsWidgets);
    await t.tapAt(const Offset(195, 60));   // cerrar la hoja
    await _settle(t, 6);
    expect(repo.seenCalls, 1);
    expect(find.text('¡Logro desbloqueado!'), findsNothing);
  });

  testWidgets('Perfil propio: sección Progreso con accesos; perfil de un amigo: Head to Head', (t) async {
    final (r, _) = await _app(t);
    r.go('/profile');
    await _settle(t);
    await t.scrollUntilVisible(find.text('Plobby Wrapped'), 400, scrollable: find.byType(Scrollable).first);
    expect(find.text('Head to Head'), findsOneWidget);
    expect(find.text('Ranking de amigos'), findsOneWidget);
    r.push('/player/laura');
    await _settle(t);
    await t.scrollUntilVisible(find.textContaining('Compárate con'), 400, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('Compárate con'), findsOneWidget);
  });

  for (final w in [320.0, 390.0]) {
    testWidgets('pantallas de gamificación sin desbordes a $w px', (t) async {
      final (r, _) = await _app(t, width: w);
      for (final route in ['/h2h/laura', '/ranking', '/wrapped', '/achievements', '/wrapped/month/2026-10', '/friends']) {
        r.push(route);
        await _settle(t);
        expect(t.takeException(), isNull, reason: route);
        r.pop();
        await _settle(t, 3);
      }
    });
  }
}
