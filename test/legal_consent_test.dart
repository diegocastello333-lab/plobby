import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/motion/app_motion.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/features/auth/application/auth_providers.dart';
import 'package:plobby/features/auth/data/mock_auth_repository.dart';
import 'package:plobby/features/auth/domain/legal.dart';
import 'package:plobby/features/auth/presentation/consent_screen.dart';
import 'package:plobby/features/auth/presentation/legal_doc_screen.dart';
import 'package:plobby/features/auth/presentation/privacy_settings_screen.dart';

/// Seguridad Fase 8: aceptación obligatoria, re-aceptación al cambiar de versión, documentos y Ajustes de privacidad.
void main() {
  group('guardia de acceso', () {
    test('con sesión y sin consentimiento → /consent (antes del onboarding)', () {
      expect(authRedirect(signedIn: true, onboardingDone: false, consentsOk: false, location: '/feed'), '/consent');
      expect(authRedirect(signedIn: true, onboardingDone: true, consentsOk: false, location: '/home'), '/consent');
      expect(authRedirect(signedIn: true, onboardingDone: true, consentsOk: false, location: '/consent'), isNull);
    });
    test('aceptado → sigue al onboarding o al Inicio; /consent ya no se muestra', () {
      expect(authRedirect(signedIn: true, onboardingDone: false, consentsOk: true, location: '/consent'), '/onboarding');
      expect(authRedirect(signedIn: true, onboardingDone: true, consentsOk: true, location: '/consent'), '/home');
    });
    test('los documentos se pueden leer siempre (sin sesión y antes de aceptar)', () {
      expect(authRedirect(signedIn: false, onboardingDone: false, consentsOk: false, location: '/legal/privacidad'), isNull);
      expect(authRedirect(signedIn: true, onboardingDone: false, consentsOk: false, location: '/legal/terminos'), isNull);
    });
  });

  test('LegalStatus: re-aceptación cuando cambia la versión', () {
    final s = LegalStatus.fromJson({'required_ok': false, 'marketing': true, 'pending': [
      {'doc_type': 'terms', 'version': 2, 'title': 'Términos', 'previously_accepted': true},
    ]});
    expect(s.requiredOk, isFalse);
    expect(s.isUpdate, isTrue);
    expect(s.marketing, isTrue);
    expect(LegalStatus.fromJson({'required_ok': false, 'pending': [{'doc_type': 'terms', 'version': 1, 'title': 'T'}]}).isUpdate, isFalse);
  });

  test('cada documento existe en la app y en la web, con título y versión', () {
    for (final d in LegalDoc.values) {
      final md = File(d.asset).readAsStringSync();
      expect(md.startsWith('# ${d.title.split(' ').first}'), isTrue, reason: d.asset);
      expect(md, contains('Versión'));
      expect(File('web/legal/${d.slug}.html').existsSync(), isTrue, reason: d.slug);
    }
    expect(LegalDoc.bySlug('privacidad'), LegalDoc.privacy);
    expect(LegalDoc.bySlug('nada'), isNull);
  });

  test('renderLegalMarkdown: títulos, avisos, listas y párrafos', () {
    final w = renderLegalMarkdown('# T\n\n## S\n\n> **Aviso** x\n\n- uno\n- dos\n\nTexto');
    expect(w.length, 6);
  });

  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Widget app(MockAuthRepository repo, Widget child) =>
      ProviderScope(overrides: [authRepositoryProvider.overrideWithValue(repo)], child: MaterialApp(home: child));

  testWidgets('«Continuar» desactivado hasta marcar Términos/Privacidad y edad; marketing opcional e independiente', (t) async {
    final repo = MockAuthRepository()..legal = const LegalStatus(requiredOk: false, pending: [PendingLegalDoc(docType: 'terms', version: 1, title: 'T')]);
    var done = false;
    tall(t);
    await t.pumpWidget(app(repo, ConsentScreen(onDone: () => done = true)));
    await t.pumpAndSettle();
    expect(find.text('Antes de empezar'), findsOneWidget);
    // las casillas empiezan desmarcadas
    for (final c in t.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(c.value, isFalse);
    }
    await t.tap(find.text('Continuar'));
    await t.pump();
    expect(done, isFalse, reason: 'sin marcar nada no continúa');
    await t.tap(find.byType(Checkbox).at(0));
    await t.pump();
    await t.tap(find.text('Continuar'));
    await t.pump();
    expect(done, isFalse, reason: 'falta la edad');
    await t.tap(find.byType(Checkbox).at(1));
    await t.pump();
    await t.tap(find.text('Continuar'));
    await t.pump(const Duration(milliseconds: 300));   // el botón queda «ocupado» hasta que el router cambia de pantalla
    expect(done, isTrue);
    expect(repo.legal.requiredOk, isTrue);
    expect(repo.legal.marketing, isFalse, reason: 'marketing no se marca solo');
  });

  testWidgets('re-aceptación: título de «condiciones actualizadas»', (t) async {
    final repo = MockAuthRepository()..legal = const LegalStatus(requiredOk: false, pending: [PendingLegalDoc(docType: 'terms', version: 2, title: 'T', previouslyAccepted: true)]);
    await t.pumpWidget(app(repo, const ConsentScreen()));
    await t.pumpAndSettle();
    expect(find.text('Hemos actualizado nuestras condiciones'), findsOneWidget);
  });

  testWidgets('Ajustes y privacidad: vibración, secciones, marketing y borrado protegido con «ELIMINAR»', (t) async {
    final repo = MockAuthRepository();
    tall(t);
    await t.pumpWidget(app(repo, const PrivacySettingsScreen()));
    await t.pumpAndSettle();
    for (final s in ['Descargar mis datos', 'Cerrar sesión en todos los dispositivos', 'Eliminar mi cuenta', 'Comunicaciones comerciales', 'Política de Privacidad']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    // Vibración (primer interruptor): se puede apagar y volver a encender
    expect(find.text('Vibración'), findsOneWidget);
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(AppHaptics.enabled, isFalse);
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(AppHaptics.enabled, isTrue);
    // Comunicaciones comerciales (segundo interruptor)
    await t.tap(find.byType(Switch).at(1));
    await t.pumpAndSettle();
    expect(repo.legal.marketing, isTrue);
    await t.ensureVisible(find.text('Eliminar mi cuenta'));
    await t.tap(find.text('Eliminar mi cuenta'));
    await t.pumpAndSettle();
    expect(find.text('¿Eliminar tu cuenta para siempre?'), findsOneWidget);
    await t.tap(find.text('Eliminar'));
    await t.pumpAndSettle();
    expect(repo.deleted, isFalse, reason: 'sin escribir ELIMINAR no se borra');
    await t.enterText(find.byType(TextField), 'eliminar');
    await t.pump();
    await t.tap(find.text('Eliminar'));
    await t.pump(const Duration(milliseconds: 500));   // queda el indicador de progreso hasta que la guardia lleva a /welcome
    expect(repo.deleted, isTrue);
  });
}
