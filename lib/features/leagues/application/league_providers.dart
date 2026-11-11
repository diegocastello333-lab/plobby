import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../data/league_repository.dart';
import '../data/mock_league_repository.dart';
import '../domain/league_models.dart';

/// Con Supabase se sustituye en `SupabaseBootstrap.overrides` por [SupabaseLeagueRepository].
final leagueRepositoryProvider = Provider<LeagueRepository>((ref) => MockLeagueRepository());

final leagueListProvider = FutureProvider<List<LeagueSummary>>((ref) => ref.watch(leagueRepositoryProvider).myLeagues());

/// Filtros de «Descubrir ligas» (el texto se busca en servidor; tipo/estado/zona se filtran en cliente).
enum DiscoverKind { all, friends, public, club }
class DiscoverFilters {
  const DiscoverFilters({this.query = '', this.kind = DiscoverKind.all, this.status, this.zone});
  final String query; final DiscoverKind kind; final LeagueStatus? status; final String? zone;
  bool get isDefault => query.isEmpty && kind == DiscoverKind.all && status == null && zone == null;
  DiscoverFilters copyWith({String? query, DiscoverKind? kind, Object? status = _k, Object? zone = _k}) => DiscoverFilters(query: query ?? this.query, kind: kind ?? this.kind,
      status: identical(status, _k) ? this.status : status as LeagueStatus?, zone: identical(zone, _k) ? this.zone : zone as String?);
}
const _k = Object();
final discoverFiltersProvider = StateProvider<DiscoverFilters>((ref) => const DiscoverFilters());
final _discoverRawProvider = FutureProvider.family<List<DiscoverLeague>, String>((ref, q) => ref.watch(leagueRepositoryProvider).discover(q));

/// Filtro puro (testeable) de los resultados de «Descubrir».
List<DiscoverLeague> applyDiscoverFilters(List<DiscoverLeague> all, DiscoverFilters f) => [
      for (final d in all)
        if ((f.kind != DiscoverKind.friends || d.friendsIn > 0) && (f.kind != DiscoverKind.public || d.visibility == LeagueVisibility.public)
            && (f.kind != DiscoverKind.club || d.visibility == LeagueVisibility.club) && (f.status == null || d.status == f.status)
            && (f.zone == null || d.location == f.zone))
          d,
    ];

final discoverProvider = Provider<AsyncValue<List<DiscoverLeague>>>((ref) {
  final f = ref.watch(discoverFiltersProvider);
  return ref.watch(_discoverRawProvider(f.query.trim())).whenData((l) => applyDiscoverFilters(l, f));
});
/// Para la pantalla «Ligas» (teasers sin filtros).
final discoverTeasersProvider = FutureProvider<List<DiscoverLeague>>((ref) => ref.watch(leagueRepositoryProvider).discover(''));

final leagueDetailProvider = FutureProvider.autoDispose.family<LeagueDetail, String>((ref, id) { ref.watch(leagueLiveProvider(id)); return ref.watch(leagueRepositoryProvider).league(id); });
final standingsProvider = FutureProvider.autoDispose.family<List<StandingRow>, String>((ref, id) { ref.watch(leagueLiveProvider(id)); return ref.watch(leagueRepositoryProvider).standings(id); });
final leagueMatchesProvider = FutureProvider.autoDispose.family<List<LifecycleMatch>, String>((ref, id) { ref.watch(leagueLiveProvider(id)); return ref.watch(leagueRepositoryProvider).matches(id); });
final joinRequestsProvider = FutureProvider.autoDispose.family<List<JoinRequest>, String>((ref, id) { ref.watch(leagueLiveProvider(id)); return ref.watch(leagueRepositoryProvider).joinRequests(id); });
final inviteCodeProvider = FutureProvider.autoDispose.family<String?, String>((ref, id) => ref.watch(leagueRepositoryProvider).inviteCode(id));

/// Realtime: cada evento de la liga incrementa el contador y los providers de arriba se recargan.
final leagueLiveProvider = StreamProvider.autoDispose.family<int, String>((ref, id) async* {
  var n = 0;
  yield n;
  await for (final _ in ref.watch(leagueRepositoryProvider).watch(id)) { yield ++n; }
});

/// Escrituras de liga + invalidación de lo afectado. Los errores llegan como [LeagueException] (mensaje en español).
class LeagueActions {
  LeagueActions(this._ref);
  final Ref _ref;
  LeagueRepository get _repo => _ref.read(leagueRepositoryProvider);
  void _refresh([String? id]) {
    _ref.invalidate(leagueListProvider); _ref.invalidate(discoverTeasersProvider); _ref.invalidate(_discoverRawProvider);
    if (id != null) { _ref.invalidate(leagueDetailProvider(id)); _ref.invalidate(standingsProvider(id)); _ref.invalidate(joinRequestsProvider(id)); _ref.invalidate(leagueMatchesProvider(id)); }
  }
  Future<({String id, String code})> create(LeagueDraft d) async { final r = await _repo.create(d); _refresh(); return r; }
  Future<JoinOutcome> join(String id, {String? code, String? message}) async { final r = await _repo.join(id, code: code, message: message); _refresh(id); return r; }
  Future<String> joinByCode(String code) async { final id = await _repo.joinByCode(code); _refresh(id); return id; }
  Future<void> respond(String leagueId, String requestId, bool accept) async { await _repo.respondRequest(requestId, accept: accept); _refresh(leagueId); }
  Future<void> leave(String id) async { await _repo.leave(id); _refresh(id); }
  Future<void> removeMember(String id, String userId) async { await _repo.removeMember(id, userId); _refresh(id); }
  Future<int> invite(String id, List<String> userIds) => _repo.invite(id, userIds);
  Future<void> update(String id, Map<String, Object?> patch) async { await _repo.update(id, patch); _refresh(id); }
}
final leagueActionsProvider = Provider((ref) => LeagueActions(ref));

// ── Asistente «Crear liga» (5 pasos) ──────────────────────────────────────────
class CreateLeagueState {
  const CreateLeagueState({required this.draft, this.step = 1, this.errors = const {}, this.busy = false, this.failure});
  final LeagueDraft draft; final int step; final Map<String, String> errors; final bool busy; final String? failure;
  CreateLeagueState copyWith({LeagueDraft? draft, int? step, Map<String, String>? errors, bool? busy, Object? failure = _k}) => CreateLeagueState(
      draft: draft ?? this.draft, step: step ?? this.step, errors: errors ?? this.errors, busy: busy ?? this.busy,
      failure: identical(failure, _k) ? this.failure : failure as String?);
}

class CreateLeagueController extends AutoDisposeNotifier<CreateLeagueState> {
  @override
  CreateLeagueState build() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).add(const Duration(days: 7));
    return CreateLeagueState(draft: LeagueDraft(startsOn: start, endsOn: start.add(const Duration(days: 90))));
  }
  void edit(LeagueDraft Function(LeagueDraft) f) => state = state.copyWith(draft: f(state.draft), errors: const {}, failure: null);
  void back() { if (state.step > 1) state = state.copyWith(step: state.step - 1, errors: const {}); }
  void goTo(int step) => state = state.copyWith(step: step, errors: const {});
  /// Valida y avanza; en el paso 5 crea la liga. Devuelve el resultado al crear, null en los demás pasos o si falla.
  Future<({String id, String code})?> next() async {
    final e = validateLeagueStep(state.draft, state.step);
    if (e.isNotEmpty) { state = state.copyWith(errors: e); return null; }
    if (state.step < 5) { state = state.copyWith(step: state.step + 1); return null; }
    state = state.copyWith(busy: true, failure: null);
    try {
      final r = await ref.read(leagueActionsProvider).create(state.draft);
      state = state.copyWith(busy: false);
      return r;
    } on LeagueException catch (x) { state = state.copyWith(busy: false, failure: x.message); return null; }
  }
}
final createLeagueProvider = AutoDisposeNotifierProvider<CreateLeagueController, CreateLeagueState>(CreateLeagueController.new);
