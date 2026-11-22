import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models.dart';
import 'profile_repository.dart';

/// Perfil real (Supabase). Lecturas con RLS + RPC `get_player_history` (migración 20261120_leagues_profile.sql);
/// escrituras solo de los campos editables (`grant update (…)` por columnas) y pareja vía `set_habitual_partner`.
/// `playerId == 'me'` se resuelve al usuario de la sesión, igual que en el mock.
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._db);
  final SupabaseClient _db;
  String get _uid => _db.auth.currentUser!.id;
  String _resolve(String id) => id == 'me' ? _uid : id;

  static const _levels = {
    'beginner': ('Iniciación', 2.0), 'intermediate': ('Intermedio', 3.0),
    'upper_intermediate': ('Intermedio alto', 4.0), 'advanced': ('Avanzado', 5.0),
  };

  @override
  Future<ProfileData> load(String playerId) async {
    final uid = _resolve(playerId);
    // `get_profile` (migración 20261128a): el servidor decide qué columnas ve cada uno. Propio perfil y amigos: todo;
    // desconocidos: nombre, usuario, foto y nivel. Incluye la pareja habitual, así que ya no hace falta otra consulta
    // (y se evita la relación ambigua de `profiles` consigo misma del 16 nov 2026).
    final results = await Future.wait<dynamic>([
      _db.rpc('get_profile', params: {'p_user': uid}),
      _db.from('player_ratings').select('elo').eq('user_id', uid).maybeSingle(),
      _db.from('league_members').select('league_id').eq('user_id', uid),
      _db.rpc('get_player_history', params: {'p_user': uid}),
    ]);
    final raw = results[0];
    if (raw is! Map) throw const PostgrestException(message: 'Perfil no encontrado', code: 'PGRST116');
    final p = raw.cast<String, dynamic>();
    final full = p['full'] != false;
    final elo = ((results[1] as Map<String, dynamic>?)?['elo'] as num?)?.toInt() ?? 1200;
    final leagues = (results[2] as List).length;
    final history = (results[3] as List? ?? const []).cast<Map<String, dynamic>>();

    PartnerLink? partner;
    final q = p['partner'];
    if (q is Map) {
      partner = PartnerLink(
        userId: q['id'] as String, name: (q['display_name'] ?? '') as String, username: (q['username'] ?? '') as String, avatarUrl: q['avatar_url'] as String?,
        // Pareja confirmada cuando los dos se han elegido mutuamente.
        status: q['mutual'] == true ? PartnerStatus.accepted : PartnerStatus.pending,
      );
    }
    final level = _levels[p['self_declared_level']];
    final club = (p['habitual_club'] as String?)?.trim();
    final profile = PlayerProfile(
      id: playerId, fullName: (p['display_name'] ?? '') as String, username: (p['username'] ?? '') as String, location: (p['city'] ?? '') as String,
      avatarUrl: p['avatar_url'] as String?, avatarId: p['avatar_id'] as String?, bannerId: p['banner_id'] as String?, bio: (p['bio'] ?? '') as String,
      declaredLevel: level?.$1 ?? 'Sin declarar', declaredLevelValue: level?.$2 ?? 0,
      side: p['court_side'] == 'left' ? PlaySide.left : PlaySide.right,
      dominantHand: p['dominant_hand'] == 'left' ? 'Izquierda' : 'Derecha',
      club: club == null || club.isEmpty ? null : ClubRef(id: club, name: club, city: ''),
      partner: partner, leaguesPlayed: leagues, limited: !full,
    );
    return ProfileData(profile: profile, matches: history.map((h) => matchFromHistory(h, uid, profile.side)).whereType<MatchResult>().toList(), currentElo: elo);
  }

  @override
  Future<void> setSide(PlaySide side) =>
      _db.from('profiles').update({'court_side': side == PlaySide.left ? 'left' : 'right', 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', _uid);

  @override
  Future<void> setClub(ClubRef? club) =>
      _db.from('profiles').update({'habitual_club': club?.name, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', _uid);

  @override
  Future<PartnerLink?> requestPartner(String userId) async {
    await _db.rpc('set_habitual_partner', params: {'p_partner': userId});
    return null; // el perfil se recarga y calcula el estado (pendiente / aceptada)
  }

  @override
  Future<void> removePartner() => _db.rpc('set_habitual_partner', params: {'p_partner': null});

  @override
  Future<void> setBio(String bio) =>
      _db.from('profiles').update({'bio': bio.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', _uid);

  @override
  Future<void> setBanner(String bannerId) => _db.rpc('set_home_banner', params: {'p_banner_id': bannerId, 'p_banner_url': null});

  @override
  Future<List<ClubRef>> searchClubs(String q) async {
    final rows = await _db.from('clubs').select('id, name, city').ilike('name', '%${q.trim()}%').order('name').limit(20);
    return [for (final r in rows) ClubRef(id: r['id'] as String, name: r['name'] as String, city: (r['city'] ?? '') as String)];
  }
}

/// Convierte una fila de `get_player_history` en [MatchResult] orientado al jugador [uid].
/// Pura (sin red) para poder probarla. Devuelve null si el partido aún no tiene sets.
MatchResult? matchFromHistory(Map<String, dynamic> h, String uid, PlaySide side) {
  final team = (h['team'] as num).toInt();
  // Sets en el orden del servidor [equipo1, equipo2] → (mis juegos, juegos rivales).
  final sets = <(int, int)>[
    for (final s in (h['sets'] as List? ?? const []).cast<List>())
      team == 1 ? ((s[0] as num).toInt(), (s[1] as num).toInt()) : ((s[1] as num).toInt(), (s[0] as num).toInt()),
  ];
  if (sets.isEmpty) return null;
  final mine = sets.where((s) => s.$1 > s.$2).length;
  final players = (h['players'] as List? ?? const []).cast<Map<String, dynamic>>();
  PlayerRef ref(Map<String, dynamic> p) => PlayerRef(p['id'] as String, (p['name'] ?? '') as String, p['avatar_url'] as String?);
  final partner = players.where((p) => p['team'] == team && p['id'] != uid).map(ref).firstOrNull ?? const PlayerRef('', '—');
  return MatchResult(
    id: h['match_id'] as String, playedAt: DateTime.parse(h['played_at'] as String).toLocal(), won: mine > sets.length - mine,
    partner: partner, opponents: players.where((p) => p['team'] != team).map(ref).toList(), sets: sets,
    venue: (h['venue'] ?? '') as String, eloDelta: ((h['elo_delta'] ?? 0) as num).toInt(), side: side,
    isLeague: h['is_league'] == true, confirmed: h['confirmed'] == true,
  );
}
