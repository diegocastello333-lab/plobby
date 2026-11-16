import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../net/network_status.dart';

/// Excepciones propias de cada funcionalidad que llevan un código ('network', 'not_friends', 'server'…). Permite
/// clasificarlas aquí sin que el núcleo dependa de cada funcionalidad.
abstract interface class CodedFailure {
  String get code;
}

/// Qué ha fallado DE VERDAD. Cada caso tiene su texto y su tratamiento (antes todo se mostraba como «no hay conexión»,
/// también un error de datos con Supabase respondiendo 200).
enum FailureKind {
  /// El dispositivo no tiene ninguna red.
  offline,
  /// Hay red pero no llega a Internet (p. ej. una wifi sin salida o la cobertura justo al cambiar de red).
  noInternet,
  /// Hay Internet pero el servidor de Plobby no respondió.
  serviceUnavailable,
  /// La petición tardó demasiado.
  timeout,
  /// La sesión caducó o no es válida.
  auth,
  /// Sin permiso para ver o hacer eso (RLS / reglas del servidor).
  permission,
  /// El servidor respondió con un error.
  server,
  /// La respuesta llegó pero la app no pudo interpretarla (fallo nuestro, no de la conexión).
  data,
}

extension FailureKindX on FailureKind {
  bool get isConnectivity => this == FailureKind.offline || this == FailureKind.noInternet || this == FailureKind.serviceUnavailable || this == FailureKind.timeout;
  /// Reintentos automáticos seguros (solo LECTURAS: las pantallas con error vuelven a cargar).
  bool get autoRetry => isConnectivity;

  String get title => switch (this) {
        FailureKind.offline => 'Sin conexión',
        FailureKind.noInternet => 'Sin acceso a Internet',
        FailureKind.serviceUnavailable => 'Plobby no responde ahora mismo',
        FailureKind.timeout => 'Está tardando demasiado',
        FailureKind.auth => 'Tu sesión ha caducado',
        FailureKind.permission => 'No tienes acceso',
        FailureKind.server => 'Algo ha fallado en el servidor',
        FailureKind.data => 'No se pudo mostrar',
      };

  String get message => switch (this) {
        FailureKind.offline => 'Tu dispositivo no tiene red. Lo reintentaremos solos en cuanto vuelva.',
        FailureKind.noInternet => 'Hay red, pero no llega a Internet. Lo reintentaremos solos en cuanto vuelva.',
        FailureKind.serviceUnavailable => 'Tu conexión funciona, pero el servidor no ha respondido. Vuelve a intentarlo en unos segundos.',
        FailureKind.timeout => 'La red va lenta. Vuelve a intentarlo.',
        FailureKind.auth => 'Pulsa Reintentar para renovarla.',
        FailureKind.permission => 'Este contenido no está disponible para tu cuenta.',
        FailureKind.server => 'No es tu conexión. Vuelve a intentarlo en unos segundos.',
        FailureKind.data => 'No es tu conexión: algo no ha ido bien al leer los datos. Vuelve a intentarlo.',
      };
}

/// Clasificación inmediata (sin red). Para los fallos de red, [diagnose] afina si es «sin red», «sin Internet» o
/// «servidor caído».
FailureKind classifyError(Object e) {
  if (e is TimeoutException) return FailureKind.timeout;
  if (e is sb.AuthRetryableFetchException) return FailureKind.serviceUnavailable;
  if (e is sb.AuthException) {
    final s = int.tryParse(e.statusCode ?? '');
    return s != null && s >= 500 ? FailureKind.server : FailureKind.auth;
  }
  if (e is sb.PostgrestException) {
    final code = e.code ?? '';
    if (code == 'PGRST301' || code == 'PGRST303' || e.message.toLowerCase().contains('jwt')) return FailureKind.auth;
    if (code == '42501' || code == 'PGRST302' || code == 'PGRST116') return FailureKind.permission;   // sin permiso, o la RLS oculta la fila
    if (code.startsWith('08') || code == '57014') return FailureKind.serviceUnavailable;   // conexión BD / statement timeout
    return FailureKind.server;
  }
  if (e is sb.StorageException) {
    final s = int.tryParse(e.statusCode ?? '');
    return s == 401 ? FailureKind.auth : s == 403 ? FailureKind.permission : FailureKind.server;
  }
  if (e is http.ClientException) return NetworkStatus.isDeviceOffline ? FailureKind.offline : FailureKind.serviceUnavailable;
  if (e is CodedFailure) {
    final c = e.code;
    if (c == 'network') return NetworkStatus.isDeviceOffline ? FailureKind.offline : FailureKind.serviceUnavailable;
    if (c == 'not_authenticated') return FailureKind.auth;
    if (c == 'not_allowed' || c == 'not_friends' || c == 'forbidden') return FailureKind.permission;
    return FailureKind.server;
  }
  final t = e.runtimeType.toString();
  if (t == 'SocketException' || t == 'HandshakeException') return NetworkStatus.isDeviceOffline ? FailureKind.offline : FailureKind.serviceUnavailable;
  if (e is TypeError || e is FormatException || e is StateError || e is NoSuchMethodError || e is ArgumentError) return FailureKind.data;
  return FailureKind.server;
}

/// Clasificación completa. Si parece un problema de red, comprueba UNA vez si hay Internet (petición mínima a nuestro
/// propio dominio) para no culpar a la conexión del usuario cuando lo que falla es el servidor.
Future<FailureKind> diagnose(Object e) async {
  final k = classifyError(e);
  if (k != FailureKind.serviceUnavailable && k != FailureKind.timeout) return k;
  if (NetworkStatus.isDeviceOffline) return FailureKind.offline;
  final internet = await NetworkStatus.probeInternet();
  if (internet == false) return NetworkStatus.isDeviceOffline ? FailureKind.offline : FailureKind.noInternet;
  return k;   // hay Internet (o no se puede saber): el problema es el servidor o la lentitud, no la conexión del usuario
}

/// Antes de reintentar tras un error de sesión: renueva el token (p. ej. al volver de segundo plano en el iPhone, cuando
/// los temporizadores de renovación estuvieron dormidos).
Future<void> refreshSessionIfPossible() async {
  try {
    final auth = sb.Supabase.instance.client.auth;
    if (auth.currentSession != null) await auth.refreshSession();
  } catch (_) {/* sin Supabase (demo) o sin red: el reintento mostrará el estado real */}
}

/// Texto del aviso cuando una ACCIÓN falla (guardar, enviar, crear…). Clasificación inmediata, sin sondeo de red: solo
/// culpa a la conexión cuando de verdad es un fallo de conexión. Las acciones NUNCA se reintentan solas (podrían
/// duplicarse): la persona decide si repetir.
String actionErrorText(Object e, {String fallback = 'No se pudo completar. Inténtalo de nuevo.'}) => switch (classifyError(e)) {
      FailureKind.offline => 'Sin conexión: no se ha enviado. Inténtalo cuando vuelva la red.',
      FailureKind.noInternet || FailureKind.serviceUnavailable => 'No se pudo conectar con Plobby. Inténtalo de nuevo.',
      FailureKind.timeout => 'La red va lenta y no hubo respuesta. Comprueba si se guardó antes de repetir.',
      FailureKind.auth => 'Tu sesión ha caducado. Vuelve a intentarlo.',
      FailureKind.permission => 'No tienes permiso para hacer esto.',
      FailureKind.server || FailureKind.data => fallback,
    };
