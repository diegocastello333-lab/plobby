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
