import 'package:supabase_flutter/supabase_flutter.dart';
import 'shared_realtime.dart';

/// Evento recibido por el canal privado del usuario (`user:<uid>`), emitido por triggers de la base de datos
/// (Broadcast desde la BD; política RLS `plobby_user_topic_read`: solo el propio usuario puede escucharlo).
sealed class UserEvent { const UserEvent(); }

/// Alta o baja de una amistad mía (trigger de `friendships`).
class FriendshipEvent extends UserEvent { const FriendshipEvent(); }

/// Un jugador que aparece en mis pantallas (amigo, compañero de grupo o de liga, o yo en otro dispositivo) cambió su
/// foto, avatar o nombre (trigger de `profiles`).
class ProfileEvent extends UserEvent {
  const ProfileEvent({required this.userId, this.avatarUrl, this.avatarId, this.displayName, this.username});
  final String userId;
  final String? avatarUrl, avatarId, displayName, username;
  factory ProfileEvent.fromJson(Map<String, dynamic> j) => ProfileEvent(userId: j['user_id'] as String,
      avatarUrl: j['avatar_url'] as String?, avatarId: j['avatar_id'] as String?, displayName: j['display_name'] as String?, username: j['username'] as String?);
}

/// Cambio en un grupo del que soy (o era) miembro: alta, baja, rol, nombre o foto (triggers de grupos).
class GroupEvent extends UserEvent {
  const GroupEvent(this.conversationId, {this.op, this.userId});
  final String conversationId;
  final String? op, userId;
}

/// Cambio en un torneo del que soy organizador o jugador (triggers de torneos: un aviso por operación).
class TournamentEvent extends UserEvent {
  const TournamentEvent(this.tournamentId);
  final String tournamentId;
}

/// UN solo canal privado por sesión para todo lo anterior. Debe existir una única instancia: el tema es exacto
/// (`user:<uid>`) y dos canales con el mismo tema se cerrarían entre sí.
class UserChannel {
  UserChannel(SupabaseClient db, String uid) : _rt = SharedRealtime<UserEvent>(db, 'user:$uid', (ch, emit) {
          Map<String, dynamic> body(Map<String, dynamic> p) => (p['payload'] as Map?)?.cast<String, dynamic>() ?? p;
          ch
            ..onBroadcast(event: 'friends', callback: (_) => emit(const FriendshipEvent()))
            ..onBroadcast(event: 'profile', callback: (p) {
              final b = body(p);
              if (b['user_id'] is String) emit(ProfileEvent.fromJson(b));
            })
            ..onBroadcast(event: 'tournament', callback: (p) {
              final id = body(p)['tournament_id'];
              if (id is String) emit(TournamentEvent(id));
            })
            ..onBroadcast(event: 'group', callback: (p) {
              final b = body(p);
              final id = b['conversation_id'];
              if (id is String) emit(GroupEvent(id, op: b['op'] as String?, userId: b['user_id'] as String?));
            });
        }, private: true);
  final SharedRealtime<UserEvent> _rt;
  Stream<UserEvent> get events => _rt.events;
  Stream<void> get resyncs => _rt.resyncs;
}
