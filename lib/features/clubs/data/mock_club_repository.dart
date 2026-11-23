import '../domain/club_models.dart';
import 'club_repository.dart';

/// Catálogo de demostración (subconjunto real del CSV de Madrid) con la misma lógica básica que `search_clubs`:
/// exacto 1,0 · prefijo 0,85 · todas las palabras 0,75 · alguna palabra 0,4. Solo para el modo demo y los tests.
class MockClubRepository implements ClubRepository {
  MockClubRepository({this.isAdmin = false});
  @override
  final bool isAdmin;

  static const _seed = <(String, String, String, String?, ClubType, List<String>)>[
    ('c-raqueta', 'BamVolea Ciudad de la Raqueta', 'Madrid', 'Mirasierra', ClubType.privateClub, ['Ciudad de la Raqueta']),
    ('c-campo', 'Real Club de Campo Villa de Madrid', 'Madrid', 'Moncloa-Aravaca', ClubType.socialClub, ['Club de Campo', 'CCVM']),
    ('c-mirasierra', 'Club Mirasierra', 'Madrid', 'Mirasierra', ClubType.socialClub, []),
    ('c-rcph', 'Real Club Puerta de Hierro', 'Madrid', 'Moncloa-Aravaca', ClubType.socialClub, ['RCPH', 'Puerta de Hierro']),
    ('c-fmp', 'Parque Deportivo Puerta de Hierro', 'Madrid', 'Moncloa-Aravaca', ClubType.federation, []),
    ('c-moraleja', 'La Moraleja Club de Pádel', 'Alcobendas', 'La Moraleja', ClubType.privateClub, ['Moraleja Pádel']),
    ('c-rclm', 'Real Club La Moraleja', 'Alcobendas', 'La Moraleja', ClubType.socialClub, ['Golf La Moraleja']),
    ('c-maspadel', 'Club Maspadel', 'Las Rozas de Madrid', null, ClubType.privateClub, ['Club Más Pádel']),
    ('c-lili', 'CDE Innova Moratalaz - Lili Álvarez', 'Madrid', 'Moratalaz', ClubType.municipal, ['Lili Álvarez']),
    ('c-alameda', 'Club Alameda Padel Xperience', 'Madrid', null, ClubType.privateClub, ['Club de Pádel Alameda']),
    ('c-ucm', 'Campus Universidad Complutense Deportes', 'Madrid', 'Ciudad Universitaria', ClubType.university, ['UCM Deportes']),
  ];
  final _proposed = <ClubHit>[];
  final _aliases = <String, List<String>>{};
  String? myClub;

  Iterable<(ClubHit, List<String>, String?)> get _all sync* {
    for (final s in _seed) {
      yield (ClubHit(id: s.$1, name: s.$2, municipality: s.$3, type: s.$5), [...s.$6, ...?_aliases[s.$1]], s.$4);
    }
    for (final p in _proposed) { yield (p, const [], null); }
  }

  @override
  Future<List<ClubHit>> search(String query, {double? lat, double? lng, List<ClubType>? types, int limit = 8}) async {
    final q = normalizeClubName(query);
    if (q.length < 2) return const [];
    final words = q.split(' ');
    double score(String text, String extra) {
      final n = normalizeClubName(text), doc = ' ${normalizeClubName('$text $extra')} ';
      if (n == q || n.replaceAll(' ', '') == q.replaceAll(' ', '')) return 1;
      if (n.startsWith(q)) return .85;
      if (words.every((w) => doc.contains(' $w '))) return .75;
      if (words.any((w) => w.length > 2 && doc.contains(w))) return .4;
      return 0;
    }
    final out = <ClubHit>[];
    for (final (c, aliases, area) in _all) {
      if (types != null && !types.contains(c.type)) continue;
      var best = score(c.name, '${area ?? ''} ${c.municipality ?? ''}');
      String? alias;
      for (final a in aliases) {
        final s = score(a, '${c.name} ${area ?? ''} ${c.municipality ?? ''}');
        if (s > best) { best = s; alias = a; }
      }
      if (best >= .3) out.add(ClubHit(id: c.id, name: c.name, municipality: c.municipality, type: c.type, pending: c.pending, matchedAlias: alias, score: best));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    final top = out.take(limit).toList();
    if (top.isEmpty) return top;
    final confident = top.first.score >= .9 && (top.length == 1 || top.first.score - top[1].score >= .2);
    return [ClubHit(id: top.first.id, name: top.first.name, municipality: top.first.municipality, type: top.first.type,
        pending: top.first.pending, matchedAlias: top.first.matchedAlias, score: top.first.score, confident: confident), ...top.skip(1)];
  }

  @override
  Future<List<ClubHit>> nearby(double lat, double lng, {int limit = 8}) async => const [];   // la demo no tiene coordenadas

  @override
  Future<ProposeOutcome> propose({required String name, required String municipality, ClubType type = ClubType.privateClub,
      String? address, bool force = false}) async {
    if (name.trim().length < 3 || municipality.trim().length < 2) throw ClubException('invalid_club');
    if (!force) {
      final d = (await search('$name $municipality')).where((h) => h.score >= .7).toList();
      final d2 = d.isNotEmpty ? d : (await search(name)).where((h) => h.score >= .85).toList();
      if (d2.isNotEmpty) return ProposeDuplicates(d2);
    }
    final c = ClubHit(id: 'p-${_proposed.length + 1}', name: name.trim(), municipality: municipality.trim(), type: type, pending: true);
    _proposed.add(c);
    return ProposeCreated(c.id);
  }

  @override
  Future<ClubPage?> page(String clubId) async {
    for (final (c, aliases, area) in _all) {
      if (c.id == clubId) {
        return ClubPage(id: c.id, name: c.name, municipality: c.municipality, area: area, type: c.type, pending: c.pending,
            playersCount: myClub == c.id ? 1 : 0, aliases: aliases,
            ranking: [if (myClub == c.id) const ClubPlayer(id: 'me', name: 'Diego Castelló', username: 'diego.c', level: 'Intermedio', elo: 1210)]);
      }
    }
    return null;
  }

  @override
  Future<void> setMyClub(String? clubId) async => myClub = clubId;

  @override
  Future<List<PendingClub>> pending() async {
    if (!isAdmin) throw ClubException('forbidden');
    return [for (final p in _proposed.where((p) => p.pending)) PendingClub(id: p.id, name: p.name, municipality: p.municipality, type: p.type)];
  }

  @override
  Future<void> review(String clubId, String action, {String? targetId, String? note}) async {
    if (!isAdmin) throw ClubException('forbidden');
    final i = _proposed.indexWhere((p) => p.id == clubId);
    if (i < 0) throw ClubException('not_found');
    final p = _proposed[i];
    if (action == 'approve') {
      _proposed[i] = ClubHit(id: p.id, name: p.name, municipality: p.municipality, type: p.type);
    } else {
      _proposed.removeAt(i);
      if (action == 'merge' && targetId != null) (_aliases[targetId] ??= []).add(p.name);
      if (myClub == clubId) myClub = action == 'merge' ? targetId : null;
    }
  }

  @override
  Future<void> addAlias(String clubId, String alias) async {
    if (!isAdmin) throw ClubException('forbidden');
    (_aliases[clubId] ??= []).add(alias);
  }
}
