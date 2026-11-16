/// Estado REAL de la red, distinguiendo tres situaciones que antes la app mezclaba en «no hay conexión»:
///  1. el dispositivo no tiene red ([isDeviceOffline]: navigator.onLine == false en la web);
///  2. hay red pero no llega a Internet;
///  3. hay Internet pero Supabase no responde.
/// 2 y 3 se distinguen con [probeInternet] (una petición mínima a nuestro propio dominio, sin caché) SOLO cuando una
/// petición ya ha fallado: no hay sondeos periódicos que gasten batería ni datos.
library;

export 'network_status_native.dart' if (dart.library.js_interop) 'network_status_web.dart';
