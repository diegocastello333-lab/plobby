import '../domain/models.dart';
import 'profile_repository.dart';

/// DATOS MOCK. Sustituir por [SupabaseProfileRepository] (ver abajo) sin tocar la UI.
class MockProfileRepository implements ProfileRepository {
  MockProfileRepository({DateTime? now}) : _now = now ?? DateTime.now();
  final DateTime _now;
  late PlayerProfile _me = const PlayerProfile(
    id: 'me', fullName: 'Diego Castello', username: 'diego.c', location: 'Madrid, España', verified: true,
    bio: 'Jugando al pádel desde 2019. Drive firme, bandeja en construcción.', declaredLevel: 'Intermedio alto',
    declaredLevelValue: 4.0, side: PlaySide.right, dominantHand: 'Derecha', leaguesPlayed: 3,
    club: ClubRef(id: 'c1', name: 'Club La Moraleja', city: 'Alcobendas, Madrid'),
    partner: PartnerLink(userId: 'marcos', name: 'Marcos Ruiz', username: 'marcos.r', status: PartnerStatus.accepted),
  );
  static const _clubs = [
    ClubRef(id: 'c1', name: 'Club La Moraleja', city: 'Alcobendas, Madrid'),
    ClubRef(id: 'c2', name: 'Padel Chamberí', city: 'Chamberí, Madrid'),
    ClubRef(id: 'c3', name: 'Club Alameda', city: 'Retiro, Madrid'),
  ];

  @override
  Future<ProfileData> load(String playerId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    const pattern = '111110110101111111101011010011011001110111_0101';
    final ps = const [PlayerRef('marcos', 'Marcos R.'), PlayerRef('alvaro', 'Álvaro P.'), PlayerRef('lucia', 'Lucía M.')];
    const ops = [PlayerRef('carlos', 'Carlos M.'), PlayerRef('laura', 'Laura G.'), PlayerRef('pablo', 'Pablo S.'), PlayerRef('sofia', 'Sofía G.')];
    final bits = pattern.replaceAll('_', '');
    var day = 1;
    final ms = <MatchResult>[];
    for (var i = 0; i < bits.length; i++) {
      final won = bits[i] == '1';
      ms.add(MatchResult(
        id: 'm$i', playedAt: _now.subtract(Duration(days: day)), won: won, partner: ps[i % 3],
        opponents: [ops[i % 4], ops[(i + 1) % 4]], sets: won ? [(6, 2 + i % 3), (6, 4)] : [(3, 6), (4 + i % 2, 6)],
        venue: _clubs[i % 3].name, eloDelta: won ? 8 + i % 8 : -(6 + i % 6),
        side: i % 4 == 0 ? PlaySide.left : PlaySide.right, isLeague: i % 3 == 0, confirmed: true,
      ));
      day += i < 8 ? 3 : 7;
    }
    // Partido pendiente: NO debe afectar a la racha ni al ELO.
    ms.insert(0, MatchResult(id: 'pending1', playedAt: _now, won: true, partner: ps[0], opponents: ops.take(2).toList(),
        sets: const [(6, 3), (7, 5)], venue: 'Club La Moraleja', eloDelta: 12, side: PlaySide.right, confirmed: false));
    return ProfileData(profile: _me, matches: ms, currentElo: 1482);
  }

  @override
  Future<void> setSide(PlaySide side) async => _me = _me.copyWith(side: side);
  @override
  Future<void> setClub(ClubRef? club) async => _me = _me.copyWith(club: club, clearClub: club == null);
  @override
  Future<PartnerLink?> requestPartner(String userId) async {
    final link = PartnerLink(userId: userId, name: userId, username: userId, status: PartnerStatus.pending);
    _me = _me.copyWith(partner: link);
    return link;
  }
  @override
  Future<void> removePartner() async => _me = _me.copyWith(clearPartner: true);
  @override
  Future<List<ClubRef>> searchClubs(String q) async =>
      _clubs.where((c) => c.name.toLowerCase().contains(q.toLowerCase())).toList();
}

/// INTEGRACIÓN SUPABASE (pendiente, no implementada aquí):
///  - profiles(id, full_name, username, avatar_url, bio, declared_level, side, dominant_hand, club_id)
///  - matches + match_players + match_sets, con `confirmed_at` (null = pendiente) y `elo_delta`
///  - partner_links(requester_id, partner_id, status 'pending'|'accepted') — el partner acepta por RLS/RPC
///  - vista/RPC `profile_stats(player_id, period)` para evitar traer todos los partidos en producción
/// No se ha creado ni modificado ninguna tabla: comprobar el esquema existente antes de añadir nada.
