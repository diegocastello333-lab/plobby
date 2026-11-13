import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/share/canvas_text.dart';
import '../../../core/theme/design_tokens.dart';
import '../../auth/presentation/avatar_catalog.dart';
import '../domain/recap_data.dart';

/// Imágenes de red ya decodificadas por jugador (id → imagen). Si falta, se usa avatar predefinido o iniciales.
typedef RecapImages = Map<String, ui.Image>;

/// Pintor ÚNICO de Match Recap: lo usan la previsualización (CustomPaint) y la exportación PNG, por lo que
/// lo que se ve es exactamente lo que se guarda. Dibuja siempre en coordenadas 1080 × H del formato.
/// El logo es el wordmark oficial «plobby» (Unbounded 700, tracking −0.03em, sin símbolo «P»), igual que PlobbyLogo.
class RecapPainter extends CustomPainter {
  RecapPainter(this.d, this.tpl, this.fmt, {this.opts = const RecapOptions(), this.images = const {}, this.log});
  final RecapData d; final RecapTemplate tpl; final RecapFormat fmt; final RecapOptions opts; final RecapImages images;
  /// Solo para tests/depuración: registra la caja de cada texto y forma (ver `canvas_text.dart`).
  final ShareLayoutLog? log;

  static const _ink = AppColors.ink900, _ink2 = AppColors.ink800, _lime = AppColors.lime300, _white = Color(0xFFF2F5EF), _mute = Color(0xFF9AA39D);
  double get W => 1080.0;
  double get H => fmt.height.toDouble();
  bool get _sq => fmt == RecapFormat.square;

  // ───────────────────────── primitivas ─────────────────────────
  // Todo el texto pasa por ShareText (core/share/canvas_text.dart): se mide, se ajusta al ancho disponible (reduciendo
  // hasta un mínimo antes de recortar) y se ancla a la altura REAL de mayúsculas y cifras. La composición vertical se
  // hace con bloques de altura medida, no con coordenadas fijas: con nombres largos, 3 sets o más datos, nada se pisa.
  static const _margin = 70.0;
  late ShareText _st;

  /// Logo + píldora «MATCH RECAP». Devuelve el borde inferior.
  double _header(Canvas c, {double y = 84}) {
    final logo = _st.draw('plobby', W / 2, y, _sq ? 66 : 80, _lime, ax: .5, family: ShareFonts.unbounded, tracking: -.03, label: 'logo');
    final f = ShareText.fit('MATCH RECAP', 24, weight: FontWeight.w700, tracking: .06, color: _lime);
    final pill = Rect.fromCenter(center: Offset(W / 2, logo.bottom + (_sq ? 26 : 34) + (f.cap + 26) / 2), width: f.width + 44, height: f.cap + 26);
    c.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)), Paint()..color = _lime.withOpacity(.5)..style = PaintingStyle.stroke..strokeWidth = 2);
    _st.paintFitted(f, pill.center.dx, pill.center.dy, v: VAnchor.capCenter, ax: .5, label: 'match recap', container: pill);
    return pill.bottom;
  }

  /// Fecha y club: una línea; si no cabe sin recortar, fecha y club en dos líneas. Devuelve el borde inferior.
  double _meta(double top, double fs, {double maxW = 940}) {
    final date = recapDate(d.playedAt), club = opts.showClub && d.club.isNotEmpty ? d.club.toUpperCase() : null;
    final one = ShareText.fit([date, if (club != null) club].join('  ·  '), fs, maxWidth: maxW, minFontSize: fs * .85, tracking: .06);
    final lines = one.truncated && club != null ? [date, club] : [one.text];
    var y = top;
    for (final l in lines) {
      y = _st.draw(l, W / 2, y, fs, _mute, ax: .5, maxWidth: maxW, minFontSize: fs * .8, tracking: .06, label: 'fecha/club').bottom + fs * .55;
    }
    return y - fs * .55;
  }

  double _metaHeight(double fs, {double maxW = 940}) {
    final club = opts.showClub && d.club.isNotEmpty ? d.club.toUpperCase() : null;
    final one = ShareText.fit([recapDate(d.playedAt), if (club != null) club].join('  ·  '), fs, maxWidth: maxW, minFontSize: fs * .85, tracking: .06);
    final cap = ShareFonts.capHeight(ShareFonts.inter) * fs;
    return one.truncated && club != null ? cap * 2 + fs * .55 + fs * .25 : cap + (RegExp('[,()]').hasMatch(one.text) ? fs * .22 : 0);
  }

  // etiquetas inferiores: duración, ELO, pista, tipo/liga. SOLO con dato real y si la opción está activa.
  List<(String, bool)> get _chips => [
        if (opts.showDuration && d.hasDuration) (recapDuration(d.durationSeconds!), true),
        if (opts.showElo && d.hasElo) ('ELO ${d.eloDelta! > 0 ? '+' : d.eloDelta! < 0 ? '−' : ''}${d.eloDelta!.abs()}', false),
        if (opts.showClub && d.courtLabel.isNotEmpty) (d.courtLabel.toUpperCase(), false),
        (d.contextLabel, false),
      ];

  /// Reparte las etiquetas en filas centradas (máx. 2) en vez de encoger toda la fila: el texto se lee siempre.
  List<List<(FittedText, bool, Color)>> _chipRows(double fs) {
    const padX = 22.0, gap = 14.0, iconW = 0.0;
    final maxW = W - _margin * 2;
    final rows = <List<(FittedText, bool, Color)>>[[]];
    var used = 0.0;
    for (final (t, clock) in _chips) {
      final isElo = t.startsWith('ELO');
      final col = isElo ? (d.eloDelta! >= 0 ? _lime : const Color(0xFFFF8A8A)) : _white;
      final f = ShareText.fit(t, fs, maxWidth: maxW - padX * 2 - (clock ? fs + 10 : iconW), minFontSize: fs * .8, tracking: .05, color: col);
      final w = f.width + padX * 2 + (clock ? fs + 10 : 0);
      if (rows.last.isNotEmpty && used + gap + w > maxW && rows.length < 2) { rows.add([]); used = 0; }
      used += (rows.last.isEmpty ? 0 : gap) + w;
      rows.last.add((f, clock, col));
    }
    return rows;
  }

  double _chipsHeight(double fs) {
    final rows = _chipRows(fs), h = ShareFonts.capHeight(ShareFonts.inter) * fs + 26;
    return rows.length * h + (rows.length - 1) * 12;
  }

  /// Dibuja las etiquetas con el borde inferior en [bottom].
  void _chipsAt(Canvas c, double bottom, double fs) {
    const padX = 22.0, gap = 14.0;
    final rows = _chipRows(fs), h = ShareFonts.capHeight(ShareFonts.inter) * fs + 26;
    var y = bottom - _chipsHeight(fs);
    for (final row in rows) {
      final widths = [for (final (f, clock, _) in row) f.width + padX * 2 + (clock ? fs + 10 : 0)];
      var x = (W - widths.fold<double>(0, (a, b) => a + b) - gap * (row.length - 1)) / 2;
      for (var i = 0; i < row.length; i++) {
        final (f, clock, col) = row[i];
        final box = Rect.fromLTWH(x, y, widths[i], h);
        c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(h / 2)), Paint()..color = _ink2);
        var tx = x + padX;
        if (clock) { paintClock(c, Offset(tx + fs / 2, box.center.dy), fs, col); tx += fs + 10; }
        _st.paintFitted(f, tx, box.center.dy, v: VAnchor.capCenter, label: 'etiqueta', container: box);
        x += widths[i] + gap;
      }
      y += h + 12;
    }
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
        // iniciales centradas ópticamente en el círculo (sin registrar: van dentro del avatar)
        ShareText(c).draw(p.initials, size / 2, size / 2, size * .38, _white, v: VAnchor.capCenter, ax: .5, weight: FontWeight.w800);
      }
    }
    c.restore();
    c.drawCircle(center, size / 2 + ringW / 2, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = ringW..isAntiAlias = true);
    _st.obstacle(Rect.fromCircle(center: center, radius: size / 2 + ringW), 'avatar ${p.first}');
  }

  /// Pareja: avatares en fila y el nombre de pila centrado bajo cada uno (ajustado al ancho de su hueco).
  double _pairHeight(double size, double nameFs, {double ringW = 10}) => size + ringW * 2 + 20 + ShareFonts.capHeight(ShareFonts.inter) * nameFs + nameFs * .22;

  void _pair(Canvas c, List<RecapPlayer> ps, double cx, double top, double size, {required bool win, double nameFs = 38, double? slot}) {
    // el hueco de cada jugador depende también del nombre (no solo del avatar): sin «…» innecesarios con sitio de sobra
    final ringW = win ? 10.0 : 6.0, gap = size * .22, pitch = slot ?? math.max(size + gap, nameFs * 7.5), total = ps.length * pitch;
    final cy = top + ringW + size / 2;
    for (var i = 0; i < ps.length; i++) {
      final x = cx - total / 2 + pitch / 2 + i * pitch;
      _avatar(c, ps[i], Offset(x, cy), size, ring: win ? _lime : _mute.withOpacity(.6), ringW: ringW);
      _st.draw(ps[i].first, x, cy + size / 2 + ringW + 20, nameFs, win ? _white : _mute, ax: .5, maxWidth: pitch - 16, minFontSize: nameFs * .7,
          weight: FontWeight.w800, label: 'nombre');
    }
  }

  /// Marcador por sets: fila ganadores / rivales con una columna por set. Devuelve la altura usada.
  double _scoreboard(Canvas c, double top, {double rowH = 150, double fs = 96, double left = 90}) {
    final n = d.sets.length, avail = W - left * 2, nameW = avail * (n >= 3 ? .36 : .40), colW = (avail - nameW) / math.max(n, 1);
    final rows = [(d.winners, true), (d.opponents, false)];
    for (var r = 0; r < 2; r++) {
      final pair = rows[r].$1, win = rows[r].$2, y = top + r * (rowH + 14);
      final box = Rect.fromLTWH(left, y, avail, rowH);
      c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(36)), Paint()..color = win ? _lime : _ink2);
      final fg = win ? _ink : _white;
      final nameBox = Rect.fromLTWH(left + 28, y, nameW - 28, rowH);
      // etiqueta + nombres como un bloque de dos líneas centrado en la fila
      final lab = ShareText.fit(win ? 'WINNERS' : 'OPPONENTS', 22, maxWidth: nameW - 60, tracking: .11, weight: FontWeight.w800, color: win ? _ink.withOpacity(.65) : _mute);
      final nm = ShareText.fit(pair.map((p) => p.first).join(' · '), 32, maxWidth: nameW - 60, minFontSize: 22, weight: FontWeight.w800, color: fg);
      final blockH = lab.cap + 16 + nm.cap, by = y + (rowH - blockH) / 2;
      _st.paintFitted(lab, left + 34, by, label: 'marcador etiqueta', container: nameBox);
      _st.paintFitted(nm, left + 34, by + lab.cap + 16, label: 'marcador nombres', container: nameBox);
      for (var i = 0; i < n; i++) {
        final v = r == 0 ? d.sets[i].$1 : d.sets[i].$2, mine = r == 0 ? d.sets[i].$1 > d.sets[i].$2 : d.sets[i].$2 > d.sets[i].$1;
        final col = Rect.fromLTWH(left + nameW + colW * i, y, colW, rowH);
        _st.draw('$v', col.center.dx, col.center.dy, fs, mine ? fg : fg.withOpacity(.55), v: VAnchor.capCenter, ax: .5, maxWidth: colW - 24,
            family: ShareFonts.unbounded, label: 'set', container: col);
      }
    }
    return rowH * 2 + 14;
  }

  /// Coloca bloques de altura conocida entre [top] y [bottom], repartiendo el espacio sobrante (con un máximo por
  /// hueco; si sobra más, el conjunto se centra).
  void _flow(double top, double bottom, List<(double, void Function(double))> blocks, {double minGap = 24, double maxGap = 90}) {
    final sum = blocks.fold<double>(0, (a, b) => a + b.$1);
    final gaps = blocks.length - 1;
    final gap = gaps == 0 ? 0.0 : ((bottom - top - sum) / gaps).clamp(minGap, maxGap);
    var y = top + math.max(0, (bottom - top - sum - gap * gaps) / 2);
    for (final (h, draw) in blocks) { draw(y); y += h + gap; }
  }

  String get _score => d.sets.map((s) => '${s.$1}-${s.$2}').join('   ');

  // ───────────────────────── plantillas ─────────────────────────
  void _result(Canvas c) {
    final sq = _sq, story = fmt == RecapFormat.story;
    final hb = _header(c, y: sq ? 64 : 84);
    final chipFs = story ? 28.0 : 24.0, chipBottom = H - (sq ? 44 : story ? 120 : 70);
    _chipsAt(c, chipBottom, chipFs);
    final regBottom = chipBottom - _chipsHeight(chipFs) - (sq ? 36 : 56);
    final metaFs = sq ? 26.0 : 28.0, labFs = sq ? 22.0 : 26.0, labCap = ShareFonts.capHeight(ShareFonts.inter) * labFs;
    if (sq) {
      final rh = 120.0, sbH = rh * 2 + 14, ws = 140.0, os = 112.0, nf = 30.0;
      final pairsH = labCap + 26 + _pairHeight(ws, nf);
      _flow(hb + 30, regBottom, [
        (_metaHeight(metaFs), (y) => _meta(y, metaFs)),
        (sbH, (y) => _scoreboard(c, y, rowH: rh, fs: 76, left: _margin)),
        (pairsH, (y) {
          _st.draw('WINNERS', W * .27, y, labFs, _lime, ax: .5, tracking: .14, weight: FontWeight.w800, label: 'winners');
          _st.draw('OPPONENTS', W * .73, y, labFs, _mute, ax: .5, tracking: .14, weight: FontWeight.w800, label: 'opponents');
          _pair(c, d.winners, W * .27, y + labCap + 26, ws, win: true, nameFs: nf, slot: W * .5 / 2 - 6);
          _pair(c, d.opponents, W * .73, y + labCap + 26 + (ws - os) / 2 + 4, os, win: false, nameFs: nf * .93, slot: W * .5 / 2 - 6);
        }),
      ], minGap: 22, maxGap: 46);
      return;
    }
    final ws = story ? 250.0 : 170.0, os = story ? 190.0 : 120.0, rh = story ? 150.0 : 116.0, wnf = story ? 46.0 : 34.0, onf = story ? 36.0 : 28.0;
    _flow(hb + (story ? 70 : 34), regBottom, [
      (_metaHeight(metaFs), (y) => _meta(y, metaFs)),
      (labCap + 30 + _pairHeight(ws, wnf), (y) {
        _st.draw('WINNERS', W / 2, y, labFs, _lime, ax: .5, tracking: .15, weight: FontWeight.w800, label: 'winners');
        _pair(c, d.winners, W / 2, y + labCap + 30, ws, win: true, nameFs: wnf);
      }),
      (rh * 2 + 14, (y) => _scoreboard(c, y, rowH: rh, fs: story ? 96 : 74)),
      (labCap + 30 + _pairHeight(os, onf, ringW: 6), (y) {
        _st.draw('OPPONENTS', W / 2, y, labFs * .92, _mute, ax: .5, tracking: .15, weight: FontWeight.w800, label: 'opponents');
        _pair(c, d.opponents, W / 2, y + labCap + 30, os, win: false, nameFs: onf);
      }),
    ], minGap: story ? 50 : 28, maxGap: story ? 110 : 60);
  }

  void _stats(Canvas c) {
    final story = fmt == RecapFormat.story, sq = _sq;
    final hb = _header(c, y: sq ? 64 : 84);
    final titleFs = sq ? 34.0 : 40.0, scoreFs = sq ? 84.0 : story ? 120.0 : 100.0, metaFs = 26.0;
    final title = d.userWon == null ? 'RESULTADO FINAL' : (d.userWon! ? 'VICTORIA' : 'DERROTA');
    final titleCol = d.userWon == false ? const Color(0xFFFF8A8A) : _lime;
    final score = ShareText.fit(_score, scoreFs, maxWidth: W - _margin * 2, minFontSize: scoreFs * .7, family: ShareFonts.unbounded, color: _white);

    // teselas: solo datos reales
    final tiles = <(String, String, Color?)>[
      ('SETS', '${d.winnerSets}–${d.loserSets}', null),
      if (opts.showDuration && d.hasDuration) ('DURACIÓN', recapDuration(d.durationSeconds!), null),
      if (opts.showElo && d.hasElo) ('ELO', '${d.eloDelta! > 0 ? '+' : d.eloDelta! < 0 ? '−' : ''}${d.eloDelta!.abs()}', d.eloDelta! >= 0 ? _lime : const Color(0xFFFF8A8A)),
      if (opts.showElo && d.eloBefore != null) ('ELO ANTES Y DESPUÉS', '${d.eloBefore}→${d.eloAfter}', null),
      if (opts.showStats && d.stats?.streak != null) ('RACHA', '${d.stats!.streak}', null),
      if (opts.showStats && d.stats?.played != null) ('PARTIDOS', '${d.stats!.played}', null),
      if (opts.showStats && d.stats?.winRate != null) ('% VICTORIAS', '${d.stats!.winRate}%', null),
    ];
    const cols = 2, gap = 22.0;
    final tw = (W - _margin * 2 - gap) / cols, rows = (tiles.length / cols).ceil();

    // participantes (abajo, fijo) y región para el resto
    final size = sq ? 72.0 : 96.0, pnf = sq ? 22.0 : 26.0;
    final partH = _pairHeight(size, pnf, ringW: 6);
    final partTop = H - (sq ? 40 : 120) - partH;
    final topBlocks = <(double, void Function(double))>[
      (ShareFonts.capHeight(ShareFonts.inter) * titleFs, (y) => _st.draw(title, W / 2, y, titleFs, titleCol, ax: .5, tracking: .15, weight: FontWeight.w800, label: 'titulo')),
      (score.cap, (y) => _st.paintFitted(score, W / 2, y, ax: .5, label: 'resultado')),
      (_metaHeight(metaFs), (y) => _meta(y, metaFs)),
    ];
    final topH = topBlocks.fold<double>(0, (a, b) => a + b.$1) + (sq ? 26.0 : 40.0) * 2;
    final regTop = hb + (sq ? 30 : 50), regBottom = partTop - (sq ? 30 : 60);
    final gridAvail = regBottom - regTop - topH - (sq ? 30 : 60);
    final th = math.min(sq ? 130.0 : 190.0, (gridAvail - gap * (rows - 1)) / math.max(rows, 1));
    final gridH = rows * th + (rows - 1) * gap;
    _flow(regTop, regBottom, [
      ...topBlocks,
      (gridH, (y0) {
        for (var i = 0; i < tiles.length; i++) {
          final last = tiles.length.isOdd && i == tiles.length - 1;
          final w = last ? W - _margin * 2 : tw, x = last ? _margin : _margin + (i % cols) * (tw + gap), y = y0 + (i ~/ cols) * (th + gap);
          final box = Rect.fromLTWH(x, y, w, th);
          c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(32)), Paint()..color = _ink2);
          final lfs = math.min(22.0, th * .15);
          final lab = _st.draw(tiles[i].$1, x + 32, y + th * .2, lfs, _mute, tracking: .1, weight: FontWeight.w800, maxWidth: w - 64, label: 'tesela etiqueta', container: box);
          final vfs = math.min(th * .34, 64.0), vcy = lab.bottom + (y + th - lab.bottom) / 2, col = tiles[i].$3 ?? _white;
          if (tiles[i].$2.contains('→')) {
            // «antes → después»: flecha dibujada (la fuente Unbounded no tiene «→»)
            final parts = tiles[i].$2.split('→');
            final a = _st.draw(parts[0], x + 32, vcy, vfs, col, v: VAnchor.capCenter, family: ShareFonts.unbounded, maxWidth: (w - 64) * .42, label: 'tesela valor', container: box);
            paintArrow(c, Offset(a.right + vfs * .55, vcy), vfs * .6, _mute, stroke: vfs * .08);
            _st.draw(parts[1], a.right + vfs * 1.1, vcy, vfs, col, v: VAnchor.capCenter, family: ShareFonts.unbounded, maxWidth: (w - 64) * .42, label: 'tesela valor', container: box);
          } else {
            _st.draw(tiles[i].$2, x + 32, vcy, vfs, col, v: VAnchor.capCenter, family: ShareFonts.unbounded, maxWidth: w - 64, minFontSize: vfs * .6, label: 'tesela valor', container: box);
          }
        }
      }),
    ], minGap: sq ? 30 : 40, maxGap: sq ? 44 : 70);

    // cuatro participantes, repartidos en el ancho
    final all = [...d.winners, ...d.opponents], slot = (W - _margin * 2) / math.max(all.length, 1);
    for (var i = 0; i < all.length; i++) {
      final win = i < d.winners.length, cx = _margin + slot * i + slot / 2;
      final cy = partTop + 6 + size / 2;
      _avatar(c, all[i], Offset(cx, cy), size, ring: win ? _lime : _mute.withOpacity(.5), ringW: win ? 6 : 4);
      _st.draw(all[i].first, cx, cy + size / 2 + 26, pnf, win ? _white : _mute, ax: .5, maxWidth: slot - 16, minFontSize: pnf * .75, weight: FontWeight.w800, label: 'nombre');
    }
  }

  void _h2h(Canvas c) {
    final story = fmt == RecapFormat.story, sq = _sq;
    if (sq) {
      final half = W / 2;
      c.drawRect(Rect.fromLTWH(0, 0, half, H), Paint()..color = _lime.withOpacity(.12));
      c.drawRect(Rect.fromLTWH(half, 0, half, H), Paint()..color = Colors.black.withOpacity(.22));
      final hb = _header(c, y: 56);
      const chipFs = 22.0, chipBottom = 1036.0;
      _chipsAt(c, chipBottom, chipFs);
      final scoreF = ShareText.fit(d.sets.map((s) => '${s.$1}-${s.$2}').join('  '), 64, maxWidth: W - _margin * 2, minFontSize: 48, family: ShareFonts.unbounded, color: _white);
      final metaH = _metaHeight(22, maxW: 960);
      final bottomTop = chipBottom - _chipsHeight(chipFs) - 30 - metaH - 26 - scoreF.cap;
      _st.paintFitted(scoreF, W / 2, bottomTop, ax: .5, label: 'resultado');
      _meta(bottomTop + scoreF.cap + 26, 22, maxW: 960);
      // columnas: etiqueta y dos jugadores por lado, centradas en el espacio libre
      const labFs = 24.0, ws = 118.0, os = 100.0, nf = 26.0;
      final labCap = ShareFonts.capHeight(ShareFonts.inter) * labFs;
      final colH = labCap + 26 + _pairHeight(ws, nf) * 2 + 18;
      final top = hb + 30 + math.max(0, (bottomTop - 30 - hb - 30 - colH) / 2);
      _st.draw('WINNERS', half / 2, top, labFs, _lime, ax: .5, tracking: .15, weight: FontWeight.w800, label: 'winners');
      _st.draw('OPPONENTS', half + half / 2, top, labFs, _mute, ax: .5, tracking: .15, weight: FontWeight.w800, label: 'opponents');
      for (var i = 0; i < math.max(d.winners.length, d.opponents.length) && i < 2; i++) {
        final rowTop = top + labCap + 26 + i * (_pairHeight(ws, nf) + 18);
        if (i < d.winners.length) _pair(c, [d.winners[i]], half / 2, rowTop, ws, win: true, nameFs: nf, slot: half - 120);
        if (i < d.opponents.length) _pair(c, [d.opponents[i]], half + half / 2, rowTop + (ws - os) / 2 + 4, os, win: false, nameFs: nf * .93, slot: half - 120);
      }
      _vs(c, W / 2, top + labCap + 26 + _pairHeight(ws, nf) + 9, 64);
      return;
    }
    // vertical: franja del marcador EXACTAMENTE en la unión de las dos mitades
    final bh = story ? 172.0 : 128.0, by = H / 2 - bh / 2;
    c.drawRect(Rect.fromLTWH(0, 0, W, H / 2), Paint()..color = _lime.withOpacity(.10));
    c.drawRect(Rect.fromLTWH(0, H / 2, W, H / 2), Paint()..color = Colors.black.withOpacity(.22));
    final hb = _header(c, y: 70);
    c.drawRect(Rect.fromLTWH(0, by, W, bh), Paint()..color = _lime);
    final band = Rect.fromLTWH(0, by, W, bh);
    _st.draw(d.sets.map((s) => '${s.$1}-${s.$2}').join('    '), W / 2, band.center.dy, story ? 92 : 70, _ink, v: VAnchor.capCenter, ax: .5,
        maxWidth: W - _margin * 2, minFontSize: story ? 64 : 50, family: ShareFonts.unbounded, label: 'resultado', container: band);
    const labFs = 26.0;
    final labCap = ShareFonts.capHeight(ShareFonts.inter) * labFs;
    final s1 = story ? 280.0 : 170.0, nf1 = story ? 44.0 : 32.0, s2 = story ? 220.0 : 130.0, nf2 = story ? 36.0 : 28.0;
    // arriba: WINNERS + pareja, centrados entre la cabecera y la franja
    final upH = labCap + 32 + _pairHeight(s1, nf1);
    final upTop = hb + 30 + math.max(0, (by - 30 - hb - 30 - upH) / 2);
    _st.draw('WINNERS', W / 2, upTop, labFs, _lime, ax: .5, tracking: .15, weight: FontWeight.w800, label: 'winners');
    _pair(c, d.winners, W / 2, upTop + labCap + 32, s1, win: true, nameFs: nf1);
    // abajo: pareja + OPPONENTS, centrados entre la franja y fecha/club + etiquetas
    final chipFs = story ? 26.0 : 22.0, chipBottom = H - (story ? 110 : 60);
    _chipsAt(c, chipBottom, chipFs);
    final metaFs = 24.0, metaH = _metaHeight(metaFs, maxW: 980);
    final metaTop = chipBottom - _chipsHeight(chipFs) - 30 - metaH;
    _meta(metaTop, metaFs, maxW: 980);
    final downH = _pairHeight(s2, nf2, ringW: 6) + 34 + labCap;
    final downTop = by + bh + 30 + math.max(0, (metaTop - 40 - by - bh - 30 - downH) / 2);
    _pair(c, d.opponents, W / 2, downTop, s2, win: false, nameFs: nf2);
    _st.draw('OPPONENTS', W / 2, downTop + _pairHeight(s2, nf2, ringW: 6) + 34, labFs * .92, _mute, ax: .5, tracking: .15, weight: FontWeight.w800, label: 'opponents');
  }

  void _vs(Canvas c, double cx, double cy, double r) {
    c.drawCircle(Offset(cx, cy), r, Paint()..color = _lime);
    ShareText(c).draw('VS', cx, cy, r * .62, _ink, v: VAnchor.capCenter, ax: .5, family: ShareFonts.unbounded);
    _st.obstacle(Rect.fromCircle(center: Offset(cx, cy), radius: r), 'vs');
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

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / W, size.height / H);
    _st = ShareText(canvas, log: log);
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
