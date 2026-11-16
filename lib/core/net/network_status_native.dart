import 'dart:async';

/// Android/iOS nativos: el sistema ya informa de los fallos de red en cada petición (SocketException); no hay
/// navigator.onLine. La reconexión se detecta al volver a primer plano (LiveSync).
class NetworkStatus {
  NetworkStatus._();
  static bool get isDeviceOffline => false;
  static Stream<void> get restored => const Stream.empty();
  static Stream<bool> get offlineChanges => const Stream.empty();
  /// null = no se puede saber en esta plataforma.
  static Future<bool?> probeInternet() async => null;
}
