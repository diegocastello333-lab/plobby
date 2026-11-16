import '../../../core/net/image_fetch.dart';
import '../../../core/share/image_io.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
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
    final img = await fetchUiImage(url);   // null → sin foto: se usa el avatar predeterminado
    if (img == null) return;
    _cache[url] = img; out[id] = img;
  }
}

enum RecapAction { saved, downloaded, shared, copied, copyUnsupported }

/// Guardar / compartir / copiar el PNG. Reutiliza `ShareService` (gal + share_plus) de share_stats.
class RecapService {
  RecapService({ShareService? share}) : _share = share ?? ShareService();
  final ShareService _share;

  Future<Uint8List> render(RecapData d, RecapTemplate t, RecapFormat f, RecapOptions o, RecapImages imgs) => RecapPainter.toPng(d, t, f, opts: o, images: imgs);

  /// Galería del dispositivo (pide permiso mediante `gal`). En la web abre la hoja del sistema («Guardar imagen») o
  /// descarga el PNG: solo se informa de «guardada» cuando de verdad fue a la galería.
  Future<RecapAction> save(Uint8List png, String name) async =>
      switch (await _share.saveToGallery(png, name)) { ImageSaveResult.savedToGallery => RecapAction.saved, ImageSaveResult.downloaded => RecapAction.downloaded, ImageSaveResult.shareSheet => RecapAction.shared };

  /// Menú del sistema (WhatsApp, Instagram, Telegram, AirDrop…). Con formato Story, Instagram aparece en la hoja.
  Future<RecapAction> shareNative(Uint8List png, String name, {String? text}) async {
    await _share.share(png, name, text: text ?? 'Mi partido en Plobby');
    return RecapAction.shared;
  }

  /// Copiar la imagen: en la web, con la Clipboard API (Safari, Chrome, Edge). En la app nativa no está disponible
  /// (`super_clipboard` no compila con Gradle 9) y el botón no se muestra ([ImageIO.canCopy]).
  Future<RecapAction> copy(Uint8List png) async {
    if (!ImageIO.canCopy) return RecapAction.copyUnsupported;
    await ImageIO.copy(png);
    return RecapAction.copied;
  }
}
