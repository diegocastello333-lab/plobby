import '../../profile/domain/models.dart' show MatchResult;

/// Hora por defecto de un partido nuevo. Antes era «ahora + 2 h» (a las 00:26 salía 02:26).
///
/// - Si el jugador suele jugar a una hora ([usualHour], la más repetida en sus partidos), la próxima vez que llegue esa
///   hora con al menos 1 h de margen.
/// - Si no, la siguiente hora en punto dentro de la franja razonable 8:00–23:00 (con 1 h de margen); fuera de ella, a
///   las 19:00 del día siguiente (o de hoy, si aún es de madrugada).
DateTime defaultMatchTime(DateTime now, {int? usualHour}) {
  final soonest = now.add(const Duration(hours: 1));   // timing: margen mínimo para organizarse
  if (usualHour != null && usualHour >= 8 && usualHour <= 23) {
    var t = DateTime(now.year, now.month, now.day, usualHour);
    if (t.isBefore(soonest)) t = DateTime(now.year, now.month, now.day + 1, usualHour);
    return t;
  }
  final t = DateTime(soonest.year, soonest.month, soonest.day, soonest.hour + (soonest.minute > 0 || soonest.second > 0 ? 1 : 0));
  if (t.hour < 8) return DateTime(t.year, t.month, t.day, 19);   // de madrugada → a las 19:00 de ese día
  return t;
}

/// Hora más repetida en los partidos del jugador (desempate: la más reciente). Null si no hay al menos 2 partidos.
int? usualPlayHour(List<MatchResult> matches) {
  if (matches.length < 2) return null;
  final count = <int, int>{};
  for (final m in matches) { count[m.playedAt.hour] = (count[m.playedAt.hour] ?? 0) + 1; }
  final best = count.entries.reduce((a, b) => b.value > a.value ? b : a);
  return best.value >= 2 ? best.key : null;
}

/// Jugadores sugeridos para un partido: primero la pareja habitual, luego los compañeros y rivales más frecuentes de
/// sus partidos (sin repetir y sin incluirse a sí mismo). Solo ids que estén en [allowed] (amigos o miembros de la liga).
List<String> suggestedPlayers({String? habitualPartnerId, required List<MatchResult> matches, required Set<String> allowed, String? meId, int max = 6}) {
  final score = <String, int>{};
  for (final m in matches) {
    score[m.partner.id] = (score[m.partner.id] ?? 0) + 2;   // compañero pesa más que rival
    for (final o in m.opponents) { score[o.id] = (score[o.id] ?? 0) + 1; }
  }
  final ordered = [
    if (habitualPartnerId != null) habitualPartnerId,
    ...(score.keys.toList()..sort((a, b) => score[b]!.compareTo(score[a]!))),
  ];
  final out = <String>[];
  for (final id in ordered) {
    if (id == meId || id.isEmpty || !allowed.contains(id) || out.contains(id)) continue;
    out.add(id);
    if (out.length == max) break;
  }
  return out;
}
