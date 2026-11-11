import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plobby/core/router/app_router.dart';
import 'package:plobby/features/auth/application/auth_providers.dart';
import 'package:plobby/features/auth/data/mock_auth_repository.dart';
import 'package:plobby/features/auth/domain/auth_models.dart';

OnboardingData full() => OnboardingData(firstName: 'Nuria', lastName: 'Díaz', username: 'nuria.d', city: 'Madrid', birthDate: DateTime(1996, 5, 2), selfLevel: SelfLevel.intermediate, side: CourtSide.left, hand: Hand.right, avatarId: 'a5');

void main() {
  test('username: formato y minúsculas', () {
    expect(isValidUsername('nuria.d'), isTrue);
    expect(isValidUsername('Nu'), isFalse);
    expect(isValidUsername('con espacio'), isFalse);
    expect(isValidUsername('MAYUS'), isFalse);
  });
  test('fecha de nacimiento: mínimo 14 años y no futura', () {
    final now = DateTime(2026, 11, 11);
    expect(isBirthDateValid(DateTime(2015, 1, 1), now: now), isFalse);
    expect(isBirthDateValid(DateTime(2012, 11, 11), now: now), isTrue);
    expect(isBirthDateValid(DateTime(2027, 1, 1), now: now), isFalse);
    expect(isBirthDateValid(null, now: now), isFalse);
  });
  test('pendingSteps: usuario nuevo ve todo; existente solo lo que falta', () {
    expect(pendingSteps(const OnboardingData()), [1, 2, 3, 4]);
    expect(pendingSteps(full().copyWith(avatarId: null, clearAvatarId: true)), [3, 4]);
    expect(pendingSteps(full()), [4]);
    expect(pendingSteps(full().copyWith(completed: true)), isEmpty);
  });
  test('validateStep1 exige disponibilidad comprobada', () {
    final d = full();
    expect(validateStep1(d, usernameAvailable: true, now: DateTime(2026, 11, 11)), isEmpty);
    expect(validateStep1(d, usernameAvailable: false)['username'], contains('en uso'));
    expect(validateStep1(d, usernameAvailable: null)['username'], isNotNull);
  });
  test('avatar: foto O avatar predefinido', () {
    expect(step3Complete(const OnboardingData()), isFalse);
    expect(step3Complete(const OnboardingData(avatarId: 'a3')), isTrue);
    expect(step3Complete(const OnboardingData(avatarUrl: 'https://x/y.jpg')), isTrue);
    expect(isValidAvatarId('a12'), isTrue); expect(isValidAvatarId('a13'), isFalse);
  });
  test('el nivel declarado es independiente del ELO (solo etiquetas)', () {
    expect(SelfLevel.advanced.label, 'Avanzado');
    expect(SelfLevel.upperIntermediate.db, 'upper_intermediate');
  });
  test('guardia de rutas', () {
    expect(authRedirect(signedIn: false, onboardingDone: false, location: '/feed'), '/welcome');
    expect(authRedirect(signedIn: false, onboardingDone: false, location: '/welcome'), isNull);
    expect(authRedirect(signedIn: true, onboardingDone: false, location: '/feed'), '/onboarding');
    expect(authRedirect(signedIn: true, onboardingDone: true, location: '/welcome'), '/home');
    expect(authRedirect(signedIn: true, onboardingDone: true, location: '/profile'), isNull);
  });
  test('onboarding reanudable: carga lo guardado y salta pasos completos', () async {
    final repo = MockAuthRepository(initial: full().copyWith(avatarId: null, clearAvatarId: true));
    final c = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    c.read(onboardingProvider);
    await Future<void>.delayed(Duration.zero); await Future<void>.delayed(Duration.zero);
    final s = c.read(onboardingProvider);
    expect(s.pending, [3, 4]); expect(s.step, 3);
  });
  test('onboarding: sin foto/avatar no avanza; con avatar guarda y llega a la bienvenida', () async {
    final repo = MockAuthRepository(initial: full().copyWith(avatarId: null, clearAvatarId: true));
    final c = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    final n = c.read(onboardingProvider.notifier);
    await Future<void>.delayed(Duration.zero); await Future<void>.delayed(Duration.zero);
    expect(await n.next(), isFalse);
    expect(c.read(onboardingProvider).errors['avatar'], isNotNull);
    n.pickAvatar('a5');
    expect(await n.next(), isTrue);
    expect(c.read(onboardingProvider).step, 4);
    expect(await n.next(), isTrue);
    expect(c.read(onboardingProvider).data.completed, isTrue);
  });
  test('error de red al guardar: no avanza y muestra error', () async {
    final repo = MockAuthRepository(initial: full().copyWith(avatarId: null, clearAvatarId: true))..failNextSave = true;
    final c = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    final n = c.read(onboardingProvider.notifier);
    await Future<void>.delayed(Duration.zero); await Future<void>.delayed(Duration.zero);
    n.pickAvatar('a2');
    expect(await n.next(), isFalse);
    expect(c.read(onboardingProvider).error, isNotNull);
    expect(c.read(onboardingProvider).step, 3);
  });
  test('un usuario con username ya cogido no puede guardar (carrera)', () async {
    final repo = MockAuthRepository(initial: const OnboardingData(firstName: 'Ana', lastName: 'Ruiz', username: 'diego.c', city: 'Madrid'));
    expect(() => repo.saveStep(1, const OnboardingData(username: 'diego.c')), throwsA(isA<Object>()));
  });
}
