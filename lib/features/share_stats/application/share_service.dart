import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  /// Guarda en la galería (requiere permiso; `gal` lo solicita).
  Future<void> saveToGallery(Uint8List png, String name) async {
    if (!await Gal.hasAccess()) await Gal.requestAccess();
    await Gal.putImageBytes(png, name: name);
  }

  /// Abre el menú nativo de compartir con el PNG adjunto.
  Future<void> share(Uint8List png, String name) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name.png')..writeAsBytesSync(png);
    await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: 'Mis stats en Plobby');
  }
}
