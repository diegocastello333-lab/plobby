import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/state/cache_for.dart';
import '../data/club_repository.dart';
import '../data/mock_club_repository.dart';
import '../domain/club_models.dart';

/// Sin Supabase (demo/tests) se usa el catálogo de demostración; SupabaseBootstrap lo sustituye por el real.
final clubRepositoryProvider = Provider<ClubRepository>((ref) => MockClubRepository());
final clubPageProvider = FutureProvider.autoDispose.family<ClubPage?, String>((ref, id) { ref.cacheFor(const Duration(minutes: 2)); return ref.watch(clubRepositoryProvider).page(id); });   // timing
final pendingClubsProvider = FutureProvider.autoDispose<List<PendingClub>>((ref) => ref.watch(clubRepositoryProvider).pending());
final isClubAdminProvider = Provider<bool>((ref) => ref.watch(clubRepositoryProvider).isAdmin);

/// Los ids del catálogo son UUID; el texto antiguo escrito a mano no lo es (no enlaza a ninguna página).
bool isCatalogClubId(String? id) => id != null && RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(id);
