import 'dart:async';
import '../domain/match_lifecycle.dart';
import '../domain/match_models.dart';
import 'lifecycle_repository.dart';

/// MOCK en memoria que aplica las MISMAS reglas que las funciones SQL (para tests y desarrollo sin backend).
/// No es seguridad: la seguridad real está en RLS + RPC (supabase/migrations/20261115_match_lifecycle.sql).
class MockLifecycleRepository implements LifecycleRepository {
  MockLifecycleRepository({required this.me, List<LifecycleMatch> seed = const [], DateTime Function()? now})
      : _now = now ?? DateTime.now, _m = {}, _ctl = StreamController<void>.broadcast(), appliedRating = [] { for (final m in seed) { _m[m.id] = m; } }
  MockLifecycleRepository._view(this.me, this._now, this._m, this._ctl, this.appliedRating);
  /// Otra «sesión» (otro usuario) sobre el MISMO almacén, como varios móviles contra un servidor.
  MockLifecycleRepository asUser(String uid) => MockLifecycleRepository._view(uid, _now, _m, _ctl, appliedRating);
  final String me;                                   // usuario que «llama» (auth.uid())
  final DateTime Function() _now;
  final Map<String, LifecycleMatch> _m;
  final StreamController<void> _ctl;
  /// Efectos de cierre (ELO/estadísticas) — solo cuentan partidos CONFIRMADOS, una vez cada uno.
  final List<String> appliedRating;
  int ratingApplications(String id) => appliedRating.where((x) => x == id).length;

  LifecycleMatch _get(String id) => _m[id] ?? (throw LifecycleException('not_found'));
  void _put(LifecycleMatch m) { _m[m.id] = m; _ctl.add(null); }
  LifecycleMatch _ev(LifecycleMatch m, String kind, String text) => m.copyWith(events: [MatchEvent(actorId: me, kind: kind, text: text, at: _now()), ...m.events]);
  MatchPerms _p(LifecycleMatch m) => MatchPerms(m, me);

  @override
  Future<List<LifecycleMatch>> confirmedMatches() async {
    final l = _m.values.where((m) => m.status == MatchStatus.confirmed && m.player(me) != null).toList();
    l.sort((a, b) => (b.endedAt ?? b.scheduledAt).compareTo(a.endedAt ?? a.scheduledAt));
    return l;
  }
  @override
  Future<DateTime> serverTime() async => _now();
  @override
  Stream<List<LifecycleMatch>> watchUpcoming() async* {
    List<LifecycleMatch> cur() => (_m.values.where((m) => m.status.isUpcoming && m.player(me) != null).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)));
    yield cur(); await for (final _ in _ctl.stream) { yield cur(); }
  }
  @override
  Stream<LifecycleMatch?> watchMatch(String id) async* { yield _m[id]; await for (final _ in _ctl.stream) { yield _m[id]; } }

  /// Atómico: solo el primero que ve `scheduled` gana; el resto recibe la hora oficial existente.
  @override
  Future<StartResult> start(String id) async {
    final m = _get(id);
    if (m.player(me) == null) throw LifecycleException('not_a_participant');
    if (m.status != MatchStatus.scheduled) return StartResult(started: false, startedAt: m.startedAt!, startedBy: m.startedBy!);
    final t = _now();
    _put(_ev(m.copyWith(status: MatchStatus.live, startedAt: t, startedBy: me), 'start', 'inició el partido'));
    return StartResult(started: true, startedAt: t, startedBy: me);
  }
  @override
  Future<void> finish(String id) async {
    final m = _get(id);
    if (!_p(m).canFinish) throw LifecycleException(m.status == MatchStatus.live ? 'not_a_participant' : 'match_not_live');
    final t = _now();
    _put(_ev(m.copyWith(status: MatchStatus.pendingResult, endedAt: t, durationSeconds: t.difference(m.startedAt!).inSeconds), 'finish', 'finalizó el partido'));
  }
  @override
  Future<int> submitResult(String id, List<SetScore> sets) async {
    final m = _get(id);
    if (!_p(m).canSubmitResult) throw LifecycleException('invalid_state_${m.status.db}');
    final c = validateSets(sets); if (!c.valid) throw LifecycleException('invalid_sets');
    final v = m.resultVersion + 1;
    // Nueva versión ⇒ las aceptaciones de versiones anteriores dejan de contar (se conservan como historial).
    _put(_ev(m.copyWith(status: MatchStatus.pendingConfirmation, resultVersion: v, sets: c.sets, clearRejection: true), v == 1 ? 'result_submitted' : 'result_edited', 'propuso el resultado (versión $v)'));
    return v;
  }
  @override
  Future<MatchStatus> respond(String id, int version, {required bool accept, String? reason}) async {
    final m = _get(id), p = m.player(me);
    if (p == null) throw LifecycleException('not_a_participant');
    if (!p.isCaptain) throw LifecycleException('only_captains_can_confirm');
    if (m.status != MatchStatus.pendingConfirmation) throw LifecycleException('invalid_state_${m.status.db}');
    if (version != m.resultVersion) throw LifecycleException('stale_version');
    if (!accept) {
      _put(_ev(m.copyWith(status: MatchStatus.disputed, rejectionReason: reason?.trim().isEmpty == true ? null : reason?.trim(), acceptances: [...m.acceptances, Acceptance(userId: me, team: p.team, version: version, accepted: false, reason: reason)]), 'result_rejected', 'rechazó el resultado'));
      return MatchStatus.disputed;
    }
    final already = m.acceptances.any((a) => a.userId == me && a.version == version);
    var n = already ? m : _ev(m.copyWith(acceptances: [...m.acceptances, Acceptance(userId: me, team: p.team, version: version, accepted: true)]), 'result_accepted', 'aceptó el resultado (versión $version)');
    if (n.bothCaptainsAccepted) { n = _finalize(n); _put(n); return MatchStatus.confirmed; }
    _put(n);
    return MatchStatus.pendingConfirmation;
  }
  /// Idempotente: si ya está confirmado no se vuelve a aplicar el ELO.
  LifecycleMatch _finalize(LifecycleMatch m) {
    if (m.status == MatchStatus.confirmed) return m;
    appliedRating.add(m.id);
    final w = m.winnerTeam!;
    return _ev(m.copyWith(status: MatchStatus.confirmed, eloDelta: {for (final p in m.players) p.id: p.team == w ? 12 : -12}), 'confirmed', 'resultado confirmado por los dos capitanes');
  }
  @override
  Future<void> update(String id, EditMatch e) async {
    final m = _get(id);
    if (!_p(m).canEdit) throw LifecycleException(m.createdBy != me ? 'only_creator_can_edit' : 'match_not_editable');
    if (!e.scheduledAt.isAfter(_now())) throw LifecycleException('date_must_be_future');
    if (e.players.length != 4 || e.players.map((p) => p.id).toSet().length != 4) throw LifecycleException('players_must_be_distinct');
    for (final t in [1, 2]) { if (e.players.where((p) => p.team == t && p.isCaptain).length != 1) throw LifecycleException('one_captain_per_team'); }
    if (!e.players.any((p) => p.id == me)) throw LifecycleException('creator_must_play');
    final changedPlayers = e.players.any((p) => m.player(p.id) == null);
    if (leagueLocked(m, _now()) && changedPlayers) throw LifecycleException('league_rule_players_locked');
    _put(_ev(m.copyWith(scheduledAt: e.scheduledAt, club: e.club, court: e.court, players: e.players), 'edited', 'editó el partido'));
  }
  @override
  Future<void> cancel(String id) async {
    final m = _get(id);
    if (!_p(m).canDelete) throw LifecycleException(m.createdBy != me ? 'only_creator_can_delete' : 'match_not_deletable');
    if (leagueLocked(m, _now())) throw LifecycleException('league_rule_delete_locked');
    _put(_ev(m.copyWith(status: MatchStatus.cancelled), 'cancelled', 'canceló el partido'));
  }
}
