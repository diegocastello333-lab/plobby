import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Portada 16:9 recortada al centro, 1200 px como mucho y JPEG 82 (en un isolate en el móvil): ligera y sin deformar.
///
/// Vive en su propio archivo porque se importa con `deferred as`: el paquete `image` (≈230 KB, el 7,7 % del JavaScript
/// de la versión web) solo se descarga cuando alguien elige una portada, no al abrir la app.
Uint8List prepareTournamentCover(Uint8List raw) {
  var im = img.decodeImage(raw);
  if (im == null) throw const FormatException('imagen no válida');
  im = img.bakeOrientation(im);
  const ratio = 16 / 9;
  var w = im.width, h = (im.width / ratio).round();
  if (h > im.height) { h = im.height; w = (im.height * ratio).round(); }
  im = img.copyCrop(im, x: (im.width - w) ~/ 2, y: (im.height - h) ~/ 2, width: w, height: h);
  if (im.width > 1200) im = img.copyResize(im, width: 1200, height: (1200 / ratio).round(), interpolation: img.Interpolation.cubic);
  return Uint8List.fromList(img.encodeJpg(im, quality: 82));
}
