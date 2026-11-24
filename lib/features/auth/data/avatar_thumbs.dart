import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Miniaturas cuadradas (recorte central) en JPEG calidad 75 para los lados indicados. Se importa con `deferred as`: el
/// paquete `image` solo se descarga en la web cuando alguien sube una foto.
List<(int, Uint8List)> buildAvatarThumbs((Uint8List, List<int>) args) {
  final (raw, sizes) = args;
  var im = img.decodeImage(raw);
  if (im == null) return const [];
  im = img.bakeOrientation(im);
  final side = im.width < im.height ? im.width : im.height;
  final sq = img.copyCrop(im, x: (im.width - side) ~/ 2, y: (im.height - side) ~/ 2, width: side, height: side);
  return [
    for (final s in sizes)
      (s, Uint8List.fromList(img.encodeJpg(side > s ? img.copyResize(sq, width: s, height: s, interpolation: img.Interpolation.average) : sq, quality: 75))),
  ];
}
