/// Tipo de partido. En backend: `matches.match_type` ('league' | 'friendly'); `league_id` solo en liga.
enum MatchType { league, friendly }

class LeagueOption {
  const LeagueOption(this.id, this.name);
  final String id, name;
}

class PlayerOption {
  const PlayerOption(this.id, this.name);
  final String id, name;
}

/// Un set: games de la pareja 1 y de la pareja 2.
class SetScore {
  const SetScore(this.a, this.b);
  final int a, b;
}

class MatchDraft {
  const MatchDraft({required this.type, this.leagueId, this.partnerId, this.rival1Id, this.rival2Id, required this.when, required this.club, this.sets = const []});
  final MatchType type;
  final String? leagueId, partnerId, rival1Id, rival2Id;
  final DateTime when;
  final String club;
  final List<SetScore> sets; // vacío = partido programado (aún no jugado)
}

/// Validación pura del formulario (sin acceso a datos). Devuelve un mensaje de error o null.
String? validateDraft(MatchDraft d, {required bool resultRequired, DateTime? now}) {
  if (d.type == MatchType.league && d.leagueId == null) return 'Elige la liga del partido.';
  if (d.type == MatchType.friendly && d.leagueId != null) return 'Un amistoso no puede tener liga.';
  final ids = [d.partnerId, d.rival1Id, d.rival2Id];
  if (ids.any((x) => x == null)) return 'Elige a tu compañero y a los dos rivales.';
  if (ids.toSet().length < 3) return 'Los tres jugadores deben ser distintos.';
  if (d.sets.isEmpty && resultRequired) return 'Introduce al menos dos sets válidos, por ejemplo 6-3, 7-5 o 7-6.';
  if (d.sets.isNotEmpty && (d.sets.length < 2 || d.sets.any((s) => !isValidSet(s.a, s.b)))) return 'Introduce al menos dos sets válidos, por ejemplo 6-3, 7-5 o 7-6.';
  if (d.sets.isEmpty && d.when.isBefore(now ?? DateTime.now())) return 'Elige una fecha futura o añade el resultado del partido.';
  return null;
}

/// Mismas reglas de set que el flujo de ligas existente (6-0..6-4, 7-5, 7-6).
bool isValidSet(int a, int b) {
  final hi = a > b ? a : b, lo = a > b ? b : a;
  return (hi == 6 && lo <= 4) || (hi == 7 && (lo == 5 || lo == 6));
}

/// Error de `create_match` traducido a un mensaje para el usuario. El repositorio Supabase lo construye a partir
/// del mensaje del servidor (la función valida jugadores, liga/amistad y sets y lanza `raise exception`).
class MatchCreateException implements Exception {
  const MatchCreateException(this.code);
  /// `players`, `not_friend`, `not_league_member`, `league_required`, `invalid_sets`, `auth`, `network`, `unknown`.
  final String code;
  String get message => switch (code) {
        'players' => 'Elige a tu compañero y a los dos rivales (tres jugadores distintos).',
        'not_friend' => 'En un amistoso solo puedes jugar con amigos que hayan aceptado tu solicitud.',
        'not_league_member' => 'Todos los jugadores deben ser miembros de la liga.',
        'league_required' => 'Elige la liga del partido.',
        'invalid_sets' => 'Revisa el resultado: al menos dos sets válidos, por ejemplo 6-3, 7-5 o 7-6.',
        'auth' => 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
        'network' => 'No hay conexión. Comprueba tu red e inténtalo de nuevo.',
        _ => 'No se pudo crear el partido. Inténtalo de nuevo.',
      };
  @override
  String toString() => 'MatchCreateException($code)';

  /// Clasifica el texto de `raise exception` de la RPC `create_match`.
  static MatchCreateException fromServerMessage(String m) {
    final t = m.toLowerCase();
    if (t.contains('three different players')) return const MatchCreateException('players');
    if (t.contains('is not your friend')) return const MatchCreateException('not_friend');
    if (t.contains('not a member of the league')) return const MatchCreateException('not_league_member');
    if (t.contains('league required') || t.contains('cannot have a league')) return const MatchCreateException('league_required');
    if (t.contains('invalid set') || t.contains('two sets')) return const MatchCreateException('invalid_sets');
    if (t.contains('not authenticated') || t.contains('jwt')) return const MatchCreateException('auth');
    return const MatchCreateException('unknown');
  }
}
