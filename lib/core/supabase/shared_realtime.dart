import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Canal de Supabase Realtime compartido: muchos oyentes, UNA sola suscripción.
///
/// Antes cada provider abría su propio canal con el mismo nombre (`groups:<uid>`, `chat:<id>`…). El servidor de
/// Realtime (Phoenix) cierra el canal anterior cuando se une otro con el mismo tema en el mismo socket, así que abrir la
/// info de un grupo dejaba sin tiempo real la lista de conversaciones y los mensajes «a veces» no llegaban.
///
/// - El canal se abre con el primer oyente y se cierra con el último (StreamController.broadcast).
/// - Los temas no privados llevan un sufijo único; los privados (`user:<uid>`, autorizados por RLS en
///   `realtime.messages`) necesitan el tema exacto y por eso solo debe existir una instancia por tema.
/// - [resyncs] emite cuando el canal vuelve a quedar suscrito tras un corte de conexión: los eventos perdidos durante
///   el corte no se reenvían, así que los consumidores recargan sus datos.
class SharedRealtime<T> {
  SharedRealtime(this._db, this._topic, this._bind, {this.private = false});
  final SupabaseClient _db;
  final String _topic;
  final bool private;
  final void Function(RealtimeChannel channel, void Function(T event) emit) _bind;

  static int _seq = 0;
  RealtimeChannel? _channel;
  bool _wasSubscribed = false;
  late final StreamController<T> _events = StreamController<T>.broadcast(onListen: _open, onCancel: _close);
  final StreamController<void> _resyncs = StreamController<void>.broadcast();

  Stream<T> get events => _events.stream;
  Stream<void> get resyncs => _resyncs.stream;

  void _open() {
    final ch = _db.channel(private ? _topic : '$_topic:${_seq++}', opts: RealtimeChannelConfig(private: private));
    _bind(ch, (e) { if (!_events.isClosed) _events.add(e); });
    _channel = ch;
    ch.subscribe((status, _) {
      if (status != RealtimeSubscribeStatus.subscribed) return;
      if (_wasSubscribed && !_resyncs.isClosed) _resyncs.add(null);
      _wasSubscribed = true;
    });
  }

  void _close() {
    final ch = _channel;
    _channel = null;
    _wasSubscribed = false;
    if (ch != null) unawaited(_db.removeChannel(ch));
  }
}
