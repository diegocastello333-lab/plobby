import 'dart:async';
import 'package:flutter/foundation.dart';

/// Cuántas operaciones de red/carga hay en curso (peticiones a Supabase, código de pantallas que se descarga en la web).
/// Lo lee [LoadingBar] para enseñar una barra de carga solo cuando algo tarda.
class NetActivity {
  NetActivity._();
  static final inFlight = ValueNotifier<int>(0);

  static void begin() => inFlight.value++;
  static void end() { if (inFlight.value > 0) inFlight.value--; }

  /// Cuenta [f] como actividad mientras dura.
  static Future<T> track<T>(Future<T> f) {
    begin();
    return f.whenComplete(end);
  }
}
