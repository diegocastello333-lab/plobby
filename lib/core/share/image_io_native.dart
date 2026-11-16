import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'image_io_types.dart';

/// Android / iOS: mismo comportamiento que antes de la versión web.
class ImageIO {
  ImageIO._();

  /// Copiar imágenes al portapapeles no está disponible en la app nativa (el paquete que lo hacía no compila con
  /// Gradle 9). El botón «Copiar» solo se muestra donde funciona.
  static bool get canCopy => false;

  static Future<ImageSaveResult> save(Uint8List png, String name) async {
    if (!await Gal.hasAccess()) await Gal.requestAccess();
    await Gal.putImageBytes(png, name: name);
    return ImageSaveResult.savedToGallery;
  }

  static Future<void> share(Uint8List png, String name, {String? text}) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name.png')..writeAsBytesSync(png);
    await Share.shareXFiles([XFile(f.path, mimeType: 'image/png', name: '$name.png')], text: text);
  }

  static Future<void> copy(Uint8List png) async => throw UnsupportedError('copy');
}
