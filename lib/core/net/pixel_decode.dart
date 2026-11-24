import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

/// Decodifica una foto (JPEG/PNG/WebP) en Dart y crea la imagen desde píxeles RGBA. Se usa en la web para las imágenes
/// para compartir: en Safari (iPhone) las imágenes decodificadas por el navegador y redimensionadas dejaban la
/// vista previa de Share Match en blanco. Con píxeles propios no se depende del decodificador del navegador.
/// Se importa con `deferred as`: el paquete `image` solo se descarga al compartir.
Future<ui.Image?> decodeToPixels(Uint8List bytes, int targetWidth) async {
  img.Image? decoded;
  try { decoded = img.decodeImage(bytes); } catch (_) { return null; }
  if (decoded == null) return null;
  final small = decoded.width > targetWidth ? img.copyResize(decoded, width: targetWidth, interpolation: img.Interpolation.average) : decoded;
  final rgba = small.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba.getBytes(order: img.ChannelOrder.rgba), rgba.width, rgba.height, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}
