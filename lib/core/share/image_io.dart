/// Guardar, compartir y copiar imágenes PNG (resúmenes de partido, stats, Head to Head, Wrapped, ranking).
///
/// Una sola API con dos implementaciones elegidas al compilar:
/// - Android / iOS (`image_io_native.dart`): galería con `gal` y hoja del sistema con un PNG temporal.
/// - Web (`image_io_web.dart`): Web Share API con el archivo (en iPhone ofrece «Guardar imagen», WhatsApp, Instagram…),
///   Clipboard API para copiar y descarga como último recurso.
library;

export 'image_io_types.dart';
export 'image_io_native.dart' if (dart.library.js_interop) 'image_io_web.dart';
