import 'dart:async';
import 'dart:js_interop';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Web (Safari en iPhone incluido).
///
/// - navigator.onLine == false SÍ es fiable (no hay ninguna red); == true NO garantiza Internet (Safari lo pone a true con
///   cualquier red, aunque no navegue). Por eso solo se usa para el caso 1.
/// - Los eventos online/offline de Safari a veces no llegan al cambiar de wifi a datos; da igual: no bloquean nada, solo
///   sirven para reintentar antes. Lo que manda es el resultado de cada petición.
class NetworkStatus {
  NetworkStatus._();
  static final _restored = StreamController<void>.broadcast();
  static final _offline = StreamController<bool>.broadcast();
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    web.window.addEventListener('online', ((web.Event _) { _offline.add(false); _restored.add(null); }).toJS);
    web.window.addEventListener('offline', ((web.Event _) => _offline.add(true)).toJS);
  }

  static bool get isDeviceOffline {
    try { return !web.window.navigator.onLine; } catch (_) { return false; }
  }

  /// Emite cuando el navegador recupera la red: las pantallas con error reintentan solas.
  static Stream<void> get restored { _listen(); return _restored.stream; }

  /// true al perder la red, false al recuperarla.
  static Stream<bool> get offlineChanges { _listen(); return _offline.stream; }

  /// ¿Llega a Internet? Pide `version.json` de nuestro propio dominio saltándose cualquier caché (el service worker no lo
  /// guarda nunca). Mismo origen: sin CORS ni terceros. true = hay Internet; false = no.
  static Future<bool?> probeInternet() async {
    try {
      final url = Uri.base.resolve('version.json').replace(queryParameters: {'probe': '${DateTime.now().millisecondsSinceEpoch}'});
      final res = await http.get(url, headers: {'cache-control': 'no-cache'}).timeout(const Duration(seconds: 5));
      return res.statusCode > 0;
    } catch (_) {
      return false;
    }
  }
}
