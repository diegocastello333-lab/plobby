import 'package:flutter/foundation.dart';

enum PlaySide { right, left }

@immutable
class ClubRef {
  const ClubRef({required this.id, required this.name, required this.city});
  final String id, name, city;
}

enum PartnerStatus { pending, accepted }

@immutable
class PartnerLink {
  const PartnerLink({required this.userId, required this.name, required this.username, this.avatarUrl, required this.status});
  final String userId, name, username;
  final String? avatarUrl;
  final PartnerStatus status; // solo `accepted` se muestra en el perfil público
}

@immutable
class PlayerProfile {
  const PlayerProfile({
    required this.id, required this.fullName, required this.username, required this.location,
    this.avatarUrl, this.avatarId, this.bannerId, this.verified = false, this.bio = '', required this.declaredLevel,
    required this.declaredLevelValue, required this.side, required this.dominantHand,
    this.club, this.partner, this.leaguesPlayed = 0,
  });
  final String id, fullName, username, location, bio, declaredLevel;
  final String? avatarUrl;
  /// Avatar predefinido (`a1`…`a12`) cuando no hay [avatarUrl] (perfiles antiguos que solo guardaron el id).
  final String? avatarId;
  /// Colección del banner de Inicio ('banner1'/'banner2'; null o un valor antiguo = Banner 1). Ver `HomeBanner`.
  final String? bannerId;
  final bool verified;
  final double declaredLevelValue;
  final PlaySide side;
  final String dominantHand; // 'Derecha' | 'Izquierda'
  final ClubRef? club; // opcional: si es null no se pinta ningún campo
  final PartnerLink? partner;
  final int leaguesPlayed;

  PlayerProfile copyWith({PlaySide? side, ClubRef? club, bool clearClub = false, PartnerLink? partner, bool clearPartner = false, String? bio, String? bannerId}) =>
      PlayerProfile(
        id: id, fullName: fullName, username: username, location: location, avatarUrl: avatarUrl, avatarId: avatarId, bannerId: bannerId ?? this.bannerId,
        verified: verified, bio: bio ?? this.bio, declaredLevel: declaredLevel, declaredLevelValue: declaredLevelValue,
        side: side ?? this.side, dominantHand: dominantHand,
        club: clearClub ? null : (club ?? this.club),
        partner: clearPartner ? null : (partner ?? this.partner), leaguesPlayed: leaguesPlayed,
      );
}

@immutable
class PlayerRef {
  const PlayerRef(this.id, this.name, [this.avatarUrl]);
  final String id, name;
  final String? avatarUrl;
}

/// Un partido. `confirmed == false` NUNCA entra en ELO, estadísticas ni racha.
@immutable
class MatchResult {
  const MatchResult({
    required this.id, required this.playedAt, required this.won, required this.partner,
    required this.opponents, required this.sets, required this.venue, required this.eloDelta,
    required this.side, this.isLeague = false, required this.confirmed,
  });
  final String id, venue;
  final DateTime playedAt;
  final bool won, isLeague, confirmed;
  final PlayerRef partner;
  final List<PlayerRef> opponents;
  final List<(int, int)> sets; // (mis juegos, juegos rivales)
  final int eloDelta;
  final PlaySide side;
  String get scoreLabel => sets.map((s) => '${s.$1}-${s.$2}').join(' · ');
}

@immutable
class ProfileData {
  const ProfileData({required this.profile, required this.matches, required this.currentElo});
  final PlayerProfile profile;
  final List<MatchResult> matches; // newest first, incluye no confirmados (se filtran en el calculador)
  final int currentElo;            // ELO vigente según el backend
}
