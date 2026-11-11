import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/match_repository.dart';
import '../data/mock_match_repository.dart';
import '../domain/match_models.dart';

final matchRepositoryProvider = Provider<MatchRepository>((ref) => MockMatchRepository());
final myLeaguesProvider = FutureProvider<List<LeagueOption>>((ref) => ref.read(matchRepositoryProvider).myLeagues());
final clubsProvider = FutureProvider<List<String>>((ref) => ref.read(matchRepositoryProvider).clubs());
final friendOptionsProvider = FutureProvider<List<PlayerOption>>((ref) => ref.read(matchRepositoryProvider).friends());
final leagueMembersProvider = FutureProvider.family<List<PlayerOption>, String>((ref, id) => ref.read(matchRepositoryProvider).leagueMembers(id));
