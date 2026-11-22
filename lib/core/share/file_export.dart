/// Guardar un archivo de texto generado por la app (p. ej. «Descargar mis datos» en JSON).
/// Móvil: hoja de compartir del sistema (Guardar en Archivos / Drive / enviar). Web: descarga directa.
export 'file_export_native.dart' if (dart.library.js_interop) 'file_export_web.dart';
