import '../../gamification/domain/gamification_models.dart';
import '../../rating/domain/rating_models.dart';
import 'match_lifecycle.dart';
import 'match_models.dart';

/// Una línea del desglose de XP («Partido jugado +100»).
class XpLine {
  const XpLine(this.label, this.xp);
  final String label;
  final int xp;
}

/// Lo que se cuenta en la pantalla post-partido, calculado SOLO con datos del servidor (partido confirmado,
/// `rating_history`, `xp_events` y logros). No inventa nada: si un dato falta, ese bloque no se muestra.
class PostMatchSummary {
  const PostMatchSummary({
    required this.matchId, required this.won, required this.sets, required this.myTeam,
    this.eloBefore, this.eloDelta, this.scale,
    this.xpLines = const [], this.xpBefore, this.xpAfter,
    this.achievements = const [], this.partner, this.rivals = const [], this.club = '', this.playedAt,
  });

  final String matchId;
  final bool won;
  final List<SetScore> sets;
  final int myTeam;
  final int? eloBefore, eloDelta;
  final RatingScale? scale;
  final List<XpLine> xpLines;
  final int? xpBefore, xpAfter;
  final List<AchievementItem> achievements;
  final String? partner;
  final List<String> rivals;
  final String club;
  final DateTime? playedAt;

  int? get eloAfter => eloBefore == null || eloDelta == null ? null : eloBefore! + eloDelta!;
  bool get hasElo => eloAfter != null;
  bool get hasXp => xpBefore != null && xpAfter != null && xpAfter! > xpBefore!;
  int get xpGained => hasXp ? xpAfter! - xpBefore! : 0;
  int get levelBefore => levelForXp(xpBefore ?? 0);
  int get levelAfter => levelForXp(xpAfter ?? 0);
  bool get leveledUp => hasXp && levelAfter > levelBefore;
  String? get tierBefore => scale == null || eloBefore == null ? null : scale!.tierOf(eloBefore!).name;
  String? get tierAfter => scale == null || eloAfter == null ? null : scale!.tierOf(eloAfter!).name;
  bool get tierUp => tierBefore != null && tierAfter != null && tierAfter != tierBefore && eloDelta! > 0;

  /// Juegos desde mi lado (mi pareja primero).
  (int, int) mine(SetScore s) => myTeam == 1 ? (s.a, s.b) : (s.b, s.a);
  String get score => sets.map((s) { final (a, b) = mine(s); return '$a-$b'; }).join('  ');

  /// Mensaje del titular. La derrota se cuenta con respeto: sin «has perdido», sin rojo como única señal.
  String get headline => won ? 'Victoria' : 'Buen partido';
  String get subline {
    if (won) return sets.every((s) { final (a, b) = mine(s); return a > b; }) ? 'Sin ceder un set.' : 'Remontada y partido cerrado.';
    final close = sets.any((s) { final (a, b) = mine(s); return a > b || (b - a) <= 2; });
    return close ? 'Se decidió por detalles. A por la próxima.' : 'Cada partido suma experiencia. A por la próxima.';
  }

  /// Construye el resumen desde los datos ya cargados. [ratings] y [ach] pueden faltar (error de red): entonces se
  /// muestran solo los bloques que tengan datos.
  static PostMatchSummary build({required LifecycleMatch m, required String uid, RatingDetail? ratings, AchievementsData? ach}) {
    final me = m.player(uid);
    final team = me?.team ?? 1;
    final won = m.winnerTeam == team;
    // ELO: la fila de rating_history de ESTE partido (antes y cambio exactos); si no está, el cambio del partido
    final hist = ratings?.history.where((h) => h.matchId == m.id).firstOrNull;
    final delta = hist?.delta ?? m.eloDelta[uid];
    final before = hist?.before ?? (delta != null && me != null && me.elo > 0 && (ratings?.history.isEmpty ?? true) ? me.elo - delta : null);

    // XP: eventos de este partido (match/win, mismo origen) y logros otorgados en la MISMA transacción (misma hora)
    final lines = <XpLine>[];
    int? xpBefore, xpAfter;
    final achievements = <AchievementItem>[];
    if (ach != null) {
      final own = ach.history.where((e) => e.source == m.id && (e.type == 'match' || e.type == 'win')).toList();
      if (own.isNotEmpty) {
        final at = own.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
        final sameTx = ach.history.where((e) => e.type == 'achievement' && e.at.isAtSameMomentAs(at)).toList();
        for (final e in own) { lines.add(XpLine(e.type == 'win' ? 'Partido ganado' : 'Partido jugado', e.xp)); }
        for (final e in sameTx) {
          final a = ach.items.where((i) => i.id == e.source).firstOrNull;
          if (a != null) achievements.add(a);
          lines.add(XpLine(a == null ? 'Logro' : 'Logro: ${a.title}', e.xp));
        }
        final later = ach.history.where((e) => e.at.isAfter(at)).fold<int>(0, (s, e) => s + e.xp);
        xpAfter = ach.xp - later;
        xpBefore = xpAfter - lines.fold<int>(0, (s, l) => s + l.xp);
      }
    }
    String first(MatchPlayer p) => p.name.trim().split(RegExp(r'\s+')).first;
    final partner = m.team(team).where((p) => p.id != uid).map(first).firstOrNull;
    return PostMatchSummary(
      matchId: m.id, won: won, sets: m.sets, myTeam: team, eloBefore: before, eloDelta: delta, scale: ratings?.scale,
      xpLines: lines, xpBefore: xpBefore, xpAfter: xpAfter, achievements: achievements,
      partner: partner, rivals: m.team(team == 1 ? 2 : 1).map(first).toList(), club: m.club, playedAt: m.endedAt ?? m.scheduledAt,
    );
  }
}
