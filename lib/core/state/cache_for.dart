import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mantiene vivo un provider `autoDispose` durante [d] después de que nadie lo escuche: volver a una pantalla de
/// detalle (liga, Head to Head, club…) poco después la muestra al instante en vez de pedir los datos otra vez.
/// Si alguien vuelve a escucharlo antes, el temporizador se cancela. Invalidarlo (tirar para refrescar, Realtime)
/// sigue funcionando igual.
extension CacheFor on Ref {
  void cacheFor(Duration d) {
    final link = keepAlive();
    Timer? t;
    onCancel(() { t?.cancel(); t = Timer(d, link.close); });
    onResume(() { t?.cancel(); t = null; });
    onDispose(() => t?.cancel());
  }
}
