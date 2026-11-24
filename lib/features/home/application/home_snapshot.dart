import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../matches/application/lifecycle_providers.dart' show currentUserIdProvider;

/// Lo último que se vio en la cabecera del Inicio (nombre, foto, banner y contadores), guardado en el dispositivo por
/// usuario. Al abrir la app se pinta AL INSTANTE con esto y se actualiza en segundo plano cuando llegan los datos
/// (stale-while-revalidate).
///
/// Privacidad: solo datos que ya se ven en el propio perfil público y cifras. NUNCA mensajes, notificaciones ni datos
/// de terceros (eso siempre se pide al servidor).
class HomeSnapshot {
  const HomeSnapshot({required this.name, this.avatarUrl, this.bannerId, this.friends = 0, this.elo, this.delta30, this.streak = 0, this.bestStreak = 0});
  final String name;
  final String? avatarUrl, bannerId;
  final int friends, streak, bestStreak;
  final int? elo, delta30;

  Map<String, Object?> toJson() => {'v': 1, 'name': name, 'avatarUrl': avatarUrl, 'bannerId': bannerId, 'friends': friends,
        'elo': elo, 'delta30': delta30, 'streak': streak, 'bestStreak': bestStreak};

  static HomeSnapshot? fromJson(Object? j) {
    if (j is! Map || j['v'] != 1 || j['name'] is! String) return null;
    int? n(Object? x) => x is num ? x.toInt() : null;
    return HomeSnapshot(name: j['name'] as String, avatarUrl: j['avatarUrl'] as String?, bannerId: j['bannerId'] as String?,
        friends: n(j['friends']) ?? 0, elo: n(j['elo']), delta30: n(j['delta30']), streak: n(j['streak']) ?? 0, bestStreak: n(j['bestStreak']) ?? 0);
  }

  @override
  bool operator ==(Object o) => o is HomeSnapshot && jsonEncode(toJson()) == jsonEncode(o.toJson());
  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Almacén local de la instantánea. Se carga en `main()` antes del primer fotograma (lectura síncrona después).
class HomeSnapshotStore {
  HomeSnapshotStore._();
  static SharedPreferences? _prefs;
  static String _key(String uid) => 'plobby.home_snapshot.$uid';

  static Future<void> load() async {
    try { _prefs = await SharedPreferences.getInstance(); } catch (_) {/* sin almacenamiento: sin instantánea */}
  }

  static HomeSnapshot? read(String uid) {
    try {
      final raw = _prefs?.getString(_key(uid));
      return raw == null ? null : HomeSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static void write(String uid, HomeSnapshot s) {
    try { _prefs?.setString(_key(uid), jsonEncode(s.toJson())); } catch (_) {/* no crítico */}
  }

  /// Solo para tests.
  static void debugReset([SharedPreferences? prefs]) => _prefs = prefs;
}

/// Instantánea del usuario actual (null la primera vez o en modo demo).
final homeSnapshotProvider = Provider<HomeSnapshot?>((ref) => HomeSnapshotStore.read(ref.watch(currentUserIdProvider)));
