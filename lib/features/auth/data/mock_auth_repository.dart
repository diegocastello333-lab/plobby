import 'dart:async';
import '../domain/auth_models.dart';
import '../domain/legal.dart';
import 'auth_repository.dart';

/// MOCK para desarrollo/tests: NO autentica con Google. La app real usa SupabaseAuthRepository (supabase/integration).
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({OnboardingData? initial, this.taken = const {'diego.c', 'plobby', 'admin'}}) : _data = initial ?? const OnboardingData();
  final Set<String> taken;
  OnboardingData _data;
  AuthUser? _user;
  final _ctl = StreamController<AuthUser?>.broadcast();
  bool failNextSave = false;

  @override
  AuthUser? get currentUser => _user;
  @override
  Stream<AuthUser?> authChanges() => _ctl.stream;
  @override
  Future<void> signInWithGoogle() async { _user = const AuthUser(id: 'u1', email: 'demo@example.com', displayName: 'Demo'); _ctl.add(_user); }
  @override
  Future<void> signOut() async { _user = null; _ctl.add(null); }
  @override
  Future<OnboardingData> loadOnboarding() async => _data;
  @override
  Future<bool> isUsernameAvailable(String u) async => isValidUsername(u) && !taken.contains(u.toLowerCase());
  @override
  Future<void> saveStep(int step, OnboardingData d) async {
    if (failNextSave) { failNextSave = false; throw AuthException('network'); }
    if (step == 1 && taken.contains(d.username.toLowerCase())) throw AuthException('username_taken');
    _data = d;
  }
  @override
  Future<String> uploadAvatar(List<int> bytes, String mime) async => 'https://example.invalid/avatars/u1/${bytes.length}';
  /// Llamadas a [deleteAvatarFiles] (para los tests): la URL que se conservó en cada una.
  final deletedKeeping = <String?>[];
  @override
  Future<void> deleteAvatarFiles({String? keepUrl}) async => deletedKeeping.add(keepUrl);
  @override
  Future<void> completeOnboarding() async {
    if (pendingSteps(_data).where((s) => s != 4).isNotEmpty) throw AuthException('onboarding_incomplete');
    _data = _data.copyWith(completed: true);
  }

  // ── Legal (modo demo y tests): por defecto ya aceptado; `legal` permite simular pendientes ──
  LegalStatus legal = const LegalStatus(requiredOk: true);
  int exports = 0;
  bool deleted = false;
  @override
  Future<LegalStatus> legalStatus() async => legal;
  @override
  Future<LegalStatus> acceptLegal({required bool marketing}) async => legal = LegalStatus(requiredOk: true, marketing: marketing);
  @override
  Future<void> setMarketing(bool accept) async => legal = LegalStatus(requiredOk: legal.requiredOk, pending: legal.pending, marketing: accept);
  @override
  Future<String> exportMyData() async { exports++; return '{"format":"plobby-export","version":1,"user_id":"${_user?.id ?? 'demo'}"}'; }
  @override
  Future<void> deleteAccount() async { deleted = true; await signOut(); }
  @override
  Future<void> signOutEverywhere() => signOut();
}
