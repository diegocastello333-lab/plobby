import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/gamification_repository.dart';
import '../data/mock_gamification_repository.dart';
import '../domain/gamification_models.dart';

final gamificationRepositoryProvider = Provider<GamificationRepository>((ref) => MockGamificationRepository());

/// Head to Head con un amigo (se reutiliza mientras la pantalla esté abierta).
final headToHeadProvider = FutureProvider.autoDispose.family<H2HData, String>((ref, other) => ref.watch(gamificationRepositoryProvider).headToHead(other));

/// Ranking por (periodo, desplazamiento): cambiar de pestaña no vuelve a pedir lo ya cargado.
final rankingProvider = FutureProvider.autoDispose.family<RankingData, (RankPeriod, int)>((ref, k) {
  ref.keepAlive();   // se libera al cerrar la sesión (el ProviderScope se recrea)
  return ref.watch(gamificationRepositoryProvider).ranking(k.$1, offset: k.$2);
});

final wrappedPeriodsProvider = FutureProvider.autoDispose<List<WrappedPeriod>>((ref) => ref.watch(gamificationRepositoryProvider).wrappedPeriods());
final wrappedProvider = FutureProvider.autoDispose.family<WrappedData, (WrappedKind, DateTime)>((ref, k) => ref.watch(gamificationRepositoryProvider).wrapped(k.$1, k.$2));
final achievementsProvider = FutureProvider<AchievementsData>((ref) => ref.watch(gamificationRepositoryProvider).achievements());
final notificationPrefsProvider = FutureProvider<NotificationPrefs>((ref) => ref.watch(gamificationRepositoryProvider).prefs());

/// Tras un partido confirmado, un logro o el cierre de una temporada: refresca todo lo que depende de las estadísticas.
void refreshGamification(WidgetRef ref) {
  ref.invalidate(achievementsProvider);
  ref.invalidate(rankingProvider);
  ref.invalidate(wrappedPeriodsProvider);
}
