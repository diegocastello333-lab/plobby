import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Presencia («En línea» / «Desconectado») con Supabase Realtime Presence.
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

class SupabasePresenceService implements PresenceService {
  SupabasePresenceService(this._db, this._me);
  final SupabaseClient _db;
  final String _me;
  RealtimeChannel? _own;
  bool _active = false, _ownJoined = false;
  final _watchers = <String, _Watch>{};

  @override
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active) {
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
  bool _online = false;

  Stream<bool> get stream async* {
    yield _online;
    yield* _ctl.stream;
  }

  void _emit() {
    final now = _ch?.presenceState().any((p) => p.presences.isNotEmpty) ?? false;
    if (now == _online) return;
    _online = now;
    if (!_ctl.isClosed) _ctl.add(now);
  }

  void _open() {
    _ch = _db.channel('presence:$_uid', opts: const RealtimeChannelConfig(private: true, enabled: true))
      ..onPresenceSync((_) => _emit())
      ..onPresenceJoin((_) => _emit())
      ..onPresenceLeave((_) => _emit())
      ..subscribe((s, _) {
        // Sin conexión no sabemos si sigue en línea: mejor mostrar «Desconectado» que un dato antiguo.
        if (s != RealtimeSubscribeStatus.subscribed && _online) { _online = false; if (!_ctl.isClosed) _ctl.add(false); }
      });
  }

  void _close() {
    final ch = _ch;
    _ch = null;
    _online = false;
    if (ch != null) unawaited(_db.removeChannel(ch));
    _onClosed();
  }
}

final presenceServiceProvider = Provider<PresenceService>((ref) => const NoPresenceService());

/// Estado en línea de un amigo (se actualiza solo mientras alguna pantalla lo muestra).
final onlineProvider = StreamProvider.autoDispose.family<bool, String>((ref, userId) => ref.watch(presenceServiceProvider).watch(userId));
