import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../matches/application/lifecycle_providers.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/stats_calculator.dart';
import '../domain/recap_data.dart';
import 'recap_service.dart';

final recapServiceProvider = Provider<RecapService>((ref) => RecapService());

/// Datos del recap a partir del MISMO partido (matchProvider): ninguna estructura duplicada. Lanza `RecapException`
/// si el partido no está confirmado por los dos capitanes o el usuario no participa.
final recapDataProvider = Provider.family<AsyncValue<RecapData>, String>((ref, id) {
  final m = ref.watch(matchProvider(id)), uid = ref.watch(currentUserIdProvider);
  final prof = ref.watch(profileProvider('me')).valueOrNull;
  return m.whenData((match) {
    if (match == null) throw RecapException(RecapRefusal.noResult);
    RecapUserStats? st;
    if (prof != null) {
      final calc = ref.read(calculatorProvider);
      final s = calc.stats(prof.matches, StatsPeriod.all);
      st = RecapUserStats(played: s.played, winRate: s.played > 0 ? s.winRate : null, streak: calc.streak(prof.matches).current);
    }
    return RecapData.fromMatch(match, uid, stats: st);
  });
});
