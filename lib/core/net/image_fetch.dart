import 'dart:async';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;

/// Descarga y decodifica una imagen de red para dibujarla en un Canvas (imágenes para compartir). Usa `package:http`,
/// que funciona igual en Android, iOS y la web (antes `HttpClient` de dart:io, que no existe en el navegador).
/// Devuelve null si falla: quien la usa dibuja iniciales o un avatar por defecto.
Future<ui.Image?> fetchUiImage(String url, {int targetWidth = 512}) async {
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(res.bodyBytes, targetWidth: targetWidth);
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}
