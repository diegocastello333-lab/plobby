import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/match_recap/domain/recap_data.dart';
import 'package:plobby/features/matches/domain/match_lifecycle.dart';
import 'package:plobby/features/matches/domain/match_models.dart';
import 'package:plobby/features/messaging/data/mock_messaging_repository.dart';
import 'package:plobby/features/messaging/domain/messaging_models.dart';

const ps = [
  MatchPlayer(id: 'me', name: 'Diego C.', team: 1, isCaptain: true),
  MatchPlayer(id: 'marcos', name: 'Marcos R.', team: 1),
  MatchPlayer(id: 'carlos', name: 'Carlos M.', team: 2, isCaptain: true),
  MatchPlayer(id: 'laura', name: 'Laura G.', team: 2),
];
const acc = [Acceptance(userId: 'me', team: 1, version: 1, accepted: true), Acceptance(userId: 'carlos', team: 2, version: 1, accepted: true)];

LifecycleMatch mt(String id, MatchStatus st, {List<MatchPlayer> players = ps, bool accepted = true}) => LifecycleMatch(
    id: id, type: MatchType.friendly, scheduledAt: DateTime(2026, 11, 8, 19), club: 'Club Alameda', status: st, players: players, createdBy: 'me',
    resultVersion: 1, sets: const [SetScore(6, 3), SetScore(6, 4)], acceptances: accepted ? acc : const []);

MockMessagingRepository repo({List<LifecycleMatch>? matches}) => MockMessagingRepository(autoReply: false, matches: () async => matches ?? [mt('ok', MatchStatus.confirmed), mt('pend', MatchStatus.pendingConfirmation)]);

Future<String> grp(MockMessagingRepository r, [List<String> ids = const ['marcos', 'lucia']]) => r.createGroup(name: 'Pádel jueves', memberIds: ids, avatarId: 'p2');
Matcher code(String c) => throwsA(isA<MessagingException>().having((e) => e.code, 'code', c));

void main() {
  group('crear grupo', () {
    test('nombre, foto y miembros; el creador es admin y aparece en la lista', () async {
      final r = repo(); final id = await grp(r);
      final c = (await r.conversations()).firstWhere((x) => x.id == id);
      expect(c.isGroup, isTrue); expect(c.title, 'Pádel jueves'); expect(c.groupAvatarId, 'p2'); expect(c.memberCount, 3);
      final ms = await r.members(id);
      expect(ms.firstWhere((m) => m.id == 'me').isAdmin, isTrue);
      expect(ms.where((m) => m.isAdmin).length, 1);
    });
    test('validación: nombre vacío/largo y sin participantes', () async {
      expect(validateGroupDraft(name: ' ', selected: 2), isNotNull);
      expect(validateGroupDraft(name: 'x' * 61, selected: 2), isNotNull);
      expect(validateGroupDraft(name: 'ok', selected: 0), isNotNull);
      expect(validateGroupDraft(name: 'ok', selected: 1), isNull);
      final r = repo();
      expect(r.createGroup(name: '', memberIds: ['marcos']), code('invalid_group_name'));
      expect(r.createGroup(name: 'x', memberIds: []), code('group_needs_members'));
    });
    test('solo se puede añadir a amigos', () async {
      final r = repo();
      expect(r.createGroup(name: 'x', memberIds: ['desconocido']), code('only_friends_allowed'));
      final id = await grp(r);
      expect(r.addMembers(id, ['desconocido']), code('only_friends_allowed'));
    });
    test('hay mensaje de sistema inicial y la lista no mezcla grupos con chats 1:1', () async {
      final r = repo(); final id = await grp(r);
      expect((await r.history(id)).first.kind, MessageKind.system);
      final all = await r.conversations();
      expect(all.any((c) => c.id == 'c_marcos' && !c.isGroup), isTrue); // el 1:1 sigue intacto
    });
  });

  group('permisos de admin', () {
    test('editar nombre/foto, ascender, degradar y expulsar', () async {
      final r = repo(); final id = await grp(r);
      await r.updateGroup(id, name: 'Nuevo nombre'); expect((await r.conversation(id))!.title, 'Nuevo nombre');
      await r.updateGroup(id, avatarId: 'p5'); expect((await r.conversation(id))!.groupAvatarId, 'p5');
      await r.setAdmin(id, 'marcos', true);
      await r.setAdmin(id, 'marcos', false);
      await r.removeMember(id, 'lucia');
      expect((await r.members(id)).map((m) => m.id), isNot(contains('lucia')));
      await r.addMembers(id, ['carla']);
      expect((await r.members(id)).map((m) => m.id), contains('carla'));
    });
    test('un admin no expulsa a otro admin sin degradarlo; nombre inválido se rechaza', () async {
      final r = repo(); final id = await grp(r);
      await r.setAdmin(id, 'marcos', true);
      expect(r.removeMember(id, 'marcos'), code('demote_admin_first'));
      expect(r.updateGroup(id, name: '  '), code('invalid_group_name'));
    });
    test('GroupPerms: un miembro normal no puede nada; siempre queda un admin', () {
      final now = DateTime(2026);
      final ms = [GroupMember(id: 'me', name: 'Yo', joinedAt: now), GroupMember(id: 'a', name: 'A', role: GroupRole.admin, joinedAt: now), GroupMember(id: 'b', name: 'B', joinedAt: now)];
      final p = GroupPerms(ms, 'me');
      expect(p.canEdit, isFalse); expect(p.canAdd, isFalse); expect(p.canRemove(ms[2]), isFalse); expect(p.canPromote(ms[2]), isFalse); expect(p.canLeave, isTrue);
      final a = GroupPerms(ms, 'a');
      expect(a.canEdit, isTrue); expect(a.canRemove(ms[2]), isTrue); expect(a.canDemote(ms[1]), isFalse); // último admin
    });
    test('no se puede degradar al último admin', () async {
      final r = repo(); final id = await grp(r);
      expect(r.setAdmin(id, 'me', false), code('last_admin'));
    });
  });

  group('abandonar grupo', () {
    test('al salir dejo de verlo y ya no tengo acceso al historial', () async {
      final r = repo(); final id = await grp(r);
      await r.leaveGroup(id);
      expect((await r.conversations()).any((c) => c.id == id), isFalse); // ya no lo veo
      expect(r.history(id), code('not_a_member'));
    });
    test('al salir ya no puedo enviar ni compartir', () async {
      final r = repo(); final id = await grp(r);
      await r.leaveGroup(id);
      expect(r.send(id, 'hola'), code('not_a_member'));
      expect(r.sendMatchCard(id, 'ok'), code('not_a_member'));
    });
  });

  group('tarjetas de resultado', () {
    test('el selector solo ofrece partidos finalizados Y confirmados donde participo', () async {
      final r = repo(matches: [mt('ok', MatchStatus.confirmed), mt('pend', MatchStatus.pendingConfirmation), mt('live', MatchStatus.live), mt('sinacc', MatchStatus.confirmed, accepted: false),
        mt('ajeno', MatchStatus.confirmed, players: const [MatchPlayer(id: 'x', name: 'X', team: 1, isCaptain: true), MatchPlayer(id: 'y', name: 'Y', team: 2, isCaptain: true)])]);
      expect((await r.shareableMatches()).map((m) => m.id), ['ok']);
    });
    test('se envía en chat directo y en grupo; el snapshot sale del partido original', () async {
      final r = repo(); final id = await grp(r);
      final g = await r.sendMatchCard(id, 'ok'); final d = await r.sendMatchCard('c_marcos', 'ok');
      for (final m in [g, d]) {
        expect(m.kind, MessageKind.match); expect(m.refId, 'ok');
        final rd = recapFromServerJson(m.payload!, sharerId: 'me');
        expect(rd.winners.map((p) => p.id), containsAll(['me', 'marcos'])); expect(rd.sets, [(6, 3), (6, 4)]); expect(rd.club, 'Club Alameda'); expect(rd.userWon, isTrue);
      }
    });
    test('rechaza no confirmados y no participantes', () async {
      final r = repo();
      expect(r.sendMatchCard('c_marcos', 'pend'), code('recap_not_confirmed'));
      expect(r.sendMatchCard('c_marcos', 'nope'), code('match_not_found'));
    });
    test('send() no permite fabricar tarjetas ni mensajes de sistema desde el cliente', () async {
      final r = repo();
      expect(r.send('c_marcos', 'falso', kind: MessageKind.match, refId: 'ok'), code('use_dedicated_function'));
      expect(r.send('c_marcos', 'falso', kind: MessageKind.system), code('use_dedicated_function'));
    });
    test('la tarjeta persiste en el historial aunque el partido cambie después (snapshot)', () async {
      var cur = [mt('ok', MatchStatus.confirmed)];
      final r = MockMessagingRepository(autoReply: false, matches: () async => cur);
      await r.sendMatchCard('c_marcos', 'ok');
      cur = [mt('ok', MatchStatus.disputed)];
      final m = (await r.history('c_marcos')).lastWhere((x) => x.kind == MessageKind.match);
      expect(recapFromServerJson(m.payload!, sharerId: 'me').sets, [(6, 3), (6, 4)]);
    });
  });

  test('vista previa en lista: en grupos antepone el remitente, tarjetas con etiqueta', () async {
    final r = repo(); final id = await grp(r);
    await r.sendMatchCard(id, 'ok');
    final c = (await r.conversations()).firstWhere((x) => x.id == id);
    expect(c.preview, 'Tú: 🏆 Resultado de partido');
    expect((await r.conversations()).firstWhere((x) => x.id == 'c_marcos').preview, '¿Jugamos el jueves a las 19:00?'); // 1:1 sin prefijo
  });
}
