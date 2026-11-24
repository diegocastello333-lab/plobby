import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'pixel_decode.dart' deferred as px;

/// Descarga y decodifica una imagen de red para dibujarla en un Canvas (imágenes para compartir). Usa `package:http`,
/// que funciona igual en Android, iOS y la web (antes `HttpClient` de dart:io, que no existe en el navegador).
/// Devuelve null si falla: quien la usa dibuja iniciales o un avatar por defecto.
Future<ui.Image?> fetchUiImage(String url, {int targetWidth = 512}) async {
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    if (kIsWeb) {
      // Web: píxeles decodificados en Dart (ver pixel_decode.dart: en Safari el decodificador del navegador dejaba la
      // vista previa en blanco). Si aun así falla, la imagen sale con iniciales en vez de romperse.
      await px.loadLibrary();
      return await px.decodeToPixels(res.bodyBytes, targetWidth);
    }
    final codec = await ui.instantiateImageCodec(res.bodyBytes, targetWidth: targetWidth);
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}
