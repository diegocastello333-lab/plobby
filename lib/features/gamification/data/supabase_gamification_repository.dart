import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/gamification_models.dart';
import 'gamification_repository.dart';

/// Implementación real: RPC `head_to_head`, `friends_ranking`, `wrapped_periods`, `wrapped`, `my_achievements`,
/// `mark_achievements_seen` y la tabla `notification_prefs` (RLS: solo la propia fila).
class SupabaseGamificationRepository implements GamificationRepository {
  SupabaseGamificationRepository(this._db);
  final SupabaseClient _db;
  @override
  String get meId => _db.auth.currentUser?.id ?? '';

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      final code = RegExp(r'(not_friends|not_authenticated|invalid_player|invalid_period)').firstMatch(e.message)?.group(1) ?? 'server';
      throw GamificationException(code);
    } on SocketException {
      throw GamificationException('network');
    } on TimeoutException {
      throw GamificationException('network');
    }
  }

  Map<String, dynamic> _map(Object? v) => (v as Map).cast<String, dynamic>();

  @override
  Future<H2HData> headToHead(String otherId) => _guard(() async => H2HData.fromJson(_map(await _db.rpc('head_to_head', params: {'p_other': otherId}))));

  @override
  Future<RankingData> ranking(RankPeriod period, {int offset = 0}) => _guard(() async =>
      RankingData.fromJson(_map(await _db.rpc('friends_ranking', params: {'p_period': period.name, 'p_offset': offset})), meId));

  @override
  Future<List<WrappedPeriod>> wrappedPeriods() => _guard(() async {
        final j = _map(await _db.rpc('wrapped_periods'));
        List<WrappedPeriod> parse(String key, WrappedKind k) => [for (final p in (j[key] as List? ?? const []).cast<Map<String, dynamic>>())
          WrappedPeriod(k, DateTime.parse(p['start'] as String), (p['played'] as num).toInt(), p['in_progress'] == true)];
        return [...parse('years', WrappedKind.year), ...parse('months', WrappedKind.month)];
      });

  @override
  Future<WrappedData> wrapped(WrappedKind kind, DateTime start) => _guard(() async => WrappedData.fromJson(_map(await _db.rpc('wrapped',
      params: {'p_kind': kind.name, 'p_start': '${start.year}-${start.month.toString().padLeft(2, '0')}-01'}))));

  @override
  Future<AchievementsData> achievements() => _guard(() async => AchievementsData.fromJson(_map(await _db.rpc('my_achievements'))));

  @override
  Future<void> markAchievementsSeen() => _guard(() async => _db.rpc('mark_achievements_seen'));

  @override
  Future<NotificationPrefs> prefs() => _guard(() async {
        final r = await _db.from('notification_prefs').select('ranking, achievements, levels, wrapped').eq('user_id', meId).maybeSingle();
        return r == null ? const NotificationPrefs() : NotificationPrefs(ranking: r['ranking'] as bool, achievements: r['achievements'] as bool,
            levels: r['levels'] as bool, wrapped: r['wrapped'] as bool);
      });

  @override
  Future<void> savePrefs(NotificationPrefs p) => _guard(() => _db.from('notification_prefs').upsert({'user_id': meId, 'ranking': p.ranking,
      'achievements': p.achievements, 'levels': p.levels, 'wrapped': p.wrapped, 'updated_at': DateTime.now().toUtc().toIso8601String()}));
}
