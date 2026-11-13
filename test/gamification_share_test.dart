import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/share/canvas_text.dart';
import 'package:plobby/features/gamification/application/gamification_share.dart';
import 'package:plobby/features/gamification/data/mock_gamification_repository.dart';
import 'package:plobby/features/gamification/domain/gamification_models.dart';
import 'support/layout_checks.dart';

/// Imágenes de Head to Head, Wrapped y Ranking: sin solapes, sin salirse, sin caracteres sin glifo, con datos normales,
/// extremos (nombres larguísimos, cifras de 4 dígitos) y vacíos.
const _long = GPlayer(id: 'x', name: 'Maximiliano Alejandro Fernández-Villaverde');
const _short = GPlayer(id: 'y', name: 'Al');
PlayerCard _card(GPlayer p, {int played = 1287, int wins = 999}) => PlayerCard(player: p, elo: 1999, played: played, wins: wins, losses: played - wins,
    winRate: played == 0 ? 0 : (100 * wins / played).round(), setsWon: 2100, setsLost: 1300, bestStreak: 125, currentStreak: -12, form: 'WLWWL');

void _paint(CustomPainter p, Size s) => p.paint(Canvas(ui.PictureRecorder(), Offset.zero & s), s);

void main() {
  final now = DateTime(2026, 11, 13, 20);
  final repo = MockGamificationRepository(now: () => now);
  final h2hCases = {
    'demo': () => repo.engine.headToHead('me', 'laura'),
    'extremo': () => H2HData(me: _card(_long), other: _card(const GPlayer(id: 'z', name: 'Bartholomew Christopherson'), wins: 1),
        directTotal: 1287, myWins: 1000, theirWins: 287, lastAt: now,
        matches: [for (var i = 0; i < 5; i++) DirectMatch(matchId: '$i', playedAt: now, won: i.isEven, sets: const [(7, 6), (6, 7), (10, 8)])]),
    'vacío': () => H2HData(me: _card(_short, played: 0, wins: 0), other: _card(const GPlayer(id: 'w', name: 'Bo'), played: 0, wins: 0),
        directTotal: 0, myWins: 0, theirWins: 0),
  };
  for (final c in h2hCases.entries) {
    for (final f in ShareSize.values) {
      test('Head to Head ${c.key} · ${f.name}', () {
        final log = ShareLayoutLog();
        _paint(H2HSharePainter(c.value(), log: log), f.size);
        final pr = layoutProblems(log, f.size, allowTruncatedNames: c.key == 'extremo');
        expect(pr, isEmpty, reason: pr.join('\n'));
      });
    }
  }

  final wrappedCases = {
    'año demo': () => repo.engine.wrapped('me', WrappedKind.year, DateTime(2026)),
    'mes demo': () => repo.engine.wrapped('me', WrappedKind.month, DateTime(2026, 10)),
    'sin partidos': () => repo.engine.wrapped('me', WrappedKind.month, DateTime(2020, 1)),
    'extremo': () => WrappedData(kind: WrappedKind.month, start: DateTime(2026, 9), inProgress: false, name: _long.name, played: 1287, wins: 999,
        losses: 288, winRate: 78, setsPlayed: 3000, setsWon: 2000, bestStreak: 125, prevPlayed: 10, prevWinRate: 50,
        topPartner: const WrappedPerson(_long, 999, 800), topRival: const WrappedPerson(GPlayer(id: 'q', name: 'Anastasiopoulou Konstantina Papadopoulos'), 500, 200),
        recordElo: 1999, isRecord: true),
  };
  for (final c in wrappedCases.entries) {
    for (final f in ShareSize.values) {
      test('Wrapped ${c.key} · ${f.name}', () {
        final log = ShareLayoutLog();
        _paint(WrappedSharePainter(c.value(), log: log), f.size);
        final pr = layoutProblems(log, f.size, allowTruncatedNames: c.key == 'extremo');
        expect(pr, isEmpty, reason: pr.join('\n'));
      });
    }
  }

  for (final m in RankMetric.values) {
    for (final f in ShareSize.values) {
      test('Ranking ${m.name} · ${f.name}', () {
        final r = repo.engine.ranking('me', RankPeriod.all, 0);
        final log = ShareLayoutLog();
        _paint(RankingSharePainter(r, m, log: log), f.size);
        final pr = layoutProblems(log, f.size, allowTruncatedNames: false);
        expect(pr, isEmpty, reason: pr.join('\n'));
      });
    }
  }
}
