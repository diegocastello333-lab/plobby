import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../data/mock_auth_repository.dart';
import '../domain/auth_models.dart';

/// En main.dart sustituye por SupabaseAuthRepository (ver supabase/integration/supabase_auth_repository.dart.txt).
final authRepositoryProvider = Provider<AuthRepository>((ref) => MockAuthRepository());

final authStateProvider = StreamProvider<AuthUser?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield repo.currentUser;            // sesión persistida (Supabase la restaura al iniciar)
  yield* repo.authChanges();
});

class OnboardingState {
  const OnboardingState({this.data = const OnboardingData(), this.pending = const [1], this.step = 1, this.usernameAvailable, this.checkingUsername = false,
      this.busy = false, this.error, this.errors = const {}, this.loaded = false});
  final OnboardingData data;
  final List<int> pending;          // pasos que le faltan a ESTE usuario (calculados al cargar)
  final int step;
  final bool? usernameAvailable;    // null = sin comprobar
  final bool checkingUsername, busy, loaded;
  final String? error;
  final Map<String, String> errors;
  int get position => pending.indexOf(step) + 1;
  OnboardingState copyWith({OnboardingData? data, List<int>? pending, int? step, Object? usernameAvailable = _k, bool? checkingUsername, bool? busy, Object? error = _k, Map<String, String>? errors, bool? loaded}) =>
      OnboardingState(data: data ?? this.data, pending: pending ?? this.pending, step: step ?? this.step,
          usernameAvailable: identical(usernameAvailable, _k) ? this.usernameAvailable : usernameAvailable as bool?, checkingUsername: checkingUsername ?? this.checkingUsername,
          busy: busy ?? this.busy, error: identical(error, _k) ? this.error : error as String?, errors: errors ?? this.errors, loaded: loaded ?? this.loaded);
}
const _k = Object();

class OnboardingController extends Notifier<OnboardingState> {
  Timer? _debounce;
  @override
  OnboardingState build() { ref.onDispose(() => _debounce?.cancel()); Future.microtask(load); return const OnboardingState(); }
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Reanuda: carga lo guardado en el servidor y solo muestra los pasos pendientes.
  Future<void> load() async {
    final d = await _repo.loadOnboarding();
    final p = pendingSteps(d);
    state = state.copyWith(data: d, pending: p, step: p.first, loaded: true, usernameAvailable: d.username.isNotEmpty ? true : null);
  }

  void update(OnboardingData d) => state = state.copyWith(data: d, errors: const {}, error: null);

  /// Comprobación de username en tiempo real (debounce 400 ms; ignora respuestas obsoletas).
  void usernameChanged(String raw) {
    final u = raw.trim().toLowerCase();
    state = state.copyWith(data: state.data.copyWith(username: u), usernameAvailable: null, checkingUsername: isValidUsername(u), errors: const {});
    _debounce?.cancel();
    if (!isValidUsername(u)) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final ok = await _repo.isUsernameAvailable(u);
        if (state.data.username == u) state = state.copyWith(usernameAvailable: ok, checkingUsername: false);
      } catch (_) {
        if (state.data.username == u) state = state.copyWith(checkingUsername: false, error: 'No se pudo comprobar el usuario. Reintenta.');
      }
    });
  }

  void back() { final i = state.pending.indexOf(state.step); if (i > 0) state = state.copyWith(step: state.pending[i - 1], error: null); }

  /// Valida el paso actual, lo guarda en Supabase y avanza. En el paso 4 completa el onboarding.
  Future<bool> next() async {
    final s = state.step, d = state.data;
    if (s == 1) { final e = validateStep1(d, usernameAvailable: state.usernameAvailable); if (e.isNotEmpty) { state = state.copyWith(errors: e); return false; } }
    if (s == 2 && !step2Complete(d)) { state = state.copyWith(errors: {'level': 'Completa nivel, posición y mano dominante.'}); return false; }
    if (s == 3 && !step3Complete(d)) { state = state.copyWith(errors: {'avatar': 'Sube una foto o elige un avatar para continuar.'}); return false; }
    state = state.copyWith(busy: true, error: null);
    try {
      if (s == 4) { await _repo.completeOnboarding(); state = state.copyWith(busy: false, data: d.copyWith(completed: true)); return true; }
      await _repo.saveStep(s, d);
      final i = state.pending.indexOf(s);
      state = state.copyWith(busy: false, step: i + 1 < state.pending.length ? state.pending[i + 1] : 4);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(busy: false, error: e.code == 'username_taken' ? 'Ese usuario ya está en uso.' : 'No se pudo guardar. Revisa tu conexión y reinténtalo.', usernameAvailable: e.code == 'username_taken' ? false : state.usernameAvailable);
      return false;
    }
  }

  /// Foto de galería: sube a Storage y guarda la URL (sustituye al avatar). `bytes` ya viene redimensionado por la UI.
  Future<void> pickPhoto(List<int> bytes, String mime) async {
    if (!const ['image/jpeg', 'image/png', 'image/webp'].contains(mime) || bytes.length > 5 * 1024 * 1024) { state = state.copyWith(errors: {'avatar': 'Elige una imagen JPG/PNG/WebP de menos de 5 MB.'}); return; }
    state = state.copyWith(busy: true, errors: const {});
    try { final url = await _repo.uploadAvatar(bytes, mime); state = state.copyWith(busy: false, data: state.data.copyWith(avatarUrl: url, clearAvatarId: true)); }
    catch (_) { state = state.copyWith(busy: false, errors: {'avatar': 'No se pudo subir la imagen. Inténtalo de nuevo.'}); }
  }
  void pickAvatar(String id) => state = state.copyWith(data: state.data.copyWith(avatarId: id, clearAvatarUrl: true), errors: const {});
}
final onboardingProvider = NotifierProvider<OnboardingController, OnboardingState>(OnboardingController.new);
