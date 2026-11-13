import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

/// Motor de texto de las imágenes para compartir (Match Recap y Compartir mis stats).
///
/// Por qué existe: antes cada pintor colocaba el texto con coordenadas «a ojo» (p. ej. suponiendo que la línea base
/// está al 85 % del tamaño, cuando en Inter con `height: 1` está al 80 %), sin medir el ancho real (los nombres largos
/// se salían de la imagen) o recortando con «…» enseguida. Aquí todo se MIDE:
///  - la posición vertical se ancla a la línea base o al centro óptico de mayúsculas y cifras, con las métricas reales
///    de las fuentes empaquetadas (altura de mayúsculas de Inter 0,7275 em; Unbounded 0,75 em);
///  - si un texto no cabe, primero se reduce hasta un mínimo legible y solo después se recorta con «…»;
///  - cada texto y cada forma relevante se apunta en un [ShareLayoutLog] opcional, que los tests usan para detectar
///    solapes, textos fuera de su contenedor o fuera de la imagen.
class ShareFonts {
  ShareFonts._();
  static const inter = 'Inter', unbounded = 'Unbounded';
  /// Altura de mayúsculas / cifras en «em» (tablas OS/2 de los TTF de assets/fonts).
  static double capHeight(String family) => family == unbounded ? .75 : .7275;
}

/// Cómo interpreta [ShareText.draw] la coordenada `y`.
enum VAnchor {
  /// `y` = parte superior de las mayúsculas.
  capTop,
  /// `y` = línea base.
  baseline,
  /// `y` = centro óptico de mayúsculas y cifras (lo que se percibe como «centrado» en una caja o un círculo).
  capCenter,
}

/// Elemento dibujado, en coordenadas del lienzo de diseño.
class ShareLayoutItem {
  const ShareLayoutItem({required this.kind, required this.label, required this.rect, this.container, this.truncated = false,
      this.scale = 1, this.text, this.family});
  /// 'text' o 'shape' (avatares, iconos: los textos no deben pisarlos).
  final String kind, label;
  /// Para textos: caja de la tinta (de la parte alta de las mayúsculas/acentos a los descendentes).
  final Rect rect;
  /// Caja que debe contener a este texto (tarjeta, píldora, fila), si la hay.
  final Rect? container;
  final bool truncated;
  /// Tamaño final / tamaño pedido (1 = sin reducir).
  final double scale;
  final String? text, family;
  @override
  String toString() => '$kind «${text ?? label}» $rect${truncated ? ' (recortado)' : ''}${scale < 1 ? ' ×${scale.toStringAsFixed(2)}' : ''}';
}

class ShareLayoutLog {
  final items = <ShareLayoutItem>[];
  Iterable<ShareLayoutItem> get texts => items.where((i) => i.kind == 'text');
  Iterable<ShareLayoutItem> get shapes => items.where((i) => i.kind == 'shape');
}

/// Resultado de medir un texto ya ajustado.
class FittedText {
  FittedText(this.painter, this.fontSize, this.requested, this.family, this.truncated, this.text);
  final TextPainter painter;
  final double fontSize, requested;
  final String family, text;
  final bool truncated;
  double get width => painter.width;
  double get baseline => painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  double get cap => ShareFonts.capHeight(family) * fontSize;
}

class ShareText {
  ShareText(this.canvas, {this.log});
  final Canvas canvas;
  final ShareLayoutLog? log;

  static TextStyle style(double fs, Color color, {String family = ShareFonts.inter, FontWeight weight = FontWeight.w700, double tracking = 0}) =>
      TextStyle(fontSize: fs, color: color, fontFamily: family, fontWeight: weight, letterSpacing: tracking * fs, height: 1);

  /// Mide [text] y lo ajusta a [maxWidth]: reduce el tamaño hasta [minFontSize] (por defecto 72 % del pedido) y, si aun
  /// así no cabe, recorta con «…». `tracking` en em (0.06 = +6 %).
  static FittedText fit(String text, double fontSize, {double maxWidth = double.infinity, double? minFontSize, String family = ShareFonts.inter,
      FontWeight weight = FontWeight.w700, double tracking = 0, Color color = const Color(0xFFFFFFFF)}) {
    TextPainter make(double fs, {bool ellipsis = false}) => TextPainter(
        text: TextSpan(text: text, style: style(fs, color, family: family, weight: weight, tracking: tracking)),
        textDirection: TextDirection.ltr, maxLines: 1, ellipsis: ellipsis ? '…' : null)..layout(maxWidth: ellipsis ? maxWidth : double.infinity);
    final min = minFontSize ?? fontSize * .72;
    var fs = fontSize;
    var tp = make(fs);
    for (var i = 0; i < 6 && tp.width > maxWidth && fs > min; i++) {
      fs = math.max(min, fs * maxWidth / tp.width * .995);
      tp = make(fs);
    }
    var truncated = false;
    if (tp.width > maxWidth) { tp = make(fs, ellipsis: true); truncated = true; }
    return FittedText(tp, fs, fontSize, family, truncated, text);
  }

  /// Pinta un texto ajustado. `ax`: 0 = izquierda, .5 = centro, 1 = derecha respecto a `x`. Devuelve la caja de tinta.
  Rect draw(String text, double x, double y, double fontSize, Color color, {VAnchor v = VAnchor.capTop, double ax = 0,
      double maxWidth = double.infinity, double? minFontSize, String family = ShareFonts.inter, FontWeight weight = FontWeight.w700,
      double tracking = 0, String label = '', Rect? container}) {
    final f = fit(text, fontSize, maxWidth: maxWidth, minFontSize: minFontSize, family: family, weight: weight, tracking: tracking, color: color);
    return paintFitted(f, x, y, v: v, ax: ax, label: label, container: container);
  }

  Rect paintFitted(FittedText f, double x, double y, {VAnchor v = VAnchor.capTop, double ax = 0, String label = '', Rect? container}) {
    final baselineY = switch (v) { VAnchor.baseline => y, VAnchor.capTop => y + f.cap, VAnchor.capCenter => y + f.cap / 2 };
    final left = x - f.width * ax;
    f.painter.paint(canvas, Offset(left, baselineY - f.baseline));
    final ink = inkRect(f, left, baselineY);
    log?.items.add(ShareLayoutItem(kind: 'text', label: label, rect: ink, container: container, truncated: f.truncated,
        scale: f.fontSize / f.requested, text: f.text, family: f.family));
    return ink;
  }

  /// Caja de tinta aproximada: mayúsculas (+ acentos en mayúscula) y descendentes solo si el texto los tiene.
  static Rect inkRect(FittedText f, double left, double baselineY) {
    final t = f.text;
    final accentUp = RegExp(r'[ÁÉÍÓÚÜÑÀÈÌÒÙÇ]').hasMatch(t);
    final hasLowerAsc = RegExp(r'[bdfhklt]').hasMatch(t);
    final top = baselineY - f.cap - (accentUp ? f.fontSize * .2 : hasLowerAsc ? f.fontSize * .03 : 0);
    final desc = RegExp(r'[gjpqy(),;]').hasMatch(t) ? f.fontSize * .22 : 0.0;
    return Rect.fromLTRB(left, top, left + f.width, baselineY + desc);
  }

  /// Apunta una forma que los textos no deben pisar (avatar, icono, llama).
  void obstacle(Rect r, String label) => log?.items.add(ShareLayoutItem(kind: 'shape', label: label, rect: r));
}

/// Triángulo ▲/▼ dibujado (las fuentes empaquetadas no traen esos símbolos: salían como un cuadro).
void paintTriangle(Canvas c, Offset center, double size, Color color, {required bool up}) {
  final h = size * .86, w = size;
  final path = Path();
  if (up) {
    path..moveTo(center.dx, center.dy - h / 2)..lineTo(center.dx + w / 2, center.dy + h / 2)..lineTo(center.dx - w / 2, center.dy + h / 2);
  } else {
    path..moveTo(center.dx - w / 2, center.dy - h / 2)..lineTo(center.dx + w / 2, center.dy - h / 2)..lineTo(center.dx, center.dy + h / 2);
  }
  c.drawPath(path..close(), Paint()..color = color..isAntiAlias = true);
}

/// Flecha → dibujada (Unbounded no tiene el carácter).
void paintArrow(Canvas c, Offset center, double width, Color color, {double stroke = 5}) {
  final p = Paint()..color = color..strokeWidth = stroke..strokeCap = StrokeCap.round..style = PaintingStyle.stroke..isAntiAlias = true;
  final l = center.dx - width / 2, r = center.dx + width / 2, head = width * .38;
  c.drawLine(Offset(l, center.dy), Offset(r, center.dy), p);
  c.drawLine(Offset(r, center.dy), Offset(r - head, center.dy - head), p);
  c.drawLine(Offset(r, center.dy), Offset(r - head, center.dy + head), p);
}

/// Reloj dibujado para la duración (el emoji ⏱ dependía de la fuente de emojis del sistema).
void paintClock(Canvas c, Offset center, double size, Color color) {
  final p = Paint()..color = color..strokeWidth = size * .12..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..isAntiAlias = true;
  c.drawCircle(center, size / 2 - p.strokeWidth / 2, p);
  c.drawLine(center, center + Offset(0, -size * .26), p);
  c.drawLine(center, center + Offset(size * .2, 0), p);
}

/// Utilidad para los tests y la depuración: ¿se pisan dos cajas (con tolerancia)?
bool overlaps(Rect a, Rect b, {double tolerance = 1}) => a.deflate(tolerance).overlaps(b.deflate(tolerance));

ui.Rect circleRect(Offset c, double r) => Rect.fromCircle(center: c, radius: r);
