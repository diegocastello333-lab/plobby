import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/rating_models.dart';
import 'rating_repository.dart';

/// Lee la vista `v_my_rating_detail` y `rating_history` (RLS: solo filas propias). Sin escrituras.
class SupabaseRatingRepository implements RatingRepository {
  SupabaseRatingRepository(this._db);
  final SupabaseClient _db;
  @override
  Future<RatingDetail> myRating({int historyLimit = 500}) async {
    // Las tres lecturas son independientes: en paralelo (1 viaje de red en vez de 3 seguidos).
    final res = await Future.wait<dynamic>([
      _db.from('v_my_rating_detail').select().single(),
      _db.from('rating_config').select().eq('id', 1).single(),
      _db.from('v_my_rating_changes').select().order('created_at', ascending: false).limit(historyLimit),
    ]);
    final d = res[0] as Map<String, dynamic>, cfg = res[1] as Map<String, dynamic>, rows = res[2];
    return RatingDetail(
      name: d['display_name'], username: d['username'], avatarUrl: d['avatar_url'],
      elo: d['elo'], bestElo: d['best_elo'], delta30: d['delta_30d'],
      confirmedMatches: d['confirmed_matches'], wins: d['wins'], losses: d['losses'],
      scale: RatingScale(cfg['min_rating'], cfg['max_rating'], [
        for (final t in (cfg['tiers'] as List)) RatingTier(t['name'], t['from']),
      ]),
      history: [
        for (final r in rows as List)
          RatingChange(matchId: r['match_id'], at: DateTime.parse(r['created_at']), won: r['won'], score: r['score'], opponents: r['opponents'], before: r['rating_before'], delta: r['delta']),
      ],
    );
  }
}
