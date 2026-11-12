import 'dart:async';
import 'package:http/http.dart' as http;

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
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request).timeout(limitFor(request));

  @override
  void close() => _inner.close();
}
