import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/feed/data/supabase_feed_repository.dart';
import 'package:plobby/features/feed/domain/feed_models.dart';
import 'package:plobby/features/profile/data/supabase_profile_repository.dart';
import 'package:plobby/features/profile/domain/models.dart';

/// Conversión de filas de Supabase (RPC/selects) a modelos de la UI. Funciones puras: no necesitan red.
void main() {
  group('get_player_history → MatchResult', () {
    final row = {
      'match_id': 'm1', 'played_at': '2026-11-10T18:00:00Z', 'confirmed': true, 'is_league': true, 'venue': 'Club Alameda', 'team': 2, 'elo_delta': -14,
      'sets': [[6, 3], [4, 6], [6, 2]],   // [equipo1, equipo2]
      'players': [
        {'id': 'u1', 'name': 'Ana', 'team': 1}, {'id': 'u2', 'name': 'Bea', 'team': 1},
        {'id': 'me', 'name': 'Diego', 'team': 2}, {'id': 'u4', 'name': 'Dani', 'team': 2},
      ],
    };
    test('orienta los sets al jugador y calcula si ganó', () {
      final m = matchFromHistory(row, 'me', PlaySide.right)!;
      expect(m.sets, [(3, 6), (6, 4), (2, 6)]);
      expect(m.won, isFalse);
      expect(m.partner.name, 'Dani');
      expect(m.opponents.map((p) => p.name), ['Ana', 'Bea']);
      expect(m.eloDelta, -14);
      expect(m.isLeague, isTrue);
      expect(m.confirmed, isTrue);
    });
    test('sin sets (pendiente sin resultado) no se muestra', () => expect(matchFromHistory({...row, 'sets': []}, 'me', PlaySide.right), isNull));
  });

  group('feed_posts.metadata → payload', () {
    final summary = {
      'match_id': 'm1', 'venue': 'Padel Chamberí', 'league_name': null,
      'players': [
        {'id': 'f1', 'name': 'Laura', 'team': 2, 'elo_delta': 15}, {'id': 'f2', 'name': 'Carlos', 'team': 2},
        {'id': 'me', 'name': 'Diego', 'team': 1}, {'id': 'f3', 'name': 'Sofía', 'team': 1},
      ],
      'sets': [[1, 6], [1, 6]],
    };
    test('partido: el equipo del autor es teamA y el marcador va orientado a él', () {
      final p = feedPayloadFrom(type: 'match', meta: const {'team': 2, 'elo_delta': 15}, authorUid: 'f1', myUid: 'me', match: summary) as MatchPayload;
      expect(p.teamA.map((u) => u.name), ['Laura', 'Carlos']);
      expect(p.teamB.map((u) => u.id), ['me', 'f3']);          // el usuario actual se expone como 'me'
      expect(p.sets, [(6, 1), (6, 1)]);
      expect(p.won, isTrue);
      expect(p.eloDelta, 15);
    });
    test('partido no visible o sin confirmar: no se publica', () => expect(feedPayloadFrom(type: 'match', meta: const {}, authorUid: 'f1', myUid: 'me'), isNull));
    test('liga y racha', () {
      expect((feedPayloadFrom(type: 'league', meta: const {'league_name': 'LIGA X', 'headline': 'Se unió a la liga', 'subtitle': 'Temporada 01'}, authorUid: 'a', myUid: 'me') as LeaguePayload).leagueName, 'LIGA X');
      expect((feedPayloadFrom(type: 'streak', meta: const {'count': 5}, authorUid: 'a', myUid: 'me') as StreakPayload).count, 5);
    });
  });

  group('notifications → AppNotification', () {
    const actor = FeedUser(id: 'u1', name: 'Marcos', username: 'marcos');
    Map<String, dynamic> n(String type, {String? title, String? body, bool read = false, int count = 1}) =>
        {'id': 'n1', 'notification_type': type, 'ref_id': 'r1', 'actor_count': count, 'is_read': read, 'created_at': '2026-11-11T10:00:00Z', 'title': title, 'body': body};
    test('solicitud de amistad: accionable y con texto', () {
      final x = notificationFrom(n('friend_request'), actor)!;
      expect(x.type, NotificationType.friendRequest);
      expect(x.text, 'Marcos quiere ser tu amigo');
      expect(x.actionable, isTrue);
    });
    test('agrupada: «Marcos y 2 más»', () => expect(notificationFrom(n('reaction', count: 3), actor)!.text, 'Marcos y 2 más reaccionó a tu actividad'));
    test('invitación a liga usa título/cuerpo del servidor y lleva a /leagues/:id', () {
      final x = notificationFrom(n('league_invite', title: 'Invitación a liga', body: 'Te han invitado a LIGA X'), actor)!;
      expect(x.text, 'Invitación a liga: Te han invitado a LIGA X');
      expect(x.type.route(x), '/leagues/r1');
      expect(x.actionable, isTrue);
    });
    // Antes los avisos de grupo se descartaban y los mensajes privados no tenían aviso: ahora todos llevan al chat.
    test('mensaje privado: remitente + texto, contador de pendientes y abre la conversación', () {
      final x = notificationFrom(n('direct_message', body: '¿Jugamos mañana?'), actor)!;
      expect((x.type, x.text, x.type.route(x)), (NotificationType.directMessage, 'Marcos: ¿Jugamos mañana?', '/messages/r1'));
      expect(notificationFrom(n('direct_message', body: 'Último', count: 3), actor)!.text, 'Marcos te ha enviado 3 mensajes · Último');
      expect(x.actionable, isFalse);
    });
    test('mensaje de grupo y alta en grupo', () {
      final g = notificationFrom(n('group_message', title: 'Pádel jueves', body: 'Hola'), actor)!;
      expect((g.text, g.type.route(g)), ('Marcos en «Pádel jueves»: Hola', '/messages/r1'));
      final a = notificationFrom(n('group_added', title: 'Te han añadido a un grupo', body: 'Pádel jueves'), actor)!;
      expect((a.type, a.text), (NotificationType.groupAdded, 'Marcos te añadió al grupo «Pádel jueves»'));
    });
    test('solicitud de amistad lleva a Amigos (pendientes con Aceptar/Rechazar)', () {
      final x = notificationFrom(n('friend_request'), actor)!;
      expect(x.type.route(x), '/friends');
    });
    test('tipos desconocidos se omiten', () => expect(notificationFrom(n('tipo_futuro'), actor), isNull));
  });
}
