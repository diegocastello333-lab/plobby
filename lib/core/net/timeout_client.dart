import 'dart:async';
import 'package:http/http.dart' as http;
import 'net_activity.dart';

/// Cliente HTTP de Supabase con límite de tiempo: una consulta que no responde (cobertura mala, red que «se queda
/// colgada») termina en [TimeoutException] en vez de dejar la pantalla cargando para siempre. Cada repositorio ya
/// traduce ese error a «revisa tu conexión» y la acción se puede repetir.
///
/// - Consultas y RPC: [requestTimeout] (por defecto 20 s).
/// - Subidas a Storage (fotos, banner): [uploadTimeout] (por defecto 60 s).
/// Realtime no pasa por aquí (usa WebSocket con su propio heartbeat).
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient([http.Client? inner, this.requestTimeout = const Duration(seconds: 20), this.uploadTimeout = const Duration(seconds: 60)])
      : _inner = inner ?? http.Client();
  final http.Client _inner;
  final Duration requestTimeout, uploadTimeout;

  /// Límite que corresponde a la petición (las subidas a Storage pueden tardar más que una consulta).
  Duration limitFor(http.BaseRequest r) =>
      r.url.path.contains('/storage/v1/object') && (r.method == 'POST' || r.method == 'PUT') ? uploadTimeout : requestTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Cuenta la petición hasta que llega el cuerpo completo (o falla): alimenta la barra de carga global.
    NetActivity.begin();
    var ended = false;
    void end() { if (!ended) { ended = true; NetActivity.end(); } }
    try {
      final r = await _inner.send(request).timeout(limitFor(request));
      final body = r.stream.transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleDone: (sink) { end(); sink.close(); },
          handleError: (e, st, sink) { end(); sink.addError(e, st); }));
      return http.StreamedResponse(body, r.statusCode, contentLength: r.contentLength, request: r.request, headers: r.headers,
          isRedirect: r.isRedirect, persistentConnection: r.persistentConnection, reasonPhrase: r.reasonPhrase);
    } catch (_) {
      end();
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
