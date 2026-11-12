import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../share_stats/application/share_service.dart';
import '../domain/recap_data.dart';
import 'recap_painter.dart';

/// Descarga y decodifica las fotos de perfil (solo las que existen). Cualquier fallo → sin imagen → avatar por defecto.
class RecapImageLoader {
  static final Map<String, ui.Image> _cache = {};
  static Future<RecapImages> load(RecapData d) async {
    final out = <String, ui.Image>{};
    await Future.wait([for (final p in [...d.winners, ...d.opponents]) if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) _one(p.avatarUrl!, p.id, out)]);
    return out;
  }

  static Future<void> _one(String url, String id, Map<String, ui.Image> out) async {
    final hit = _cache[url];
    if (hit != null) { out[id] = hit; return; }
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final res = await (await client.getUrl(Uri.parse(url))).close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final bytes = await res.fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
      final codec = await ui.instantiateImageCodec(bytes.takeBytes(), targetWidth: 512);
      final img = (await codec.getNextFrame()).image;
      _cache[url] = img; out[id] = img;
    } catch (_) {/* sin foto: se usa el avatar predeterminado */}
  }
}

enum RecapAction { saved, shared, copied, copyUnsupported }

/// Guardar / compartir / copiar el PNG. Reutiliza `ShareService` (gal + share_plus) de share_stats.
class RecapService {
  RecapService({ShareService? share}) : _share = share ?? ShareService();
  final ShareService _share;

  Future<Uint8List> render(RecapData d, RecapTemplate t, RecapFormat f, RecapOptions o, RecapImages imgs) => RecapPainter.toPng(d, t, f, opts: o, images: imgs);

  /// Galería del dispositivo (pide permiso mediante `gal`).
  Future<RecapAction> save(Uint8List png, String name) async { await _share.saveToGallery(png, name); return RecapAction.saved; }

  /// Menú nativo (WhatsApp, Instagram, Telegram, AirDrop…). Con formato Story, Instagram aparece en la hoja del sistema.
  Future<RecapAction> shareNative(Uint8List png, String name, {String? text}) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name.png')..writeAsBytesSync(png);
    await Share.shareXFiles([XFile(f.path, mimeType: 'image/png', name: '$name.png')], text: text ?? 'Mi partido en Plobby');
    return RecapAction.shared;
  }

  /// Copiar la imagen al portapapeles: desactivado. `super_clipboard` (super_native_extensions) no compila con
  /// Gradle 9, que exige Flutter 3.50, y bloqueaba el APK. El botón se mantiene y avisa al usuario; guardar en la
  /// galería y compartir siguen disponibles. Para recuperarlo, añadir de nuevo un paquete de portapapeles de imágenes
  /// compatible con Gradle 9 y devolver `RecapAction.copied` tras escribir el PNG.
  Future<RecapAction> copy(Uint8List png) async => RecapAction.copyUnsupported;
}
