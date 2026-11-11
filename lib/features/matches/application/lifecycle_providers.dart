
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/lifecycle_repository.dart';
import '../data/mock_lifecycle_repository.dart';
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';


/// Entrada de un set desde los campos de texto (puede estar incompleta).
class SetScoreInput { SetScoreInput(this.a, this.b); int? a, b; SetScore toScore() => SetScore(a ?? 0, b ?? 0); bool get filled => a != null && b != null; }

/// En main.dart sustituye por SupabaseLifecycleRepository (supabase/integration/supabase_lifecycle_repository.dart.txt).
final lifecycleRepositoryProvider = Provider<LifecycleRepository>((ref) => MockLifecycleRepository(me: 'me'));
final currentUserIdProvider = Provider<String>((ref) => 'me');   // = supabase.auth.currentUser!.id

/// UNA fuente para Home y perfil: lo que se edite/elimine/empiece se refleja en ambos sin duplicar registros.
final upcomingMatchesProvider = StreamProvider<List<LifecycleMatch>>((ref) => ref.watch(lifecycleRepositoryProvider).watchUpcoming());
final matchProvider = StreamProvider.family<LifecycleMatch?, String>((ref, id) => ref.watch(lifecycleRepositoryProvider).watchMatch(id));

/// Reloj de servidor sincronizado una vez al abrir (y cada 5 min): corrige el desfase del reloj del dispositivo.
final serverClockProvider = FutureProvider<ServerClock>((ref) async {
  final repo = ref.watch(lifecycleRepositoryProvider);
  final before = DateTime.now(); final s = await repo.serverTime(); final after = DateTime.now();
  return ServerClock.fromServerSample(s, before, after);
});

/// Tick de 1 s para repintar el cronómetro. El valor mostrado es siempre `serverNow - startedAt`.
final tickProvider = StreamProvider<int>((ref) => Stream.periodic(const Duration(seconds: 1), (i) => i));

class LifecycleActions {
  LifecycleActions(this.repo);
  final LifecycleRepository repo;
  Future<StartResult> start(String id) => repo.start(id);
  Future<void> finish(String id) => repo.finish(id);
  Future<int> submit(String id, List<SetScoreInput> s) => repo.submitResult(id, [for (final x in s) x.toScore()]);
  Future<MatchStatus> respond(String id, int v, {required bool accept, String? reason}) => repo.respond(id, v, accept: accept, reason: reason);
  Future<void> update(String id, EditMatch e) => repo.update(id, e);
  Future<void> cancel(String id) => repo.cancel(id);
}
final lifecycleActionsProvider = Provider((ref) => LifecycleActions(ref.watch(lifecycleRepositoryProvider)));
