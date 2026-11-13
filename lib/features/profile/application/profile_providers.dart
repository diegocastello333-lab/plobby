import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_profile_repository.dart';
import '../data/profile_repository.dart';
import '../domain/models.dart';
import '../domain/stats_calculator.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => MockProfileRepository());
final clockProvider = Provider<DateTime>((ref) => DateTime.now());
final calculatorProvider = Provider<StatsCalculator>((ref) => StatsCalculator(now: ref.watch(clockProvider)));

final statsPeriodProvider = StateProvider<StatsPeriod>((ref) => StatsPeriod.all);
final eloRangeProvider = StateProvider<EloRange>((ref) => EloRange.d90);

class ProfileNotifier extends FamilyAsyncNotifier<ProfileData, String> {
  @override
  Future<ProfileData> build(String playerId) => ref.read(profileRepositoryProvider).load(playerId);

  Future<void> setSide(PlaySide s) async { await ref.read(profileRepositoryProvider).setSide(s); ref.invalidateSelf(); }
  Future<void> setClub(ClubRef? c) async { await ref.read(profileRepositoryProvider).setClub(c); ref.invalidateSelf(); }
  Future<void> requestPartner(String id) async { await ref.read(profileRepositoryProvider).requestPartner(id); ref.invalidateSelf(); }
  Future<void> removePartner() async { await ref.read(profileRepositoryProvider).removePartner(); ref.invalidateSelf(); }
}

final profileProvider = AsyncNotifierProvider.family<ProfileNotifier, ProfileData, String>(ProfileNotifier.new);

/// Estadísticas derivadas (solo partidos confirmados) y reactivas a los filtros.
class ProfileView {
  ProfileView(this.data, this.calc, this.period, this.eloRange);
  final ProfileData data;
  final StatsCalculator calc;
  final StatsPeriod period;
  final EloRange eloRange;
  Stats get stats => calc.stats(data.matches, period);
  Streak get streak => calc.streak(data.matches);
  List<MatchResult> get confirmed => calc.confirmed(data.matches);
  List<MatchResult> get pending => data.matches.where((m) => !m.confirmed).toList();
  List<EloPoint> get series => calc.eloSeries(data.matches, data.currentElo, eloRange);
  int get eloMonth => calc.eloChange(data.matches, data.currentElo, EloRange.d30);
  int get eloPeriod => calc.eloChange(data.matches, data.currentElo, eloRange);
}

final profileViewProvider = Provider.family<AsyncValue<ProfileView>, String>((ref, id) {
  final calc = ref.watch(calculatorProvider);
  final p = ref.watch(statsPeriodProvider), r = ref.watch(eloRangeProvider);
  return ref.watch(profileProvider(id)).whenData((d) => ProfileView(d, calc, p, r));
});
