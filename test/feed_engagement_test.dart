import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/feed/application/feed_providers.dart';
import 'package:plobby/features/feed/data/mock_feed_repository.dart';
import 'package:plobby/features/feed/data/supabase_feed_repository.dart' show feedPayloadFrom;
import 'package:plobby/features/feed/domain/feed_models.dart';
import 'package:plobby/features/feed/presentation/feed_screen.dart';
import 'package:plobby/features/feed/presentation/widgets/comments_sheet.dart' show friendlyFeedError;

const _a = FeedUser(id: 'a', name: 'Ana', username: 'ana');
FeedPost _m(String id, String match) => FeedPost(id: id, author: _a, createdAt: DateTime(2026, 11, 13), reactions: const ReactionSummary(),
    payload: MatchPayload(matchId: match, teamA: const [_a], teamB: const [_a], sets: const [(6, 1), (6, 1)], won: true, eloDelta: 16));

/// Repositorio con reacciones lentas y registro del orden en que llegan al «servidor».
class _SlowRepo extends MockFeedRepository {
  final sent = <ReactionType?>[];
  var fail = false;
  @override
  Future<void> setReaction(String postId, ReactionType? type) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (fail) throw Exception('network');
    sent.add(type);
  }
}

void main() {
  group('Feed sin duplicados', () {
    test('el mismo partido publicado por varios jugadores aparece una sola vez, también entre páginas', () {
      final first = collapseDuplicateMatches(const [], [_m('1', 'x'), _m('2', 'x'), _m('3', 'y')]);
      expect(first.map((p) => p.id), ['1', '3']);
      final next = collapseDuplicateMatches(first, [_m('4', 'y'), _m('5', 'z'), _m('1', 'x')]);
      expect(next.map((p) => p.id), ['5']);
    });

    testWidgets('el feed de demo no repite el partido m1 y muestra al campeón del torneo', (t) async {
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(child: MaterialApp(theme: buildPlobbyTheme(), home: const FeedScreen())));
      for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 250)); }
      expect(find.text('Laura G. + Carlos M.'), findsOneWidget);
      expect(find.text('CAMPEÓN'), findsOneWidget);
      expect(find.text('Open de Otoño'), findsOneWidget);
      expect(find.text('Con Irene · 6 parejas'), findsOneWidget);
      expect(find.text('Competiciones'), findsOneWidget);      // filtro (antes «Ligas»)
      expect(t.takeException(), isNull);
    });
  });

  group('Publicaciones del servidor', () {
    test('campeón de torneo y récord de ELO se interpretan bien', () {
      final champ = feedPayloadFrom(type: 'tournament', meta: {'tournament_id': 't1', 'name': 'Open', 'partner_name': 'Antonio', 'teams': 8}, authorUid: 'u', myUid: 'me');
      expect(champ, isA<TournamentPayload>().having((p) => p.tournamentId, 'id', 't1').having((p) => p.teams, 'teams', 8));
      expect(feedPayloadFrom(type: 'tournament', meta: const {}, authorUid: 'u', myUid: 'me'), isNull);
      final elo = feedPayloadFrom(type: 'elo', meta: {'from': 1096, 'to': 1107, 'headline': 'Nuevo récord personal'}, authorUid: 'u', myUid: 'me') as EloPayload;
      expect((elo.delta, elo.headline), (11, 'bate su récord personal de ELO'));
      expect((feedPayloadFrom(type: 'streak', meta: {'count': 5}, authorUid: 'u', myUid: 'me') as StreakPayload).count, 5);
    });
  });

  group('Reacciones', () {
    test('pulsaciones rápidas se envían en orden y el último estado es el que se guarda', () async {
      final repo = _SlowRepo();
      final c = ProviderContainer(overrides: [feedRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      final s = await c.read(feedControllerProvider.future);
      final post = s.posts.firstWhere((p) => p.reactions.mine == null);
      final n = c.read(feedControllerProvider.notifier);
      unawaited(n.react(post.id, ReactionType.fire));
      unawaited(n.react(post.id, ReactionType.fire));      // quitar
      await n.react(post.id, ReactionType.heart);
      expect(repo.sent, [ReactionType.fire, null, ReactionType.heart]);
      expect(c.read(feedControllerProvider).value!.posts.firstWhere((p) => p.id == post.id).reactions.mine, ReactionType.heart);
    });

    test('si el servidor falla, la reacción vuelve a su estado anterior', () async {
      final repo = _SlowRepo()..fail = true;
      final c = ProviderContainer(overrides: [feedRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      final s = await c.read(feedControllerProvider.future);
      final post = s.posts.firstWhere((p) => p.reactions.mine == null);
      await c.read(feedControllerProvider.notifier).react(post.id, ReactionType.fire);
      final after = c.read(feedControllerProvider).value!.posts.firstWhere((p) => p.id == post.id);
      expect(after.reactions.mine, isNull);
      expect(after.reactions.counts, post.reactions.counts);
    });
  });

  test('los errores del servidor se traducen a frases para el usuario', () {
    expect(friendlyFeedError(Exception('PostgrestException(message: rate_limited, code: P0001)')), contains('Vas muy rápido'));
    expect(friendlyFeedError(Exception('SocketException')), contains('Revisa tu conexión'));
  });
}
