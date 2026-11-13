import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../../../core/share/canvas_text.dart';
import '../../../core/theme/plobby_theme.dart';
import '../../../core/widgets/flame_paths.dart';

enum ShareTemplate { performance, streak }
enum ShareFormat { story, post }

extension ShareFormatX on ShareFormat {
  ui.Size get size => this == ShareFormat.story ? const ui.Size(1080, 1920) : const ui.Size(1080, 1350);
}

/// Datos YA calculados a partir de partidos confirmados. El pintor no inventa cifras.
class ShareCardData {
  const ShareCardData({required this.name, required this.username, required this.elo, required this.eloDelta, required this.category,
    required this.played, required this.winRate, required this.wins, required this.losses, required this.streak, required this.bestStreak,
    required this.periodLabel, required this.last, this.club, this.partner, this.avatar});
  final String name, username, category, periodLabel;
  final int elo, eloDelta, played, winRate, wins, losses, streak, bestStreak;
  final List<bool> last; // últimos resultados, más reciente primero
  final String? club, partner;
  final ui.Image? avatar;
}

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

class ShareCardPainter extends CustomPainter {
  ShareCardPainter(this.d, this.tpl, {this.log});
  final ShareCardData d; final ShareTemplate tpl;
  /// Solo para tests/depuración: registra la caja de cada texto y forma (ver `canvas_text.dart`).
  final ShareLayoutLog? log;
  static const _ivory = PlobbyColors.ivory, _lime = PlobbyColors.lime, _forest = PlobbyColors.forest;
  static const _m = 80.0; // margen lateral

  /// Llama de [h] de alto con la parte superior en [top]; devuelve su caja (para que nada la pise).
  Rect _flame(Canvas c, ShareText t, double cx, double top, double h, Color col, Color inner, {double glow = 0}) {
    c.save();
    final sc = h / 130;
    c.translate(cx - 50 * sc, top);
    c.scale(sc);
    if (glow > 0) c.drawPath(flameOuter(), Paint()..color = _lime.withOpacity(.55)..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, glow));
    c.drawPath(flameOuter(), Paint()..color = col);
    c.drawPath(flameInner(), Paint()..color = inner.withOpacity(.85));
    c.restore();
    final r = Rect.fromLTWH(cx - 50 * sc, top, 100 * sc, h);
    t.obstacle(r, 'llama');
    return r;
  }

  @override
  void paint(Canvas c, Size s) {
    final W = s.width, H = s.height, story = H > 1500;
    final t = ShareText(c, log: log);
    c.drawRect(Offset.zero & s, Paint()..color = _forest);
    // pista de pádel sutil
    final line = Paint()..color = _lime.withOpacity(.13)..style = PaintingStyle.stroke..strokeWidth = 5;
    final cw = W * 1.05, ch = H * .82, cx = W / 2, cy = H * .52;
    c.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: cw, height: ch), line);
    for (final y in [cy, cy - ch * .22, cy + ch * .22]) { c.drawLine(Offset(cx - cw / 2, y), Offset(cx + cw / 2, y), line); }
    c.drawLine(Offset(cx, cy - ch * .22), Offset(cx, cy - ch / 2), line);
    c.drawLine(Offset(cx, cy + ch * .22), Offset(cx, cy + ch / 2), line);
    c.drawCircle(Offset(W * .86, H * .2), 360, Paint()..color = _lime.withOpacity(.07));

    // ── cabecera: marca a la izquierda, periodo en una píldora medida a la derecha (centrados en la misma línea) ──
    const headY = 116.0;
    final brand = t.draw('PLOBBY', _m, headY, 46, _ivory, v: VAnchor.capCenter, weight: FontWeight.w800, tracking: .22, label: 'marca');
    c.drawCircle(Offset(brand.right + 22, headY), 9, Paint()..color = _lime);
    final pillMax = W - _m - (brand.right + 70) - 56;
    final per = ShareText.fit(d.periodLabel.toUpperCase(), 30, maxWidth: pillMax, minFontSize: 22, weight: FontWeight.w700, tracking: .13, color: _ivory);
    final pill = Rect.fromLTWH(W - _m - per.width - 56, headY - 28, per.width + 56, 56);
    c.drawRRect(RRect.fromRectAndRadius(pill, const Radius.circular(14)), Paint()..color = _ivory.withOpacity(.12));
    t.paintFitted(per, pill.center.dx, headY, v: VAnchor.capCenter, ax: .5, label: 'periodo', container: pill);

    // ── jugador ──
    final ay = story ? 230.0 : 210.0, r = 105.0, acx = _m + r, acy = ay + r;
    c.drawCircle(Offset(acx, acy), r + 8, Paint()..color = _lime);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(acx, acy), radius: r)));
    if (d.avatar != null) {
      paintImage(canvas: c, rect: Rect.fromLTWH(_m, ay, r * 2, r * 2), image: d.avatar!, fit: BoxFit.cover);
    } else {
      c.drawRect(Rect.fromLTWH(_m, ay, r * 2, r * 2), Paint()..color = PlobbyColors.sage);
    }
    c.restore();
    t.obstacle(Rect.fromCircle(center: Offset(acx, acy), radius: r + 8), 'avatar');
    final nx = _m + r * 2 + 44, nW = W - _m - nx;
    t.draw(d.name, nx, acy - 18, 68, _ivory, v: VAnchor.baseline, maxWidth: nW, minFontSize: 46, weight: FontWeight.w800, label: 'nombre');
    t.draw('@${d.username}', nx, acy + 42, 36, PlobbyColors.sage, v: VAnchor.baseline, maxWidth: nW, minFontSize: 26, weight: FontWeight.w500, label: 'usuario');
    var ty = ay + r * 2 + 8 + 56; // cap-top de la línea de club/pareja
    final parts = [if (d.club != null) d.club!, if (d.partner != null) 'con ${d.partner}'];
    if (parts.isNotEmpty) {
      final joined = ShareText.fit(parts.join('   ·   '), 34, maxWidth: W - _m * 2, minFontSize: 28, weight: FontWeight.w600);
      // Si club + pareja no caben en una línea sin recortar, van en dos (no se pierde información).
      final lines = joined.truncated && parts.length == 2 ? parts : [parts.join('   ·   ')];
      for (final l in lines) {
        final rr = t.draw(l, _m, ty, 34, _ivory.withOpacity(.78), maxWidth: W - _m * 2, minFontSize: 26, weight: FontWeight.w600, label: 'club/pareja');
        ty = rr.bottom + 22;
      }
    }

    final footY = H - 40.0;
    if (tpl == ShareTemplate.performance) {
      // Bloque inferior: tarjetas + racha. Bloque ELO centrado en el hueco que queda entre la cabecera y las tarjetas.
      const tileH = 230.0;
      final by = H - 420, w3 = (W - _m * 2 - 40) / 3;
      final fs = story ? 300.0 : 200.0;
      final label = ShareText.fit('RATING ELO', 36, weight: FontWeight.w700, tracking: .22);
      final num = ShareText.fit(_fmt(d.elo), fs, maxWidth: W - _m * 2, family: ShareFonts.inter, weight: FontWeight.w800);
      final delta = ShareText.fit('${d.eloDelta >= 0 ? '+' : '−'}${d.eloDelta.abs()}  ·  ${d.category}', 44, maxWidth: W - _m * 2 - 50, minFontSize: 32, weight: FontWeight.w800);
      final g1 = 38.0, g2 = 44.0;
      final blockH = label.cap + g1 + num.cap + g2 + delta.cap;
      final reg0 = ty + 10, reg1 = by - 30;
      final top = reg0 + math.max(0, (reg1 - reg0 - blockH) / 2);
      t.paintFitted(ShareText.fit('RATING ELO', 36, weight: FontWeight.w700, tracking: .22, color: _ivory.withOpacity(.6)), _m, top, label: 'rating');
      // La cifra grande se alinea ópticamente con el margen: su lado izquierdo tiene «aire» propio de la fuente.
      t.paintFitted(ShareText.fit(_fmt(d.elo), num.fontSize, family: ShareFonts.inter, weight: FontWeight.w800, color: _lime), _m - num.fontSize * .04, top + label.cap + g1, label: 'elo');
      final dy = top + label.cap + g1 + num.cap + g2;
      final up = d.eloDelta >= 0, dc = up ? _lime : const Color(0xFFFF6B6F);
      paintTriangle(c, Offset(_m + 14, dy + delta.cap / 2), 28, dc, up: up);
      t.paintFitted(ShareText.fit(delta.text, delta.fontSize, maxWidth: W - _m * 2 - 50, weight: FontWeight.w800, color: dc), _m + 46, dy, label: 'delta');

      final tiles = [('PARTIDOS', '${d.played}'), ('VICTORIAS', '${d.winRate}%'), ('V · D', '${d.wins} · ${d.losses}')];
      for (var i = 0; i < 3; i++) {
        final x = _m + i * (w3 + 20), hi = i == 1, box = Rect.fromLTWH(x, by, w3, tileH);
        c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(22)), Paint()..color = hi ? _lime : _ivory.withOpacity(.1));
        final fg = hi ? _forest : _ivory;
        // cifra centrada en la parte alta de la tarjeta; etiqueta debajo con separación fija
        t.draw(tiles[i].$2, box.center.dx, by + 96, 96, fg, v: VAnchor.capCenter, ax: .5, maxWidth: w3 - 40, minFontSize: 30, weight: FontWeight.w800, label: 'valor ${tiles[i].$1}', container: box);
        t.draw(tiles[i].$1, box.center.dx, by + 176, 26, fg.withOpacity(.75), v: VAnchor.capCenter, ax: .5, maxWidth: w3 - 32, weight: FontWeight.w700, tracking: .15, label: 'etiqueta ${tiles[i].$1}', container: box);
      }
      final sy = by + tileH + 62; // centro de la fila de racha
      final fl = _flame(c, t, _m + 24, sy - 30, 60, d.streak > 0 ? _lime : PlobbyColors.sage, _forest);
      t.draw('${d.streak} ${d.streak == 1 ? 'victoria seguida' : 'victorias seguidas'}', fl.right + 20, sy, 50, _ivory, v: VAnchor.capCenter,
          maxWidth: W - _m - fl.right - 20, minFontSize: 36, weight: FontWeight.w800, label: 'racha');
    } else {
      // Pila vertical: llama → número → «VICTORIAS SEGUIDAS» → resumen, centrada en el hueco entre el jugador y los
      // últimos partidos. Si el hueco es menor (p. ej. club y pareja en dos líneas en 4:5), la llama y el número se
      // escalan juntos: nunca invaden la fila de abajo.
      final n = math.min(10, d.last.length);
      final dotsTop = n > 0 ? (story ? H - 220 : H - 190.0) - 31 : footY - 60;
      final g0 = story ? 70.0 : 40.0, g1 = story ? 56.0 : 36.0, g2 = story ? 40.0 : 30.0;
      final title = d.streak == 1 ? 'VICTORIA SEGUIDA' : 'VICTORIAS SEGUIDAS';
      final titleF = ShareText.fit(title, 46, maxWidth: W - _m * 2, minFontSize: 34, weight: FontWeight.w800, tracking: .2, color: _lime);
      final sumF = ShareText.fit('Mejor racha: ${d.bestStreak}   ·   ${d.winRate}% de victorias   ·   ELO ${_fmt(d.elo)}', 34,
          maxWidth: W - _m * 2, minFontSize: 26, weight: FontWeight.w600, color: _ivory.withOpacity(.7));
      final regTop = ty + 10, regBottom = dotsTop - (story ? 60 : 40);
      final fixed = g0 + g1 + titleF.cap + g2 + sumF.cap;
      var fh = story ? 470.0 : 220.0, nf = story ? 400.0 : 210.0;
      final k = math.min(1.0, (regBottom - regTop - fixed) / (fh + nf * ShareFonts.capHeight(ShareFonts.inter)));
      fh *= k; nf *= k;
      final stackH = fh + fixed + nf * ShareFonts.capHeight(ShareFonts.inter);
      final top = regTop + math.max(0, (regBottom - regTop - stackH) / 2);
      final fl = _flame(c, t, W / 2, top, fh, d.streak > 0 ? _lime : PlobbyColors.sage, _forest, glow: 70 * k);
      final n1 = t.draw('${d.streak}', W / 2, fl.bottom + g0, nf, _ivory, ax: .5, maxWidth: W - _m * 2, weight: FontWeight.w800, label: 'racha');
      final n2 = t.paintFitted(titleF, W / 2, n1.bottom + g1, ax: .5, label: 'titulo');
      t.paintFitted(sumF, W / 2, n2.bottom + g2, ax: .5, label: 'resumen');
      if (n > 0) {
        const sz = 62.0, gap = 18.0;
        final tw = n * sz + (n - 1) * gap, yy = story ? H - 220 : H - 190.0;
        for (var i = 0; i < n; i++) {
          final win = d.last[n - 1 - i], p = Offset((W - tw) / 2 + i * (sz + gap) + sz / 2, yy);
          win ? c.drawCircle(p, sz / 2 - 3, Paint()..color = _lime)
              : c.drawCircle(p, sz / 2 - 3, Paint()..color = PlobbyColors.sage..style = PaintingStyle.stroke..strokeWidth = 5);
        }
        t.obstacle(Rect.fromLTWH((W - tw) / 2, yy - sz / 2, tw, sz), 'últimos partidos');
        t.draw('ÚLTIMOS $n ${n == 1 ? 'PARTIDO' : 'PARTIDOS'}', W / 2, yy + sz / 2 + 34, 28, PlobbyColors.sage, ax: .5, weight: FontWeight.w600, tracking: .05, label: 'ultimos');
      }
    }
    t.draw('plobby.app  ·  Solo partidos confirmados', W / 2, footY, 26, _ivory.withOpacity(.5), v: VAnchor.baseline, ax: .5, weight: FontWeight.w600, label: 'pie');
  }

  @override
  bool shouldRepaint(ShareCardPainter o) => o.d != d || o.tpl != tpl;

  /// Renderiza a PNG real (no una captura de widget): 1080 × 1920 o 1080 × 1350.
  static Future<Uint8List> toPng(ShareCardData data, ShareTemplate tpl, ShareFormat fmt) async {
    final size = fmt.size;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Offset.zero & size);
    ShareCardPainter(data, tpl).paint(canvas, size);
    final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }
}
