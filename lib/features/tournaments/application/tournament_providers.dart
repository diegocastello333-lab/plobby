import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_tournament_repository.dart';
import '../data/tournament_repository.dart';
import '../domain/tournament_models.dart';

/// Repositorio de Torneos (Supabase con sesión: lo sustituye `SupabaseBootstrap.overrides`).
final tournamentRepositoryProvider = Provider<TournamentRepository>((ref) => MockTournamentRepository());

/// Avisos de cambios (Realtime) compartidos: un solo listener por sesión para lista y detalle.
final _tournamentChangesProvider = StreamProvider<String>((ref) => ref.watch(tournamentRepositoryProvider).changes());

class MyTournamentsNotifier extends AsyncNotifier<List<TournamentSummary>> {
  Timer? _debounce;
  @override
  Future<List<TournamentSummary>> build() {
    // Cualquier cambio en un torneo mío (aquí o en otro móvil) recarga la lista; varios avisos seguidos → una consulta.
    ref.listen(_tournamentChangesProvider, (_, __) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), ref.invalidateSelf);
    });
    ref.onDispose(() => _debounce?.cancel());
    return ref.read(tournamentRepositoryProvider).myTournaments();
  }
}
final myTournamentsProvider = AsyncNotifierProvider<MyTournamentsNotifier, List<TournamentSummary>>(MyTournamentsNotifier.new);

class TournamentDetailNotifier extends AutoDisposeFamilyAsyncNotifier<TournamentDetail, String> {
  Timer? _debounce;
  @override
  Future<TournamentDetail> build(String id) {
    ref.listen(_tournamentChangesProvider, (_, next) {
      final changed = next.valueOrNull;
      if (changed != id && changed != '*') return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _reload);
    });
    ref.onDispose(() => _debounce?.cancel());
    return ref.read(tournamentRepositoryProvider).detail(id);
  }

  /// Recarga sin pasar por «cargando» (los datos anteriores siguen en pantalla mientras llega lo nuevo).
  Future<void> _reload() async {
    try {
      final d = await ref.read(tournamentRepositoryProvider).detail(arg);
      state = AsyncData(d);
    } catch (e, s) {
      if (state.hasValue) return;   // se conserva lo que había; el siguiente aviso lo reintenta
      state = AsyncError(e, s);
    }
  }

  TournamentRepository get _repo => ref.read(tournamentRepositoryProvider);

  /// Registrar/corregir: si otro organizador lo cambió antes (`result_conflict`), se recarga y se relanza el error
  /// para que el usuario vea el resultado actual.
  Future<void> record(TMatch m, List<(int, int)> sets) async {
    try {
      await _repo.recordResult(m.id, sets, m.version);
    } on TournamentException catch (e) {
      if (e.code == 'result_conflict') await _reload();
      rethrow;
    }
    await _reload();
    ref.invalidate(myTournamentsProvider);
  }

  Future<void> clear(TMatch m) async {
    try {
      await _repo.clearResult(m.id, m.version);
    } on TournamentException catch (e) {
      if (e.code == 'result_conflict') await _reload();
      rethrow;
    }
    await _reload();
    ref.invalidate(myTournamentsProvider);
  }

  Future<void> setLive(TMatch m, bool live) async { await _repo.setLive(m.id, live); await _reload(); }

  Future<void> updateInfo(Map<String, dynamic> patch) async { await _repo.updateInfo(arg, patch); await _reload(); ref.invalidate(myTournamentsProvider); }

  Future<void> replaceTeams(List<(TPlayer, TPlayer)> teams) async { await _repo.replaceTeams(arg, teams); await _reload(); ref.invalidate(myTournamentsProvider); }
}
final tournamentDetailProvider = AsyncNotifierProvider.autoDispose.family<TournamentDetailNotifier, TournamentDetail, String>(TournamentDetailNotifier.new);

/// Pestaña elegida dentro de Competiciones (0 = Ligas, 1 = Torneos). Se conserva al volver.
final competitionsTabProvider = StateProvider<int>((ref) => 0);
