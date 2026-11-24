import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Miniaturas de las fotos de perfil. Al subir una foto se guardan también dos copias pequeñas en JPEG:
/// `<nombre>_t96.jpg` (listas, ~4 KB) y `<nombre>_t256.jpg` (perfil y cabeceras, ~15 KB) junto a la original
/// (`avatars/<uid>/<nombre>.<ext>`). Las transformaciones de imagen de Supabase no están en el plan actual, por eso las
/// genera la app (`avatar_thumbs.dart`).
class AvatarThumbs {
  AvatarThumbs._();
  static const sizes = [96, 256];
  static final _avatar = RegExp(r'^(https?://[^?#]+/storage/v1/object/public/avatars/[^/?#]+/)(avatar_[^/?#]+?)\.(jpg|jpeg|png|webp)$');

  /// Nombre de la miniatura de [baseName] (sin extensión) para el lado [px].
  static String thumbName(String baseName, int px) => '${baseName}_t$px.jpg';

  /// URL de la miniatura más pequeña que cubre [decodeWidth] píxeles físicos; si [url] no es una foto de perfil de
  /// Plobby (grupos, portadas, otro origen) o hace falta más resolución, la propia [url].
  static String pick(String url, int? decodeWidth) {
    final m = _avatar.firstMatch(url);
    if (m == null || decodeWidth == null) return url;
    for (final s in sizes) {
      if (decodeWidth <= s) return '${m[1]}${thumbName(m[2]!, s)}';
    }
    return url;
  }
}

/// `Image.network` que pide la miniatura adecuada al tamaño en pantalla ([cacheWidth], en píxeles físicos) y, si la
/// miniatura no existe (fotos subidas con versiones anteriores), carga la original antes de rendirse a [errorBuilder].
class NetImage extends StatelessWidget {
  const NetImage(this.src, {super.key, this.fit, this.width, this.height, this.cacheWidth, this.errorBuilder, this.color});
  final String src;
  final BoxFit? fit;
  final double? width, height;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;
  final Color? color;

  /// Miniaturas que no existen (fotos de otros jugadores subidas con versiones anteriores). Flutter no guarda en caché
  /// los fallos: sin esto, cada repintado volvía a pedir la miniatura (400 en bucle en los registros de Supabase).
  /// Se recuerdan también entre aperturas de la app durante [missingTtl] ([loadMissing] al arrancar).
  static final missing = <String>{};
  static const missingTtl = Duration(hours: 24);   // timing: el dueño puede generarlas al abrir la app nueva
  static const _prefKey = 'plobby.missing_thumbs';
  static Timer? _save;

  /// Carga las miniaturas que faltaban (y no han caducado). Se llama al arrancar.
  static Future<void> loadMissing() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in (await SharedPreferences.getInstance()).getStringList(_prefKey) ?? const <String>[]) {
        final i = e.indexOf('|');
        if (i > 0 && now - (int.tryParse(e.substring(0, i)) ?? 0) < missingTtl.inMilliseconds) missing.add(e.substring(i + 1));
      }
    } catch (_) {}
  }

  static void _remember(String url) {
    if (!missing.add(url)) return;
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () async {   // timing: agrupa varias en una escritura
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        await (await SharedPreferences.getInstance()).setStringList(_prefKey, [for (final u in missing.take(300)) '$now|$u']);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final thumb = AvatarThumbs.pick(src, cacheWidth);
    Widget original() => Image.network(src, fit: fit, width: width, height: height, cacheWidth: cacheWidth, color: color, errorBuilder: errorBuilder);
    if (thumb == src || missing.contains(thumb)) return original();
    return Image.network(thumb, fit: fit, width: width, height: height, cacheWidth: cacheWidth, color: color,
        errorBuilder: (_, __, ___) { _remember(thumb); return original(); });
  }
}
