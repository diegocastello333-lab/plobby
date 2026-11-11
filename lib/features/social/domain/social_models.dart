/// Resumen público de un jugador (viene de `profiles` + `player_ratings`; nunca se calcula en cliente).
class PlayerSummary {
  final String id, name, username;
  final String? avatarUrl, city, club;
  final int elo;
  final String level; // categoría según la configuración del sistema de rating
  final int mutualFriends;
  final bool online;
  const PlayerSummary({
    required this.id, required this.name, required this.username, required this.elo, required this.level,
    this.avatarUrl, this.city, this.club, this.mutualFriends = 0, this.online = false,
  });
  String get initials => name.trim().split(' ').take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
}

/// Actividad reciente que se muestra bajo cada amigo (último partido confirmado, racha, logro).
class FriendActivity {
  final String? lastMatch; // "Ganó 6-3 6-1 · ayer"
  final int streak;
  final String? recentAchievement;
  const FriendActivity({this.lastMatch, this.streak = 0, this.recentAchievement});
}

class Friend {
  final PlayerSummary player;
  final FriendActivity activity;
  const Friend(this.player, this.activity);
}

enum RelationState { none, friend, requestSent, requestReceived }

class FriendRequest {
  final String id;
  final PlayerSummary player;
  final DateTime createdAt;
  const FriendRequest(this.id, this.player, this.createdAt);
}

class FriendRequests {
  final List<FriendRequest> incoming, outgoing;
  const FriendRequests({this.incoming = const [], this.outgoing = const []});
}

class SearchHit {
  final PlayerSummary player;
  final RelationState relation;
  final String? reason; // "3 amigos en común · Misma ciudad"
  const SearchHit(this.player, this.relation, {this.reason});
}
