import 'dart:typed_data';
import '../../../core/share/image_io.dart';

/// Guardar y compartir imágenes generadas. Delega en [ImageIO], que elige la implementación nativa (galería + hoja del
/// sistema) o la web (Web Share API / descarga) al compilar.
class ShareService {
  /// Galería en el móvil (pide permiso mediante `gal`); en la web, hoja del sistema («Guardar imagen») o descarga.
  Future<ImageSaveResult> saveToGallery(Uint8List png, String name) => ImageIO.save(png, name);

  /// Hoja de compartir con el PNG adjunto.
  Future<void> share(Uint8List png, String name, {String? text}) => ImageIO.share(png, name, text: text);
}
