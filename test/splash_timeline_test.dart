import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/features/splash/presentation/splash_screen.dart';

void main() {
  test('el primer fotograma coincide con el splash nativo', () {
    expect(SplashTimeline.hit(0), 1);
    expect(SplashTimeline.ball(0), Offset.zero);
    expect(SplashTimeline.lift(0), 0);
    expect(SplashTimeline.title(0), 0);
    expect(SplashTimeline.court(0), 0);
    for (var i = 0; i < 9; i++) {
      expect(SplashTimeline.dot(0, i), 1);
    }
  });

  test('al final todo queda en reposo y visible', () {
    expect(SplashTimeline.hit(1), closeTo(1, 1e-9));
    expect(SplashTimeline.ball(1).distance, closeTo(0, 1e-9));
    expect(SplashTimeline.lift(1), 56);
    expect(SplashTimeline.title(1), 1);
    expect(SplashTimeline.tagline(1), 1);
    expect(SplashTimeline.court(1), 1);
    expect(SplashTimeline.loader(1), 1);
    for (var i = 0; i < 9; i++) {
      expect(SplashTimeline.dot(1, i), closeTo(1, 1e-9));
    }
  });

  test('la bola sube en el globo', () {
    expect(SplashTimeline.ball(.23).dy, lessThan(-70));
  });
}
