import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
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
  ShareCardPainter(this.d, this.tpl);
  final ShareCardData d; final ShareTemplate tpl;
  static const _ivory = PlobbyColors.ivory, _lime = PlobbyColors.lime, _forest = PlobbyColors.forest;

  double _text(Canvas c, String t, double x, double y, double fs, Color col, {FontWeight w = FontWeight.w800, double ls = 0, TextAlign al = TextAlign.left, double? width}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: fs, fontWeight: w, color: col, letterSpacing: ls, fontFamily: 'Inter', height: 1)),
        textDirection: TextDirection.ltr, textAlign: al)..layout(maxWidth: width ?? double.infinity);
    final dx = al == TextAlign.center ? x - tp.width / 2 : al == TextAlign.right ? x - tp.width : x;
    tp.paint(c, Offset(dx, y - fs * .85));
    return tp.width;
  }

  void _flame(Canvas c, double cx, double top, double h, Color col, Color inner, {double glow = 0}) {
    c.save();
    final sc = h / 130;
    c.translate(cx - 50 * sc, top);
    c.scale(sc);
    if (glow > 0) c.drawPath(flameOuter(), Paint()..color = _lime.withOpacity(.55)..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, glow));
    c.drawPath(flameOuter(), Paint()..color = col);
    c.drawPath(flameInner(), Paint()..color = inner.withOpacity(.85));
    c.restore();
  }

  @override
  void paint(Canvas c, Size s) {
    final W = s.width, H = s.height, story = H > 1500;
    c.drawRect(Offset.zero & s, Paint()..color = _forest);
    // pista de pádel sutil
    final line = Paint()..color = _lime.withOpacity(.13)..style = PaintingStyle.stroke..strokeWidth = 5;
    final cw = W * 1.05, ch = H * .82, cx = W / 2, cy = H * .52;
    c.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: cw, height: ch), line);
    for (final y in [cy, cy - ch * .22, cy + ch * .22]) { c.drawLine(Offset(cx - cw / 2, y), Offset(cx + cw / 2, y), line); }
    c.drawLine(Offset(cx, cy - ch * .22), Offset(cx, cy - ch / 2), line);
    c.drawLine(Offset(cx, cy + ch * .22), Offset(cx, cy + ch / 2), line);
    c.drawCircle(Offset(W * .86, H * .2), 360, Paint()..color = _lime.withOpacity(.07));
    // marca y periodo
    final bw = _text(c, 'PLOBBY', 80, 130, 46, _ivory, ls: 10);
    c.drawCircle(Offset(80 + bw + 30, 114), 9, Paint()..color = _lime);
    final pw = d.periodLabel.length * 22.0 + 56;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(W - 80 - pw, 88, pw, 56), const Radius.circular(14)), Paint()..color = _ivory.withOpacity(.12));
    _text(c, d.periodLabel.toUpperCase(), W - 80 - pw / 2, 126, 30, _ivory, w: FontWeight.w700, ls: 4, al: TextAlign.center);
    // jugador
    final ay = story ? 230.0 : 210.0, r = 105.0;
    c.drawCircle(Offset(80 + r, ay + r), r + 8, Paint()..color = _lime);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(80 + r, ay + r), radius: r)));
    if (d.avatar != null) {
      paintImage(canvas: c, rect: Rect.fromLTWH(80, ay, r * 2, r * 2), image: d.avatar!, fit: BoxFit.cover);
    } else {
      c.drawRect(Rect.fromLTWH(80, ay, r * 2, r * 2), Paint()..color = PlobbyColors.sage);
    }
    c.restore();
    _text(c, d.name, 80 + r * 2 + 44, ay + 95, 68, _ivory);
    _text(c, '@${d.username}', 80 + r * 2 + 44, ay + 148, 36, PlobbyColors.sage, w: FontWeight.w500);
    var ty = ay + r * 2 + 60;
    final sub = [if (d.club != null) d.club!, if (d.partner != null) 'con ${d.partner}'].join('   ·   ');
    if (sub.isNotEmpty) { _text(c, sub, 80, ty, 34, _ivory.withOpacity(.78), w: FontWeight.w600); ty += 30; }

    if (tpl == ShareTemplate.performance) {
      final by = H - 420, fs = story ? 300.0 : 200.0, blockH = 40 + fs * .75 + 90;
      final reg0 = ty + 20, reg1 = by - 20, top = reg0 + (reg1 - reg0 - blockH) / 2;
      _text(c, 'RATING ELO', 80, top + 30, 36, _ivory.withOpacity(.6), w: FontWeight.w700, ls: 8);
      _text(c, _fmt(d.elo), 68, top + 40 + fs * .75, fs, _lime);
      _text(c, '${d.eloDelta >= 0 ? '▲ +' : '▼ '}${d.eloDelta}  ·  ${d.category}', 80, top + blockH, 44, d.eloDelta >= 0 ? _lime : const Color(0xFFFF6B6F));
      final w3 = (W - 160 - 40) / 3;
      final tiles = [('PARTIDOS', '${d.played}'), ('VICTORIAS', '${d.winRate}%'), ('V · D', '${d.wins} · ${d.losses}')];
      for (var i = 0; i < 3; i++) {
        final x = 80 + i * (w3 + 20), hi = i == 1;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, by, w3, 230), const Radius.circular(22)), Paint()..color = hi ? _lime : _ivory.withOpacity(.1));
        _text(c, tiles[i].$2, x + w3 / 2, by + 125, i == 2 ? 74 : 96, hi ? _forest : _ivory, al: TextAlign.center);
        _text(c, tiles[i].$1, x + w3 / 2, by + 185, 26, (hi ? _forest : _ivory).withOpacity(.75), w: FontWeight.w700, ls: 4, al: TextAlign.center);
      }
      _flame(c, 123, by + 270, 60, d.streak > 0 ? _lime : PlobbyColors.sage, _forest);
      _text(c, '${d.streak} victorias seguidas', 150, by + 322, 50, _ivory);
    } else {
      final fh = story ? 470.0 : 220.0, nf = story ? 400.0 : 210.0, gp = story ? 330.0 : 165.0, fy = ty + 30;
      _flame(c, W / 2, fy, fh, d.streak > 0 ? _lime : PlobbyColors.sage, _forest, glow: 70);
      final ny = fy + fh + gp;
      _text(c, '${d.streak}', W / 2, ny, nf, _ivory, al: TextAlign.center);
      _text(c, 'VICTORIAS SEGUIDAS', W / 2, ny + 78, 46, _lime, ls: 10, al: TextAlign.center);
      _text(c, 'Mejor racha: ${d.bestStreak}   ·   ${d.winRate}% de victorias   ·   ELO ${_fmt(d.elo)}', W / 2, ny + 140, 34, _ivory.withOpacity(.7), w: FontWeight.w600, al: TextAlign.center);
      final n = math.min(10, d.last.length), sz = 62.0, gap = 18.0, tw = n * sz + (n - 1) * gap, yy = story ? H - 70 - 150 : H - 190.0;
      for (var i = 0; i < n; i++) {
        final win = d.last[n - 1 - i], p = Offset((W - tw) / 2 + i * (sz + gap) + sz / 2, yy);
        win ? c.drawCircle(p, sz / 2 - 3, Paint()..color = _lime)
            : c.drawCircle(p, sz / 2 - 3, Paint()..color = PlobbyColors.sage..style = PaintingStyle.stroke..strokeWidth = 5);
      }
      _text(c, 'ÚLTIMOS $n PARTIDOS', W / 2, yy + (story ? 80 : 72), 28, PlobbyColors.sage, w: FontWeight.w600, al: TextAlign.center);
    }
    _text(c, 'plobby.app  ·  Solo partidos confirmados', W / 2, H - 40, 26, _ivory.withOpacity(.5), w: FontWeight.w600, al: TextAlign.center);
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
