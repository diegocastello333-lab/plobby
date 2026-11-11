import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../../auth/presentation/avatar_catalog.dart';
import '../domain/recap_data.dart';

/// Imágenes de red ya decodificadas por jugador (id → imagen). Si falta, se usa avatar predefinido o iniciales.
typedef RecapImages = Map<String, ui.Image>;

/// Pintor ÚNICO de Match Recap: lo usan la previsualización (CustomPaint) y la exportación PNG, por lo que
/// lo que se ve es exactamente lo que se guarda. Dibuja siempre en coordenadas 1080 × H del formato.
/// El logo es el wordmark oficial «plobby» (Unbounded 700, tracking −0.03em, sin símbolo «P»), igual que PlobbyLogo.
class RecapPainter extends CustomPainter {
  RecapPainter(this.d, this.tpl, this.fmt, {this.opts = const RecapOptions(), this.images = const {}});
  final RecapData d; final RecapTemplate tpl; final RecapFormat fmt; final RecapOptions opts; final RecapImages images;

  static const _ink = AppColors.ink900, _ink2 = AppColors.ink800, _lime = AppColors.lime300, _white = Color(0xFFF2F5EF), _mute = Color(0xFF9AA39D);
  double get W => 1080.0;
  double get H => fmt.height.toDouble();
  bool get _sq => fmt == RecapFormat.square;

  // ───────────────────────── primitivas ─────────────────────────
  TextPainter _tp(String t, double fs, Color col, {String fam = 'Inter', FontWeight w = FontWeight.w700, double ls = 0, double maxW = 1000, TextAlign al = TextAlign.left}) =>
      TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: fs, color: col, fontFamily: fam, fontWeight: w, letterSpacing: ls, height: 1.05)),
          textDirection: TextDirection.ltr, textAlign: al, maxLines: 1, ellipsis: '…')..layout(maxWidth: maxW);

  /// Texto con ancla horizontal: `ax` 0 = izquierda, .5 = centro, 1 = derecha; `y` = borde superior.
  double _t(Canvas c, String t, double x, double y, double fs, Color col, {String fam = 'Inter', FontWeight w = FontWeight.w700, double ls = 0, double ax = 0, double maxW = 1000}) {
    final p = _tp(t, fs, col, fam: fam, w: w, ls: ls, maxW: maxW);
    p.paint(c, Offset(x - p.width * ax, y));
    return p.height;
  }

  void _logo(Canvas c, double cx, double y, double fs) {
    final p = _tp('plobby', fs, _lime, fam: 'Unbounded', w: FontWeight.w700, ls: -0.03 * fs);
    p.paint(c, Offset(cx - p.width / 2, y));
  }

  void _pill(Canvas c, String t, double x, double y, double fs, {Color bg = _ink2, Color fg = _white, double ax = 0, double padX = 22, double padY = 12, Color? border}) {
    final p = _tp(t, fs, fg, w: FontWeight.w700, ls: fs * .06);
    final w = p.width + padX * 2, h = p.height + padY * 2, left = x - w * ax;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(left, y, w, h), Radius.circular(h / 2));
    c.drawRRect(r, Paint()..color = bg);
    if (border != null) c.drawRRect(r, Paint()..color = border..style = PaintingStyle.stroke..strokeWidth = 2);
    p.paint(c, Offset(left + padX, y + padY));
  }

  void _avatar(Canvas c, RecapPlayer p, Offset center, double size, {Color ring = _lime, double ringW = 8}) {
    final r = Rect.fromCenter(center: center, width: size, height: size);
    c.save();
    c.clipPath(Path()..addOval(r));
    final img = images[p.id];
    if (img != null) {
      final s = math.min(img.width, img.height).toDouble();
      c.drawImageRect(img, Rect.fromLTWH((img.width - s) / 2, (img.height - s) / 2, s, s), r, Paint()..filterQuality = FilterQuality.high..isAntiAlias = true);
    } else {
      c.translate(r.left, r.top);
      if (p.avatarId == null || !paintPlobbyAvatar(c, size, p.avatarId!)) {
        c.drawRect(Offset.zero & Size(size, size), Paint()..color = _ink2);
        final t = _tp(p.initials, size * .38, _white, fam: 'Inter', w: FontWeight.w800);
        t.paint(c, Offset((size - t.width) / 2, (size - t.height) / 2));
      }
    }
    c.restore();
    c.drawCircle(center, size / 2 + ringW / 2, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = ringW..isAntiAlias = true);
  }

  void _background(Canvas c) {
    c.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(W, H), [const Color(0xFF1C231F), _ink, const Color(0xFF0D110F)], [0, .55, 1]));
    // pista de pádel sutil
    final line = Paint()..color = _lime.withOpacity(.07)..style = PaintingStyle.stroke..strokeWidth = 6;
    final cw = W * .86, ch = H * .74, cx = W / 2, cy = H * .55;
    c.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: cw, height: ch), line);
    c.drawLine(Offset(cx - cw / 2, cy), Offset(cx + cw / 2, cy), line);
    c.drawLine(Offset(cx, cy - ch / 2), Offset(cx, cy + ch / 2), line);
    // resplandor lima
    c.drawCircle(Offset(W * .85, -H * .02), W * .55, Paint()..shader = ui.Gradient.radial(Offset(W * .85, -H * .02), W * .55, [_lime.withOpacity(.22), _lime.withOpacity(0)]));
  }

  void _header(Canvas c, {double y = 84}) {
    _logo(c, W / 2, y, _sq ? 66 : 80);
    _pill(c, 'MATCH RECAP', W / 2, y + (_sq ? 92 : 112), 24, bg: Colors.transparent, fg: _lime, ax: .5, border: _lime.withOpacity(.5));
  }

  String get _whenWhere {
    final parts = <String>[recapDate(d.playedAt)];
    if (opts.showClub && d.club.isNotEmpty) parts.add(d.club.toUpperCase());
    return parts.join('  ·  ');
  }

  // chips inferiores: duración, ELO, pista/liga. SOLO con dato real y si la opción está activa.
  List<String> get _chips => [
        if (opts.showDuration && d.hasDuration) '⏱ ${recapDuration(d.durationSeconds!)}',
        if (opts.showElo && d.hasElo) 'ELO ${d.eloDelta! > 0 ? '+' : ''}${d.eloDelta}',
        if (opts.showClub && d.courtLabel.isNotEmpty) d.courtLabel.toUpperCase(),
        d.contextLabel,
      ];

  void _chipRow(Canvas c, double y, {double fs = 26}) {
    final chips = _chips;
    final ps = [for (final t in chips) _tp(t, fs, _white, w: FontWeight.w700, ls: fs * .05)];
    final gap = 14.0, padX = 22.0;
    double total = 0; for (final p in ps) { total += p.width + padX * 2; } total += gap * (ps.length - 1);
    var scale = total > W - 120 ? (W - 120) / total : 1.0;
    var x = (W - total * scale) / 2;
    c.save(); c.translate(x, y); c.scale(scale); x = 0;
    for (var i = 0; i < ps.length; i++) {
      final p = ps[i], w = p.width + padX * 2, h = p.height + 24, isElo = chips[i].startsWith('ELO');
      final col = isElo ? (d.eloDelta! >= 0 ? _lime : const Color(0xFFFF8A8A)) : _white;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w, h), Radius.circular(h / 2)), Paint()..color = _ink2);
      final pp = _tp(chips[i], fs, col, w: FontWeight.w700, ls: fs * .05); pp.paint(c, Offset(x + padX, 12));
      x += w + gap;
    }
    c.restore();
  }

  /// Marcador por sets: filas ganadores/rivales con una columna por set. Devuelve la altura usada.
  double _scoreboard(Canvas c, double top, {double rowH = 150, double fs = 96, double left = 90}) {
    final n = d.sets.length, avail = W - left * 2, nameW = avail * .30, colW = (avail - nameW) / math.max(n, 1);
    final rows = [(d.winners, true), (d.opponents, false)];
    for (var r = 0; r < 2; r++) {
      final pair = rows[r].$1, win = rows[r].$2, y = top + r * (rowH + 14);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, y, avail, rowH), const Radius.circular(36));
      c.drawRRect(rect, Paint()..color = win ? _lime : _ink2);
      final fg = win ? _ink : _white;
      _t(c, win ? 'WINNERS' : 'OPPONENTS', left + 34, y + rowH * .26, 22, win ? _ink.withOpacity(.65) : _mute, ls: 2.4, w: FontWeight.w800, maxW: nameW);
      _t(c, pair.map((p) => p.first).join(' · '), left + 34, y + rowH * .52, 32, fg, w: FontWeight.w800, maxW: nameW - 20);
      for (var i = 0; i < n; i++) {
        final v = r == 0 ? d.sets[i].$1 : d.sets[i].$2, mine = r == 0 ? d.sets[i].$1 > d.sets[i].$2 : d.sets[i].$2 > d.sets[i].$1;
        _t(c, '$v', left + nameW + colW * i + colW / 2, y + rowH / 2 - fs * .52, fs, mine ? fg : fg.withOpacity(.55), fam: 'Unbounded', w: FontWeight.w700, ax: .5, maxW: colW);
      }
    }
    return rowH * 2 + 14;
  }

  void _pair(Canvas c, List<RecapPlayer> ps, double cx, double cy, double size, {required bool win, double nameFs = 38}) {
    final gap = size * .18, total = ps.length * size + (ps.length - 1) * gap;
    for (var i = 0; i < ps.length; i++) {
      final x = cx - total / 2 + size / 2 + i * (size + gap);
      _avatar(c, ps[i], Offset(x, cy), size, ring: win ? _lime : _mute.withOpacity(.6), ringW: win ? 10 : 6);
      _t(c, ps[i].first, x, cy + size / 2 + 26, nameFs, win ? _white : _mute, w: FontWeight.w800, ax: .5, maxW: size + gap);
    }
  }

  // ───────────────────────── plantillas ─────────────────────────
  void _result(Canvas c) {
    _header(c);
    final sq = _sq, story = fmt == RecapFormat.story;
    if (sq) {
      _t(c, _whenWhere, W / 2, 262, 26, _mute, ls: 1.6, ax: .5, maxW: 960);
      _scoreboard(c, 322, rowH: 124, fs: 78, left: 70);
      _t(c, 'WINNERS', W * .27, 640, 22, _lime, ls: 3, ax: .5, w: FontWeight.w800);
      _t(c, 'OPPONENTS', W * .73, 640, 22, _mute, ls: 3, ax: .5, w: FontWeight.w800);
      _pair(c, d.winners, W * .27, 760, 150, win: true, nameFs: 30);
      _pair(c, d.opponents, W * .73, 760, 118, win: false, nameFs: 28);
      _chipRow(c, 960, fs: 24);
      return;
    }
    final y0 = story ? 420.0 : 318.0, wsz = story ? 260.0 : 190.0, wcy = story ? y0 + 210 : 470.0, sb = story ? 880.0 : 655.0, rh = story ? 150.0 : 116.0, osz = story ? 200.0 : 116.0;
    _t(c, _whenWhere, W / 2, story ? 330 : 262, 28, _mute, ls: 1.6, ax: .5, maxW: 960);
    _t(c, 'WINNERS', W / 2, y0, 26, _lime, ls: 4, ax: .5, w: FontWeight.w800);
    _pair(c, d.winners, W / 2, wcy, wsz, win: true, nameFs: story ? 46 : 34);
    _scoreboard(c, sb, rowH: rh, fs: story ? 96 : 74);
    final op = sb + rh * 2 + 14 + (story ? 70 : 36);
    _t(c, 'OPPONENTS', W / 2, op, 24, _mute, ls: 4, ax: .5, w: FontWeight.w800);
    _pair(c, d.opponents, W / 2, op + (story ? 40 : 36) + osz / 2 + 10, osz, win: false, nameFs: story ? 36 : 28);
    _chipRow(c, H - (story ? 170 : 120), fs: story ? 28 : 24);
  }

  void _stats(Canvas c) {
    _header(c);
    final story = fmt == RecapFormat.story, sq = _sq;
    final top = sq ? 262.0 : story ? 330.0 : 280.0;
    // resultado + cabecera
    _t(c, d.userWon == null ? 'RESULTADO FINAL' : (d.userWon! ? 'VICTORIA' : 'DERROTA'), W / 2, top, sq ? 34 : 40, d.userWon == false ? const Color(0xFFFF8A8A) : _lime, ls: 6, ax: .5, w: FontWeight.w800);
    final score = d.sets.map((s) => '${s.$1}-${s.$2}').join('   ');
    _t(c, score, W / 2, top + (sq ? 56 : 70), sq ? 84 : story ? 120 : 100, _white, fam: 'Unbounded', w: FontWeight.w700, ax: .5, maxW: 980);
    _t(c, _whenWhere, W / 2, top + (sq ? 160 : story ? 230 : 200), 26, _mute, ls: 1.4, ax: .5, maxW: 960);

    // teselas: solo datos reales
    final tiles = <(String, String, Color?)>[
      ('SETS', '${d.winnerSets}–${d.loserSets}', null),
      if (opts.showDuration && d.hasDuration) ('DURACIÓN', recapDuration(d.durationSeconds!), null),
      if (opts.showElo && d.hasElo) ('ELO', '${d.eloDelta! > 0 ? '+' : ''}${d.eloDelta}', d.eloDelta! >= 0 ? _lime : const Color(0xFFFF8A8A)),
      if (opts.showElo && d.eloBefore != null) ('ELO ANTES → DESPUÉS', '${d.eloBefore} → ${d.eloAfter}', null),
      if (opts.showStats && d.stats?.streak != null) ('RACHA', '${d.stats!.streak}', null),
      if (opts.showStats && d.stats?.played != null) ('PARTIDOS', '${d.stats!.played}', null),
      if (opts.showStats && d.stats?.winRate != null) ('% VICTORIAS', '${d.stats!.winRate}%', null),
    ];
    final cols = 2, gap = 24.0, left = 70.0, tw = (W - left * 2 - gap) / cols;
    final gridTop = top + (sq ? 232 : story ? 330 : 290);
    final avail = H - gridTop - (sq ? 190 : 330), rows = (tiles.length / cols).ceil();
    final th = math.min(sq ? 150.0 : 190.0, (avail - gap * (rows - 1)) / math.max(rows, 1));
    for (var i = 0; i < tiles.length; i++) {
      final x = left + (i % cols) * (tw + gap), y = gridTop + (i ~/ cols) * (th + gap), last = tiles.length.isOdd && i == tiles.length - 1;
      final w = last ? W - left * 2 : tw, xx = last ? left : x;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(xx, y, w, th), const Radius.circular(32)), Paint()..color = _ink2);
      _t(c, tiles[i].$1, xx + 32, y + th * .14, math.min(22, th * .15), _mute, ls: 2.2, w: FontWeight.w800, maxW: w - 64);
      var vf = math.min(th * .36, 64.0);
      final mw = _tp(tiles[i].$2, vf, _white, fam: 'Unbounded', w: FontWeight.w700, maxW: 4000).width;
      if (mw > w - 64) vf = vf * (w - 64) / mw; // reduce en vez de truncar
      _t(c, tiles[i].$2, xx + 32, y + th * .42, vf, tiles[i].$3 ?? _white, fam: 'Unbounded', w: FontWeight.w700, maxW: w - 64);
    }
    // cuatro participantes
    final py = H - (sq ? 120 : 190), size = sq ? 70.0 : 96.0;
    final all = [...d.winners, ...d.opponents];
    final slot = (W - 140) / 4;
    for (var i = 0; i < all.length; i++) {
      final cx = 70 + slot * i + slot / 2, win = i < d.winners.length;
      _avatar(c, all[i], Offset(cx, py), size, ring: win ? _lime : _mute.withOpacity(.5), ringW: win ? 6 : 4);
      _t(c, all[i].first, cx, py + size / 2 + 20, sq ? 22 : 26, win ? _white : _mute, w: FontWeight.w800, ax: .5, maxW: slot - 8);
    }
  }

  void _h2h(Canvas c) {
    final story = fmt == RecapFormat.story, sq = _sq;
    // paneles
    if (sq) {
      final half = W / 2;
      c.drawRect(Rect.fromLTWH(0, 0, half, H), Paint()..color = _lime.withOpacity(.12));
      c.drawRect(Rect.fromLTWH(half, 0, half, H), Paint()..color = Colors.black.withOpacity(.22));
      _header(c, y: 64);
      _t(c, 'WINNERS', half / 2, 300, 24, _lime, ls: 4, ax: .5, w: FontWeight.w800);
      _t(c, 'OPPONENTS', half + half / 2, 300, 24, _mute, ls: 4, ax: .5, w: FontWeight.w800);
      for (var i = 0; i < 2; i++) {
        _avatar(c, d.winners[i], Offset(half / 2, 400 + i * 190), 128, ringW: 10);
        _t(c, d.winners[i].first, half / 2, 400 + i * 190 + 80, 28, _white, w: FontWeight.w800, ax: .5, maxW: 360);
        _avatar(c, d.opponents[i], Offset(half + half / 2, 400 + i * 190), 108, ring: _mute.withOpacity(.6), ringW: 6);
        _t(c, d.opponents[i].first, half + half / 2, 400 + i * 190 + 70, 26, _mute, w: FontWeight.w800, ax: .5, maxW: 360);
      }
      _vs(c, W / 2, 560, 84);
      _t(c, d.sets.map((s) => '${s.$1}-${s.$2}').join('  '), W / 2, 800, 64, _white, fam: 'Unbounded', w: FontWeight.w700, ax: .5, maxW: 1000);
      _t(c, _whenWhere, W / 2, 920, 22, _mute, ls: 1.4, ax: .5, maxW: 980);
      _chipRow(c, 980, fs: 22);
      return;
    }
    c.drawRect(Rect.fromLTWH(0, 0, W, H / 2), Paint()..color = _lime.withOpacity(.10));
    c.drawRect(Rect.fromLTWH(0, H / 2, W, H / 2), Paint()..color = Colors.black.withOpacity(.22));
    _header(c, y: 70);
    final lab = story ? 390.0 : 290.0, s1 = story ? 300.0 : 190.0, nf1 = story ? 44.0 : 34.0, by = story ? 850.0 : 600.0, bh = story ? 172.0 : 128.0,
        s2 = story ? 240.0 : 150.0, nf2 = story ? 36.0 : 28.0, gp = story ? 60.0 : 44.0;
    _t(c, 'WINNERS', W / 2, lab, 26, _lime, ls: 4, ax: .5, w: FontWeight.w800);
    _pair(c, d.winners, W / 2, lab + 40 + s1 / 2, s1, win: true, nameFs: nf1);
    c.drawRect(Rect.fromLTWH(0, by, W, bh), Paint()..color = _lime);
    _t(c, d.sets.map((s) => '${s.$1}-${s.$2}').join('    '), W / 2, by + bh / 2 - (story ? 46 : 35), story ? 92 : 70, _ink, fam: 'Unbounded', w: FontWeight.w700, ax: .5, maxW: 980);
    final cy2 = by + bh + gp + s2 / 2;
    _pair(c, d.opponents, W / 2, cy2, s2, win: false, nameFs: nf2);
    _t(c, 'OPPONENTS', W / 2, cy2 + s2 / 2 + 26 + nf2 + 34, 24, _mute, ls: 4, ax: .5, w: FontWeight.w800);
    _t(c, _whenWhere, W / 2, H - (story ? 190 : 140), 24, _mute, ls: 1.4, ax: .5, maxW: 980);
    _chipRow(c, H - (story ? 130 : 90), fs: story ? 26 : 22);
  }

  void _vs(Canvas c, double cx, double cy, double r, {bool small = false}) {
    if (small) return; // en la franja central el marcador ya actúa de separador
    c.drawCircle(Offset(cx, cy), r, Paint()..color = _lime);
    final t = _tp('VS', r * .62, _ink, fam: 'Unbounded', w: FontWeight.w800);
    t.paint(c, Offset(cx - t.width / 2, cy - t.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / W, size.height / H);
    _background(canvas);
    switch (tpl) {
      case RecapTemplate.result: _result(canvas);
      case RecapTemplate.stats: _stats(canvas);
      case RecapTemplate.headToHead: _h2h(canvas);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RecapPainter o) => o.d != d || o.tpl != tpl || o.fmt != fmt || o.opts != opts || o.images != images;

  /// PNG REAL (no captura de pantalla): graba el mismo pintor en un Canvas independiente a la resolución exacta
  /// del formato (1080 × 1920 | 1350 | 1080). Sin UI, sin márgenes.
  static Future<Uint8List> toPng(RecapData d, RecapTemplate t, RecapFormat f, {RecapOptions opts = const RecapOptions(), RecapImages images = const {}}) async {
    final size = Size(f.width.toDouble(), f.height.toDouble());
    final rec = ui.PictureRecorder();
    RecapPainter(d, t, f, opts: opts, images: images).paint(Canvas(rec, Offset.zero & size), size);
    final img = await rec.endRecording().toImage(f.width, f.height);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bytes!.buffer.asUint8List();
  }
}
