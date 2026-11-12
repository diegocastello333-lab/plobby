import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Presencia («En línea» / «Desconectado») con Supabase Realtime Presence + heartbeat y caducidad.
///
/// - Cada usuario publica su presencia SOLO en su canal privado `presence:<uid>` mientras la app está en primer plano
///   ([setActive]); al pasar a segundo plano se retira.
/// - Sus amigos escuchan ese canal (política RLS `plobby_presence_read`: solo amigos). No se usa «última conexión»:
///   el servidor elimina la presencia cuando el socket deja de responder a su heartbeat (cierre forzado, sin red…),
///   así nadie se queda «en línea» por una sesión mal cerrada.
abstract class PresenceService {
  /// La app está activa (primer plano) o no.
  void setActive(bool active);
  /// ¿Está ese amigo en línea ahora? Emite el valor actual y cada cambio.
  Stream<bool> watch(String userId);
}

/// Modo demo y sin sesión: nadie aparece en línea.
class NoPresenceService implements PresenceService {
  const NoPresenceService();
  @override
  void setActive(bool active) {}
  @override
  Stream<bool> watch(String userId) => Stream.value(false);
}

/// Cada cuánto se renueva la presencia propia (heartbeat) y a partir de cuánto se considera caducada la de un amigo.
const presenceHeartbeat = Duration(seconds: 30);
const presenceExpiry = Duration(seconds: 75);

class SupabasePresenceService implements PresenceService {
  SupabasePresenceService(this._db, this._me);
  final SupabaseClient _db;
  final String _me;
  RealtimeChannel? _own;
  bool _active = false, _ownJoined = false;
  Timer? _heartbeat;
  final _watchers = <String, _Watch>{};

  @override
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _heartbeat?.cancel();
    if (active) {
      // Heartbeat: se vuelve a publicar la presencia cada 30 s. Los amigos la dan por caducada si pasan 75 s sin
      // renovarse (app congelada o cerrada sin avisar, red caída), aunque el servidor aún no la haya retirado.
      _heartbeat = Timer.periodic(presenceHeartbeat, (_) { if (_active && _ownJoined) unawaited(_track()); });
      if (_own == null) {
        _own = _db.channel('presence:$_me', opts: const RealtimeChannelConfig(private: true, enabled: true))
          ..subscribe((s, _) {
            _ownJoined = s == RealtimeSubscribeStatus.subscribed;
            if (_ownJoined && _active) unawaited(_track());   // también tras reconectar
          });
      } else if (_ownJoined) {
        unawaited(_track());
      }
    } else if (_ownJoined) {
      unawaited(_own!.untrack().then((_) {}, onError: (_) {}));
    }
  }

  Future<void> _track() async {
    try { await _own?.track({'online_at': DateTime.now().toUtc().toIso8601String()}); } catch (_) {/* se reintenta al reconectar */}
  }

  @override
  Stream<bool> watch(String userId) => (_watchers[userId] ??= _Watch(_db, userId, () => _watchers.remove(userId))).stream;
}

/// Un canal por amigo observado, compartido por todas las pantallas que lo muestran y cerrado al dejar de usarse.
class _Watch {
  _Watch(this._db, this._uid, this._onClosed) {
    _ctl = StreamController<bool>.broadcast(onListen: _open, onCancel: _close);
  }
  final SupabaseClient _db;
  final String _uid;
  final void Function() _onClosed;
  late final StreamController<bool> _ctl;
  RealtimeChannel? _ch;
  Timer? _expiry;
  bool _online = false;
  /// Última vez (reloj de ESTE móvil) que llegó una presencia o su renovación: evita depender de que los relojes de
  /// los dos dispositivos coincidan.
  DateTime? _lastSeen;

  Stream<bool> get stream async* {
    yield _online;
    yield* _ctl.stream;
  }

  void _set(bool v) {
    if (v == _online) return;
    _online = v;
    if (!_ctl.isClosed) _ctl.add(v);
  }

  /// Hay presencia publicada y se ha renovado hace menos de [presenceExpiry].
  void _evaluate() {
    final present = _ch?.presenceState().any((p) => p.presences.isNotEmpty) ?? false;
    final fresh = _lastSeen != null && DateTime.now().difference(_lastSeen!) < presenceExpiry;
    _set(present && fresh);
  }

  void _seen() { _lastSeen = DateTime.now(); _evaluate(); }

  void _open() {
    _ch = _db.channel('presence:$_uid', opts: const RealtimeChannelConfig(private: true, enabled: true))
      ..onPresenceSync((_) => _seen())
      ..onPresenceJoin((_) => _seen())        // también llega con cada renovación (heartbeat)
      ..onPresenceLeave((_) => _evaluate())
      ..subscribe((s, _) {
        // Sin conexión no sabemos si sigue en línea: mejor «Desconectado» que un dato antiguo.
        if (s != RealtimeSubscribeStatus.subscribed) { _lastSeen = null; _set(false); }
      });
    _expiry = Timer.periodic(const Duration(seconds: 15), (_) => _evaluate());
  }

  void _close() {
    final ch = _ch;
    _ch = null;
    _expiry?.cancel();
    _online = false;
    _lastSeen = null;
    if (ch != null) unawaited(_db.removeChannel(ch));
    _onClosed();
  }
}

final presenceServiceProvider = Provider<PresenceService>((ref) => const NoPresenceService());

/// Estado en línea de un amigo (se actualiza solo mientras alguna pantalla lo muestra).
final onlineProvider = StreamProvider.autoDispose.family<bool, String>((ref, userId) => ref.watch(presenceServiceProvider).watch(userId));
