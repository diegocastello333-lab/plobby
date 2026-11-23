import 'package:flutter/foundation.dart';

/// Tipos de club del catálogo (columna `clubs.type`).
enum ClubType {
  privateClub('private_club', 'Club privado'),
  socialClub('social_club', 'Club social'),
  municipal('municipal', 'Municipal'),
  publicRegional('public_regional', 'Público'),
  federation('federation', 'Federación'),
  gym('gym', 'Gimnasio'),
  university('university', 'Universidad'),
  school('school', 'Colegio');

  const ClubType(this.db, this.label);
  final String db, label;
  static ClubType of(String? db) => values.firstWhere((t) => t.db == db, orElse: () => privateClub);
}

/// Un resultado de `search_clubs`: club del catálogo + qué alias coincidió + puntuación.
@immutable
class ClubHit {
  const ClubHit({required this.id, required this.name, this.municipality, this.type = ClubType.privateClub,
      this.pending = false, this.matchedAlias, this.score = 0, this.confident = false});
  final String id, name;
  final String? municipality, matchedAlias;
  final ClubType type;
  final bool pending, confident;
  final double score;

  /// «Nombre · Municipio»
  String get title => municipality == null || municipality!.isEmpty ? name : '$name · $municipality';

  factory ClubHit.fromJson(Map<String, dynamic> j) => ClubHit(
        id: j['id'] as String, name: j['name'] as String, municipality: j['municipality'] as String?,
        type: ClubType.of(j['type'] as String?), pending: j['status'] == 'pending', matchedAlias: j['matched_alias'] as String?,
        score: (j['score'] as num?)?.toDouble() ?? 0, confident: j['confident'] == true);

  @override
  bool operator ==(Object o) => o is ClubHit && o.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Respuesta de `propose_club`: o se ha creado (id) o hay clubes muy parecidos (avisar antes de crear).
sealed class ProposeOutcome { const ProposeOutcome(); }
class ProposeCreated extends ProposeOutcome { const ProposeCreated(this.id); final String id; }
class ProposeDuplicates extends ProposeOutcome { const ProposeDuplicates(this.candidates); final List<ClubHit> candidates; }

/// Jugador en la página del club (datos públicos mínimos).
@immutable
class ClubPlayer {
  const ClubPlayer({required this.id, required this.name, this.username = '', this.avatarUrl, this.level, this.elo});
  final String id, name, username;
  final String? avatarUrl, level;
  final int? elo;
  factory ClubPlayer.fromJson(Map<String, dynamic> j) => ClubPlayer(id: j['id'] as String, name: (j['name'] ?? '') as String,
      username: (j['username'] ?? '') as String, avatarUrl: j['avatar_url'] as String?, level: j['level'] as String?, elo: (j['elo'] as num?)?.toInt());
}

/// Página del club (`club_page`).
@immutable
class ClubPage {
  const ClubPage({required this.id, required this.name, this.municipality, this.area, this.address, this.postalCode,
      this.type = ClubType.privateClub, this.pending = false, this.playersCount = 0, this.aliases = const [], this.ranking = const [],
      this.leagues = const [], this.lat, this.lng});
  final String id, name;
  final String? municipality, area, address, postalCode;
  final ClubType type;
  final bool pending;
  final int playersCount;
  final List<String> aliases;
  final List<ClubPlayer> ranking;
  final List<(String, String)> leagues;   // (id, nombre)
  final double? lat, lng;

  factory ClubPage.fromJson(Map<String, dynamic> j) {
    final c = (j['club'] as Map).cast<String, dynamic>();
    return ClubPage(
      id: c['id'] as String, name: c['name'] as String, municipality: c['municipality'] as String?, area: c['area'] as String?,
      address: c['address'] as String?, postalCode: c['postal_code'] as String?, type: ClubType.of(c['type'] as String?),
      pending: c['status'] == 'pending', playersCount: (c['players_count'] as num?)?.toInt() ?? 0,
      aliases: [for (final a in (c['aliases'] as List? ?? const [])) a as String],
      ranking: [for (final p in (j['ranking'] as List? ?? const [])) ClubPlayer.fromJson((p as Map).cast<String, dynamic>())],
      leagues: [for (final l in (j['leagues'] as List? ?? const [])) ((l as Map)['id'] as String, l['name'] as String)],
      lat: (c['lat'] as num?)?.toDouble(), lng: (c['lng'] as num?)?.toDouble(),
    );
  }
}

/// Propuesta pendiente en la cola de moderación.
@immutable
class PendingClub {
  const PendingClub({required this.id, required this.name, this.municipality, this.type = ClubType.privateClub, this.address,
      this.creator, this.players = 0, this.similar = const []});
  final String id, name;
  final String? municipality, address, creator;
  final ClubType type;
  final int players;
  final List<ClubHit> similar;
  factory PendingClub.fromJson(Map<String, dynamic> j) => PendingClub(
        id: j['id'] as String, name: j['name'] as String, municipality: j['municipality'] as String?, type: ClubType.of(j['type'] as String?),
        address: j['address'] as String?, creator: j['creator'] as String?, players: (j['players'] as num?)?.toInt() ?? 0,
        similar: [for (final s in (j['similar'] as List? ?? const [])) ClubHit.fromJson((s as Map).cast<String, dynamic>())]);
}

/// Réplica en Dart de `normalize_club_name` (para el repositorio de demostración y los tests).
String normalizeClubName(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç', to = 'aaaaaeeeeiiiiooooouuuunc';
  var t = s.toLowerCase();
  for (var i = 0; i < from.length; i++) { t = t.replaceAll(from[i], to[i]); }
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').replaceAll(RegExp(r'\b(paddle|padle)\b'), 'padel');
  const stop = {'club', 'de', 'del', 'la', 'las', 'el', 'los', 'y', 'e', 'centro', 'deportivo', 'deportiva', 'sport', 'sports', 'cd', 'cde', 'cdm', 'real'};
  return t.split(' ').where((w) => w.isNotEmpty && !stop.contains(w)).join(' ');
}
