import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/share/canvas_text.dart';
import '../../../core/theme/design_tokens.dart';
import '../domain/gamification_models.dart';

/// Imágenes compartibles de Head to Head, Wrapped y Ranking. Usan el mismo motor de texto medido que Match Recap y
/// «Compartir mis stats» (`core/share/canvas_text.dart`): nada se solapa ni se sale, y los tests lo comprueban.
enum ShareSize {
  story(1920), post(1350);
  const ShareSize(this.height);
  final int height;
  Size get size => Size(1080, height.toDouble());
}

const _ink = AppColors.ink900, _ink2 = AppColors.ink800, _lime = AppColors.lime300, _white = Color(0xFFF2F5EF), _mute = Color(0xFF9AA39D);
const _m = 80.0;

typedef ShareImages = Map<String, ui.Image>;

/// Fondo común: degradado tinta, pista sutil y resplandor lima (como Match Recap).
void _background(Canvas c, Size s) {
  c.drawRect(Offset.zero & s, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(s.width, s.height), const [Color(0xFF1C231F), _ink, Color(0xFF0D110F)], const [0, .55, 1]));
  final line = Paint()..color = _lime.withValues(alpha: .07)..style = PaintingStyle.stroke..strokeWidth = 6;
  final cw = s.width * .86, ch = s.height * .74, cx = s.width / 2, cy = s.height * .55;
  c.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: cw, height: ch), line);
  c.drawLine(Offset(cx - cw / 2, cy), Offset(cx + cw / 2, cy), line);
  c.drawCircle(Offset(s.width * .85, -s.height * .02), s.width * .55,
      Paint()..shader = ui.Gradient.radial(Offset(s.width * .85, -s.height * .02), s.width * .55, [_lime.withValues(alpha: .2), _lime.withValues(alpha: 0)]));
}

/// Logo + píldora con el nombre de la pieza. Devuelve el borde inferior.
double _header(Canvas c, ShareText t, double w, String pill, {double y = 84}) {
  final logo = t.draw('plobby', w / 2, y, 72, _lime, ax: .5, family: ShareFonts.unbounded, tracking: -.03, label: 'logo');
  final f = ShareText.fit(pill, 24, weight: FontWeight.w700, tracking: .08, color: _lime);
  final box = Rect.fromCenter(center: Offset(w / 2, logo.bottom + 34 + (f.cap + 26) / 2), width: f.width + 48, height: f.cap + 26);
  c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)), Paint()..color = _lime.withValues(alpha: .5)..style = PaintingStyle.stroke..strokeWidth = 2);
  t.paintFitted(f, box.center.dx, box.center.dy, v: VAnchor.capCenter, ax: .5, label: 'pieza', container: box);
  return box.bottom;
}

void _avatar(Canvas c, ShareText t, GPlayer p, Offset center, double size, ShareImages images, {Color ring = _lime, double ringW = 8}) {
  final r = Rect.fromCenter(center: center, width: size, height: size);
  c.save();
  c.clipPath(Path()..addOval(r));
  final img = images[p.id];
  if (img != null) {
    final s = math.min(img.width, img.height).toDouble();
    c.drawImageRect(img, Rect.fromLTWH((img.width - s) / 2, (img.height - s) / 2, s, s), r, Paint()..filterQuality = FilterQuality.high);
  } else {
    c.drawRect(r, Paint()..color = _ink2);
    ShareText(c).draw(p.initials, center.dx, center.dy, size * .36, _white, v: VAnchor.capCenter, ax: .5, weight: FontWeight.w800);
  }
  c.restore();
  c.drawCircle(center, size / 2 + ringW / 2, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = ringW);
  t.obstacle(Rect.fromCircle(center: center, radius: size / 2 + ringW), 'avatar');
}

/// Centra verticalmente el contenido entre la cabecera y el pie: se pinta una vez en un lienzo de prueba para MEDIR
/// dónde acaba (con el registro de cajas) y después se pinta de verdad desplazado. Así una Story con pocos datos no
/// deja medio lienzo vacío abajo, y una con muchos datos no se mueve.
void _centered(Canvas c, ShareText t, Size s, double headerBottom, void Function(Canvas c, ShareText t, double hb) body) {
  final probeCanvas = Canvas(ui.PictureRecorder()), probe = ShareLayoutLog();
  body(probeCanvas, ShareText(probeCanvas, log: probe), headerBottom);
  final bottom = probe.items.fold<double>(headerBottom, (a, i) => math.max(a, i.rect.bottom));
  final slack = (s.height - 120) - bottom;
  body(c, t, headerBottom + (slack > 0 ? slack / 2 : 0));
}

void _footer(ShareText t, Size s) =>
    t.draw('plobby.app  ·  Solo partidos confirmados', s.width / 2, s.height - 56, 24, _white.withValues(alpha: .5), v: VAnchor.baseline, ax: .5, weight: FontWeight.w600, label: 'pie');

Future<Uint8List> _png(void Function(Canvas, Size) paint, Size size) async {
  final rec = ui.PictureRecorder();
  paint(Canvas(rec, Offset.zero & size), size);
  final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bytes!.buffer.asUint8List();
}

// ───────────────────────────── Head to Head ─────────────────────────────

class H2HSharePainter extends CustomPainter {
  H2HSharePainter(this.d, {this.images = const {}, this.log});
  final H2HData d;
  final ShareImages images;
  final ShareLayoutLog? log;

  @override
  void paint(Canvas c, Size s) {
    final t = ShareText(c, log: log), story = s.height > 1500, W = s.width;
    _background(c, s);
    final headerBottom = _header(c, t, W, 'HEAD TO HEAD');
    _centered(c, t, s, headerBottom, (c, t, hb) {
      // jugadores enfrentados
      final av = story ? 200.0 : 160.0, ay = hb + (story ? 90 : 60) + av / 2, lx = W * .21, rx = W * .79;
      // hueco REAL entre los dos avatares (con su aro y un margen): ahí va el marcador, que se ajusta a ese ancho
      final gapW = (rx - lx) - av - 2 * 10 - 48;
      final v = d.verdict;
      _avatar(c, t, d.me.player, Offset(lx, ay), av, images, ring: v.leader == H2HLeader.me ? _lime : _mute, ringW: v.leader == H2HLeader.me ? 10 : 6);
      _avatar(c, t, d.other.player, Offset(rx, ay), av, images, ring: v.leader == H2HLeader.other ? _lime : _mute, ringW: v.leader == H2HLeader.other ? 10 : 6);
      final ny = ay + av / 2 + 34;
      t.draw(d.me.player.first, lx, ny, 40, _white, ax: .5, maxWidth: lx * 2 - 60, minFontSize: 28, weight: FontWeight.w800, label: 'nombre');
      t.draw(d.other.player.first, rx, ny, 40, _white, ax: .5, maxWidth: (W - rx) * 2 - 60, minFontSize: 28, weight: FontWeight.w800, label: 'nombre');
      // marcador del cara a cara, entre los dos
      final rec = t.draw('${d.myWins}–${d.theirWins}', W / 2, ay, story ? 104 : 84, _white, v: VAnchor.capCenter, ax: .5, family: ShareFonts.unbounded,
          maxWidth: gapW, minFontSize: 40, label: 'cara a cara');
      t.draw(d.directTotal == 1 ? '1 PARTIDO' : '${d.directTotal} PARTIDOS', W / 2, rec.bottom + 22, 20, _mute, ax: .5, tracking: .12, weight: FontWeight.w800,
          maxWidth: gapW, label: 'partidos');
      // conclusión: solo con datos (H2HData.verdict nunca inventa un ganador)
      var y = ny + 40 + (story ? 70 : 46);
      final vt = t.draw(v.title.toUpperCase(), W / 2, y, story ? 40 : 34, v.leader == H2HLeader.unknown ? _white : _lime, ax: .5, maxWidth: W - _m * 2,
          minFontSize: 26, weight: FontWeight.w800, tracking: .04, label: 'conclusión');
      final vd = t.draw(v.detail, W / 2, vt.bottom + 22, 26, _mute, ax: .5, maxWidth: W - _m * 2, minFontSize: 20, weight: FontWeight.w600, label: 'detalle');
      // estadísticas generales enfrentadas
      y = vd.bottom + (story ? 70 : 44);
      final stats = d.stats.take(story ? 6 : 4).toList(), rowH = story ? 104.0 : 92.0;
      for (final st in stats) {
        final box = Rect.fromLTWH(_m, y, W - _m * 2, rowH - 16);
        c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(28)), Paint()..color = _ink2);
        final cy = box.top + 30;
        t.draw(st.mineText, box.left + 34, cy, 34, st.leader == H2HLeader.me ? _lime : _white, v: VAnchor.capCenter, family: ShareFonts.unbounded,
            maxWidth: box.width * .28, minFontSize: 24, label: 'valor', container: box);
        t.draw(st.theirsText, box.right - 34, cy, 34, st.leader == H2HLeader.other ? _lime : _white, v: VAnchor.capCenter, ax: 1, family: ShareFonts.unbounded,
            maxWidth: box.width * .28, minFontSize: 24, label: 'valor', container: box);
        t.draw(st.label.toUpperCase(), box.center.dx, cy, 20, _mute, v: VAnchor.capCenter, ax: .5, tracking: .1, weight: FontWeight.w800,
            maxWidth: box.width * .36, minFontSize: 16, label: 'estadística', container: box);
        // barra
        final bar = Rect.fromLTWH(box.left + 34, box.bottom - 22, box.width - 68, 8), split = bar.left + bar.width * st.myShare;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(bar.left, bar.top, split - 2, bar.bottom), const Radius.circular(4)),
            Paint()..color = st.leader == H2HLeader.me ? _lime : _white.withValues(alpha: .25));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(split + 2, bar.top, bar.right, bar.bottom), const Radius.circular(4)),
            Paint()..color = st.leader == H2HLeader.other ? _lime : _white.withValues(alpha: .25));
        y += rowH;
      }
      // últimos enfrentamientos (solo en Story, si hay sitio)
      if (story && d.matches.isNotEmpty) {
        y += 30;
        final lab = t.draw('ÚLTIMOS ENFRENTAMIENTOS', W / 2, y, 22, _mute, ax: .5, tracking: .12, weight: FontWeight.w800, label: 'historial');
        y = lab.bottom + 30;
        for (final m in d.matches.take(3)) {
          if (y > s.height - 170) break;
          final who = m.won ? d.me.player.first : d.other.player.first;
          t.draw('${m.playedAt.day}/${m.playedAt.month}/${m.playedAt.year % 100}   ·   ${m.score}   ·   gana $who', W / 2, y, 28, _white, ax: .5,
              maxWidth: W - _m * 2, minFontSize: 22, weight: FontWeight.w700, label: 'enfrentamiento');
          y += 56;
        }
      }
    });
    _footer(t, s);
  }

  @override
  bool shouldRepaint(H2HSharePainter o) => o.d != d || o.images != images;
  static Future<Uint8List> toPng(H2HData d, ShareSize f, {ShareImages images = const {}}) => _png((c, s) => H2HSharePainter(d, images: images).paint(c, s), f.size);
}

// ───────────────────────────── Wrapped ─────────────────────────────

/// Resumen del Wrapped en una imagen (la «pantalla final»), en Story o publicación.
class WrappedSharePainter extends CustomPainter {
  WrappedSharePainter(this.w, {this.images = const {}, this.log});
  final WrappedData w;
  final ShareImages images;
  final ShareLayoutLog? log;

  @override
  void paint(Canvas c, Size s) {
    final t = ShareText(c, log: log), story = s.height > 1500, W = s.width;
    _background(c, s);
    final headerBottom = _header(c, t, W, 'PLOBBY WRAPPED');
    _centered(c, t, s, headerBottom, (c, t, hb) {
      final title = t.draw(w.kind == WrappedKind.year ? 'MI ${w.start.year}' : w.periodLabel.toUpperCase(), W / 2, hb + (story ? 90 : 56), story ? 92 : 76, _white, ax: .5,
          family: ShareFonts.unbounded, maxWidth: W - _m * 2, minFontSize: 52, label: 'periodo');
      final name = t.draw(w.name, W / 2, title.bottom + 30, 30, _mute, ax: .5, maxWidth: W - _m * 2, minFontSize: 22, weight: FontWeight.w700, label: 'nombre');
      // cifras clave en una rejilla 2×2
      final tiles = <(String, String)>[
        ('PARTIDOS', '${w.played}'), ('VICTORIAS', '${w.wins}'),
        ('% VICTORIAS', w.winRate == null ? '—' : '${w.winRate}%'), ('MEJOR RACHA', '${w.bestStreak}'),
      ];
      final gap = 24.0, tw = (W - _m * 2 - gap) / 2, th = story ? 230.0 : 190.0;
      var y = name.bottom + (story ? 80 : 50);
      for (var i = 0; i < tiles.length; i++) {
        final box = Rect.fromLTWH(_m + (i % 2) * (tw + gap), y + (i ~/ 2) * (th + gap), tw, th);
        c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(32)), Paint()..color = i == 0 ? _lime : _ink2);
        final fg = i == 0 ? _ink : _white;
        final lab = t.draw(tiles[i].$1, box.left + 32, box.top + 34, 20, i == 0 ? _ink.withValues(alpha: .7) : _mute, tracking: .1, weight: FontWeight.w800,
            maxWidth: box.width - 64, label: 'etiqueta', container: box);
        t.draw(tiles[i].$2, box.left + 32, lab.bottom + (box.bottom - lab.bottom) / 2, story ? 88 : 72, fg, v: VAnchor.capCenter, family: ShareFonts.unbounded,
            maxWidth: box.width - 64, minFontSize: 40, label: 'cifra', container: box);
      }
      y += th * 2 + gap + (story ? 70 : 44);
      // momentos: compañero, rival y mes más activo / récord (solo los que existen)
      final lines = <(String, String)>[
        if (w.topPartner != null) ('COMPAÑERO HABITUAL', '${w.topPartner!.player.name} · ${w.topPartner!.played} partidos'),
        if (w.topRival != null) ('RIVAL MÁS FRECUENTE', '${w.topRival!.player.name} · ${w.topRival!.played} partidos'),
        if (w.kind == WrappedKind.year && w.busiestBucket != null) ('MES MÁS ACTIVO', '${capitalize(monthName(w.busiestBucket!.start.month))} · ${w.busiestBucket!.played} partidos'),
        if (w.recordElo != null && w.isRecord) ('RÉCORD DE ELO', '${w.recordElo}'),
      ];
      for (final (k, v) in lines.take(story ? 4 : 2)) {
        if (y > s.height - (story ? 200 : 150)) break;
        final a = t.draw(k, W / 2, y, 20, _lime, ax: .5, tracking: .12, weight: FontWeight.w800, label: 'momento');
        final b = t.draw(v, W / 2, a.bottom + 20, 32, _white, ax: .5, maxWidth: W - _m * 2, minFontSize: 22, weight: FontWeight.w700, label: 'momento valor');
        y = b.bottom + (story ? 50 : 36);
      }
    });
    _footer(t, s);
  }

  @override
  bool shouldRepaint(WrappedSharePainter o) => o.w != w;
  static Future<Uint8List> toPng(WrappedData w, ShareSize f) => _png((c, s) => WrappedSharePainter(w).paint(c, s), f.size);
}

// ───────────────────────────── Ranking ─────────────────────────────

/// Mi posición (y el podio) en una clasificación entre amigos, en formato publicación.
class RankingSharePainter extends CustomPainter {
  RankingSharePainter(this.r, this.metric, {this.images = const {}, this.log});
  final RankingData r;
  final RankMetric metric;
  final ShareImages images;
  final ShareLayoutLog? log;

  String _value(RankRow x) => switch (metric) { RankMetric.wins => '${x.wins}', RankMetric.rate => '${x.winRate}%', RankMetric.activity => '${x.played}' };
  String get _unit => switch (metric) { RankMetric.wins => 'VICTORIAS', RankMetric.rate => 'DE VICTORIAS', RankMetric.activity => 'PARTIDOS' };

  @override
  void paint(Canvas c, Size s) {
    final t = ShareText(c, log: log), story = s.height > 1500, W = s.width;
    _background(c, s);
    final headerBottom = _header(c, t, W, 'RANKING ENTRE AMIGOS');
    _centered(c, t, s, headerBottom, (c, t, hb) {
      final per = t.draw('${metric.label.toUpperCase()} · ${r.period.label.toUpperCase()}', W / 2, hb + 50, 26, _mute, ax: .5, tracking: .1, weight: FontWeight.w800,
          maxWidth: W - _m * 2, label: 'periodo');
      final list = r.ranked(metric);
      final me = list.where((x) => x.player.id == r.meId).firstOrNull;
      // mi puesto
      var y = per.bottom + (story ? 90 : 56);
      if (me != null) {
        final pos = t.draw('#${me.pos(metric)}', W / 2, y, story ? 200 : 150, _lime, ax: .5, family: ShareFonts.unbounded, label: 'puesto');
        final sub = t.draw('de ${list.length}  ·  ${_value(me)} $_unit', W / 2, pos.bottom + 34, 32, _white, ax: .5, maxWidth: W - _m * 2, minFontSize: 24,
            weight: FontWeight.w700, label: 'mi dato');
        y = sub.bottom + (story ? 90 : 56);
      }
      // podio (tres primeros)
      final top = list.take(3).toList();
      final order = [if (top.length > 1) 1, 0, if (top.length > 2) 2];
      final colW = (W - _m * 2) / 3;
      for (final i in order) {
        if (i >= top.length) continue;
        final x = top[i], col = order.length == 1 ? 1 : (order.indexOf(i) + (order.length == 2 ? .5 : 0));
        final cx = _m + colW * col + colW / 2, size = i == 0 ? 150.0 : 118.0, lift = i == 0 ? 0.0 : 40.0;
        _avatar(c, t, x.player, Offset(cx, y + lift + size / 2 + 8), size, images, ring: i == 0 ? _lime : _mute, ringW: i == 0 ? 8 : 5);
        final nb = t.draw(x.player.first, cx, y + lift + size + 40, 28, _white, ax: .5, maxWidth: colW - 20, minFontSize: 20, weight: FontWeight.w800, label: 'podio nombre');
        t.draw('${x.pos(metric)}º · ${_value(x)}', cx, nb.bottom + 18, 24, i == 0 ? _lime : _mute, ax: .5, maxWidth: colW - 20, weight: FontWeight.w800, label: 'podio dato');
      }
    });
    _footer(t, s);
  }

  @override
  bool shouldRepaint(RankingSharePainter o) => o.r != r || o.metric != metric;
  static Future<Uint8List> toPng(RankingData r, RankMetric m, ShareSize f, {ShareImages images = const {}}) =>
      _png((c, s) => RankingSharePainter(r, m, images: images).paint(c, s), f.size);
}

/// Descarga y decodifica fotos de perfil para las imágenes (las que fallen se dibujan con iniciales).
Future<ShareImages> loadShareImages(Iterable<GPlayer> players) async {
  final out = <String, ui.Image>{};
  await Future.wait([for (final p in players) if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) () async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final res = await (await client.getUrl(Uri.parse(p.avatarUrl!))).close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final bytes = await res.fold<BytesBuilder>(BytesBuilder(), (b, x) => b..add(x));
      final codec = await ui.instantiateImageCodec(bytes.takeBytes(), targetWidth: 400);
      out[p.id] = (await codec.getNextFrame()).image;
    } catch (_) {/* sin foto: iniciales */}
  }()]);
  return out;
}
