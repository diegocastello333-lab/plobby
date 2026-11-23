import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/widgets/verified_badge.dart';
import 'package:plobby/features/profile/domain/verified_users.dart';

void main() {
  test('solo la cuenta del fundador está verificada (por id, no por email)', () {
    expect(isVerifiedUser('48eee197-dc9e-4f4f-bddd-b45f8b88c3a0'), isTrue);
    expect(isVerifiedUser('00000000-0000-0000-0000-000000000000'), isFalse);
    expect(isVerifiedUser(null), isFalse);
    expect(verifiedUserIds, hasLength(1));
  });

  testWidgets('el sello se anuncia al lector de pantalla y el brillo se mueve', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(const MaterialApp(home: Center(child: VerifiedBadge())));
    expect(find.bySemanticsLabel('Perfil verificado'), findsOneWidget);
    double phase() => (t.widget<CustomPaint>(find.descendant(of: find.byType(VerifiedBadge), matching: find.byType(CustomPaint))).painter! as VerifiedSealPainter).t;
    final a = phase();
    await t.pump(const Duration(milliseconds: 600));   // timing
    expect(phase(), isNot(a));
    h.dispose();
  });

  testWidgets('con «reducir movimiento» queda quieto', (t) async {
    await t.pumpWidget(const MaterialApp(home: MediaQuery(data: MediaQueryData(disableAnimations: true), child: Center(child: VerifiedBadge()))));
    expect(Motion.reduced(t.element(find.byType(VerifiedBadge))), isTrue);
    expect(t.hasRunningAnimations, isFalse);
  });
}
